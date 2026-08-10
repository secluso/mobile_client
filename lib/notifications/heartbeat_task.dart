//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/download_task.dart';
import 'package:secluso_flutter/notifications/epoch.dart';
import 'package:secluso_flutter/notifications/notifications.dart';
import 'package:secluso_flutter/notifications/thumbnails.dart';
import 'package:secluso_flutter/utilities/camera_version_info.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/utilities/lock.dart';
import 'package:secluso_flutter/src/rust/frb_generated.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/app_coordination_state.dart';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class RustBridgeHelper {
  static bool _initialized = false;

  static Future<void>? _initFuture;

  /// Call this to avoid double-initialize in Android in the entry-point
  static Future<void> ensureInitialized() {
    if (_initialized) {
      return Future.value();
    }

    _initFuture ??= _doInit();
    return _initFuture!;
  }

  static Future<void> _doInit() async {
    await RustLib.init();
    _initialized = true;
  }
}

Future<bool> _cameraStillExists(
  SharedPreferences prefs,
  String cameraName,
) async {
  return AppCoordinationState.containsCameraInSnapshotFresh(prefs, cameraName);
}

Future<void> _incrementCommonChannelEpochs(String cameraName) async {
  final videoEpoch = await readEpoch(cameraName, 'video');
  await writeEpoch(cameraName, 'video', videoEpoch + 1);

  final thumbnailEpoch = await readEpoch(cameraName, 'thumbnail');
  await writeEpoch(cameraName, 'thumbnail', thumbnailEpoch + 1);
}

Future<bool> _handleMembershipResult(
  String cameraName,
  String result,
) async {
  if (result == 'add_app') {
    await _incrementCommonChannelEpochs(cameraName);
    return false;
  }
  if (!result.startsWith('remove_app')) return false;

  final removedAppName = result.substring('remove_app'.length);
  if (removedAppName.isEmpty) {
    throw const FormatException('Missing removed app name');
  }
  final prefs = await SharedPreferences.getInstance();
  final ownAppName = prefs.getString(PrefKeys.ownAppNamePrefix + cameraName);
  if (ownAppName == null || ownAppName != removedAppName) {
    await _incrementCommonChannelEpochs(cameraName);
    return false;
  }
  if (prefs.getBool(PrefKeys.cameraArchivedPrefix + cameraName) == true) {
    return true;
  }

  final client = HttpClientService.instance;
  final livestreamGroup = await getGroupName(
    clientTag: Group.livestream,
    cameraName: cameraName,
  );
  final configGroup = await getGroupName(
    clientTag: Group.config,
    cameraName: cameraName,
  );
  for (final group in [livestreamGroup, configGroup]) {
    final result = await client.deregisterGroup(group);
    if (result.isFailure) {
      Log.w('$cameraName: Failed to remove an archived server group');
    }
  }

  await prefs.setBool(PrefKeys.cameraArchivedPrefix + cameraName, true);
  await AppCoordinationState.removeCamera(cameraName);
  await AppCoordinationState.removeCameraFromDownloadQueues(cameraName);
  await deregisterCamera(cameraName: cameraName);
  invalidateCameraInit(cameraName);
  client.clearGroupNameCache(cameraName);
  try {
    await showCameraArchivedNotification(cameraName: cameraName);
  } catch (e, st) {
    Log.e('$cameraName: Failed to show archived-camera notification: $e\n$st');
  }
  Log.d('$cameraName: Camera archived after this app was removed');
  return true;
}

Future<bool> processNewAppInfoNotification(String cameraName) async {
  final configLock = "heartbeat$cameraName.lock";
  if (!await lock(configLock)) {
    Log.w("$cameraName: Config lock busy while processing new app info");
    return false;
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    if (!await _cameraStillExists(prefs, cameraName)) {
      Log.d("$cameraName: Camera deleted before new app info processing");
      return false;
    }

    final fetchResult = await HttpClientService.instance.fetchConfigResponse(
      cameraName: cameraName,
    );
    if (fetchResult.isFailure) {
      Log.w("$cameraName: Failed to fetch new app config response");
      return false;
    }

    final result = await processHeartbeatConfigResponse(
      cameraName: cameraName,
      configResponse: fetchResult.value!,
      // This value is ignored when processing an add_app config response.
      expectedTimestamp: BigInt.zero,
    );
    if (result != 'add_app' && !result.startsWith('remove_app')) {
      Log.w("$cameraName: Unexpected membership config response");
      return false;
    }

    await _handleMembershipResult(cameraName, result);
    Log.d("$cameraName: Processed membership config response");
    return true;
  } catch (e, st) {
    Log.e("$cameraName: Failed to process new app config response: $e\n$st");
    return false;
  } finally {
    await unlock(configLock);
  }
}

