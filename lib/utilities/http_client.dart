//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/android_push_transport.dart';
import 'package:secluso_flutter/notifications/epoch.dart';
import 'package:secluso_flutter/notifications/ios_notification_relay.dart';
import 'package:secluso_flutter/notifications/notifications.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/utilities/enterprise_session.dart';
import 'package:secluso_flutter/utilities/object_name.dart';
import 'package:secluso_flutter/utilities/server_backend.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/utilities/app_coordination_state.dart';
import 'package:secluso_flutter/utilities/http_entities.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/utilities/version_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'result.dart';
import 'logger.dart';

// Entity used to return from download()
class DownloadResult {
  final bool not_found;
  final File? file;
  final Uint8List? data;

  DownloadResult({this.not_found = false, this.file, this.data});
}

class SilentException implements Exception {
  final String message;
  SilentException(this.message);
  @override
  String toString() => message;
}

class FcmConfig {
  final String api_key_ios;
  final String api_key_android;
  final String app_id_ios;
  final String app_id_android;
  final String messaging_sender_id;
  final String project_id;
  final String storage_bucket;
  final String bundle_id;

  FcmConfig({
    required this.api_key_ios,
    required this.api_key_android,
    required this.app_id_ios,
    required this.app_id_android,
    required this.messaging_sender_id,
    required this.project_id,
    required this.storage_bucket,
    required this.bundle_id,
  });

  static String? _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  static String _requireString(Map<String, dynamic> json, String key) {
    final primary = _readString(json, key);
    if (primary != null) {
      return primary;
    }
    throw Exception('Missing $key in FCM config');
  }

  factory FcmConfig.fromJson(Map<String, dynamic> json) {
    return FcmConfig(
      api_key_ios: _requireString(json, 'api_key_ios'),
      api_key_android: _requireString(json, 'api_key_android'),
      app_id_ios: _requireString(json, 'app_id_ios'),
      app_id_android: _requireString(json, 'app_id_android'),
      messaging_sender_id: _requireString(json, 'messaging_sender_id'),
      project_id: _requireString(json, 'project_id'),
      storage_bucket: _requireString(json, 'storage_bucket'),
      bundle_id: _requireString(json, 'bundle_id'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'api_key_ios': api_key_ios,
      'api_key_android': api_key_android,
      'app_id_ios': app_id_ios,
      'app_id_android': app_id_android,
      'messaging_sender_id': messaging_sender_id,
      'project_id': project_id,
      'storage_bucket': storage_bucket,
      'bundle_id': bundle_id,
    };
  }

  static FcmConfig? fromPrefs(SharedPreferences prefs) {
    final cached = prefs.getString(PrefKeys.fcmConfigJson);
    if (cached == null || cached.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(cached);
      if (decoded is! Map<String, dynamic>) {
        Log.e("Invalid cached FCM config format");
        return null;
      }
      return FcmConfig.fromJson(decoded);
    } catch (e, st) {
      Log.e("Failed to parse cached FCM config: $e\n$st");
      return null;
    }
  }
}

class HttpClientService {
  // Some of these constants are based on the ones in server/main.rs.
  static const int maxMotionFileSize = 50 * 1024 * 1024; // 50 mebibytes
  static const int maxLivestreamFileSize = 20 * 1024 * 1024; // 20 mebibytes
  static const int maxCommandFileSize = 100 * 1024; // 100 kibibytes
  static const int maxFcmConfigSize = 10 * 1024; // 10 kibibytes
  static const int maxServerVersionSize = 10 * 1024; // 10 kibibytes
  static const int maxAddAppRequestSize = 100 * 1024; // 100 kibibytes

  HttpClientService._();
  static final HttpClientService instance = HttpClientService._();
  Future<void>? _versionCheckInFlight;
  bool _versionMatchConfirmed = false;

  /// Bearer tokens... when talking to the enterprise delivery service.
  final EnterpriseSession _enterpriseSession = EnterpriseSession();
  static final Future<String> _versionFuture = rustLibVersion();
  static const Duration _groupNameInitCooldown = Duration(seconds: 30);
  static const Duration _groupNameInitTimeout = Duration(seconds: 8);
  final Map<String, DateTime> _groupNameInitLast = {};
  final Map<String, String> _groupNameCache = {};

  // The session id for a livestream is stored in memory, keyed by the group name. It is not persisted across app restarts.
  final Map<String, String> _livestreamSessions = {};
  final http.Client _client = http.Client();

  /// cameraName -> subscription uuid
  final Map<String, String> _cameraSubUuid = {};

