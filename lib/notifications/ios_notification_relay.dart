//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants.dart';
import '../keys.dart';
import '../utilities/logger.dart';
import '../utilities/hub_identity.dart';
import 'ios_push_native.dart';

class IosRelayBinding {
  final String relayBaseUrl;
  final String hubToken;
  final String appInstallId;
  final String hubId;
  final String deviceToken;
  final int expiresAtEpochMs;
  final int refreshedAtEpochMs;

  const IosRelayBinding({
    required this.relayBaseUrl,
    required this.hubToken,
    required this.appInstallId,
    required this.hubId,
    required this.deviceToken,
    required this.expiresAtEpochMs,
    required this.refreshedAtEpochMs,
  });

  Map<String, dynamic> toJson() {
    return {
      'relay_base_url': relayBaseUrl,
      'hub_token': hubToken,
      'app_install_id': appInstallId,
      'hub_id': hubId,
      'device_token': deviceToken,
      'expires_at_epoch_ms': expiresAtEpochMs,
      'refreshed_at_epoch_ms': refreshedAtEpochMs,
    };
  }

  factory IosRelayBinding.fromJson(Map<String, dynamic> json) {
    return IosRelayBinding(
      relayBaseUrl: (json['relay_base_url'] ?? '').toString(),
      hubToken: (json['hub_token'] ?? '').toString(),
      appInstallId: (json['app_install_id'] ?? '').toString(),
      hubId: (json['hub_id'] ?? '').toString(),
      deviceToken: (json['device_token'] ?? '').toString(),
      expiresAtEpochMs: _coerceEpochMs(json['expires_at_epoch_ms']),
      refreshedAtEpochMs: _coerceEpochMs(json['refreshed_at_epoch_ms']),
    );
  }
}

