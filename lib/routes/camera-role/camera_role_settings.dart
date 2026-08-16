//! SPDX-License-Identifier: GPL-3.0-or-later
//
// What this phone remembers about being a camera.

import 'package:flutter/foundation.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/routes/camera-role/android_camera_hub_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class CameraRoleSettings {
  const CameraRoleSettings({
    this.lens,
    this.quality,
    this.keepScreenDark = true,
    this.showRecLight = true,
  });

  /// Which camera is recording, e.g. "Back"
  final String? lens;

  /// The video mode in the shorthand people expect, e.g. "1080p".
  final String? quality;

  /// Dim the screen to black while recording, to save battery and draw less attention.
  final bool keepScreenDark;

  /// Show a small REC indicator while recording.
  final bool showRecLight;

  CameraRoleSettings copyWith({bool? keepScreenDark, bool? showRecLight}) =>
      CameraRoleSettings(
        lens: lens,
        quality: quality,
        keepScreenDark: keepScreenDark ?? this.keepScreenDark,
        showRecLight: showRecLight ?? this.showRecLight,
      );

  static Future<CameraRoleSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CameraRoleSettings(
      lens: prefs.getString(PrefKeys.cameraRoleLens),
      quality: prefs.getString(PrefKeys.cameraRoleQuality),
      keepScreenDark: prefs.getBool(PrefKeys.cameraRoleKeepScreenDark) ?? true,
      showRecLight: prefs.getBool(PrefKeys.cameraRoleShowRecLight) ?? true,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefKeys.cameraRoleKeepScreenDark, keepScreenDark);
    await prefs.setBool(PrefKeys.cameraRoleShowRecLight, showRecLight);
  }

  /// Records the mode the camera was actually started with.
  static Future<void> saveVideoMode(AndroidCameraSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.cameraRoleLens, settings.facingLabel);
    await prefs.setString(PrefKeys.cameraRoleQuality, '${settings.height}p');
  }
}