  /// The subscription a request should bill against
  Future<String?> _subscriptionUuidFor(String? cameraName) async {
    if (cameraName != null && cameraName.isNotEmpty) {
      var uuid = _cameraSubUuid[cameraName];
      if (uuid == null) {
        try {
          uuid = await subscriptionUuidFor(cameraName: cameraName);
        } catch (_) {
          uuid = '';
        }
        _cameraSubUuid[cameraName] = uuid;
      }
      if (uuid.isNotEmpty) {
        return uuid;
      }
    }

    final fallback = (await _pref(PrefKeys.subscriptionUuid))?.trim();
    return (fallback == null || fallback.isEmpty) ? null : fallback;
  }

  void clearSubscriptionUuidCache(String cameraName) {
    _cameraSubUuid.remove(cameraName);
  }

  Future<http.Response> _cappedGetResponse(
    Uri url, {
    required Map<String, String> headers,
    required int maxBytes,
    Duration? timeout,
  }) async {
    final request = http.Request('GET', url);
    request.headers.addAll(headers);

    Future<http.StreamedResponse> future = _client.send(request);
    final streamed =
        timeout == null ? await future : await future.timeout(timeout);

    // Early reject if the server tells us the size.
    final contentLength = streamed.contentLength;
    if (contentLength != null && contentLength > maxBytes) {
      throw Exception(
        'Response too large: $contentLength bytes exceeds cap of $maxBytes',
      );
    }

    final chunks = <int>[];
    var received = 0;

    await for (final chunk in streamed.stream) {
      received += chunk.length;
      if (received > maxBytes) {
        throw Exception(
          'Response exceeded cap of $maxBytes bytes while downloading',
        );
      }
      chunks.addAll(chunk);
    }

    return http.Response.bytes(
      Uint8List.fromList(chunks),
      streamed.statusCode,
      headers: streamed.headers,
      request: streamed.request,
      reasonPhrase: streamed.reasonPhrase,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
    );
  }

  void clearGroupNameCache(String cameraName) {
    _groupNameCache.removeWhere((key, _) => key.startsWith('$cameraName|'));
  }

  void clearAllGroupNameCache() {
    _groupNameCache.clear();
  }

  void resetVersionGateState() {
    _versionCheckInFlight = null;
    _versionMatchConfirmed = false;
  }

  /// bulk check the list of camera names against the server to check for updates
  /// returns list of corresponding cameras that have available videos/thumbnails for download
  /// Parameter minimumTime: The minimum amount of time the resource has been on the server to qualify for the list
  Future<Result<List<String>>> bulkCheckAvailableCameras(
    int minimumTime,
  ) => _wrap(() async {
    final cameraNames = await AppCoordinationState.getCameraSet();
    if (cameraNames.isEmpty) {
      return [];
    }

    final creds = await _getValidatedCredentials();

    var associatedNameToGroup = {};
    List<MotionPair> convertedCameraList = [];
    for (final cameraName in cameraNames) {
      final motionGroup = await _groupName(cameraName, Group.motion);
      if (motionGroup.startsWith("Error")) {
        continue;
      }

      final int epoch = await readEpoch(cameraName, "video");

      // The enterprise service looks objects up by their hashed name
      String? filename;
      if (creds.backend.isEnterprise) {
        filename = await ObjectName.forEpoch(
          cameraName: cameraName,
          groupName: motionGroup,
          epoch: epoch,
        );
      }

      convertedCameraList.add(
        MotionPair(motionGroup, epoch, filename: filename),
      );
      associatedNameToGroup[motionGroup] = cameraName;
    }
    Log.d("Association map: $associatedNameToGroup");

    // One camera, one subscription
    final pairsBySub = <String?, List<MotionPair>>{};
    final representativeCamera = <String?, String>{};
    for (final pair in convertedCameraList) {
      final cameraName = associatedNameToGroup[pair.groupName] as String;
      final subUuid =
          creds.backend.isEnterprise
              ? await _subscriptionUuidFor(cameraName)
              : null;
      pairsBySub.putIfAbsent(subUuid, () => []).add(pair);
      representativeCamera[subUuid] = cameraName;
    }

    final url = _buildUrl(creds.serverAddr, ['bulkCheck']);
    final List<dynamic> decoded = [];
    for (final entry in pairsBySub.entries) {
      final jsonContent = jsonEncode(MotionPairs(entry.value));
      Log.d("JSON content: $jsonContent");
      final headers = await _basicAuthHeaders(
        creds.username,
        creds.password,
        jsonContent: true,
        cameraName: representativeCamera[entry.key],
      );

      // Bulk check fetch action
      final response = await http.post(
        url,
        headers: headers,
        body: jsonContent,
      );
      await _handleServerVersionHeader(response);
      final responseBody =
          response
              .body; // Format is comma separated strings representing the associated motion groups
      Log.d("Server response: $responseBody");

      decoded.addAll(jsonDecode(responseBody) as List<dynamic>);
    }
    final List<String> convertedToGroups = [];
    final now =
        DateTime.now().millisecondsSinceEpoch ~/
        1000; // current UNIX time in seconds

    for (final item in decoded) {
      final groupName = item['group_name'] as String;
      final timestamp = item['timestamp'] as int;

      final age = now - timestamp;
      Log.d("Iterating $groupName with ts $timestamp (age=$age)");

      if (age >= minimumTime && associatedNameToGroup.containsKey(groupName)) {
        convertedToGroups.add(associatedNameToGroup[groupName]);
      }
    }
    return convertedToGroups;
  });

