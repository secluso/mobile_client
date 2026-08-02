//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/src/rust_camera/api.dart' as rust_camera_api;
import 'package:secluso_flutter/src/rust_camera/guard.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AndroidCameraResolution {
  const AndroidCameraResolution({required this.width, required this.height});

  final int width;
  final int height;

  factory AndroidCameraResolution.fromJson(Map<String, Object?> json) {
    return AndroidCameraResolution(
      width: json['width'] as int,
      height: json['height'] as int,
    );
  }

  String get label => '${width}x$height';
}

class AndroidCameraFrameRateRange {
  const AndroidCameraFrameRateRange({required this.min, required this.max});

  final int min;
  final int max;

  factory AndroidCameraFrameRateRange.fromJson(Map<String, Object?> json) {
    return AndroidCameraFrameRateRange(
      min: json['min'] as int,
      max: json['max'] as int,
    );
  }

  String get label => min == max ? '$max fps' : '$min-$max fps';
}

class AndroidCameraSpec {
  const AndroidCameraSpec({
    required this.facing,
    required this.resolutions,
    required this.frameRateRanges,
  });

  final int facing;
  final List<AndroidCameraResolution> resolutions;
  final List<AndroidCameraFrameRateRange> frameRateRanges;

  factory AndroidCameraSpec.fromJson(Map<String, Object?> json) {
    return AndroidCameraSpec(
      facing: json['facing'] as int,
      resolutions:
          (json['resolutions'] as List<Object?>)
              .map((item) => Map<String, Object?>.from(item as Map))
              .map(AndroidCameraResolution.fromJson)
              .toList(growable: false),
      frameRateRanges:
          (json['frame_rate_ranges'] as List<Object?>)
              .map((item) => Map<String, Object?>.from(item as Map))
              .map(AndroidCameraFrameRateRange.fromJson)
              .toList(growable: false),
    );
  }

  String get facingLabel => switch (facing) {
    AndroidCameraHubLauncher.facingFront => 'Front camera',
    AndroidCameraHubLauncher.facingBack => 'Back camera',
    // This should be unreachable given that our Rust code only returns front and back cameras.
    _ => 'Unsupported',
  };
}

class AndroidCameraSettings {
  const AndroidCameraSettings({
    required this.facing,
    required this.width,
    required this.height,
    required this.frameRateRange,
  });

  final int facing;
  final int width;
  final int height;
  final AndroidCameraFrameRateRange frameRateRange;

  String get facingLabel => switch (facing) {
    AndroidCameraHubLauncher.facingFront => 'Front camera',
    AndroidCameraHubLauncher.facingBack => 'Back camera',
    _ => 'Unsupported camera',
  };
}

class AndroidCameraHubLauncher {
  static const facingBack = 0;
  static const facingFront = 1;
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

  static Future<List<AndroidCameraSpec>> cameraSpecs() async {
    if (!Platform.isAndroid) {
      return const [];
    }

    final cameraPermission = await Permission.camera.request();
    if (!cameraPermission.isGranted) {
      throw StateError('Camera permission is required.');
    }

    await RustCameraLibGuard.initOnce();
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      throw StateError('No Flutter display is available.');
    }
    final physicalSize = views.first.physicalSize;
    final displayWidth = physicalSize.width.round();
    final displayHeight = physicalSize.height.round();
    if (displayWidth <= 0 || displayHeight <= 0) {
      throw StateError('The Flutter display has invalid physical dimensions.');
    }
    final specsJson = await rust_camera_api.getAndroidCameraSpecsJson(
      displayWidth: displayWidth,
      displayHeight: displayHeight,
    );
    final decoded = jsonDecode(specsJson) as List<Object?>;
    return decoded
        .map((item) => Map<String, Object?>.from(item as Map))
        .map(AndroidCameraSpec.fromJson)
        .toList(growable: false);
  }

  static Future<void> setCameraSettings(AndroidCameraSettings settings) async {
    if (!Platform.isAndroid) {
      return;
    }

    await RustCameraLibGuard.initOnce();
    await rust_camera_api.setAndroidCameraSettings(
      facing: settings.facing,
      width: settings.width,
      height: settings.height,
      frameRateMin: settings.frameRateRange.min,
      frameRateMax: settings.frameRateRange.max,
    );
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
