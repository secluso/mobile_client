//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:secluso_flutter/notifications/ios_notification_relay.dart';
import 'package:secluso_flutter/notifications/alert_preferences.dart';
import 'package:secluso_flutter/notifications/android_push_transport.dart';
import 'package:secluso_flutter/utilities/firebase_init.dart';
import 'package:secluso_flutter/notifications/heartbeat_task.dart';
import 'package:secluso_flutter/notifications/notifications.dart';
import 'package:secluso_flutter/notifications/scheduler.dart';
import 'package:secluso_flutter/notifications/thumbnails.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../keys.dart';
import '../utilities/hub_identity.dart';
//TODO: import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import '../utilities/result.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/utilities/app_coordination_state.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/utilities/version_gate.dart';
import 'package:secluso_flutter/src/rust/guard.dart';
import 'dart:io' show File, Platform;

class RustBridgeHelper {
  static Future<void> ensureInitialized() {
    Log.init();
    return RustLibGuard.initOnce();
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize the background isolate
  WidgetsFlutterBinding.ensureInitialized();
  Log.init();
  DartPluginRegistrant.ensureInitialized();
  unawaited(Log.ensureStorageReady());
  await initLocalNotifications();

  try {
    var prefs = await SharedPreferences.getInstance();

    if (prefs.containsKey(PrefKeys.serverAddr)) {
      final fcmConfig = FcmConfig.fromPrefs(prefs);
      if (fcmConfig == null) {
        Log.e("Missing cached FCM config; clearing server credentials");
        await _invalidateServerCredentials(prefs);
      } else {
        try {
          await FirebaseInit.ensure(fcmConfig);
        } catch (e, st) {
          Log.e("Firebase init failed: $e\n$st");
        }
      }
    }

    if (Platform.isAndroid) {
      await RustBridgeHelper.ensureInitialized();
    }

    await PushNotificationService.instance.processMessageData(
      message.data,
      source: 'background',
    );
  } catch (e, st) {
    Log.e("Background handler error: $e\n$st");
    await Log.saveBackgroundSnapshot(reason: 'FCM background handler error');
    await showSupportLogNotification();
  }
}

Future<void> _invalidateServerCredentials(SharedPreferences prefs) async {
  await prefs.remove(PrefKeys.serverAddr);
  await prefs.remove(PrefKeys.serverUsername);
  await prefs.remove(PrefKeys.serverPassword);
  await prefs.remove(PrefKeys.fcmConfigJson);
}

Future<void> handleEncryptedAndroidPushBytes(
  Uint8List bytes, {
  required String source,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  Log.init();
  DartPluginRegistrant.ensureInitialized();
  unawaited(Log.ensureStorageReady());
  await initLocalNotifications();
  if (Platform.isAndroid) {
    await RustBridgeHelper.ensureInitialized();
  }

  await PushNotificationService.instance.processMessageData({
    'body': base64Encode(bytes),
  }, source: source);
}

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();
  bool _initialized = false;
  Future<void>? _initFuture;
  static const Duration _initTimeout = Duration(seconds: 8);
  static const Duration _decryptTimeout = Duration(seconds: 8);
  static const Duration _decryptRetryDelay = Duration(milliseconds: 200);
  static const Duration _forceInitCooldown = Duration(seconds: 30);
  static const Duration _dedupeTtl = Duration(seconds: 60);
  static const Duration _iosSkipCooldown = Duration(seconds: 30);
  Future<void> _processTail = Future.value();
  int _processSeq = 0;
  int _processPending = 0;
  final Map<String, DateTime> _forceInitLast = {};
  final Map<String, DateTime> _recentBodies = {};
  static DateTime? _iosSkipRetryUntil;
  static String? _iosSkipReason;

  Future<bool> _cameraStillExists(SharedPreferences prefs, String cameraName) {
    return AppCoordinationState.containsCameraInSnapshotFresh(
      prefs,
      cameraName,
    );
  }

  Future<void> init() async {
    if (_initialized) {
      return;
    }
    if (_initFuture != null) {
      return _initFuture!;
    }
    _initFuture = _doInit();
    return _initFuture!;
  }

  Future<void> _doInit() async {
    try {
      Log.d("Initializing PushNotificationService");

      if (Platform.isIOS) {
        await initLocalNotifications();
        await IosNotificationRelay.instance.init(
          onPayload: (data, source) => processMessageData(data, source: source),
        );
        await IosNotificationRelay.instance.tryAuthorizeIfNeeded(false);
        _initialized = true;
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final androidTransport = AndroidPushTransport.fromPrefs(prefs);
      if (AndroidPushTransport.isUnifiedValue(androidTransport)) {
        await initLocalNotifications();
        _initialized = true;
        return;
      }

      if (!FirebaseInit.isInitialized) {
        Log.d("Skipping push setup; Firebase not initialized");
        return;
      }
      final messaging = FirebaseMessaging.instance;

      try {
        await messaging.setAutoInitEnabled(true);
        final autoInit = messaging.isAutoInitEnabled;
        Log.d("[FCM] auto-init enabled: $autoInit");
      } catch (e, st) {
        Log.e("[FCM] auto-init toggle failed: $e\n$st");
      }

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // FCM streams
      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        Log.d('onMessage');
        _handleMessage(msg);
      });

      messaging.onTokenRefresh.listen(_updateToken);

      await initLocalNotifications();

      if (Platform.isAndroid ||
          (Platform.isIOS && await messaging.getAPNSToken() != null)) {
        final tok = await messaging.getToken();
        Log.d("Set FCM token to $tok");
        if (tok != null) await _updateToken(tok);
      }
      _initialized = true;
    } finally {
      _initFuture = null;
    }
  }