  Future<Result<String>> fetchServerVersion() =>
      _wrap(() async => _fetchServerVersionRaw(), bypassVersionGate: true);

  /// POST /pair, waits for camera to join pairing
  Future<Result<String>> waitForPairingStatus({
    required String pairingToken,
  }) => _wrap(() async {
    final url = _buildUrl((await _getValidatedCredentials()).serverAddr, [
      'pair',
    ]);
    final headers = await _basicAuthHeaders(
      (await _getValidatedCredentials()).username,
      (await _getValidatedCredentials()).password,
      jsonContent: true,
    );

    final notificationTarget = await _buildNotificationTargetPayload();
    final request = PairingRequest(
      pairingToken,
      'phone',
      notificationTarget: notificationTarget,
    );
    final body = jsonEncode(request);

    Log.d("Pairing body: $body");

    final response = await http.post(url, headers: headers, body: body);
    await _handleServerVersionHeader(response);

    Log.d("Response code: ${response.statusCode}");

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to check pairing status: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(response.body);
    Log.d("Pairing response: $decoded");
    final status = decoded['status'] as String?;
    if (status == null) throw Exception('Missing status in response');

    return status;
  });

  Future<NotificationTarget> _buildNotificationTargetPayload() async {
    final prefs = await SharedPreferences.getInstance();

    if (Platform.isIOS) {
      final binding = loadStoredIosRelayBinding(prefs);
      if (!isStoredIosRelayBindingUsable(prefs: prefs, binding: binding)) {
        return NotificationTarget(platform: 'ios');
      }
      return NotificationTarget(
        platform: 'ios',
        iosRelayBinding: IosRelayBindingPayload(
          relayBaseUrl: binding!.relayBaseUrl,
          hubToken: binding.hubToken,
          appInstallId: binding.appInstallId,
          hubId: binding.hubId,
          deviceToken: binding.deviceToken,
          expiresAtEpochMs: binding.expiresAtEpochMs,
          refreshedAtEpochMs: binding.refreshedAtEpochMs,
        ),
      );
    }

    final androidPushPlatform = AndroidPushTransport.fromPrefs(prefs);
    if (AndroidPushTransport.isUnifiedValue(androidPushPlatform)) {
      return NotificationTarget(
        platform: AndroidPushTransport.unified,
        unifiedpushEndpointUrl: prefs.getString(
          PrefKeys.unifiedPushEndpointUrl,
        ),
        unifiedpushPubKey: prefs.getString(PrefKeys.unifiedPushPubKey),
        unifiedpushAuth: prefs.getString(PrefKeys.unifiedPushAuth),
      );
    }

    return NotificationTarget(platform: AndroidPushTransport.fcm);
  }

  Future<void> uploadSettings(
    String cameraName,
    ClientSettingsMessage message,
  ) => _wrap(() async {
    final creds = await _getValidatedCredentials();
    final configGroup = await _groupName(cameraName, Group.config);

    var jsonContent = jsonEncode(message);
    var encodedContent = utf8.encode(jsonContent);
    var encryptedMessage = await encryptSettingsMessage(
      cameraName: cameraName,
      data: encodedContent,
    );
    final url = _buildUrl(creds.serverAddr, [configGroup, 'app']);
    final headers = await _basicAuthHeaders(creds.username, creds.password);

    final response = await http.post(
      url,
      headers: headers,
      body: encryptedMessage,
    );
    await _handleServerVersionHeader(response);
    return response;
  });

  /// Downloads fcm config
  ///
  /// `backend` is for callers validating credentials that aren't saved yet
  Future<Result<FcmConfig>> fetchFcmConfigWithCredentials({
    required String serverAddr,
    required String username,
    required String password,
    ServerBackend? backend,
  }) => _wrap(() async {
    Log.d("Fetching fcm config from server");

    final url = _buildUrl(serverAddr, ['fcm_config']);
    final headers = await _basicAuthHeaders(
      username,
      password,
      serverAddr: serverAddr,
      backend: backend,
    );

    // Fetch fcm config action
    final response = await _cappedGetResponse(
      url,
      headers: headers,
      maxBytes: maxFcmConfigSize,
    );
    await _handleServerVersionHeader(response);
    if (response.statusCode != 200) {
      if (response.statusCode == 404) {
        throw SilentException(
          'Failed to fetch fcm config: ${response.statusCode} ${response.reasonPhrase}',
        );
      } else {
        throw Exception(
          'Failed to fetch fcm config: ${response.statusCode} ${response.reasonPhrase}',
        );
      }
    }

    Log.d("Success fetching fcm config (bytes=${response.body.length})");
    return FcmConfig.fromJson(jsonDecode(response.body));
  }, bypassVersionGate: true);

