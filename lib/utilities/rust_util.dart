//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';

class _InitState {
  Future<bool>? inFlight;
  bool ready = false;
  DateTime? startedAt;
  DateTime? lastSuccess;
  DateTime? lastFailure;
  DateTime? lastTimeout;
  int attempts = 0;
}

final Map<String, _InitState> _initStateByCamera = {};
const Duration _initTimeoutCooldown = Duration(seconds: 10);
const Duration _initFailureCooldown = Duration(seconds: 12);

enum InitOutcome { ok, timeout, failed }

extension InitOutcomeX on InitOutcome {
  bool get isOk => this == InitOutcome.ok;
}

void invalidateCameraInit(String cameraName) {
  final state = _initStateByCamera.remove(cameraName);
  if (state != null) {
    Log.d("[init] Cleared init cache for $cameraName");
  }
}

Future<String> addCamera(
  String cameraName,
  String ip,
  List<int> secret,
  bool standalone,
  String ssid,
  String password,
  String pairingToken,
  bool android,
) async {
  Log.d("In addCamera");
  final initOutcome = await initialize(cameraName);
  if (!initOutcome.isOk) {
    Log.e("Connect = false");
    return "Error";
  }

  final prefs = await SharedPreferences.getInstance();
  final serverAddress = prefs.getString(PrefKeys.serverAddr);
  final serverUsername = prefs.getString(PrefKeys.serverUsername);
  final serverPassword = prefs.getString(PrefKeys.serverPassword);

  if (serverAddress == null ||
      serverUsername == null ||
      serverPassword == null) {
    Log.e("credentials for server are null");
    return "Error";
  }

  Log.d("Calling flutter add camera");

  return await flutterAddCamera(
    cameraName: cameraName,
    ip: ip,
    secret: secret,
    standalone: standalone,
    ssid: ssid,
    password: password,
    pairingToken: pairingToken,
    credentialsFull: serverUsername + serverPassword + serverAddress,
    android: android,
  );
}

Future<InitOutcome> initialize(
  String cameraName, {
  Duration timeout = const Duration(seconds: 15),
  bool force = false,
}) async {
  final state = _initStateByCamera.putIfAbsent(cameraName, () => _InitState());

  if (force) {
    state.ready = false;
  }

  if (!force && state.ready) {
    Log.d("[init] $cameraName already initialized; using cached state");
    return InitOutcome.ok;
  }

  if (state.inFlight != null) {
    final ageMs =
        state.startedAt == null
            ? null
            : DateTime.now().difference(state.startedAt!).inMilliseconds;
    if (state.lastTimeout != null &&
        DateTime.now().difference(state.lastTimeout!) < _initTimeoutCooldown) {
      Log.w(
        "[init] Init still running for $cameraName; skipping to avoid stall (age=${ageMs ?? -1}ms)",
      );
      return InitOutcome.timeout;
    }
    Log.d(
      "[init] Reusing in-flight init for $cameraName (age=${ageMs ?? -1}ms)",
    );
    return _awaitInit(cameraName, state.inFlight!, timeout, state);
  }

  if (!force) {
    final now = DateTime.now();
    final lastFailure = state.lastFailure;
    if (lastFailure != null &&
        now.difference(lastFailure) < _initFailureCooldown) {
      Log.w("[init] Recent init failure for $cameraName; skipping retry");
      return InitOutcome.failed;
    }
    final lastTimeout = state.lastTimeout;
    if (lastTimeout != null &&
        now.difference(lastTimeout) < _initFailureCooldown) {
      Log.w("[init] Recent init timeout for $cameraName; skipping retry");
      return InitOutcome.timeout;
    }
  }

  state.attempts += 1;
  state.startedAt = DateTime.now();
  final sw = Stopwatch()..start();
  final future = _doInitialize(cameraName, state, sw);
  state.inFlight = future;
  return _awaitInit(cameraName, future, timeout, state);
}

Future<InitOutcome> _awaitInit(
  String cameraName,
  Future<bool> future,
  Duration timeout,
  _InitState state,
) async {
  try {
    final success = await future.timeout(timeout);
    return success ? InitOutcome.ok : InitOutcome.failed;
  } on TimeoutException {
    state.lastTimeout = DateTime.now();
    Log.w(
      "[init] Init timeout for $cameraName after ${timeout.inSeconds}s (${Log.ownerTag()})",
    );
    return InitOutcome.timeout;
  } catch (e, st) {
    state.lastFailure = DateTime.now();
    Log.e("[init] Init error for $cameraName: $e\n$st");
    return InitOutcome.failed;
  }
}

Future<bool> _doInitialize(
  String cameraName,
  _InitState state,
  Stopwatch sw,
) async {
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool firstTimeConnectionDone =
        prefs.getBool("first_time_$cameraName") ?? false;

    Log.d("First time connection done: $firstTimeConnectionDone");
    Log.d(
      "[init] Starting init for $cameraName (attempt ${state.attempts}, firstTime=${!firstTimeConnectionDone})",
    );

    final success = await initializeCore(cameraName, !firstTimeConnectionDone);
    sw.stop();

    if (success) {
      state.ready = true;
      state.lastSuccess = DateTime.now();
      Log.d(
        "[init] Init succeeded for $cameraName in ${sw.elapsedMilliseconds}ms",
      );
    } else {
      state.lastFailure = DateTime.now();
      Log.w(
        "[init] Init failed for $cameraName in ${sw.elapsedMilliseconds}ms",
      );
    }
    return success;
  } catch (e, st) {
    sw.stop();
    state.lastFailure = DateTime.now();
    Log.e(
      "[init] Init exception for $cameraName in ${sw.elapsedMilliseconds}ms: $e\n$st",
    );
    return false;
  } finally {
    state.inFlight = null;
  }
}

Future<bool> initializeCore(String cameraName, bool firstTime) async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  //FIXME: do we still need these checks on serverAddr and user credentials?
  final String serverAddr =
      prefs.getString(PrefKeys.serverAddr) ??
      "Error"; // TODO: Make this not a static field
  if (serverAddr == "Error") {
    Log.e("Error: Failed to retrieve server address");
    return false;
  }

  var userCredentialsString =
      prefs.getString(PrefKeys.serverPassword) ??
      "Error"; // If the password's set, we implicitly know the username is too (validity checks before setting either)
  if (userCredentialsString == "Error") {
    Log.e("Error: Failed to retrieve user credentials");
    return false;
  }

  var filesDir = p.join(
    (await AppPaths.dataDirectory()).absolute.path,
    'camera_dir_$cameraName',
  );

  var videosDir = "$filesDir/videos";
  var encryptedDir = "$filesDir/encrypted";

  // Create directory if it doesn't exist
  var videoDirHandle = Directory(videosDir);
  if (!(await videoDirHandle.exists())) {
    try {
      await videoDirHandle.create(recursive: true);
    } catch (e) {
      Log.e("Error: Failed to create directory for videos");
    }
  }

  var encDirHandle = Directory(encryptedDir);
  if (!(await encDirHandle.exists())) {
    try {
      await encDirHandle.create(recursive: true);
    } catch (e) {
      Log.e("Error: Failed to create directory for encrypted files");
    }
  }

  Log.d("Proceeding to call rust initializeCamera method");

  return await initializeCamera(
    fileDir: filesDir,
    cameraName: cameraName,
    firstTime: firstTime,
  );
}
