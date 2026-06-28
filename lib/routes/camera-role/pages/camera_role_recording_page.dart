//! SPDX-License-Identifier: GPL-3.0-or-later
//
// We've already paired. Now we just show the current state of what this "camera" (the disposable phone) is doing.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/camera-role/theme.dart';
import 'package:secluso_flutter/routes/camera-role/widgets/shared_widgets.dart';

class CameraRoleRecordingPage extends StatefulWidget {
  const CameraRoleRecordingPage({super.key});

  @override
  State<CameraRoleRecordingPage> createState() =>
      _CameraRoleRecordingPageState();
}

class _CameraRoleRecordingPageState extends State<CameraRoleRecordingPage> {
  Future<void> _confirmStopAndUnpair() async {
    final shouldStop = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Are you sure?'),
          content: const Text(
            'This will stop recording and unpair the camera role from this phone.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            Padding(padding: EdgeInsetsGeometry.all(5)),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Unpair the camera.'),
            ),
          ],
        );
      },
    );

    if (shouldStop != true || !mounted) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cameraRoleBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final s = cameraRoleFlowScale(constraints);
            double sz(double v) => v * s;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(sz(24), sz(12), sz(24), sz(24)),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        tooltip: 'Stop and unpair',
                        icon: Icon(
                          Icons.power_settings_new_rounded,
                          color: cameraRoleDanger,
                          size: sz(22),
                        ),
                        onPressed: _confirmStopAndUnpair,
                      ),
                    ],
                  ),
                  SizedBox(height: sz(20)),
                  CameraRoleRingOrb(
                    scale: s,
                    icon: Icons.videocam_rounded,
                    pulse: true,
                  ),
                  SizedBox(height: sz(32)),
                  CameraRoleFlowHeading(
                    scale: s,
                    title: 'Recording',
                    body:
                        'Camera and microphone are streaming,\n'
                        'encrypted, to your relay.',
                  ),
                  SizedBox(height: sz(32)),
                  CameraRoleInfoCard(
                    scale: s,
                    rows: [
                      CameraRoleInfoRow(
                        scale: s,
                        label: 'Status',
                        value: 'Recording',
                        valueColor: cameraRoleEmerald,
                        leading: cameraRoleDot(sz(6), cameraRoleEmerald),
                      ),
                      CameraRoleInfoRow(
                        scale: s,
                        label: 'Encryption',
                        value: 'E2EE Active',
                        leading: Icon(
                          Icons.lock_outline_rounded,
                          size: sz(11),
                          color: cameraRoleBlue,
                        ),
                      ),
                      CameraRoleInfoRow(
                        scale: s,
                        label: 'Uploaded',
                        value: '1.2 MB',
                        mono: true,
                      ),
                      CameraRoleInfoRow(
                        scale: s,
                        label: 'Pending',
                        value: '0 segments',
                        mono: true,
                        showDivider: false,
                      ),
                    ],
                  ),
                  SizedBox(height: sz(16)),
                  CameraRoleTintedCard(
                    scale: s,
                    accent: cameraRoleEmerald,
                    icon: Icons.battery_charging_full_rounded,
                    title: 'Leave it plugged in',
                    body:
                        'The screen can stay dark. Secluso keeps recording in the background.',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