  Future<Result<FcmConfig>> fetchFcmConfig() async {
    final creds = await _getValidatedCredentials();
    return fetchFcmConfigWithCredentials(
      serverAddr: creds.serverAddr,
      username: creds.username,
      password: creds.password,
    );
  }

  /// Downloads file and saves as [fileName]
  Future<Result<DownloadResult>> download({
    String? destinationFile,
    required String cameraName,
    required String type, // As dictated in constants.dart
    required String serverFile, // This is epoch in motion
    Duration? timeout,
  }) => _wrap(() async {
    final creds = await _getValidatedCredentials();
    final group = await _groupName(cameraName, type);
    Log.d(
      "Camera Name: $cameraName, Group Type: $type, Group: $group, Server File: $serverFile",
    );
    final url = _buildUrl(creds.serverAddr, [group, serverFile]);
    final headers = await _basicAuthHeaders(
      creds.username,
      creds.password,
      cameraName: cameraName,
    );

    // Video download action
    final Future<http.Response> responseFuture = _cappedGetResponse(
      url,
      headers: headers,
      maxBytes: maxMotionFileSize,
    );
    final http.Response response;
    try {
      response =
          timeout == null
              ? await responseFuture
              : await responseFuture.timeout(timeout);
    } on TimeoutException {
      throw Exception(
        'Download timeout after ${timeout?.inSeconds ?? 0}s ($cameraName, $type, $serverFile, ${Log.ownerTag()})',
      );
    }
    await _handleServerVersionHeader(response);
    if (response.statusCode != 200) {
      if (response.statusCode == 404) {
        return DownloadResult(not_found: true);
      } else {
        throw Exception(
          'Failed to download file: ${response.statusCode} ${response.reasonPhrase}',
        );
      }
    }

    File? file;
    if (destinationFile != null) {
      final dir = await _ensureEncryptedDir(cameraName);
      file = File('${dir.path}/$destinationFile');
      if (await file.exists()) {
        Log.d("File name $destinationFile existed already");
        await file.delete();
      }
      await file.writeAsBytes(response.bodyBytes);
    }

    Log.d("Success downloading $serverFile for camera $cameraName");
    if (destinationFile == null) {
      return DownloadResult(data: response.bodyBytes);
    } else {
      return DownloadResult(file: file);
    }
  });

  /// Deletes file at URL
  Future<Result<void>> delete({
    String? destinationFile,
    required String cameraName,
    required String type, // As dictated in constants.dart
    required String serverFile, // This is epoch in motion
  }) => _wrap(() async {
    final creds = await _getValidatedCredentials();
    final group = await _groupName(cameraName, type);
    Log.d(
      "Camera Name: $cameraName, Group Type: $type, Group: $group, Server File: $serverFile",
    );
    final url = _buildUrl(creds.serverAddr, [group, serverFile]);
    final headers = await _basicAuthHeaders(
      creds.username,
      creds.password,
      cameraName: cameraName,
    );

    // Delete action TODO: Should we retry if fail?
    final delResponse = await http.delete(url, headers: headers);
    await _handleServerVersionHeader(delResponse);
    if (delResponse.statusCode != 200) {
      if (delResponse.statusCode == 404) {
        throw SilentException(
          'Failed to delete video from server: ${delResponse.statusCode} ${delResponse.reasonPhrase}',
        );
      } else {
        throw Exception(
          'Failed to delete video from server: ${delResponse.statusCode} ${delResponse.reasonPhrase}',
        );
      }
    }
    Log.d("Successfully deleted $serverFile from server");
  });