int _coerceEpochMs(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class IosNotificationRelay {
  IosNotificationRelay._();

  static final instance = IosNotificationRelay._();
  static const _tokenWaitTimeout = Duration(seconds: 15);
  static const _hubTokenRefreshInterval = Duration(hours: 24);
  static const _missingHubRetryCooldown = Duration(seconds: 30);
  static const _relayRateLimitCooldown = Duration(minutes: 5);

  final _client = _IosNotificationRelayClient();
  Future<void>? _initFuture;
  Future<void>? _authorizeFuture;
  IosPushPayloadHandler? _payloadHandler;
  DateTime? _missingHubRetryUntil;
  DateTime? _relayRateLimitedUntil;

  Future<void> init({required IosPushPayloadHandler onPayload}) {
    _payloadHandler = onPayload;
    _initFuture ??= _doInit();
    return _initFuture!;
  }

  Future<void> _doInit() async {
    await IosPushNativeBridge.init(
      onPayload: _handleNativePayload,
      onToken: _handleApnsTokenUpdate,
    );
    await IosPushNativeBridge.registerForRemoteNotifications();

    final pending = await IosPushNativeBridge.drainPendingPushPayloads();
    for (final payload in pending) {
      await _handleNativePayload(payload, 'ios-apns-pending');
    }
  }

  Future<void> tryAuthorizeIfNeeded(bool force) async {
    if (_authorizeFuture != null) {
      return _authorizeFuture!;
    }
    _authorizeFuture = _doAuthorizeIfNeeded(force);
    try {
      await _authorizeFuture!;
    } finally {
      _authorizeFuture = null;
    }
  }

  Future<void> _doAuthorizeIfNeeded(bool force) async {
    var currentStep = 'init';
    String? hubId;
    String? apnsToken;
    String? keyId;
    String? appInstallId;
    String? attestationChallenge;
    String? authChallenge;
    IosRelayBinding? cachedBinding;
    var bindingMatchesHubId = true;
    var previouslyAttested = false;
    var retriedMissingAttestation = false;
    var retriedKeyRotation = false;
    try {
      await init(onPayload: _payloadHandler ?? (_, __) async {});

      final prefs = await SharedPreferences.getInstance();
      final relayBaseUrl = _relayBaseUrl();
      hubId = _hubId(prefs);

      if (hubId == null) {
        if (_shouldLogMissingHub(force)) {
          Log.d(
            'Skipping iOS relay auth; hub id is unavailable '
            '(cooldownMs=${_missingHubRetryCooldown.inMilliseconds})',
          );
        }
        return;
      }
      _missingHubRetryUntil = null;
      final resolvedHubId = hubId;

      final now = DateTime.now().millisecondsSinceEpoch;
      final needUpdate =
          prefs.getBool(PrefKeys.needUpdateIosRelayBinding) ?? true;
      cachedBinding = _loadBinding(prefs);
      bindingMatchesHubId =
          cachedBinding == null || cachedBinding.hubId == resolvedHubId;
      final hasUsableCachedBinding = isStoredIosRelayBindingUsable(
        prefs: prefs,
        binding: cachedBinding,
        nowEpochMs: now,
      );
      final hasCurrentCachedBinding = isIosRelayBindingRefreshCurrent(
        binding: cachedBinding,
        nowEpochMs: now,
        refreshInterval: _hubTokenRefreshInterval,
      );
      Log.d(
        'Starting iOS relay auth '
        '(force=$force, relay=${_summarizeUrl(relayBaseUrl)}, '
        'hub=${_summarizeOpaque(resolvedHubId)}, needUpdate=$needUpdate, '
        'cachedBinding=${_describeBinding(cachedBinding, now)})',
      );
      if (cachedBinding != null && !bindingMatchesHubId) {
        Log.d(
          'Refreshing iOS relay auth; cached binding hub id changed '
          '(cached=${_summarizeOpaque(cachedBinding.hubId)}, '
          'expected=${_summarizeOpaque(resolvedHubId)})',
        );
      }
      if (hasUsableCachedBinding &&
          hasCurrentCachedBinding &&
          bindingMatchesHubId &&
          !needUpdate) {
        await prefs.setBool(PrefKeys.needUpdateIosRelayBinding, false);
        Log.d(
          'Skipping iOS relay auth; cached binding is still current '
          '(refreshAgeMs=${now - cachedBinding!.refreshedAtEpochMs}, '
          'expiresInMs=${cachedBinding.expiresAtEpochMs - now})',
        );
        return;
      }

      currentStep = 'wait_for_apns_token';
      apnsToken = await _waitForApnsToken();
      if (apnsToken == null || apnsToken.isEmpty) {
        Log.w('APNs token is unavailable; deferring relay authorization');
        await prefs.setBool(PrefKeys.needUpdateIosRelayBinding, true);
        return;
      }
      Log.d(
        'Resolved APNs token for relay auth '
        '(token=${_summarizeOpaque(apnsToken)})',
      );
      final resolvedApnsToken = apnsToken;

      await prefs.setString(PrefKeys.iosApnsToken, resolvedApnsToken);

      final hasUsableBindingAfterTokenResolution = isIosRelayBindingUsable(
        binding: cachedBinding,
        hubId: resolvedHubId,
        apnsToken: resolvedApnsToken,
        nowEpochMs: now,
      );
      final hasCurrentBindingAfterTokenResolution =
          isIosRelayBindingRefreshCurrent(
            binding: cachedBinding,
            nowEpochMs: now,
            refreshInterval: _hubTokenRefreshInterval,
          );
      if (_relayRateLimitedUntil != null &&
          DateTime.now().isBefore(_relayRateLimitedUntil!)) {
        if (hasUsableBindingAfterTokenResolution) {
          await prefs.setBool(PrefKeys.needUpdateIosRelayBinding, false);
          Log.d(
            'Skipping iOS relay auth; cached binding is still usable during local rate-limit backoff '
            '(backoffUntil=${_relayRateLimitedUntil!.toIso8601String()}, '
            'refreshCurrent=$hasCurrentBindingAfterTokenResolution)',
          );
          return;
        }
        Log.w(
          'Skipping iOS relay auth; local rate-limit backoff is active and no fresh cached binding is available '
          '(backoffUntil=${_relayRateLimitedUntil!.toIso8601String()})',
        );
        return;
      }
      if (hasUsableBindingAfterTokenResolution &&
          hasCurrentBindingAfterTokenResolution &&
          !needUpdate) {
        await prefs.setBool(PrefKeys.needUpdateIosRelayBinding, false);
        if (force) {
          Log.d(
            'Skipping iOS relay auth; cached binding still matches current hub and APNs token '
            '(refreshAgeMs=${now - cachedBinding!.refreshedAtEpochMs}, '
            'expiresInMs=${cachedBinding.expiresAtEpochMs - now})',
          );
        }
        return;
      }

      while (true) {
        final persistedKeyId = prefs.getString(PrefKeys.iosAppAttestKeyId);
        currentStep = 'ensure_app_attest_key';
        final resolvedKeyId = await IosPushNativeBridge.ensureAppAttestKey();
        keyId = resolvedKeyId;
        await prefs.setString(PrefKeys.iosAppAttestKeyId, resolvedKeyId);

        previouslyAttested = prefs.getBool(PrefKeys.iosRelayAttested) ?? false;
        final attestedKeyId = prefs.getString(PrefKeys.iosRelayAttestedKeyId);
        final needsReattest =
            !previouslyAttested || attestedKeyId != resolvedKeyId;
        final shouldRotateReusedUntrackedKey =
            !retriedKeyRotation &&
            !previouslyAttested &&
            attestedKeyId == null &&
            persistedKeyId != null &&
            persistedKeyId == resolvedKeyId;
        Log.d(
          'Using App Attest key for relay auth '
          '(key=${_summarizeOpaque(resolvedKeyId)}, previouslyAttested=$previouslyAttested, '
          'storedAttestedKey=${_summarizeOpaque(attestedKeyId)}, '
          'needsReattest=$needsReattest)',
        );
        if (shouldRotateReusedUntrackedKey) {
          retriedKeyRotation = true;
          currentStep = 'rotate_app_attest_key';
          attestationChallenge = null;
          authChallenge = null;
          keyId = await _rotateAppAttestKey(
            prefs: prefs,
            previousKeyId: resolvedKeyId,
            reason:
                'Local relay attestation metadata is missing for a reused App Attest key',
          );
          continue;
        }
        if (needsReattest) {
          currentStep = 'issue_attestation_challenge';
          final issuedAttestationChallenge = await _client.issueChallenge(
            relayBaseUrl,
          );
          attestationChallenge = issuedAttestationChallenge;
          Log.d(
            'Issued relay attestation challenge '
            '(challenge=${_summarizeOpaque(issuedAttestationChallenge)})',
          );

          currentStep = 'create_attestation';
          late final AppAttestAttestation attestation;
          try {
            attestation = await IosPushNativeBridge.attestKey(
              issuedAttestationChallenge,
            );
          } catch (e) {
            if (!retriedKeyRotation && _isAppAttestKeyReuseError(e)) {
              retriedKeyRotation = true;
              currentStep = 'rotate_app_attest_key';
              attestationChallenge = null;
              authChallenge = null;
              keyId = await _rotateAppAttestKey(
                prefs: prefs,
                previousKeyId: resolvedKeyId,
                reason:
                    'iOS refused to attest the reused App Attest key; rotating and retrying',
              );
              continue;
            }
            rethrow;
          }
          Log.d(
            'Generated App Attest attestation '
            '(key=${_summarizeOpaque(attestation.keyId)}, '
            'attestationObjectLen=${attestation.attestationObject.length})',
          );

          currentStep = 'verify_attestation';
          await _client.verifyAttestation(
            relayBaseUrl: relayBaseUrl,
            keyId: attestation.keyId,
            challenge: issuedAttestationChallenge,
            attestationObject: attestation.attestationObject,
          );
          Log.d(
            'Relay attestation verified '
            '(key=${_summarizeOpaque(attestation.keyId)})',
          );
          await prefs.setBool(PrefKeys.iosRelayAttested, true);
          await prefs.setString(
            PrefKeys.iosRelayAttestedKeyId,
            attestation.keyId,
          );
        }

        currentStep = 'issue_authorize_challenge';
        final issuedAuthChallenge = await _client.issueChallenge(relayBaseUrl);
        authChallenge = issuedAuthChallenge;
        Log.d(
          'Issued relay authorization challenge '
          '(challenge=${_summarizeOpaque(issuedAuthChallenge)})',
        );

        currentStep = 'generate_assertion';
        final assertion = await IosPushNativeBridge.generateAssertion(
          issuedAuthChallenge,
        );
        final resolvedAppInstallId = await _ensureAppInstallId(prefs);
        appInstallId = resolvedAppInstallId;
        Log.d(
          'Generated App Attest assertion for relay auth '
          '(key=${_summarizeOpaque(assertion.keyId)}, '
          'assertionLen=${assertion.assertion.length}, '
          'clientDataJsonLen=${assertion.clientDataJson.length}, '
          'appInstall=${_summarizeOpaque(resolvedAppInstallId)}, '
          'hub=${_summarizeOpaque(resolvedHubId)}, '
          'deviceToken=${_summarizeOpaque(resolvedApnsToken)})',
        );

        try {
          currentStep = 'authorize_hub';
          final authorization = await _client.authorizeHub(
            relayBaseUrl: relayBaseUrl,
            keyId: assertion.keyId,
            challenge: issuedAuthChallenge,
            assertion: assertion.assertion,
            clientDataJson: assertion.clientDataJson,
            appInstallId: resolvedAppInstallId,
            hubId: resolvedHubId,
            deviceToken: resolvedApnsToken,
          );

          final authorizedAtEpochMs = DateTime.now().millisecondsSinceEpoch;
          final expiresAtEpochMs =
              authorizedAtEpochMs + (authorization.expiresInSeconds * 1000);
          final binding = IosRelayBinding(
            relayBaseUrl: relayBaseUrl,
            hubToken: authorization.hubToken,
            appInstallId: resolvedAppInstallId,
            hubId: resolvedHubId,
            deviceToken: resolvedApnsToken,
            expiresAtEpochMs: expiresAtEpochMs,
            refreshedAtEpochMs: authorizedAtEpochMs,
          );
          final previousNeedUpload =
              prefs.getBool(PrefKeys.needUploadIosNotificationTarget) ?? true;
          final needsUpload =
              previousNeedUpload ||
              _bindingRequiresNotificationTargetUpload(
                previousBinding: cachedBinding,
                nextBinding: binding,
              );

          await prefs.setString(
            PrefKeys.iosRelayBindingJson,
            jsonEncode(binding.toJson()),
          );
          await prefs.setString(
            PrefKeys.iosRelayHubToken,
            authorization.hubToken,
          );
          await prefs.setInt(
            PrefKeys.iosRelayHubTokenExpiryMs,
            expiresAtEpochMs,
          );
          await prefs.setBool(PrefKeys.needUpdateIosRelayBinding, false);
          await prefs.setBool(
            PrefKeys.needUploadIosNotificationTarget,
            needsUpload,
          );

          Log.d(
            'Stored iOS relay binding '
            '(hub=${_summarizeOpaque(resolvedHubId)}, appInstall=${_summarizeOpaque(resolvedAppInstallId)}, '
            'expiresAtEpochMs=$expiresAtEpochMs, refreshedAtEpochMs=$authorizedAtEpochMs, '
            'expiresInSeconds=${authorization.expiresInSeconds}, needsUpload=$needsUpload)',
          );
          break;
        } catch (e) {
          if (!retriedMissingAttestation &&
              _isMissingRelayAttestationError(e)) {
            retriedMissingAttestation = true;
            attestationChallenge = null;
            authChallenge = null;
            currentStep = 'rotate_app_attest_key';
            keyId = await _rotateAppAttestKey(
              prefs: prefs,
              previousKeyId: keyId,
              reason:
                  'Relay no longer recognizes the App Attest key; rotating and retrying',
            );
            continue;
          }
          rethrow;
        }
      }
    } catch (e, st) {
      final prefs = await SharedPreferences.getInstance();
      final backoff = _relayBackoffDuration(e);
      if (backoff != null) {
        _relayRateLimitedUntil = DateTime.now().add(backoff);
      }
      final preserveCachedBinding = _shouldPreserveCachedBindingOnFailure(
        error: e,
        cachedBinding: cachedBinding,
        hubId: hubId,
        apnsToken: apnsToken,
      );
      if (preserveCachedBinding) {
        await prefs.setBool(PrefKeys.needUpdateIosRelayBinding, false);
        Log.w(
          'Preserving cached iOS relay binding after soft authorization failure '
          '(step=$currentStep, hub=${_summarizeOpaque(hubId)}, '
          'apnsToken=${_summarizeOpaque(apnsToken)}, '
          'key=${_summarizeOpaque(keyId)}, '
          'appInstall=${_summarizeOpaque(appInstallId)}, '
          'backoffUntil=${_relayRateLimitedUntil?.toIso8601String()}, '
          'error=$e)',
        );
        return;
      }
      final onSimulator = Platform.environment.containsKey(
        'SIMULATOR_DEVICE_NAME',
      );
      (onSimulator ? Log.w : Log.e)(
        'iOS relay authorization failed '
        '${onSimulator ? '(simulator: App Attest unavailable) ' : ''}'
        '(step=$currentStep, hub=${_summarizeOpaque(hubId)}, '
        'apnsToken=${_summarizeOpaque(apnsToken)}, '
        'key=${_summarizeOpaque(keyId)}, '
        'appInstall=${_summarizeOpaque(appInstallId)}, '
        'previouslyAttested=$previouslyAttested, '
        'attestationChallenge=${_summarizeOpaque(attestationChallenge)}, '
        'authChallenge=${_summarizeOpaque(authChallenge)})'
        ': $e\n$st',
      );
      await prefs.setBool(PrefKeys.needUpdateIosRelayBinding, true);
    }
  }

  bool _isSoftRelayFailure(Object error) {
    if (error is _RelayHttpException) {
      return error.statusCode == 429;
    }
    final message = error.toString();
    return message.contains('SocketException') ||
        message.contains('Failed host lookup') ||
        message.contains('Network is unreachable') ||
        message.contains('Operation timed out') ||
        message.contains('Connection timed out');
  }

  bool _shouldPreserveCachedBindingOnFailure({
    required Object error,
    required IosRelayBinding? cachedBinding,
    required String? hubId,
    required String? apnsToken,
  }) {
    if (!_isSoftRelayFailure(error)) {
      return false;
    }
    return isIosRelayBindingUsable(
      binding: cachedBinding,
      hubId: hubId,
      apnsToken: apnsToken,
      nowEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Duration? _relayBackoffDuration(Object error) {
    if (error is _RelayHttpException && error.statusCode == 429) {
      return error.retryAfter ?? _relayRateLimitCooldown;
    }
    return null;
  }

  Future<void> _handleNativePayload(
    Map<String, dynamic> payload,
    String source,
  ) async {
    if (_payloadHandler == null) {
      return;
    }

    final data = _extractPayloadData(payload);
    final encodedBody = data['body'];
    if (encodedBody is! String || encodedBody.isEmpty) {
      Log.d('Ignoring APNs payload without encrypted body (source=$source)');
      return;
    }

    await _payloadHandler!(data, source);
  }

  Future<void> _handleApnsTokenUpdate(String token) async {
    if (token.isEmpty) {
      return;
    }
    unawaited(tryAuthorizeIfNeeded(false));
  }

  Map<String, dynamic> _extractPayloadData(Map<String, dynamic> payload) {
    if (payload['body'] is String) {
      return payload;
    }
    final nested = payload['data'];
    if (nested is Map) {
      return Map<String, dynamic>.from(nested);
    }
    return payload;
  }

  Future<String?> _waitForApnsToken() async {
    var attempts = 0;
    final deadline = DateTime.now().add(_tokenWaitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      attempts += 1;
      final token = await IosPushNativeBridge.getApnsToken();
      if (token != null && token.isNotEmpty) {
        if (attempts > 1) {
          Log.d(
            'Received APNs token after polling '
            '(attempts=$attempts, token=${_summarizeOpaque(token)})',
          );
        }
        return token;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final token = await IosPushNativeBridge.getApnsToken();
    Log.d(
      'Finished APNs token polling '
      '(attempts=$attempts, available=${token != null && token.isNotEmpty}, '
      'token=${_summarizeOpaque(token)})',
    );
    return token;
  }

  Future<String> _ensureAppInstallId(SharedPreferences prefs) async {
    final existing = prefs.getString(PrefKeys.iosAppInstallId);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final created = const Uuid().v4();
    await prefs.setString(PrefKeys.iosAppInstallId, created);
    return created;
  }

  IosRelayBinding? _loadBinding(SharedPreferences prefs) {
    return loadStoredIosRelayBinding(prefs);
  }

  String _relayBaseUrl() {
    return Constants.iosNotificationRelayBaseUrl;
  }

  Future<void> _clearLocalAttestationState(SharedPreferences prefs) async {
    await prefs.setBool(PrefKeys.iosRelayAttested, false);
    await prefs.remove(PrefKeys.iosRelayAttestedKeyId);
  }

  Future<String> _rotateAppAttestKey({
    required SharedPreferences prefs,
    required String? previousKeyId,
    required String reason,
  }) async {
    await _clearLocalAttestationState(prefs);
    final rotatedKeyId = await IosPushNativeBridge.rotateAppAttestKey();
    await prefs.setString(PrefKeys.iosAppAttestKeyId, rotatedKeyId);
    Log.w(
      '$reason '
      '(old=${_summarizeOpaque(previousKeyId)}, '
      'new=${_summarizeOpaque(rotatedKeyId)})',
    );
    return rotatedKeyId;
  }

  String? _hubId(SharedPreferences prefs) {
    return deriveHubIdFromServerUsername(
      prefs.getString(PrefKeys.serverUsername),
    );
  }

  bool _shouldLogMissingHub(bool force) {
    final now = DateTime.now();
    final retryUntil = _missingHubRetryUntil;
    if (!force && retryUntil != null && now.isBefore(retryUntil)) {
      return false;
    }
    _missingHubRetryUntil = now.add(_missingHubRetryCooldown);
    return true;
  }

  bool _isMissingRelayAttestationError(Object error) {
    return error.toString().contains('Key id not attested');
  }

  bool _isAppAttestKeyReuseError(Object error) {
    return error.toString().contains('com.apple.devicecheck.error error 3');
  }
}

bool isIosRelayBindingUsable({
  required IosRelayBinding? binding,
  required String? hubId,
  required String? apnsToken,
  required int nowEpochMs,
}) {
  if (binding == null || hubId == null || hubId.isEmpty) {
    return false;
  }
  final effectiveApnsToken =
      (apnsToken != null && apnsToken.isNotEmpty)
          ? apnsToken
          : binding.deviceToken;
  if (effectiveApnsToken.isEmpty) {
    return false;
  }
  if (binding.hubId != hubId || binding.deviceToken != effectiveApnsToken) {
    return false;
  }
  return binding.expiresAtEpochMs > nowEpochMs;
}

bool isStoredIosRelayBindingUsable({
  required SharedPreferences prefs,
  required IosRelayBinding? binding,
  int? nowEpochMs,
}) {
  return isIosRelayBindingUsable(
    binding: binding,
    hubId: deriveHubIdFromServerUsername(
      prefs.getString(PrefKeys.serverUsername),
    ),
    apnsToken: prefs.getString(PrefKeys.iosApnsToken),
    nowEpochMs: nowEpochMs ?? DateTime.now().millisecondsSinceEpoch,
  );
}

bool isIosRelayBindingRefreshCurrent({
  required IosRelayBinding? binding,
  required int nowEpochMs,
  required Duration refreshInterval,
}) {
  if (binding == null || binding.refreshedAtEpochMs <= 0) {
    return false;
  }
  return nowEpochMs - binding.refreshedAtEpochMs <
      refreshInterval.inMilliseconds;
}

IosRelayBinding? loadStoredIosRelayBinding(SharedPreferences prefs) {
  final raw = prefs.getString(PrefKeys.iosRelayBindingJson);
  if (raw == null || raw.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return IosRelayBinding.fromJson(decoded);
    }
    if (decoded is Map) {
      return IosRelayBinding.fromJson(Map<String, dynamic>.from(decoded));
    }
  } catch (_) {
    return null;
  }
  return null;
}

bool _bindingRequiresNotificationTargetUpload({
  required IosRelayBinding? previousBinding,
  required IosRelayBinding nextBinding,
}) {
  if (previousBinding == null) {
    return true;
  }
  return previousBinding.relayBaseUrl != nextBinding.relayBaseUrl ||
      previousBinding.hubToken != nextBinding.hubToken ||
      previousBinding.appInstallId != nextBinding.appInstallId ||
      previousBinding.hubId != nextBinding.hubId ||
      previousBinding.deviceToken != nextBinding.deviceToken;
}

class _HubAuthorizeResponse {
  final String hubToken;
  final int expiresInSeconds;

  const _HubAuthorizeResponse({
    required this.hubToken,
    required this.expiresInSeconds,
  });
}

class _RelayHttpException implements Exception {
  final String action;
  final int statusCode;
  final String? reasonPhrase;
  final String body;
  final Duration? retryAfter;

  const _RelayHttpException({
    required this.action,
    required this.statusCode,
    required this.reasonPhrase,
    required this.body,
    this.retryAfter,
  });

  @override
  String toString() {
    return 'Failed to $action: $statusCode ${reasonPhrase ?? ''} $body'.trim();
  }
}

class _IosNotificationRelayClient {
  final http.Client _http = http.Client();

  Future<String> issueChallenge(String relayBaseUrl) async {
    final url = _buildUrl(relayBaseUrl, ['attest', 'challenge']);
    Log.d(
      'Sending relay challenge request '
      '(url=${_summarizeUrl(url.toString())})',
    );
    final response = await _http.post(url);
    _logResponse(action: 'issue relay challenge', url: url, response: response);
    _throwIfNotOk(response, 'issue relay challenge');
    final decoded = _decodeJson(response.body);
    final challenge = (decoded['challenge'] ?? '').toString();
    if (challenge.isEmpty) {
      throw Exception('Relay challenge response did not include a challenge');
    }
    Log.d(
      'Received relay challenge '
      '(url=${_summarizeUrl(url.toString())}, challenge=${_summarizeOpaque(challenge)})',
    );
    return challenge;
  }

  Future<void> verifyAttestation({
    required String relayBaseUrl,
    required String keyId,
    required String challenge,
    required String attestationObject,
  }) async {
    final url = _buildUrl(relayBaseUrl, ['attest', 'verify']);
    Log.d(
      'Sending relay attestation verification '
      '(url=${_summarizeUrl(url.toString())}, '
      'key=${_summarizeOpaque(keyId)}, '
      'challenge=${_summarizeOpaque(challenge)}, '
      'attestationObjectLen=${attestationObject.length})',
    );
    final response = await _http.post(
      url,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'key_id': keyId,
        'challenge': challenge,
        'attestation_object': attestationObject,
      }),
    );
    _logResponse(
      action: 'verify relay attestation',
      url: url,
      response: response,
    );
    _throwIfNotOk(response, 'verify relay attestation');
  }

  Future<_HubAuthorizeResponse> authorizeHub({
    required String relayBaseUrl,
    required String keyId,
    required String challenge,
    required String assertion,
    required String clientDataJson,
    required String appInstallId,
    required String hubId,
    required String deviceToken,
  }) async {
    final url = _buildUrl(relayBaseUrl, ['hub', 'authorize']);
    Log.d(
      'Sending relay hub authorization '
      '(url=${_summarizeUrl(url.toString())}, '
      'key=${_summarizeOpaque(keyId)}, '
      'challenge=${_summarizeOpaque(challenge)}, '
      'assertionLen=${assertion.length}, '
      'clientDataJsonLen=${clientDataJson.length}, '
      'appInstall=${_summarizeOpaque(appInstallId)}, '
      'hub=${_summarizeOpaque(hubId)}, '
      'deviceToken=${_summarizeOpaque(deviceToken)})',
    );
    final response = await _http.post(
      url,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'key_id': keyId,
        'challenge': challenge,
        'assertion': assertion,
        'client_data_json': clientDataJson,
        'app_install_id': appInstallId,
        'hub_id': hubId,
        'device_token': deviceToken,
      }),
    );
    _logResponse(action: 'authorize relay hub', url: url, response: response);
    _throwIfNotOk(response, 'authorize relay hub');
    final decoded = _decodeJson(response.body);
    final hubToken = (decoded['hub_token'] ?? '').toString();
    final expiresInSeconds = decoded['expires_in_seconds'];
    if (hubToken.isEmpty || expiresInSeconds is! int) {
      throw Exception('Relay authorize response is missing fields');
    }
    return _HubAuthorizeResponse(
      hubToken: hubToken,
      expiresInSeconds: expiresInSeconds,
    );
  }

  void _logResponse({
    required String action,
    required Uri url,
    required http.Response response,
  }) {
    final bodySummary =
        response.statusCode >= 200 && response.statusCode < 300
            ? 'len=${response.body.length}'
            : _summarizeBody(response.body);
    Log.d(
      'Relay response '
      '(action=$action, url=${_summarizeUrl(url.toString())}, '
      'status=${response.statusCode}, reason=${response.reasonPhrase}, '
      'body=$bodySummary)',
    );
  }

  Uri _buildUrl(String baseUrl, List<String> segments) {
    final uri = Uri.parse(baseUrl);
    final pathSegments = [
      ...uri.pathSegments.where((segment) => segment.isNotEmpty),
      ...segments,
    ];
    return uri.replace(pathSegments: pathSegments);
  }

  Map<String, dynamic> _decodeJson(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Relay response is not a JSON object');
    }
    return decoded;
  }

  void _throwIfNotOk(http.Response response, String action) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final retryAfterHeader = response.headers['retry-after'];
    final retryAfterSeconds =
        retryAfterHeader == null ? null : int.tryParse(retryAfterHeader);
    throw _RelayHttpException(
      action: action,
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase,
      body: response.body,
      retryAfter:
          retryAfterSeconds == null
              ? null
              : Duration(seconds: retryAfterSeconds),
    );
  }
}

