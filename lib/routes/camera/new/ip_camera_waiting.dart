//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/routes/camera/list_cameras.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/app_coordination_state.dart';
import 'package:secluso_flutter/utilities/camera_version_info.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/notification_permissions.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_theme.dart';

class CameraSetupStatusDialog extends StatefulWidget {
  final Map<String, dynamic> result;

  const CameraSetupStatusDialog({super.key, required this.result});

  static Future<void> show(BuildContext context, Map<String, dynamic> result) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder:
          (_) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: CameraSetupStatusDialog(result: result),
          ),
    );
  }

  @override
  State<CameraSetupStatusDialog> createState() =>
      _CameraSetupStatusDialogState();
}

class _CameraSetupStatusDialogState extends State<CameraSetupStatusDialog> {
  bool? _success;

  @override
  void initState() {
    super.initState();
    _startSetup();
  }

  void _startSetup() {
    setState(() => _success = null);

    final cameraName = widget.result["cameraName"]! as String;
    final ip = widget.result["cameraIp"]! as String;
    final qrCode = List<int>.from(widget.result["qrCode"]! as Uint8List);

    Log.d("CameraSetup: begin for $cameraName");

    addCamera(cameraName, ip, qrCode, false, '', '', '').then((
      versionInfoJson,
    ) async {
      if (!mounted) return;

      final success =
          !versionInfoJson.startsWith("Error") &&
          versionInfoJson != "PairVersionIncompatible";

      if (success) {
        await _persistCamera(
          cameraName,
          CameraVersionInfo.fromJsonString(versionInfoJson),
        );
      }

      setState(() => _success = success);

      if (success) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        });
      }
    });
  }

  Future<void> _persistCamera(
    String cameraName,
    CameraVersionInfo versionInfo,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool("first_time_$cameraName", true);

    final existingCameraSet = await AppCoordinationState.getCameraSet();
    final wasFirstCamera = existingCameraSet.isEmpty;
    if (await AppCoordinationState.addCamera(cameraName)) {
      await prefs.setInt(PrefKeys.numIgnoredHeartbeatsPrefix + cameraName, 0);
      await prefs.setInt(
        PrefKeys.cameraStatusPrefix + cameraName,
        CameraStatus.online,
      );
      await prefs.setInt(
        PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
        0,
      );
      await prefs.setInt(PrefKeys.lastHeartbeatTimestampPrefix + cameraName, 0);
      await prefs.setString(
        PrefKeys.firmwareVersionPrefix + cameraName,
        versionInfo.firmwareVersion,
      );
      await prefs.setInt(
        PrefKeys.cameraOsVersionPrefix + cameraName,
        versionInfo.osVersion,
      );
    }

    await AppStores.instance.cameraStore.put(Camera(cameraName));

    CameraListNotifier.instance.refreshCallback?.call();

    if (wasFirstCamera) {
      await requestNotificationsAfterFirstCameraAdd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0E11),
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF111216), Color(0xFF0B0B0D)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child:
              _success == null
                  ? _buildLoading()
                  : _success == true
                  ? _buildSuccess()
                  : _buildError(),
        ),
      ),
    );
  }

  Widget _buildLoading() => Column(
    key: const ValueKey('loading'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SeclusoStatusChip(
        label: 'Pairing in progress',
        color: SeclusoColors.blueSoft,
      ),
      const SizedBox(height: 18),
      const CircularProgressIndicator(),
      const SizedBox(height: 20),
      Text(
        'Setting up the camera.',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(color: Colors.white, fontSize: 26),
      ),
      const SizedBox(height: 8),
      Text(
        'The relay is registering the camera and applying its credentials now.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.74),
          height: 1.45,
        ),
      ),
    ],
  );

  Widget _buildSuccess() => Column(
    key: const ValueKey('success'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SeclusoStatusChip(
        label: 'Camera linked',
        color: SeclusoColors.success,
      ),
      const SizedBox(height: 18),
      const Icon(
        Icons.check_circle_outline_rounded,
        color: SeclusoColors.success,
        size: 54,
      ),
      const SizedBox(height: 18),
      Text(
        'Camera added successfully.',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(color: Colors.white, fontSize: 26),
      ),
      const SizedBox(height: 8),
      Text(
        'The new feed is ready and the app will return to the main screen shortly.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.74),
          height: 1.45,
        ),
      ),
    ],
  );

  Widget _buildError() => Column(
    key: const ValueKey('error'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SeclusoStatusChip(
        label: 'Pairing failed',
        color: SeclusoColors.danger,
      ),
      const SizedBox(height: 18),
      const Icon(
        Icons.error_outline_rounded,
        color: SeclusoColors.danger,
        size: 54,
      ),
      const SizedBox(height: 18),
      Text(
        'Failed to add the camera.',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(color: Colors.white, fontSize: 26),
      ),
      const SizedBox(height: 8),
      Text(
        'The relay did not finish importing this device. You can go back or retry the setup flow.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.74),
          height: 1.45,
        ),
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _startSetup,
              child: const Text('Retry'),
            ),
          ),
        ],
      ),
    ],
  );
}
