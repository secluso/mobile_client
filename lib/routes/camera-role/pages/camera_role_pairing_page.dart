//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Allow another phone to pair to this one; act in the role of Bluetooth advertising.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/camera-role/android_camera_hub_launcher.dart';
import 'package:secluso_flutter/routes/camera-role/pages/camera_role_recording_page.dart';
import 'package:secluso_flutter/routes/camera-role/theme.dart';
import 'package:secluso_flutter/routes/camera-role/widgets/qr_card.dart';
import 'package:secluso_flutter/routes/camera-role/widgets/shared_widgets.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';
import 'package:secluso_flutter/utilities/logger.dart';

class CameraRolePairingPage extends StatefulWidget {
  const CameraRolePairingPage({
    super.key,
    this.onConnected,
    this.onClose,
  });

  final ValueChanged<bool>? onConnected;
  final VoidCallback? onClose;

  @override
  State<CameraRolePairingPage> createState() => _CameraRolePairingPageState();
}

class _CameraRolePairingPageState extends State<CameraRolePairingPage> {
  String? _qrPayload;
  String _statusTitle = 'Starting camera';
  String _statusBody = 'Preparing this phone to act as a Secluso camera.';
  bool _starting = true;
  bool _waitingForPairing = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_bootCameraRole());
  }

  Future<void> _bootCameraRole() async {
    setState(() {
      _qrPayload = null;
      _starting = true;
      _waitingForPairing = false;
      _error = null;
      _statusTitle = 'Starting camera';
      _statusBody = 'Checking whether this phone is already paired.';
    });

    try {
      final alreadyPaired =
          await AndroidCameraHubLauncher.hasCompletedFirstPairing();

      if (alreadyPaired) {
        if (!mounted) return;
        _goToRecording(isRunning: false);
        return;
      }

      await _startFirstTimePairing();
    } catch (e, st) {
      Log.e('Camera role boot failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _starting = false;
        _waitingForPairing = false;
        _error = e;
        _statusTitle = 'Unable to start camera';
        _statusBody = e.toString();
      });
    }
  }

  Future<void> _startFirstTimePairing() async {
    if (!mounted) return;
    setState(() {
      _starting = true;
      _waitingForPairing = false;
      _statusTitle = 'Starting Android camera';
      _statusBody = 'Launching the camera hub and waiting for a pairing code.';
    });

    final qrPayload = await AndroidCameraHubLauncher.startHubAndWaitForQrPayload();

    if (!mounted) return;
    setState(() {
      _qrPayload = qrPayload;
      _starting = false;
      _waitingForPairing = true;
      _statusTitle = 'Advertising over QR';
      _statusBody =
          'On the phone you watch cameras from, add a camera and scan this code.';
    });

    unawaited(_waitForPairingCompletion());
  }

  Future<void> _waitForPairingCompletion() async {
    try {
      await AndroidCameraHubLauncher.waitForFirstTimeDone();
      if (!mounted) return;
      _goToRecording(isRunning: true);
    } catch (e, st) {
      Log.e('Waiting for first_time_done failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _waitingForPairing = false;
        _error = e;
        _statusTitle = 'Pairing interrupted';
        _statusBody = e.toString();
      });
    }
  }

  void _goToRecording({required bool isRunning}) {
    final onConnected = widget.onConnected;
    if (onConnected != null) {
      onConnected(isRunning);
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CameraRoleRecordingPage(initialRunning: isRunning),
      ),
    );
  }

  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
      return;
    }

    Navigator.of(context).maybePop();
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

            final qrPayload = _qrPayload;
            final hasError = _error != null;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(sz(24), sz(8), sz(24), sz(24)),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: sz(22),
                      ),
                      onPressed: _close,
                    ),
                  ),
                  SizedBox(height: sz(8)),
                  CameraRoleFlowHeading(
                    scale: s,
                    title:
                        hasError
                            ? 'Camera setup needs attention'
                            : qrPayload == null
                                ? 'Starting camera mode'
                                : 'Scan from your main phone',
                    body:
                        hasError
                            ? 'Fix the issue below, then try again.'
                            : qrPayload == null
                                ? 'Keep this phone unlocked while Secluso prepares the pairing code.'
                                : 'On the phone you watch your cameras from, add a camera and scan this code.',
                  ),
                  SizedBox(height: sz(28)),
                  if (qrPayload != null)
                    QrCard(scale: s, payload: qrPayload)
                  else
                    CameraRoleRingOrb(
                      scale: s,
                      icon:
                          hasError
                              ? Icons.error_outline_rounded
                              : Icons.videocam_rounded,
                      pulse: _starting && !hasError,
                    ),
                  SizedBox(height: sz(24)),
                  CameraRoleTintedCard(
                    scale: s,
                    accent: hasError ? cameraRoleDanger : cameraRoleBlue,
                    icon:
                        hasError
                            ? Icons.report_problem_outlined
                            : Icons.qr_code_rounded,
                    title: _statusTitle,
                    body: _statusBody,
                  ),
                  SizedBox(height: sz(16)),
                  CameraRoleInfoCard(
                    scale: s,
                    rows: [
                      CameraRoleInfoRow(
                        scale: s,
                        label: 'Status',
                        value:
                            hasError
                                ? 'Failed'
                                : _waitingForPairing
                                    ? 'Waiting'
                                    : _starting
                                        ? 'Starting'
                                        : 'Advertising',
                        valueColor:
                            hasError
                                ? cameraRoleDanger
                                : _waitingForPairing
                                    ? cameraRoleAmber
                                    : cameraRoleBlue,
                        leading: cameraRoleDot(
                          sz(6),
                          hasError
                              ? cameraRoleDanger
                              : _waitingForPairing
                                  ? cameraRoleAmber
                                  : cameraRoleBlue,
                        ),
                        showDivider: false,
                      ),
                    ],
                  ),
                  SizedBox(height: sz(18)),
                  if (hasError)
                    FilledButton.icon(
                      onPressed: _starting ? null : _bootCameraRole,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    )
                  else if (_starting || _waitingForPairing)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: sz(15),
                          height: sz(15),
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: sz(10)),
                        Text(
                          _waitingForPairing
                              ? 'Waiting for pairing...'
                              : 'Starting camera...',
                          style: GoogleFonts.inter(
                            color: cameraRoleWhite20,
                            fontSize: sz(11),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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