Future<bool> _doHeartbeatTask(String cameraName) async {
  Log.d("$cameraName: Starting to work (heartbeat)");
  final cameraHeartbeatLock = "heartbeat$cameraName.lock";
  if (await lock(cameraHeartbeatLock)) {
    try {
      //FIXME: don't attempt a heartbeat if we're livestreaming.

      final prefs = await SharedPreferences.getInstance();
      if (!await _cameraStillExists(prefs, cameraName)) {
        Log.d(
          "$cameraName: Camera deleted before heartbeat started; skipping.",
        );
        return false;
      }
      final timestampInt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final timestamp = BigInt.from(timestampInt);
      var receivedHeartbeat = false;
      var downloaded = false;
      var networkError = false;
      Log.d("$cameraName: Heartbeat timestamp = $timestamp");

      var lastHeartbeatTimestamp =
          prefs.getInt(PrefKeys.lastHeartbeatTimestampPrefix + cameraName) ?? 0;
      if (timestampInt - lastHeartbeatTimestamp < 60) {
        Log.d(
          "$cameraName: Dropping this heartbeat task since we recently executed one.",
        );
        return false;
      }
      await prefs.setInt(
        PrefKeys.lastHeartbeatTimestampPrefix + cameraName,
        timestampInt,
      );

      final encConfigMsg = await generateHeartbeatRequestConfigCommand(
        cameraName: cameraName,
        timestamp: timestamp,
      );

      final res = await HttpClientService.instance.configCommand(
        cameraName: cameraName,
        command: encConfigMsg,
      );

      await res.fold(
        (_) async {
          for (int i = 0; i < 30 && !receivedHeartbeat; i++) {
            if (!await _cameraStillExists(prefs, cameraName)) {
              Log.d(
                "$cameraName: Camera deleted during heartbeat retries; aborting.",
              );
              return;
            }
            await Future.delayed(Duration(seconds: 2));
            // Download pending videos and thumbnails before processing the heartbeat response.
            // This prevents thinking that the MLS channel is corrupted if there
            // are pending video files in the server.
            if (!await ThumbnailManager.retrieveThumbnails(
              camera: cameraName,
            )) {
              Log.d(
                "$cameraName: retrieveThumbnails returned false. Will skip this iteration.",
              );
              continue;
            }
            if (!await retrieveVideos(cameraName)) {
              Log.d(
                "$cameraName: retrieveVideos returned false. Will skip this iteration.",
              );
              continue;
            }

            downloaded = true; // Videos and thumbnails successfully downloaded

            final fetchRes = await HttpClientService.instance
                .fetchConfigResponse(cameraName: cameraName);
            var receivedAddApp = false;
            await fetchRes.fold(
              (configResponse) async {
                if (!await _cameraStillExists(prefs, cameraName)) {
                  Log.d(
                    "$cameraName: Camera deleted before heartbeat response handling; aborting.",
                  );
                  return;
                }
                final heartbeatResult = await processHeartbeatConfigResponse(
                  cameraName: cameraName,
                  configResponse: configResponse,
                  expectedTimestamp: timestamp,
                );
                Log.d("$cameraName: heartbeatResult = $heartbeatResult");
                if (heartbeatResult == 'add_app' ||
                    heartbeatResult.startsWith('remove_app')) {
                  Log.d(
                    "$cameraName: Received and processed a membership commit",
                  );
                  final archived = await _handleMembershipResult(
                    cameraName,
                    heartbeatResult,
                  );
                  receivedAddApp = true;
                  if (archived) receivedHeartbeat = true;
                  return;
                }

                final heartbeatStatus = HeartbeatStatus.fromJsonString(
                  heartbeatResult,
                );

                if (heartbeatStatus.status == "healthy") {
                  Log.d("$cameraName: Processing healthy heartbeat");
                  await prefs.setInt(
                    PrefKeys.numIgnoredHeartbeatsPrefix + cameraName,
                    0,
                  );
                  var previousCameraStatus =
                      prefs.getInt(PrefKeys.cameraStatusPrefix + cameraName) ??
                      CameraStatus.online;
                  await prefs.setInt(
                    PrefKeys.cameraStatusPrefix + cameraName,
                    CameraStatus.online,
                  );
                  await prefs.setInt(
                    PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
                    0,
                  );
                  final versionInfo = heartbeatStatus.versionInfo;
                  if (versionInfo != null) {
                    final currentFirmware = prefs.getString(
                      PrefKeys.firmwareVersionPrefix + cameraName,
                    );
                    if (shouldNotifyFirmwareUpdate(
                      currentFirmware,
                      versionInfo.firmwareVersion,
                    )) {
                      showCameraStatusNotification(
                        cameraName: cameraName,
                        msg:
                            "Camera's Secluso firmware version has been updated to ${versionInfo.firmwareVersion}.",
                      );

                      // TODO: We should compare it with the app version. If they don't match, display notice to user.
                    }
                    await prefs.setString(
                      PrefKeys.firmwareVersionPrefix + cameraName,
                      versionInfo.firmwareVersion,
                    );
                    await prefs.setString(
                      PrefKeys.cameraOsVersionPrefix + cameraName,
                      versionInfo.osVersion,
                    );
                  }
                  var sendNotificationGlobal =
                      prefs.getBool(PrefKeys.notificationsEnabled) ?? true;

                  if (previousCameraStatus != CameraStatus.online &&
                      sendNotificationGlobal) {
                    Log.d(
                      "Showing notification: Camera connection is restored.",
                    );
                    showCameraStatusNotification(
                      cameraName: cameraName,
                      msg: "Camera connection is restored.",
                    );
                  }
                } else if (heartbeatStatus.status == "invalid ciphertext") {
                  Log.d("$cameraName: Processing invalid ciphertext heartbeat");
                  await prefs.setInt(
                    PrefKeys.cameraStatusPrefix + cameraName,
                    CameraStatus.corrupted,
                  );
                  var numHeartbeatNotifications =
                      prefs.getInt(
                        PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
                      ) ??
                      0;
                  var sendNotificationGlobal =
                      prefs.getBool(PrefKeys.notificationsEnabled) ?? true;
                  // It could be annoying if we keep showing these notifications.
                  if (numHeartbeatNotifications < 2 && sendNotificationGlobal) {
                    Log.d(
                      "Showing notification: Camera connection is corrupted.",
                    );
                    showCameraStatusNotification(
                      cameraName: cameraName,
                      msg: "Camera connection is corrupted. Pair again.",
                    );
                    await prefs.setInt(
                      PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
                      numHeartbeatNotifications + 1,
                    );
                  }
                } else {
                  //invalid timestamp || invalid epoch || Error
                  // Note on "invalid epoch": Ideally, we want to be able to move this case to the previous else if block (i.e, invalid ciphertext).
                  // That is, we want "invalid epoch" to clearly show an MLS channel corruption.
                  // However, "invalid epoch" could also happen if there's a race between a heartbeat
                  // and motion video trigger on the camera (or even a livestream start on the app).
                  // We've tried to prevent that for motion videos by downloading and processing any pending motion
                  // videos in the server before processing the heartbeat response.
                  // To prevent a race with livestream, we should disallow livestreaming while we're working on a heartbeat.
                  var numIgnoredHeartbeats =
                      prefs.getInt(
                        PrefKeys.numIgnoredHeartbeatsPrefix + cameraName,
                      ) ??
                      0;
                  numIgnoredHeartbeats++;
                  await prefs.setInt(
                    PrefKeys.numIgnoredHeartbeatsPrefix + cameraName,
                    numIgnoredHeartbeats,
                  );
                  Log.d(
                    "$cameraName: number of consecutive ignored heartbeats = $numIgnoredHeartbeats",
                  );
                  if (numIgnoredHeartbeats >= 2) {
                    await prefs.setInt(
                      PrefKeys.cameraStatusPrefix + cameraName,
                      CameraStatus.possiblyCorrupted,
                    );
                    var numHeartbeatNotifications =
                        prefs.getInt(
                          PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
                        ) ??
                        0;
                    var sendNotificationGlobal =
                        prefs.getBool(PrefKeys.notificationsEnabled) ?? true;
                    if (numHeartbeatNotifications < 2 &&
                        sendNotificationGlobal) {
                      Log.d(
                        "Showing notification: Camera connection is likely corrupted.",
                      );
                      showCameraStatusNotification(
                        cameraName: cameraName,
                        msg:
                            "Camera connection is likely corrupted. Pair again.",
                      );
                      await prefs.setInt(
                        PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
                        numHeartbeatNotifications + 1,
                      );
                    }
                  }
                }

                receivedHeartbeat = true;
              },
              (err) async {
                Log.d(
                  '$cameraName: Error fetching heartbeat config response (attempt $i): $err',
                );
                if (err is! SilentException) {
                  Log.d('$cameraName: Non-404 error detected');
                  networkError = true;
                }
              },
            );

            if (receivedAddApp) {
              continue;
            }
          }

          if (downloaded && !receivedHeartbeat && !networkError) {
            // We get here if we could not fetch a heartbeat response in all the attempts in the loop.
            // An add_app config response does not count as a heartbeat response.
            // If we delete the camera while heartbeat is taking place, we could end up
            // here after the camera is deleted. So we check that here.
            if (await _cameraStillExists(prefs, cameraName)) {
              Log.d(
                '$cameraName: Error fetching heartbeat config response in all attempts.',
              );
              await prefs.setInt(
                PrefKeys.cameraStatusPrefix + cameraName,
                CameraStatus.offline,
              );
              var numHeartbeatNotifications =
                  prefs.getInt(
                    PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
                  ) ??
                  0;
              var sendNotificationGlobal =
                  prefs.getBool(PrefKeys.notificationsEnabled) ?? true;
              if (numHeartbeatNotifications < 2 && sendNotificationGlobal) {
                Log.d("Showing notification: Camera is offline.");
                showCameraStatusNotification(
                  cameraName: cameraName,
                  msg: "Camera seems to be offline.",
                );
                await prefs.setInt(
                  PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
                  numHeartbeatNotifications + 1,
                );
              }
            }
          }
        },
        (err) async {
          if (await _cameraStillExists(prefs, cameraName)) {
            Log.d('$cameraName: Error sending heartbeat config command: $err');
          } else {
            Log.d(
              '$cameraName: Camera deleted after heartbeat command send failed; ignoring.',
            );
          }
        },
      );

      return receivedHeartbeat;
    } finally {
      await unlock(cameraHeartbeatLock);
    }
  } else {
    Log.w("Heartbeat lock busy for $cameraName; skipping");
    return false;
  }
}