  static Future<void>? _uploadFuture;

  static Future<void> tryUploadIfNeeded(bool force) async {
    if (_uploadFuture != null) {
      return _uploadFuture!;
    }
    _uploadFuture = _doUploadIfNeeded(force);
    return _uploadFuture!;
  }

  static Future<void> _doUploadIfNeeded(bool force) async {
    try {
      if (Platform.isIOS) {
        final prefs = await SharedPreferences.getInstance();
        final hubId = _iosHubId(prefs);
        if (hubId == null) {
          if (_shouldLogIosSkip(force: force, reason: 'missing_hub_id')) {
            Log.d(
              'Skipping iOS notification target upload; '
              'hub id is unavailable '
              '(cooldownMs=${_iosSkipCooldown.inMilliseconds})',
            );
          }
          return;
        }

        await IosNotificationRelay.instance.tryAuthorizeIfNeeded(force);
        final needUpload =
            prefs.getBool(PrefKeys.needUploadIosNotificationTarget) ?? true;
        final needRelayBindingUpdate =
            prefs.getBool(PrefKeys.needUpdateIosRelayBinding) ?? true;
        final relayBinding = loadStoredIosRelayBinding(prefs);
        final hasUsableRelayBinding = isStoredIosRelayBindingUsable(
          prefs: prefs,
          binding: relayBinding,
        );
        final hasServerCredentials = _hasServerCredentials(prefs);

        if (!hasServerCredentials) {
          if (_shouldLogIosSkip(
            force: force,
            reason: 'missing_server_credentials',
          )) {
            Log.d(
              'Skipping iOS notification target upload; '
              'server credentials are unavailable '
              '(cooldownMs=${_iosSkipCooldown.inMilliseconds})',
            );
          }
          return;
        }

        if (!force && !needUpload) {
          _clearIosSkipCooldown();
          return;
        }

        if (!hasUsableRelayBinding) {
          await prefs.setBool(PrefKeys.needUploadIosNotificationTarget, true);
          if (_shouldLogIosSkip(
            force: force,
            reason: 'missing_relay_binding',
          )) {
            Log.d(
              'Skipping iOS notification target upload; '
              'relay binding is unavailable '
              '(needRelayBindingUpdate=$needRelayBindingUpdate, '
              'hasBinding=${relayBinding != null}, '
              'bindingUsable=$hasUsableRelayBinding, '
              'cooldownMs=${_iosSkipCooldown.inMilliseconds})',
            );
          }
          return;
        }

        _clearIosSkipCooldown();
        final result =
            await HttpClientService.instance.uploadNotificationTarget();
        if (result.isSuccess) {
          await prefs.setBool(PrefKeys.needUploadIosNotificationTarget, false);
          Log.d('[IOS RELAY] notification target uploaded');
        } else {
          await prefs.setBool(PrefKeys.needUploadIosNotificationTarget, true);
          Log.d('[IOS RELAY] notification target upload failed');
        }
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final hasServerCredentials = _hasServerCredentials(prefs);
      final androidTransport = AndroidPushTransport.fromPrefs(prefs);
      final useUnifiedPush =
          Platform.isAndroid &&
          AndroidPushTransport.isUnifiedValue(androidTransport);

      if (useUnifiedPush) {
        if (!hasServerCredentials) {
          Log.d(
            "Skipping Android UnifiedPush upload; server credentials unavailable",
          );
          return;
        }

        final targetResult =
            await HttpClientService.instance.uploadNotificationTarget();
        if (targetResult.isSuccess) {
          Log.d('[UP] Android notification target uploaded');
        } else {
          Log.d('[UP] Android notification target upload failed');
        }
        return;
      }

      final firebaseReady = FirebaseInit.isInitialized;
      FirebaseMessaging? messaging;
      if (!firebaseReady) {
        Log.d(
          "Firebase not initialized; skipping Android FCM token work but still allowing notification target upload",
        );
      } else {
        messaging = FirebaseMessaging.instance;
      }

      var needUpdate = prefs.getBool(PrefKeys.needUpdateFcmToken) ?? false;
      var token = prefs.getString(PrefKeys.fcmToken) ?? '';

      if (firebaseReady && token.isEmpty) {
        var android = Platform.isAndroid;
        Log.d("Attempting to capture token $android");
        if (Platform.isAndroid ||
            (Platform.isIOS && await messaging!.getAPNSToken() != null)) {
          Log.d("Entered capturing area");

          final tok = await messaging!.getToken();
          Log.d("Set FCM token to $tok");
          if (tok != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(PrefKeys.fcmToken, tok);
            token = tok;
            needUpdate = true;
          }
        }
      }

      if (!hasServerCredentials) {
        Log.d("Skipping Android push upload; server credentials unavailable");
        return;
      }

      final shouldUploadFcmToken =
          firebaseReady && token.isNotEmpty && (force || needUpdate);
      if (shouldUploadFcmToken) {
        final result = await HttpClientService.instance.uploadFcmToken(token);
        if (result.isSuccess) {
          prefs.setBool(PrefKeys.needUpdateFcmToken, false);
          Log.d('[FCM] token re-uploaded');
        } else {
          prefs.setBool(PrefKeys.needUpdateFcmToken, true);
          Log.d('[FCM] token upload failed');
        }
      } else {
        Log.d("Skipping FCM token upload");
      }

      if (force || token.isNotEmpty) {
        final targetResult =
            await HttpClientService.instance.uploadNotificationTarget();
        if (targetResult.isSuccess) {
          Log.d('[FCM] Android notification target uploaded');
        } else {
          Log.d('[FCM] Android notification target upload failed');
        }
      }
    } finally {
      _uploadFuture = null;
    }
  }

  static String? _iosHubId(SharedPreferences prefs) {
    return deriveHubIdFromServerUsername(
      prefs.getString(PrefKeys.serverUsername),
    );
  }

  static bool _hasServerCredentials(SharedPreferences prefs) {
    final serverAddr = prefs.getString(PrefKeys.serverAddr);
    final username = prefs.getString(PrefKeys.serverUsername);
    final password = prefs.getString(PrefKeys.serverPassword);
    return [
      serverAddr,
      username,
      password,
    ].every((value) => value != null && value.trim().isNotEmpty);
  }

  static bool _shouldLogIosSkip({required bool force, required String reason}) {
    final now = DateTime.now();
    final retryUntil = _iosSkipRetryUntil;
    if (!force &&
        reason == _iosSkipReason &&
        retryUntil != null &&
        now.isBefore(retryUntil)) {
      return false;
    }
    _iosSkipReason = reason;
    _iosSkipRetryUntil = now.add(_iosSkipCooldown);
    return true;
  }

  static void _clearIosSkipCooldown() {
    _iosSkipRetryUntil = null;
    _iosSkipReason = null;
  }

  Future<void> _handleMessage(RemoteMessage msg) =>
      processMessageData(msg.data, source: 'foreground');

  Future<void> processMessageData(
    Map<String, dynamic> data, {
    required String source,
  }) {
    final traceId = Log.deriveContext('fcm');
    return Log.runWithContext(traceId, () async {
      Log.d("FCM context started (source=$source, id=$traceId)");
      await _enqueueProcess(data, source: source);
    });
  }

  Future<void> _enqueueProcess(
    Map<String, dynamic> data, {
    required String source,
  }) {
    final seq = ++_processSeq;
    _processPending++;
    Log.d("Enqueued message #$seq from $source (pending=$_processPending)");

    _processTail = _processTail
        .catchError((e, st) {
          Log.e("Previous processing error: $e\n$st");
        })
        .then((_) async {
          final sw = Stopwatch()..start();
          Log.d("Processing message #$seq from $source");
          try {
            await _processInternal(data, source: source, seq: seq);
          } catch (e, st) {
            Log.e("Unhandled error in message #$seq: $e\n$st");
          } finally {
            sw.stop();
            _processPending--;
            Log.d(
              "Finished message #$seq in ${sw.elapsedMilliseconds}ms (pending=$_processPending)",
            );
          }
        });

    if (_processPending > 3) {
      Log.w("Message backlog detected: pending=$_processPending");
    }

    return _processTail;
  }

  int _motionNotifId(String cameraName, String timestamp) {
    // deterministic id
    final ts = int.tryParse(timestamp) ?? 0;
    return cameraName.hashCode ^ ts;
  }

  // Core notification processing method
  Future<void> _processInternal(
    Map<String, dynamic> data, {
    required String source,
    required int seq,
  }) async {
    Log.d("Core processing entered (#$seq, source=$source)");
    final encoded = data['body'];
    if (encoded is! String || encoded.isEmpty) {
      Log.w(
        "Missing or invalid body for message #$seq (keys=${data.keys.toList()})",
      );
      return;
    }

    if (_isDuplicateBody(encoded)) {
      Log.d("Skipping duplicate body for message #$seq");
      return;
    }

    Log.d("Got a message");
    Log.d("Body length: ${encoded.length}");

    final prefs = await SharedPreferences.getInstance();
    //  await WakelockPlus.enable(); // TODO: Make this optional depending on if it's called from background processing

    try {
      final Uint8List bytes = base64Decode(encoded);
      final List<String> cameraSet = await AppCoordinationState.getCameraSet();

      Log.d("Pre-existing camera set: $cameraSet");
      if (cameraSet.isEmpty) {
        Log.w("No cameras found for message #$seq");
        return;
      }
      // TODO: what happens if we have an invalid name?
      for (final cameraName in cameraSet) {
        if (!await _cameraStillExists(prefs, cameraName)) {
          Log.d(
            "[FCM] Camera deleted before processing $cameraName; skipping.",
          );
          continue;
        }
        // This code might be called after the app is killed/terminated. We need to initialize the cameras again.
        final initOutcome = await initialize(cameraName, timeout: _initTimeout);
        if (!initOutcome.isOk) {
          // Avoid error-level logs for expected init timeouts when background
          // work is already holding the MLS locks; only true failures should
          // surface as errors.
          if (initOutcome == InitOutcome.timeout) {
            Log.w(
              "Init timeout for $cameraName; skipping message #$seq (${Log.ownerTag()})",
            );
          } else {
            Log.e("Init failed for $cameraName; skipping message #$seq");
          }
          continue;
        }
        Log.d("Starting to iterate $cameraName");
        String response;
        try {
          response = await decryptMessage(
            clientTag: "fcm",
            cameraName: cameraName,
            data: bytes,
          ).timeout(_decryptTimeout);
        } on TimeoutException {
          Log.e(
            "[FCM] decryptMessage timeout for $cameraName after ${_decryptTimeout.inSeconds}s (${Log.ownerTag()})",
          );
          await Future.delayed(_decryptRetryDelay);
          try {
            response = await decryptMessage(
              clientTag: "fcm",
              cameraName: cameraName,
              data: bytes,
            ).timeout(_decryptTimeout);
          } on TimeoutException {
            Log.e(
              "[FCM] decryptMessage retry timeout for $cameraName after ${_decryptTimeout.inSeconds}s (${Log.ownerTag()})",
            );
            continue;
          }
        }

        if (response.startsWith('Error')) {
          if (response.startsWith('Error: Busy')) {
            Log.w(
              "[FCM] decryptMessage busy for $cameraName; skipping message #$seq",
            );
            continue;
          }
          if (response.contains('SecretReuseError')) {
            Log.w(
              "[FCM] SecretReuseError for $cameraName; treating as duplicate message",
            );
            continue;
          }
          final now = DateTime.now();
          final lastAttempt = _forceInitLast[cameraName];
          final allowForce =
              lastAttempt == null ||
              now.difference(lastAttempt) >= _forceInitCooldown;
          if (allowForce) {
            _forceInitLast[cameraName] = now;
            Log.w("[FCM] Decrypt error; forcing init for $cameraName");
            if (!await _cameraStillExists(prefs, cameraName)) {
              Log.d(
                "[FCM] Camera deleted before forced init for $cameraName; skipping.",
              );
              continue;
            }
            final forceOutcome = await initialize(
              cameraName,
              timeout: _initTimeout,
              force: true,
            );
            if (forceOutcome.isOk) {
              try {
                response = await decryptMessage(
                  clientTag: "fcm",
                  cameraName: cameraName,
                  data: bytes,
                ).timeout(_decryptTimeout);
              } on TimeoutException {
                Log.e(
                  "[FCM] decryptMessage timeout after forced init for $cameraName (${Log.ownerTag()})",
                );
                continue;
              }
            }
          } else {
            Log.w(
              "[FCM] Skipping forced init for $cameraName (cooldown active)",
            );
          }
        }

        Log.d("Decoded response is: $response");
        try {
          final decodedJson = jsonDecode(response) as Map<String, dynamic>;
          if (decodedJson.containsKey("type")) {
            // TODO: This was made for future use cases.
          } else {
            Log.e("Error: JSON FCM message didn't contain type key");
          }
        } catch (_) {
          // TODO: What if logic from above failed for reasons other than jsonDecode?
          if (!await _cameraStillExists(prefs, cameraName)) {
            Log.d(
              "[FCM] Camera deleted before handling response for $cameraName; skipping.",
            );
            continue;
          }
          if (response == 'Download') {
            Log.d("Downloading video");
            final bool allowCellular = true;

            final statuses = await Connectivity().checkConnectivity();
            final bool isMetered = statuses.contains(ConnectivityResult.mobile);
            final bool isRestricted = false;

            if (!isMetered || (allowCellular && !isRestricted)) {
              unawaited(
                DownloadScheduler.scheduleVideoDownload(cameraName),
              ); // Don't await, as the lock may freeze this up
            }

            await prefs.setBool(
              PrefKeys.recordingMotionVideosPrefix + cameraName,
              false,
            ); // Allow livestreaming.
            await prefs.setInt(
              PrefKeys.lastRecordingTimestampPrefix + cameraName,
              0,
            );
          } else if (!response.startsWith('Error') && response != 'None') {
            final shouldShowProvisional = shouldShowProvisionalMotionAlert(
              prefs,
              cameraName,
            );
            final notifId = _motionNotifId(cameraName, response);
            final cameraStillExists = await _cameraStillExists(
              prefs,
              cameraName,
            );
            if (shouldShowProvisional && cameraStillExists) {
              showMotionNotification(
                cameraName: cameraName,
                timestamp: response,
                notificationId: notifId,
                onlyAlertOnce: false,
                alertLabel: 'Motion',
              );
            } else if (!await _cameraStillExists(prefs, cameraName)) {
              Log.d(
                "[FCM] Camera deleted before motion notification for $cameraName; skipping.",
              );
            } else {
              Log.d("Not showing motion notification due to preference");
            }

            // Even if preferences are set to not show notifications, we should
            // still donwload the thumbnail as it will be used in the video list
            // in the app too.
            if (cameraStillExists) {
              unawaited(_tryAttachThumbLater(cameraName, response, notifId));
            }

            final nowTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            await prefs.setBool(
              PrefKeys.recordingMotionVideosPrefix + cameraName,
              true,
            ); // Restrict livestreaming.
            await prefs.setInt(
              PrefKeys.lastRecordingTimestampPrefix + cameraName,
              nowTimestamp,
            );

            // TODO: I removed the pending to repository addition for Android because it's not possible to init ObjectBox in the background handler (as Android requires). Find alternate solution maybe. Not sure this is needed anymore (as we don't want to show users pending videos in cases of failure)
            if (Platform.isIOS) {
              if (!await _cameraStillExists(prefs, cameraName)) {
                Log.d(
                  "[FCM] Camera deleted before iOS pending add for $cameraName; skipping.",
                );
                continue;
              }
              await addPendingToRepository(cameraName, response);
              unawaited(DownloadScheduler.scheduleVideoDownload(cameraName));
            }

            // Prevent back-to-back notifications
            await Future.delayed(const Duration(seconds: 10));
            if (!await _cameraStillExists(prefs, cameraName)) {
              Log.d(
                "[FCM] Camera deleted before status refresh for $cameraName; skipping.",
              );
              continue;
            }
            updateCameraStatusFcmNotification(response, cameraName);
          } else {
            Log.d("[FCM] No-op response for $cameraName: $response");
          }
        }
      }
    } on FormatException catch (e, st) {
      Log.e("[FCM] Base64 decode failed: $e\n$st");
    } finally {
      Log.d("After processing");
      // await WakelockPlus.disable(); TODO: Fix above wakelock depending on foreground or not
    }
  }

  bool _isDuplicateBody(String body) {
    final now = DateTime.now();
    _recentBodies.removeWhere((_, ts) => now.difference(ts) > _dedupeTtl);
    if (_recentBodies.containsKey(body)) {
      return true;
    }
    _recentBodies[body] = now;
    return false;
  }

  Future<void> _tryAttachThumbLater(
    String cameraName,
    String timestamp,
    int notifId, {
    Duration timeout = const Duration(seconds: 10),
    Duration pollEvery = const Duration(milliseconds: 300),
  }) async {
    if (VersionGate.isBlocked) {
      await HttpClientService.instance.potentiallySendBackgroundNotification();
      Log.d(
        "Skipping thumbnail attachment because version gate is active (${Log.ownerTag()})",
      );
      return;
    }
    final deadline = DateTime.now().add(timeout);
    final prefs = await SharedPreferences.getInstance();

    while (DateTime.now().isBefore(deadline)) {
      if (VersionGate.isBlocked) {
        await HttpClientService.instance
            .potentiallySendBackgroundNotification();
        Log.d(
          "Aborting thumbnail attachment because version gate is active (${Log.ownerTag()})",
        );
        return;
      }
      if (!await _cameraStillExists(prefs, cameraName)) {
        Log.d(
          "[FCM] Camera deleted before thumbnail attachment for $cameraName; aborting.",
        );
        return;
      }
      final hasThumb = await ThumbnailManager.checkThumbnailsForCamera(
        cameraName,
        timestamp,
      );
      if (hasThumb) {
        Log.d(
          "Acquired target thumbnail for notification, attempting to update",
        );

        final docs = await AppPaths.dataDirectory();
        final cameraDir = await AppPaths.cameraDirectory(cameraName);
        final thumbPath = '${cameraDir.path}/videos/thumbnail_$timestamp.png';

        try {
          final bytes = await File(thumbPath).readAsBytes();
          await decodeImageFromList(bytes);
        } catch (e) {
          Log.e("Invalid notification thumbnail $thumbPath: $e");
          await Future.delayed(pollEvery);
          continue;
        }

        // Get the detected event from the metadata file
        final metaPath = '${docs.path}/waiting/meta/meta_$timestamp.txt';

        List<String> detections = [];

        try {
          final raw = await File(metaPath).readAsString();
          if (raw.trim().isNotEmpty) {
            detections = (jsonDecode(raw) as List).cast<String>();
          }
        } catch (e) {
          Log.w('Could not read notification metadata $metaPath: $e');
        }

        final decision = evaluateMotionAlertPreferences(
          prefs,
          cameraName,
          motion: true,
          detections: detections,
        );

        if (decision.shouldShow) {
          var upgradedNotifId = notifId;
          if (Platform.isIOS) {
            // Reposting over an already delivered notification doesn't seem to work on newer iOS builds
            // So we now replace it by revoking the old notification and sending a new one
            await cancelMotionNotification(
              cameraName: cameraName,
              timestamp: timestamp,
            );
            upgradedNotifId = upgradedMotionNotificationId(
              cameraName,
              timestamp,
            );
          }

          // Update same notification id with a BigPicture version (on Android).
          // Repost as a fresh notification on iOS so the attachment is now rendered
          String alertLabel = decision.label ?? 'Motion';
          await showMotionNotification(
            cameraName: cameraName,
            timestamp: timestamp,
            thumbnailPath: thumbPath,
            notificationId: upgradedNotifId,
            onlyAlertOnce: true, // don't vibrate/sound again on Android
            alertLabel: alertLabel,
          );
          Log.d("Upgraded motion notification with thumbnail: $thumbPath");
        }

        return;
      }
      await Future.delayed(pollEvery);
    }

    Log.d(
      "Thumbnail not ready within timeout; leaving text-only notification (${Log.ownerTag()})",
    );
  }

  Future<void> addPendingToRepository(
    String cameraName,
    String timestamp,
  ) async {
    final videoName = 'video_$timestamp.mp4';
    final existing = await AppStores.instance.videoStore.hasVideo(
      cameraName,
      videoName,
    );

    if (existing) {
      return;
    }

    var video = Video(cameraName, videoName, false, true);
    await AppStores.instance.videoStore.put(video);
  }

  // TODO: Consider combining this with _tryUploadIfNeeded... although this mainly functions as a callback
  Future<void> _updateToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.fcmToken, token);

    Log.d('[FCM] token re‑uploaded');
    Result<void> result = await HttpClientService.instance.uploadFcmToken(
      token,
    );

    await prefs.setBool(PrefKeys.needUpdateFcmToken, result.isFailure);
  }
}
