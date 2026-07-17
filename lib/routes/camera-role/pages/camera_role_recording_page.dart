//! SPDX-License-Identifier: GPL-3.0-or-later
//
// We've already paired. Now we just show the current state of what this "camera" (the disposable phone) is doing.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/camera-role/theme.dart';
import 'package:secluso_flutter/routes/camera-role/widgets/shared_widgets.dart';

class CameraRoleRecordingPage extends StatefulWidget {
  const CameraRoleRecordingPage({
    super.key,
    this.initialRunning = false,
    this.onStart,
    this.onStop,
    this.onResetCamera,
    this.onSwitchRole,
  });

  final bool initialRunning;
  final Future<void> Function()? onStart;
  final Future<void> Function()? onStop;
  final Future<void> Function()? onResetCamera;
  final Future<void> Function()? onSwitchRole;

  @override
  State<CameraRoleRecordingPage> createState() =>
      _CameraRoleRecordingPageState();
}

class _CameraRoleRecordingPageState extends State<CameraRoleRecordingPage> {
  late bool _running = widget.initialRunning;
  bool _starting = false;
  bool _resetting = false;
  bool _switchingRole = false;

  void _showFirstStopRecording() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('First stop recording.'),
      ),
    );
  }

  Future<void> _startRecording() async {
    final start = widget.onStart;
    if (start == null || _running || _starting) return;

    setState(() => _starting = true);
    try {
      await start();
      if (mounted) {
        setState(() => _running = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to start recording: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  Future<void> _confirmResetCamera() async {
    if (_running) {
      _showFirstStopRecording();
      return;
    }

    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161616),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          contentTextStyle: const TextStyle(
            color: cameraRoleWhite40,
            fontSize: 14,
            height: 1.4,
          ),
          title: const Text('Reset this camera?'),
          content: const Text(
            'This deletes the local camera state from the phone. '
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: cameraRoleDanger,
                foregroundColor: cameraRoleBg,
              ),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (shouldReset != true || !mounted) return;

    final reset = widget.onResetCamera;
    if (reset == null) return;

    setState(() => _resetting = true);
    try {
      await reset();
    } finally {
      if (mounted) {
        setState(() => _resetting = false);
      }
    }
  }

  Future<void> _requestSwitchRole() async {
    final switchRole = widget.onSwitchRole;
    if (switchRole == null) return;

    setState(() => _switchingRole = true);
    try {
      await switchRole();
    } finally {
      if (mounted) {
        setState(() => _switchingRole = false);
      }
    }
  }

  Future<void> _confirmStop() async {
    if (!_running) return;

    final shouldStop = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161616),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          contentTextStyle: const TextStyle(
            color: cameraRoleWhite40,
            fontSize: 14,
            height: 1.4,
          ),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(child: Text('Stop?')),
              IconButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                icon: const Icon(Icons.close_rounded),
                color: cameraRoleWhite40,
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Cancel',
              ),
            ],
          ),
          content: const Text(
            'This will stop recording and return to role selection.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: cameraRoleDanger,
                foregroundColor: cameraRoleBg,
              ),
              child: const Text('Stop'),
            ),
          ],
        );
      },
    );

    if (shouldStop != true || !mounted) {
      return;
    }
    await widget.onStop?.call();
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
                      if (_running)
                        IconButton(
                          tooltip: 'Stop',
                          icon: Icon(
                            Icons.power_settings_new_rounded,
                            color: cameraRoleDanger,
                            size: sz(22),
                          ),
                          onPressed: _confirmStop,
                        ),
                    ],
                  ),
                  SizedBox(height: sz(20)),
                  CameraRoleRingOrb(
                    scale: s,
                    icon:
                        _running
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                    pulse: _running,
                  ),
                  SizedBox(height: sz(32)),
                  CameraRoleFlowHeading(
                    scale: s,
                    title: _running ? 'Recording' : 'Camera Ready',
                    body:
                        _running
                            ? 'Camera and microphone are recording,\n'
                                'If an event is detected, vidoe and audio will be sent encrypted to your relay.'
                            : 'Recording is stopped. Start when this\n'
                                'phone is ready to act as a camera.',
                  ),
                  SizedBox(height: sz(32)),
                  if (!_running) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _starting ? null : _startRecording,
                        icon:
                            _starting
                                ? SizedBox(
                                  width: sz(14),
                                  height: sz(14),
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.play_arrow_rounded),
                        label: Text(_starting ? 'Starting...' : 'Start Recording'),
                      ),
                    ),
                    SizedBox(height: sz(16)),
                  ],
                  CameraRoleInfoCard(
                    scale: s,
                    rows: [
                      CameraRoleInfoRow(
                        scale: s,
                        label: 'Status',
                        value:
                            _running
                                ? 'Recording'
                                : _starting
                                    ? 'Starting'
                                    : 'Stopped',
                        valueColor: _running ? cameraRoleEmerald : cameraRoleAmber,
                        leading: cameraRoleDot(
                          sz(6),
                          _running ? cameraRoleEmerald : cameraRoleAmber,
                        ),
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
                  CameraRoleInfoCard(
                    scale: s,
                    rows: [
                      CameraRoleInfoRow(
                        scale: s,
                        label: 'Reset Camera',
                        value:
                            _running
                                ? 'First stop recording'
                                : _resetting
                                    ? 'Resetting...'
                                    : 'Delete state',
                        valueColor: _running ? cameraRoleAmber : cameraRoleDanger,
                        leading: Icon(
                          Icons.restart_alt_rounded,
                          size: sz(11),
                          color: _running ? cameraRoleAmber : cameraRoleDanger,
                        ),
                        onTap: _resetting ? null : _confirmResetCamera,
                      ),
                      CameraRoleInfoRow(
                        scale: s,
                        label: 'Switch Role',
                        value: _switchingRole ? 'Checking...' : 'Requires reset',
                        leading: Icon(
                          Icons.swap_horiz_rounded,
                          size: sz(11),
                          color: cameraRoleBlue,
                        ),
                        onTap: _switchingRole ? null : _requestSwitchRole,
                        showDivider: false,
                      ),
                    ],
                  ),
                  SizedBox(height: sz(16)),
                  CameraRoleTintedCard(
                    scale: s,
                    accent: _running ? cameraRoleEmerald : cameraRoleBlue,
                    icon:
                        _running
                            ? Icons.battery_charging_full_rounded
                            : Icons.play_circle_outline_rounded,
                    title: _running ? 'Leave it plugged in' : 'Ready to record',
                    body:
                        _running
                            ? 'The screen can stay dark. Secluso keeps recording in the background.'
                            : 'Press Start Recording when you want this phone to begin recording.',
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