String _summarizeOpaque(String? value) {
  if (value == null) {
    return 'null';
  }
  if (value.isEmpty) {
    return 'empty';
  }
  if (value.length <= 12) {
    return '$value(len=${value.length})';
  }
  final prefix = value.substring(0, 6);
  final suffix = value.substring(value.length - 4);
  return '$prefix...$suffix(len=${value.length})';
}

String _summarizeUrl(String value) {
  try {
    final uri = Uri.parse(value);
    final path = uri.path.isEmpty ? '/' : uri.path;
    final host = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    return '${uri.scheme}://$host$path';
  } catch (_) {
    return value;
  }
}

String _summarizeBody(String body) {
  if (body.isEmpty) {
    return 'empty';
  }
  final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= 180) {
    return normalized;
  }
  return '${normalized.substring(0, 177)}...';
}

String _describeBinding(IosRelayBinding? binding, int nowEpochMs) {
  if (binding == null) {
    return 'missing';
  }
  return 'present(expiresInMs=${binding.expiresAtEpochMs - nowEpochMs}, '
      'refreshAgeMs=${binding.refreshedAtEpochMs <= 0 ? 'unknown' : nowEpochMs - binding.refreshedAtEpochMs}, '
      'hub=${_summarizeOpaque(binding.hubId)}, '
      'appInstall=${_summarizeOpaque(binding.appInstallId)}, '
      'deviceToken=${_summarizeOpaque(binding.deviceToken)})';
}