Future<void> updateCameraStatusFcmNotification(
  String fcmTimestampString,
  String cameraName,
) async {
  final prefs = await SharedPreferences.getInstance();
  if (!await _cameraStillExists(prefs, cameraName)) {
    Log.d(
      "updateCameraStatusFcmNotification: camera $cameraName was deleted; skipping.",
    );
    return;
  }
  var cameraStatus =
      prefs.getInt(PrefKeys.cameraStatusPrefix + cameraName) ??
      CameraStatus.online;
  Log.d("updateCameraStatusFcmNotification: camera status = $cameraStatus");

  if (cameraStatus == CameraStatus.offline) {
    final lastHeartbeatTimestamp =
        prefs.getInt(PrefKeys.lastHeartbeatTimestampPrefix + cameraName) ?? 0;
    final fcmTimestamp = int.tryParse(fcmTimestampString);

    if (lastHeartbeatTimestamp != 0 && fcmTimestamp! > lastHeartbeatTimestamp) {
      await prefs.setInt(
        PrefKeys.cameraStatusPrefix + cameraName,
        CameraStatus.online,
      );
      var sendNotificationGlobal =
          prefs.getBool(PrefKeys.notificationsEnabled) ?? true;
      if (sendNotificationGlobal) {
        Log.d("Showing notification: Camera connection is restored.");
        showCameraStatusNotification(
          cameraName: cameraName,
          msg: "Camera connection is restored.",
        );
      }
    }
  }
}

