//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/app_coordination_state.dart';
import 'package:secluso_flutter/utilities/review_environment.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';

class CameraUiBridge {
  CameraUiBridge._();

  static Future<void> Function(String cameraName)? deleteCameraCallback;
  static VoidCallback? refreshCameraListCallback;
  static VoidCallback? refreshActivityCallback;
  static VoidCallback? showBackgroundLogDialogCallback;
  static void Function(int index, {bool openRelayScanOnLoad})?
  switchShellTabCallback;

  static Future<void> deleteCamera(String cameraName) async {
    await ReviewEnvironment.instance.ensureLoaded();
    if (ReviewEnvironment.instance.session?.cameraByName(cameraName) != null) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(
        PrefKeys.cameraNotificationsEnabledPrefix + cameraName,
      );
      await prefs.remove(PrefKeys.cameraNotificationEventsPrefix + cameraName);
      await ReviewEnvironment.instance.removeCameraByName(cameraName);
      return;
    }

    if (!AppStores.isInitialized) {
      await AppStores.init();
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.numIgnoredHeartbeatsPrefix + cameraName);
    await prefs.remove(PrefKeys.cameraStatusPrefix + cameraName);
    await prefs.remove(PrefKeys.numHeartbeatNotificationsPrefix + cameraName);
    await prefs.remove(PrefKeys.lastHeartbeatTimestampPrefix + cameraName);
    await prefs.remove(PrefKeys.firmwareVersionPrefix + cameraName);
    await prefs.remove(PrefKeys.cameraOsVersionPrefix + cameraName);
    await prefs.remove(PrefKeys.cameraNotificationsEnabledPrefix + cameraName);
    await prefs.remove(PrefKeys.cameraNotificationEventsPrefix + cameraName);

    await deregisterCamera(cameraName: cameraName);
    invalidateCameraInit(cameraName);
    HttpClientService.instance.clearGroupNameCache(cameraName);

    final cameraStore = AppStores.instance.cameraStore;
    final videoStore = AppStores.instance.videoStore;

    await prefs.remove('first_time_$cameraName');

    await AppCoordinationState.removeCamera(cameraName);
    await AppCoordinationState.removeCameraFromDownloadQueues(cameraName);

    final cams = await cameraStore.findByName(cameraName);
    for (final cam in cams) {
      await cameraStore.remove(cam.id);
    }

    final videos = await videoStore.listByCamera(cameraName);
    await videoStore.removeMany(videos.map((video) => video.id).toList());

    final camDir = await AppPaths.cameraDirectory(cameraName);
    if (await camDir.exists()) {
      try {
        await camDir.delete(recursive: true);
        Log.d('Deleted camera folder: ${camDir.path}');
      } catch (e) {
        Log.e('Error deleting folder: $e');
      }
    }

    final docsDir = await AppPaths.dataDirectory();
    final lock = File(
      p.join(docsDir.path, 'locks', 'thumbnail$cameraName.lock'),
    );
    if (await lock.exists()) {
      await lock.delete();
    }

    final camDirPending = Directory(
      p.join(docsDir.path, 'waiting', 'camera_$cameraName'),
    );
    if (await camDirPending.exists()) {
      try {
        await camDirPending.delete(recursive: true);
        Log.d('Deleted camera waiting folder: ${camDirPending.path}');
      } catch (e) {
        Log.e('Error deleting folder: $e');
      }
    }
  }
}
