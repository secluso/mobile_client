import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:secluso_flutter/notifications/epoch.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/notification_permissions.dart';
import 'package:secluso_flutter/routes/camera/list_cameras.dart';
import 'package:secluso_flutter/utilities/app_coordination_state.dart';
import 'package:secluso_flutter/utilities/connected_apps.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/routes/camera/camera_ui_bridge.dart';

class AddAppFlow {
  static Future<Map<String, Object>?> show(
    BuildContext context, {
    required Uint8List addAppSecret,
  }) async {
    final cameraNameController = TextEditingController();

    final result = await showDialog<Map<String, Object>?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var working = false;
        String? error;

        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Add camera to this phone'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: cameraNameController,
                    enabled: !working,
                    decoration: const InputDecoration(
                      labelText: 'Camera name',
                    ),
                  ),
                  if (working) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: working ? null : () => Navigator.of(ctx).pop(null),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: working
                      ? null
                      : () async {
                          final cameraName = cameraNameController.text.trim();
                          if (cameraName.isEmpty) {
                            setState(() {
                              error = 'Camera name is required.';
                            });
                            return;
                          }

                          if (await AppCoordinationState.containsCamera(cameraName)) {
                            setState(() {
                                error = 'A camera with this name already exists.';
                            });
                            return;
                          }

                          setState(() {
                            working = true;
                            error = null;
                          });

                          try {
                            final initOutcome = await initialize(cameraName);
                            if (!initOutcome.isOk) {
                              throw Exception('failed to initialize camera state');
                            }

                            final keyPackages = await getKeyPackages(
                              cameraName: cameraName,
                            );
                            if (keyPackages.isEmpty) {
                              throw Exception('failed to get key packages');
                            }

                            final addAppRequestResult =
                                await HttpClientService.instance.sendMsg(
                              'add_app_start',
                              keyPackages,
                            );

                            if (addAppRequestResult.isFailure) {
                              throw Exception(
                                'failed to send the add-phone request: '
                                '${addAppRequestResult.error}',
                              );
                            }

                            final newAppDataResult =
                                await HttpClientService.instance.receiveMsg(
                              'add_app_finish',
                            );

                            if (newAppDataResult.isFailure) {
                              throw Exception(
                                'failed to wait for the add-phone response: '
                                '${newAppDataResult.error}',
                              );
                            }

                            final newAppDataVec = newAppDataResult.value;
                            if (newAppDataVec == null) {
                              throw Exception(
                                'failed to wait for the add-phone response: missing data',
                              );
                            }

                            final addAppResp = decodeAddAppResp(newAppDataVec);
                            final epochs = await joinCameraGroups(
                              cameraName: cameraName,
                              secret: addAppSecret,
                              newAppDataVec: addAppResp.payload,
                            );

                            if (epochs.length < 2) {
                              throw Exception('failed to join camera groups');
                            }

                            await writeEpoch(
                              cameraName,
                              'video',
                              epochs[0].toInt() + 1,
                            );
                            await writeEpoch(
                              cameraName,
                              'thumbnail',
                              epochs[1].toInt() + 1,
                            );

                            await _persistAddedCamera(
                              cameraName,
                              addAppResp.appName,
                            );

                            CameraUiBridge.switchShellTabCallback?.call(0);

                            if (!ctx.mounted) return;
                            Navigator.of(ctx, rootNavigator: true).popUntil((route) => route.isFirst);
                          } catch (e) {
                            setState(() {
                              working = false;
                              error = e.toString();
                            });
                          }
                        },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    cameraNameController.dispose();
    return result;
  }

  static Future<void> _persistAddedCamera(
    String cameraName,
    String ownAppName,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool("first_time_$cameraName", true);

    await prefs.setBool(
        PrefKeys.cameraAddedViaAddAppPrefix + cameraName,
        true,
    );
    await prefs.setString(PrefKeys.ownAppNamePrefix + cameraName, ownAppName);

    final existingCameraSet = await AppCoordinationState.getCameraSet();
    final wasFirstCamera = existingCameraSet.isEmpty;

    if (await AppCoordinationState.addCamera(cameraName)) {
        await prefs.setInt(
        PrefKeys.numIgnoredHeartbeatsPrefix + cameraName,
        0,
        );
        await prefs.setInt(
        PrefKeys.cameraStatusPrefix + cameraName,
        CameraStatus.online,
        );
        await prefs.setInt(
        PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
        0,
        );
        await prefs.setInt(
        PrefKeys.lastHeartbeatTimestampPrefix + cameraName,
        0,
        );
    }

    await AppStores.instance.cameraStore.put(Camera(cameraName));

    CameraListNotifier.instance.refreshCallback?.call();

    if (wasFirstCamera) {
        await requestNotificationsAfterFirstCameraAdd();
    }
  }
}
