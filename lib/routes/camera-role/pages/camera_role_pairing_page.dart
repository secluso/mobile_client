//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Allow another phone to pair to this one; act in the role of Bluetooth advertising.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/camera-role/android_camera_hub_launcher.dart';
import 'package:secluso_flutter/routes/camera-role/pages/camera_role_recording_page.dart';
import 'package:secluso_flutter/routes/camera-role/pages/camera_role_preview_page.dart';
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
  static const _checkingTitle = 'Checking camera';
  static const _checkingBody =
    'Loading the camera settings available on this phone.';

  String? _qrPayload;
  String _statusTitle = _checkingTitle;
  String _statusBody = _checkingBody;
  bool _loadingSpecs = true;
  bool _starting = false;
  bool _waitingForPairing = false;
  Object? _error;
  List<AndroidCameraSpec> _cameraSpecs = const [];
  AndroidCameraSpec? _selectedSpec;
  AndroidCameraResolution? _selectedResolution;
  AndroidCameraFrameRateRange? _selectedFrameRateRange;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCameraSpecs());
  }

  Future<void> _loadCameraSpecs() async {
    setState(() {
      _loadingSpecs = true;
      _starting = false;
      _waitingForPairing = false;
      _error = null;
      _statusTitle = _checkingTitle;
      _statusBody = _checkingBody;
    });

    try {
      final specs = await AndroidCameraHubLauncher.cameraSpecs();
      if (specs.isEmpty) {
        throw StateError('No Android cameras are available on this phone.');
      }

      final selectedSpec = specs.firstWhere(
        (spec) => spec.facing == AndroidCameraHubLauncher.facingBack,
        orElse: () => specs.first,
      );
      final selectedResolution = _defaultResolution(selectedSpec);
      final selectedFrameRateRange = _defaultFrameRateRange(selectedSpec);

      if (!mounted) return;
      setState(() {
        _cameraSpecs = specs;
        _selectedSpec = selectedSpec;
        _selectedResolution = selectedResolution;
        _selectedFrameRateRange = selectedFrameRateRange;
        _loadingSpecs = false;
        _statusTitle = 'Choose camera settings';
        _statusBody =
            'Select the camera, resolution, and frame rate before starting.';
      });
    } catch (e, st) {
      Log.e('Loading Android camera specs failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadingSpecs = false;
        _starting = false;
        _waitingForPairing = false;
        _error = e;
        _statusTitle = 'Unable to read camera settings';
        _statusBody = e.toString();
      });
    }
  }

  AndroidCameraResolution _defaultResolution(AndroidCameraSpec spec) {
    return spec.resolutions.firstWhere(
      (resolution) => resolution.width == 1280 && resolution.height == 720,
      orElse: () => spec.resolutions.first,
    );
  }

  AndroidCameraFrameRateRange _defaultFrameRateRange(AndroidCameraSpec spec) {
    return spec.frameRateRanges.firstWhere(
      (range) => range.min <= 10 && range.max >= 10,
      orElse: () => spec.frameRateRanges.first,
    );
  }

  Future<void> _bootCameraRole() async {
    final selectedSpec = _selectedSpec;
    final selectedResolution = _selectedResolution;
    final selectedFrameRateRange = _selectedFrameRateRange;

    if (selectedSpec == null ||
        selectedResolution == null ||
        selectedFrameRateRange == null) {
      setState(() {
        _error = StateError('Choose camera settings before starting.');
        _statusTitle = 'Camera settings missing';
        _statusBody = _error.toString();
      });
      return;
    }

    setState(() {
      _qrPayload = null;
      _starting = true;
      _waitingForPairing = false;
      _error = null;
      _statusTitle = 'Starting camera';
      _statusBody = 'Checking whether this phone is already paired.';
    });

    try {
      await AndroidCameraHubLauncher.setCameraSettings(
        AndroidCameraSettings(
          facing: selectedSpec.facing,
          width: selectedResolution.width,
          height: selectedResolution.height,
          frameRateRange: selectedFrameRateRange,
        ),
      );

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

  void _selectSpec(AndroidCameraSpec? spec) {
    if (spec == null) return;
    setState(() {
      _selectedSpec = spec;
      _selectedResolution = _defaultResolution(spec);
      _selectedFrameRateRange = _defaultFrameRateRange(spec);
    });
  }

  void _selectResolution(AndroidCameraResolution? resolution) {
    if (resolution == null) return;
    setState(() => _selectedResolution = resolution);
  }

  void _selectFrameRateRange(AndroidCameraFrameRateRange? range) {
    if (range == null) return;
    setState(() => _selectedFrameRateRange = range);
  }

  Future<void> _previewCamera() async {
    final selectedSpec = _selectedSpec;
    final selectedResolution = _selectedResolution;
    final selectedFrameRateRange = _selectedFrameRateRange;
    if (selectedSpec == null ||
        selectedResolution == null ||
        selectedFrameRateRange == null) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder:
            (_) => CameraRolePreviewPage(
              settings: AndroidCameraSettings(
                facing: selectedSpec.facing,
                width: selectedResolution.width,
                height: selectedResolution.height,
                frameRateRange: selectedFrameRateRange,
              ),
            ),
      ),
    );
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
            final readyToConfigure =
                !_loadingSpecs &&
                !_starting &&
                !_waitingForPairing &&
                qrPayload == null &&
                !hasError;

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
                            : readyToConfigure
                                ? 'Choose camera settings'
                            : qrPayload == null
                                ? 'Starting camera mode'
                                : 'Scan from your main phone',
                    body:
                        hasError
                            ? 'Fix the issue below, then try again.'
                            : readyToConfigure
                                ? 'Pick the camera, resolution, and frame rate before pairing.'
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
                              : readyToConfigure
                                  ? Icons.tune_rounded
                              : Icons.videocam_rounded,
                      pulse: (_loadingSpecs || _starting) && !hasError,
                    ),
                  SizedBox(height: sz(24)),
                  if (readyToConfigure) ...[
                    _buildSettingsSelector(s),
                    SizedBox(height: sz(16)),
                  ],
                  CameraRoleTintedCard(
                    scale: s,
                    accent: hasError ? cameraRoleDanger : cameraRoleBlue,
                    icon:
                        hasError
                            ? Icons.report_problem_outlined
                            : readyToConfigure
                                ? Icons.settings_input_component_rounded
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
                                : readyToConfigure
                                    ? 'Ready'
                                : _waitingForPairing
                                    ? 'Waiting'
                                    : _loadingSpecs
                                        ? 'Checking'
                                        : _starting
                                        ? 'Starting'
                                        : 'Advertising',
                        valueColor:
                            hasError
                                ? cameraRoleDanger
                                : readyToConfigure
                                    ? cameraRoleEmerald
                                : _waitingForPairing
                                    ? cameraRoleAmber
                                    : cameraRoleBlue,
                        leading: cameraRoleDot(
                          sz(6),
                          hasError
                              ? cameraRoleDanger
                              : readyToConfigure
                                  ? cameraRoleEmerald
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
                      onPressed: _starting ? null : _loadCameraSpecs,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    )
                  else if (readyToConfigure)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _previewCamera,
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Preview Camera'),
                        ),
                        SizedBox(height: sz(10)),
                        FilledButton.icon(
                          onPressed: _bootCameraRole,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Start Camera'),
                        ),
                      ],
                    )
                  else if (_loadingSpecs)
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
                          'Checking available settings...',
                          style: GoogleFonts.inter(
                            color: cameraRoleWhite20,
                            fontSize: sz(11),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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

  Widget _buildSettingsSelector(double scale) {
    final selectedSpec = _selectedSpec;
    final selectedResolution = _selectedResolution;
    final selectedFrameRateRange = _selectedFrameRateRange;

    if (selectedSpec == null ||
        selectedResolution == null ||
        selectedFrameRateRange == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          _SettingsDropdown<AndroidCameraSpec>(
            scale: scale,
            value: selectedSpec,
            items: _cameraSpecs,
            label: 'Camera',
            itemLabel: (spec) => spec.facingLabel,
            onChanged: _selectSpec,
          ),
          SizedBox(height: 10 * scale),
          _SettingsDropdown<AndroidCameraResolution>(
            scale: scale,
            value: selectedResolution,
            items: selectedSpec.resolutions,
            label: 'Resolution',
            itemLabel: (resolution) => resolution.label,
            onChanged: _selectResolution,
          ),
          SizedBox(height: 10 * scale),
          _SettingsDropdown<AndroidCameraFrameRateRange>(
            scale: scale,
            value: selectedFrameRateRange,
            items: selectedSpec.frameRateRanges,
            label: 'Frame rate',
            itemLabel: (range) => range.label,
            onChanged: _selectFrameRateRange,
          ),
        ],
      ),
    );
  }
}

class _SettingsDropdown<T> extends StatelessWidget {
  const _SettingsDropdown({
    required this.scale,
    required this.value,
    required this.items,
    required this.label,
    required this.itemLabel,
    required this.onChanged,
  });

  final double scale;
  final T value;
  final List<T> items;
  final String label;
  final String Function(T item) itemLabel;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items:
          items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(itemLabel(item)),
                ),
              )
              .toList(growable: false),
      onChanged: onChanged,
      dropdownColor: cameraRoleBg,
      iconEnabledColor: Colors.white,
      style: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 12 * scale,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(
          color: cameraRoleWhite40,
          fontSize: 11 * scale,
          fontWeight: FontWeight.w500,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8 * scale),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8 * scale),
          borderSide: BorderSide(color: cameraRoleBlue),
        ),
      ),
    );
  }
}