Future<void> updateCameraStatusLivestream(String cameraName) async {
  final prefs = await SharedPreferences.getInstance();
  if (!await _cameraStillExists(prefs, cameraName)) {
    Log.d(
      "updateCameraStatusLivestream: camera $cameraName was deleted; skipping.",
    );
    return;
  }
  var cameraStatus =
      prefs.getInt(PrefKeys.cameraStatusPrefix + cameraName) ??
      CameraStatus.online;
  Log.d("updateCameraStatusLivestream: camera status = $cameraStatus");

  if (cameraStatus == CameraStatus.offline) {
    await prefs.setInt(
      PrefKeys.cameraStatusPrefix + cameraName,
      CameraStatus.online,
    );
    var sendNotificationGlobal =
        prefs.getBool(PrefKeys.notificationsEnabled) ?? true;
    if (sendNotificationGlobal) {
      Log.d("Showing notification: Camera connection is restored.");
      showCameraStatusNotification(
        cameraName: cameraName,
        msg: "Camera connection is restored.",
      );
    }
  }
}

Future<void> doAllHeartbeatTasks(bool inBackground) async {
  if (Platform.isAndroid && inBackground) {
    await RustBridgeHelper.ensureInitialized();
  }
  Log.d("Starting to run all heartbeat tasks");

  final List<String> cameraSet = await AppCoordinationState.getCameraSet();

  for (final cameraName in cameraSet) {
    await _doHeartbeatTask(cameraName);
  }
}
