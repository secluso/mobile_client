//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/src/rust_camera/api.dart' as rust_camera_api;
import 'package:secluso_flutter/src/rust_camera/guard.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AndroidCameraHubLauncher {
  static const _qrPollAttempts = 60;
  static const _qrPollInterval = Duration(milliseconds: 500);

  static Future<Directory> workDir() async {
    final docsDir = await AppPaths.dataDirectory();
    return Directory(p.join(docsDir.path, 'android_camera_hub'));
  }

  static Future<File> firstTimeDoneFile() async {
    final dir = await workDir();
    return File(p.join(dir.path, 'state', 'first_time_done'));
  }

  static Future<bool> hasCompletedFirstPairing() async {
    final file = await firstTimeDoneFile();
    return file.exists();
  }

  static Future<void> startHub() async {
    if (!Platform.isAndroid) {
      throw StateError('Camera role is only available on Android.');
    }

    final cameraPermission = await Permission.camera.request();
    if (!cameraPermission.isGranted) {
      throw StateError('Camera permission is required.');
    }

    final microphonePermission = await Permission.microphone.request();
    if (!microphonePermission.isGranted) {
      throw StateError('Microphone permission is required.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final serverUsername = prefs.getString(PrefKeys.serverUsername);
    final serverPassword = prefs.getString(PrefKeys.serverPassword);
    final serverAddr = prefs.getString(PrefKeys.serverAddr);

    if (serverUsername == null ||
        serverUsername.isEmpty ||
        serverPassword == null ||
        serverPassword.isEmpty ||
        serverAddr == null ||
        serverAddr.isEmpty) {
      throw StateError(
        'Relay credentials are missing. Set up the relay first.',
      );
    }

    final dir = await workDir();
    await dir.create(recursive: true);

    Log.i('Android camera hub workDir: ${dir.path}');

    await RustCameraLibGuard.initOnce();

    await rust_camera_api.startAndroidCameraHub(
        workDir: dir.path,
        serverUsername: serverUsername,
        serverPassword: serverPassword,
        serverAddr: serverAddr,
    );
  }

  static Future<void> stopHub() async {
    if (!Platform.isAndroid) {
      return;
    }

    await RustCameraLibGuard.initOnce();
    await rust_camera_api.stopAndroidCameraHub();
  }

  static Future<String> startHubAndWaitForQrPayload() async {
    await startHub();

    final dir = await workDir();
    final payload = await _waitForQrPayload(dir);
    if (payload == null || payload.trim().isEmpty) {
      throw StateError(
        'Android camera started, but no QR payload was produced.',
      );
    }

    return payload;
  }

  static Future<void> resetCameraState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final serverUsername = prefs.getString(PrefKeys.serverUsername);
    final serverPassword = prefs.getString(PrefKeys.serverPassword);
    final serverAddr = prefs.getString(PrefKeys.serverAddr);

    if (serverUsername == null ||
        serverUsername.isEmpty ||
        serverPassword == null ||
        serverPassword.isEmpty ||
        serverAddr == null ||
        serverAddr.isEmpty) {
      throw StateError(
        'Relay credentials are missing, which are needed for cleaning the server state.',
      );
    }

    final dir = await workDir();
    await dir.create(recursive: true);

    await RustCameraLibGuard.initOnce();

    await rust_camera_api.resetAndroidCameraHub(
	workDir: dir.path,
        serverUsername: serverUsername,
        serverPassword: serverPassword,
        serverAddr: serverAddr,
    );

    // We do this just to be sure. Otherwise, the Rust reset should delete this.
    final firstTimeDone = File(p.join(dir.path, 'state', 'first_time_done'));
    if (await firstTimeDone.exists()) {
      await firstTimeDone.delete();
    }
  }

  static Future<bool> waitForFirstTimeDone({
    Duration pollInterval = const Duration(milliseconds: 500),
  }) async {
    while (true) {
      if (await hasCompletedFirstPairing()) {
        return true;
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  static Future<String?> _waitForQrPayload(Directory dir) async {
    for (var i = 0; i < _qrPollAttempts; i++) {
      final files =
          dir
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .where((file) => file.path.endsWith('_secret_qrcode_payload.json'))
              .toList();

      if (files.isNotEmpty) {
        files.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );

        final file = files.first;
        final payload = await file.readAsString(encoding: utf8);

        return payload;
      }

      await Future<void>.delayed(_qrPollInterval);
    }

    return null;
  }
}