  /// POST /fcm_token
  Future<Result<void>> uploadFcmToken(String token) => _wrap(() async {
    final creds = await _getValidatedCredentials();

    final url = _buildUrl(creds.serverAddr, ['fcm_token']);

    // Token rows are subscription-scoped
    for (final cameraName in await _notificationCameraScopes(creds)) {
      final headers = await _basicAuthHeaders(
        creds.username,
        creds.password,
        cameraName: cameraName,
      );

      final response = await http.post(url, headers: headers, body: token);
      await _handleServerVersionHeader(response);

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to send data: ${response.statusCode} ${response.reasonPhrase}',
        );
      } else {
        Log.d("Successfully sent data");
      }
    }
  });

  Future<List<String?>> _notificationCameraScopes(
    ({
      String serverAddr,
      String username,
      String password,
      ServerBackend backend,
    })
    creds,
  ) async {
    if (!creds.backend.isEnterprise) {
      return const [null];
    }

    final seen = <String?>{};
    final scopes = <String?>[];
    for (final cameraName in await AppCoordinationState.getCameraSet()) {
      final subUuid = await _subscriptionUuidFor(cameraName);
      if (seen.add(subUuid)) {
        scopes.add(cameraName);
      }
    }

    return scopes.isEmpty ? const [null] : scopes;
  }

  /// POST /notification_target
  Future<Result<void>> uploadNotificationTarget() => _wrap(() async {
    final creds = await _getValidatedCredentials();
    final target = await _buildNotificationTargetPayload();

    final url = _buildUrl(creds.serverAddr, ['notification_target']);
    Log.d(
      'Uploading notification target '
      '(url=$url, platform=${target.platform}, '
      'hasIosRelayBinding=${target.iosRelayBinding != null})',
    );

    // Target rows are subscription-scoped, same as FCM tokens above.
    for (final cameraName in await _notificationCameraScopes(creds)) {
      final headers = await _basicAuthHeaders(
        creds.username,
        creds.password,
        jsonContent: true,
        cameraName: cameraName,
      );

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(target),
      );
      await _handleServerVersionHeader(response);

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to upload notification target: '
          '${response.statusCode} ${response.reasonPhrase} ${response.body}',
        );
      }
    }
  });

  /// POST /livestream/<group>
  Future<Result<void>> livestreamStart(String cameraName) => _wrap(() async {
    final creds = await _getValidatedCredentials();

    final group = await _groupName(cameraName, Group.livestream);
    final url = _buildUrl(creds.serverAddr, ['livestream', group]);
    final headers = await _basicAuthHeaders(
      creds.username,
      creds.password,
      cameraName: cameraName,
    );

    final response = await http.post(url, headers: headers);
    await _handleServerVersionHeader(response);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to send data: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    // If the server is enterprise, it will return a session id in the response body. We store that in memory for later use when retrieving chunks.
    if ((await _backend()).isEnterprise) {
      final session = _sessionFromStatusBody(response.body);
      if (session != null) {
        _livestreamSessions[group] = session;
      }
    }
  });

  /// GET /livestream/<group>/<chunkNumber> then deletes the file
  /// using /<group>/<chunkNumber>
  Future<Result<Uint8List>> livestreamRetrieve({
    required String cameraName,
    required int chunkNumber,
  }) => _wrap(() async {
    final creds = await _getValidatedCredentials();

    final group = await _groupName(cameraName, Group.livestream);
    final url = _buildUrl(creds.serverAddr, ['livestream', group, chunkNumber]);
    final headers = await _basicAuthHeaders(
      creds.username,
      creds.password,
      cameraName: cameraName,
    );

    final enterprise = (await _backend()).isEnterprise;
    if (enterprise) {
      final session = await _livestreamSession(
        creds.serverAddr,
        group,
        headers,
      );
      if (session == null) {
        throw SilentException('No active livestream session for $group');
      }
      headers['X-Livestream-Session'] = session;
    }

    final response = await _cappedGetResponse(
      url,
      headers: headers,
      maxBytes: maxLivestreamFileSize,
    );
    await _handleServerVersionHeader(response);
    if (response.statusCode != 200) {
      final message =
          'Failed to fetch data: ${response.statusCode} ${response.reasonPhrase}';
      if (response.statusCode == 404) {
        // A missing next chunk is a normal livestream pause/end condition.
        throw SilentException(message);
      }
      throw Exception(message);
    }

    // Delete action.
    if (!enterprise) {
      final delUrl = _buildUrl(creds.serverAddr, [group, chunkNumber]);
      final delResponse = await http.delete(delUrl, headers: headers);
      await _handleServerVersionHeader(delResponse);
      if (delResponse.statusCode != 200) {
        throw Exception(
          'Failed to delete video from server: ${delResponse.statusCode} ${delResponse.reasonPhrase}',
        );
      }
    }

    return response.bodyBytes;
  });

  /// GET /livestream/<group> to retrieve the session id for an enterprise livestream
  Future<String?> _livestreamSession(
    String serverAddr,
    String group,
    Map<String, String> headers,
  ) async {
    final cached = _livestreamSessions[group];
    if (cached != null) {
      return cached;
    }

    final url = _buildUrl(serverAddr, ['livestream', group]);
    final response = await http.get(url, headers: headers);
    if (response.statusCode != 200) {
      return null;
    }

    final session = _sessionFromStatusBody(response.body);
    if (session != null) {
      _livestreamSessions[group] = session;
    }
    return session;
  }

  String? _sessionFromStatusBody(String body) {
    try {
      final decoded = jsonDecode(body);
      final session = decoded is Map ? decoded['session'] : null;
      return session is String && session.isNotEmpty ? session : null;
    } catch (_) {
      return null;
    }
  }

  /// POST /livestream_end/<group>
  Future<Result<void>> livestreamEnd(String cameraName) => _wrap(() async {
    final creds = await _getValidatedCredentials();
    final group = await _groupName(cameraName, Group.livestream);
    _livestreamSessions.remove(group);
    final url = _buildUrl(creds.serverAddr, ['livestream_end', group]);
    final headers = await _basicAuthHeaders(
      creds.username,
      creds.password,
      cameraName: cameraName,
    );

    final response = await http.post(url, headers: headers);
    await _handleServerVersionHeader(response);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to send data: ${response.statusCode} ${response.reasonPhrase}',
      );
    }
  });

  /// POST /config/<group>
  Future<Result<void>> configCommand({
    required String cameraName,
    required Uint8List command,
  }) => _wrap(() async {
    final creds = await _getValidatedCredentials();
    final group = await _groupName(cameraName, Group.config);
    final url = _buildUrl(creds.serverAddr, ['config', group]);

    if (command.isEmpty) {
      throw Exception('Error: empty config command');
    }

    final headers = await _basicAuthHeaders(
      creds.username,
      creds.password,
      cameraName: cameraName,
    );
    headers['X-Command-Size'] = command.length.toString();

    final response = await http.post(url, headers: headers, body: command);

    await _handleServerVersionHeader(response);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to send config command: ${response.statusCode} '
        '${response.reasonPhrase}: ${response.body}',
      );
    }

    Log.d("Successfully sent config command");
  });

  /// GET /config_response/<group>
  Future<Result<Uint8List>> fetchConfigResponse({
    required String cameraName,
  }) => _wrap(() async {
    final creds = await _getValidatedCredentials();

    final group = await _groupName(cameraName, Group.config);
    final url = _buildUrl(creds.serverAddr, ['config_response', group]);
    final headers = await _basicAuthHeaders(
      creds.username,
      creds.password,
      cameraName: cameraName,
    );

    final response = await _cappedGetResponse(
      url,
      headers: headers,
      maxBytes: maxCommandFileSize,
    );
    await _handleServerVersionHeader(response);
    if (response.statusCode != 200) {
      if (response.statusCode == 404) {
        throw SilentException(
          'Failed to fetch config response: ${response.statusCode} ${response.reasonPhrase}',
        );
      } else {
        throw Exception(
          'Failed to fetch config response: ${response.statusCode} ${response.reasonPhrase}',
        );
      }
    } else {
      Log.d("Successfully fetched config response");
    }

    return response.bodyBytes;
  });

  Future<Result<Uint8List>> receiveMsg(String msgTag) => _wrap(() async {
    final creds = await _getValidatedCredentials();

    final url = _buildUrl(creds.serverAddr, ['receive_msg', msgTag]);
    final headers = await _basicAuthHeaders(creds.username, creds.password);

    final response = await _cappedGetResponse(
      url,
      headers: headers,
      maxBytes: maxAddAppRequestSize,
    );
    await _handleServerVersionHeader(response);

    if (response.statusCode != 200) {
      throw Exception(
        'Server error: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    return response.bodyBytes;
  });

  Future<Result<void>> sendMsg(String msgTag, Uint8List data) =>
      _wrap(() async {
        final creds = await _getValidatedCredentials();

        final url = _buildUrl(creds.serverAddr, ['send_msg', msgTag]);
        final headers = await _basicAuthHeaders(creds.username, creds.password);
        headers[HttpHeaders.contentTypeHeader] = 'application/octet-stream';

        final response = await http.post(url, headers: headers, body: data);
        await _handleServerVersionHeader(response);

        if (response.statusCode != 200) {
          throw Exception(
            'Server error: ${response.statusCode} ${response.reasonPhrase}',
          );
        }
      });

  /// Utility methods below

  Future<Result<T>> _wrap<T>(
    Future<T> Function() block, {
    bool bypassVersionGate = false,
  }) async {
    try {
      if (!bypassVersionGate) {
        await _ensureVersionCompatible();
      }
      return Result.success(await block());
    } catch (e, st) {
      if (e is SilentException) {
        Log.d("HttpClientService error: $e");
        return Result.failure(e);
      } else if (_isNetworkException(e)) {
        Log.w("HttpClientService warning: $e");
      } else {
        Log.e("HttpClientService error: $e\n$st");
      }
      return Result.failure(Exception(e.toString()));
    }
  }

  bool _isNetworkException(Object e) {
    if (e is SocketException) {
      return true;
    }
    if (e is http.ClientException && e.message.contains('SocketException')) {
      return true;
    }
    return false;
  }

  Future<void> _ensureVersionCompatible() async {
    if (VersionGate.isBlocked) {
      await potentiallySendBackgroundNotification();
      throw SilentException('Version gate active');
    }
    if (_versionMatchConfirmed) {
      return;
    }
    _versionCheckInFlight ??= _checkServerVersionAndGate();
    await _versionCheckInFlight;
    _versionCheckInFlight = null;
    if (VersionGate.isBlocked) {
      throw SilentException('Version gate active');
    }
  }

  Future<void> _handleServerVersionHeader(http.Response response) async {
    final serverVersion = response.headers['x-server-version'];
    if (serverVersion == null || serverVersion.isEmpty) {
      return;
    }

    final clientVersion = await _versionFuture;
    if (serverVersion != clientVersion) {
      Log.i(
        'Server version ($serverVersion) differs from client version ($clientVersion)',
      );
      _versionMatchConfirmed = false;
      VersionGate.block(
        VersionGateInfo.mismatch(
          serverVersion: serverVersion,
          clientVersion: clientVersion,
        ),
      );

      await potentiallySendBackgroundNotification();
      throw SilentException('Server/client version mismatch');
    }

    _versionMatchConfirmed = true;
  }

  Future<void> _checkServerVersionAndGate() async {
    try {
      final serverVersion = await _fetchServerVersionRaw();
      final clientVersion = await _versionFuture;

      if (serverVersion != clientVersion) {
        Log.i(
          'Server version ($serverVersion) differs from client version ($clientVersion)',
        );
        _versionMatchConfirmed = false;
        VersionGate.block(
          VersionGateInfo.mismatch(
            serverVersion: serverVersion,
            clientVersion: clientVersion,
          ),
        );
        return;
      }

      _versionMatchConfirmed = true;
      VersionGate.clear();
    } catch (e) {
      Log.d('Version check failed: $e');
    }
  }

  Future<String> _fetchServerVersionRaw() async {
    final creds = await _getValidatedCredentials();

    final url = _buildUrl(creds.serverAddr, ['status']);
    final headers = await _basicAuthHeaders(creds.username, creds.password);

    final response = await _cappedGetResponse(
      url,
      headers: headers,
      maxBytes: maxServerVersionSize,
    );
    if (response.statusCode != 200 && response.statusCode != 409) {
      throw Exception(
        'Failed to fetch server version: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    // Check the X-Server-Version response header.
    final serverVersion = response.headers['x-server-version'];
    if (serverVersion == null || serverVersion.isEmpty) {
      throw Exception('Missing X-Server-Version header in response');
    }

    return serverVersion;
  }

  Future<String?> _pref(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Uri _buildUrl(String serverAddr, List<dynamic> segments) {
    final base = Uri.parse(serverAddr);
    final pathSegments = [
      ...base.pathSegments.where((segment) => segment.isNotEmpty),
      ...segments
          .map((segment) => segment.toString())
          .where((segment) => segment.isNotEmpty),
    ];
    return base.replace(pathSegments: pathSegments);
  }

  /// Attach whatever the server we are talking to expects.
  Future<Map<String, String>> _basicAuthHeaders(
    String username,
    String password, {
    bool jsonContent = false,
    String? serverAddr,
    ServerBackend? backend,
    String? cameraName,
  }) async {
    final resolved = backend ?? await _backend();

    if (resolved.isEnterprise) {
      // Resolve the address ourselves when the caller didn't pass one.
      final resolvedAddr =
          serverAddr ?? (await _pref(PrefKeys.serverAddr))?.trim();
      if (resolvedAddr == null || resolvedAddr.isEmpty) {
        throw SilentException('Missing server address for enterprise auth');
      }

      final token = await _enterpriseSession.accessToken(
        serverAddr: resolvedAddr,
        username: username,
        password: password,
      );

      // Which of the account's subscriptions this device works under.
      final subscriptionUuid = (await _pref(PrefKeys.subscriptionUuid))?.trim();

      return {
        HttpHeaders.authorizationHeader: 'Bearer $token',
        if (subscriptionUuid != null && subscriptionUuid.isNotEmpty)
          'X-Subscription-Uuid': subscriptionUuid,
        if (jsonContent) HttpHeaders.contentTypeHeader: 'application/json',
      };
    }

    final credentials = base64Encode(utf8.encode('$username:$password'));
    if (jsonContent) {
      return {
        HttpHeaders.authorizationHeader: 'Basic $credentials',
        HttpHeaders.contentTypeHeader: 'application/json',
        'Client-Version': await _versionFuture,
      };
    } else {
      return {
        HttpHeaders.authorizationHeader: 'Basic $credentials',
        'Client-Version': await _versionFuture,
      };
    }
  }

  Future<Directory> _ensureEncryptedDir(String cameraName) async {
    final base = await AppPaths.dataDirectory();
    final dir = Directory('${base.path}/camera_dir_$cameraName/encrypted');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<bool> hasStoredServerCredentials() async {
    final serverAddr = await _pref(PrefKeys.serverAddr);
    final username = await _pref(PrefKeys.serverUsername);
    final password = await _pref(PrefKeys.serverPassword);

    return [
      serverAddr?.trim(),
      username?.trim(),
      password?.trim(),
    ].every((value) => value != null && value.isNotEmpty);
  }

  Future<
    ({
      String serverAddr,
      String username,
      String password,
      ServerBackend backend,
    })
  >
  _getValidatedCredentials() async {
    final serverAddr = await _pref(PrefKeys.serverAddr);
    final username = await _pref(PrefKeys.serverUsername);
    final password = await _pref(PrefKeys.serverPassword);

    if ([
      serverAddr?.trim(),
      username?.trim(),
      password?.trim(),
    ].any((value) => value == null || value.isEmpty)) {
      throw SilentException('Missing server credentials');
    }

    return (
      serverAddr: serverAddr!.trim(),
      username: username!.trim(),
      password: password!.trim(),
      backend: await _backend(),
    );
  }

  Future<ServerBackend> _backend() async =>
      ServerBackend.parse(await _pref(PrefKeys.serverBackend));

  Future<void> setServerBackend(ServerBackend backend) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.serverBackend, backend.wireName);
    // A different server means a different account; the old token is meaningless.
    _enterpriseSession.clear();
  }

  Future<void> registerIfEnterprise() async {
    final creds = await _getValidatedCredentials();
    if (!creds.backend.isEnterprise) {
      return;
    }

    await _enterpriseSession.register(
      serverAddr: creds.serverAddr,
      username: creds.username,
      password: creds.password,
    );
  }

  // TODO: Should we put a lock around this? Is it possible for two bg tasks to run simultaneously?
  Future<void> potentiallySendBackgroundNotification() async {
    if (await background()) {
      var currentTime = DateTime.now().millisecondsSinceEpoch;

      var prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(PrefKeys.lastOutdatedNotification)) {
        // Check to ensure it wasn't too long ago
        var lastOutdatedNotification =
            prefs.getInt(PrefKeys.lastOutdatedNotification)!;

        var timeDiff = currentTime - lastOutdatedNotification;
        var minDiff =
            3 * 60 * 60 * 1000; // We're okay with notifying them every 3 hours.

        if (timeDiff < minDiff) {
          return;
        }
      }

      // Proceed if okay; set the time and send the notification now
      Log.d("Sending background notification");
      await prefs.setInt(PrefKeys.lastOutdatedNotification, currentTime);
      await showOutdatedNotification();
    }
  }

  Future<bool> background() async {
    var currentContextId = Log.currentContextId();
    Log.d("Checking current context: $currentContextId");
    final segments = currentContextId
        .split('/')
        .where((segment) => segment.isNotEmpty);
    return segments.any(
      (segment) =>
          segment.startsWith("sched-") ||
          segment.startsWith("fcm-") ||
          segment.startsWith("dl-") ||
          segment.startsWith("thumb-"),
    );
  }

  Future<String> _groupName(String cameraName, String clientTag) async {
    final cacheKey = "$cameraName|$clientTag";
    final cached = _groupNameCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    String groupName = await getGroupName(
      clientTag: clientTag,
      cameraName: cameraName,
    );

    if (!groupName.startsWith("Error")) {
      _groupNameCache[cacheKey] = groupName;
      return groupName;
    }

    if (groupName.startsWith("Error: Busy")) {
      throw SilentException('Group name busy for $cameraName ($clientTag)');
    }

    Log.w(
      "[http] getGroupName failed for $cameraName ($clientTag): $groupName",
    );

    final retryKey = cacheKey;
    final now = DateTime.now();
    final lastAttempt = _groupNameInitLast[retryKey];
    if (lastAttempt != null &&
        now.difference(lastAttempt) < _groupNameInitCooldown) {
      throw SilentException(
        'Group name unavailable for $cameraName ($clientTag)',
      );
    }

    _groupNameInitLast[retryKey] = now;
    invalidateCameraInit(cameraName);
    final initOutcome = await initialize(
      cameraName,
      timeout: _groupNameInitTimeout,
      force: true,
    );
    if (initOutcome.isOk) {
      groupName = await getGroupName(
        clientTag: clientTag,
        cameraName: cameraName,
      );
      if (!groupName.startsWith("Error")) {
        _groupNameCache[cacheKey] = groupName;
        return groupName;
      }
      Log.w(
        "[http] getGroupName retry failed for $cameraName ($clientTag): $groupName",
      );
    } else if (initOutcome == InitOutcome.timeout) {
      Log.w(
        "[http] Init timeout before getGroupName retry for $cameraName ($clientTag, ${Log.ownerTag()})",
      );
    } else {
      Log.w(
        "[http] Init failed before getGroupName retry for $cameraName ($clientTag)",
      );
    }

    throw SilentException(
      'Group name unavailable for $cameraName ($clientTag)',
    );
  }
}
