//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';

class DeviceRoleController {
  DeviceRoleController._();

  static const viewerRole = 'viewer';
  static const cameraRole = 'camera';

  static final ValueNotifier<int> roleSelectionRequests = ValueNotifier<int>(0);

  static Future<String?> currentRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(PrefKeys.deviceRole);
  }

  static Future<void> setViewerRole() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.deviceRole, viewerRole);
  }

  static Future<void> setCameraRole() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.deviceRole, cameraRole);
  }

  static Future<void> clearRole() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.deviceRole);
  }

  static void requestRoleSelection() {
    roleSelectionRequests.value++;
  }
}
