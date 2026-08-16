//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Allow another phone to pair to this one; act in the role of Bluetooth advertising.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/camera-role/android_camera_hub_launcher.dart';
import 'package:secluso_flutter/routes/camera-role/camera_role_settings.dart';
import 'package:secluso_flutter/routes/camera-role/pages/camera_role_preview_page.dart';
import 'package:secluso_flutter/routes/camera-role/pages/camera_role_recording_page.dart';
import 'package:secluso_flutter/routes/camera-role/theme.dart';
import 'package:secluso_flutter/routes/camera-role/widgets/editorial.dart';
import 'package:secluso_flutter/routes/camera-role/widgets/qr_card.dart';
import 'package:secluso_flutter/utilities/logger.dart';

/// Where this phone is in the process of becoming a camera.
enum _Stage {
  /// Asking the platform which cameras and video modes exist here.
  readingSpecs,

  /// Waiting for the user to pick a camera, resolution and frame rate.
  configuring,

  /// Handing the settings to the hub and bringing it up.
  starting,

  /// Showing the code, waiting for the main phone to scan it.
  awaitingScan,

  failed,
}

class CameraRolePairingPage extends StatefulWidget {
  const CameraRolePairingPage({
    super.key,
    this.onConnected,
    this.onClose,
    this.previewQrPayload,
  });

  final ValueChanged<bool>? onConnected;
  final VoidCallback? onClose;

  /// Renders the scan step with this payload instead of talking to the camera  hub.
  /// Only for the design lab
  final String? previewQrPayload;

  @override
  State<CameraRolePairingPage> createState() => _CameraRolePairingPageState();
}

class _CameraRolePairingPageState extends State<CameraRolePairingPage> {
  _Stage _stage = _Stage.readingSpecs;
  Object? _error;
  String? _qrPayload;

  List<AndroidCameraSpec> _specs = const [];
  AndroidCameraSpec? _spec;
  AndroidCameraResolution? _resolution;
  AndroidCameraFrameRateRange? _frameRate;

  @override
  void initState() {
    super.initState();
    final preview = widget.previewQrPayload;
    if (preview != null) {
      _qrPayload = preview;
      _stage = _Stage.awaitingScan;
      return;
    }
    unawaited(_readCameraSpecs());
  }

  Future<void> _readCameraSpecs() async {
    setState(() {
      _stage = _Stage.readingSpecs;
      _error = null;
      _qrPayload = null;
    });

    try {
      final specs = await AndroidCameraHubLauncher.cameraSpecs();
      if (specs.isEmpty) {
        throw StateError('No Android cameras are available on this phone.');
      }

      final spec = specs.firstWhere(
        (s) => s.facing == AndroidCameraHubLauncher.facingBack,
        orElse: () => specs.first,
      );

      if (!mounted) return;
      setState(() {
        _specs = specs;
        _spec = spec;
        _resolution = _defaultResolution(spec);
        _frameRate = _defaultFrameRate(spec);
        _stage = _Stage.configuring;
      });
    } catch (e, st) {
      Log.e('Loading Android camera specs failed: $e\n$st');
      _fail(e);
    }
  }

  AndroidCameraResolution _defaultResolution(AndroidCameraSpec spec) =>
      spec.resolutions.firstWhere(
        (r) => r.width == 1280 && r.height == 720,
        orElse: () => spec.resolutions.first,
      );

  AndroidCameraFrameRateRange _defaultFrameRate(AndroidCameraSpec spec) =>
      spec.frameRateRanges.firstWhere(
        (r) => r.min <= 10 && r.max >= 10,
        orElse: () => spec.frameRateRanges.first,
      );

  AndroidCameraSettings? get _settings {
    final spec = _spec;
    final resolution = _resolution;
    final frameRate = _frameRate;
    if (spec == null || resolution == null || frameRate == null) return null;
    return AndroidCameraSettings(
      facing: spec.facing,
      width: resolution.width,
      height: resolution.height,
      frameRateRange: frameRate,
    );
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      _error = error;
    });
  }

  /// Applies the chosen settings, then either jumps straight to recording (if this phone was already paired)
  ///  or brings up a fresh pairing code.
  Future<void> _startCamera() async {
    final settings = _settings;
    if (settings == null) {
      _fail(StateError('Choose camera settings before starting.'));
      return;
    }

    setState(() {
      _stage = _Stage.starting;
      _error = null;
      _qrPayload = null;
    });

    try {
      await AndroidCameraHubLauncher.setCameraSettings(settings);
      await CameraRoleSettings.saveVideoMode(settings);

      if (await AndroidCameraHubLauncher.hasCompletedFirstPairing()) {
        if (!mounted) return;
        _goToRecording(isRunning: false);
        return;
      }

      final payload =
          await AndroidCameraHubLauncher.startHubAndWaitForQrPayload();
      if (!mounted) return;
      setState(() {
        _qrPayload = payload;
        _stage = _Stage.awaitingScan;
      });

      unawaited(_awaitScan());
    } catch (e, st) {
      Log.e('Camera role boot failed: $e\n$st');
      _fail(e);
    }
  }

  Future<void> _awaitScan() async {
    try {
      await AndroidCameraHubLauncher.waitForFirstTimeDone();
      if (!mounted) return;
      _goToRecording(isRunning: true);
    } catch (e, st) {
      Log.e('Waiting for first_time_done failed: $e\n$st');
      _fail(e);
    }
  }

  Future<void> _preview() async {
    final settings = _settings;
    if (settings == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CameraRolePreviewPage(settings: settings),
      ),
    );
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

  ({String title, String body}) get _copy => switch (_stage) {
    _Stage.readingSpecs => (
      title: 'Checking this phone',
      body:
          'Reading which cameras and video modes are available here. This only '
          'takes a moment.',
    ),
    _Stage.configuring => (
      title: 'Choose how it records',
      body:
          'Pick the camera, resolution, and frame rate. You can preview the '
          'view before you start.',
    ),
    _Stage.starting => (
      title: 'Starting camera mode',
      body: 'Keep this phone unlocked while Secluso prepares the pairing code.',
    ),
    _Stage.awaitingScan => (
      title: 'Scan from your main phone',
      body:
          'On the phone you watch from, add a camera and scan this code. Keep '
          'both phones nearby, pairing finishes on its own.',
    ),
    _Stage.failed => (
      title: 'Camera setup needs attention',
      body: _describe(_error),
    ),
  };

  /// Dart's own wording ("Bad state: ...") should not reach the screen.
  static String _describe(Object? error) => switch (error) {
    null => 'Something went wrong.',
    StateError(:final message) => message,
    _ => '$error',
  };

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    return Scaffold(
      backgroundColor: CamRole.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EditorialHeader(
                eyebrow: 'Be a camera',
                title: copy.title,
                body: copy.body,
                action: IconButton(
                  onPressed: _close,
                  icon: const Icon(Icons.close_rounded),
                  color: CamRole.paper,
                  iconSize: 22,
                  tooltip: 'Close',
                ),
              ),
              ..._stageContent(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _stageContent() => switch (_stage) {
    _Stage.awaitingScan => [
      const SizedBox(height: 34),
      Center(child: PairingQr(payload: _qrPayload!)),
      const SizedBox(height: 34),
      const EditorialFootnote(
        "Pairing shares this camera's keys, device to device.",
      ),
    ],
    _Stage.configuring => [
      const SizedBox(height: 30),
      _VideoModePicker(
        specs: _specs,
        spec: _spec!,
        resolution: _resolution!,
        frameRate: _frameRate!,
        onSpec:
            (spec) => setState(() {
              _spec = spec;
              _resolution = _defaultResolution(spec);
              _frameRate = _defaultFrameRate(spec);
            }),
        onResolution: (r) => setState(() => _resolution = r),
        onFrameRate: (r) => setState(() => _frameRate = r),
      ),
      const SizedBox(height: 26),
      EditorialButton(label: 'Preview the view', onPressed: _preview),
      const SizedBox(height: 12),
      EditorialButton(
        label: 'Start camera',
        onPressed: _startCamera,
        primary: true,
      ),
    ],
    _Stage.readingSpecs ||
    _Stage.starting => const [SizedBox(height: 44), Center(child: _Waiting())],
    _Stage.failed => [
      const SizedBox(height: 30),
      EditorialButton(label: 'Try again', onPressed: _readCameraSpecs),
    ],
  };
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2, color: CamRole.warmDim),
    );
  }
}

/// Camera, resolution and frame rate, as three quiet hairline rows.
class _VideoModePicker extends StatelessWidget {
  const _VideoModePicker({
    required this.specs,
    required this.spec,
    required this.resolution,
    required this.frameRate,
    required this.onSpec,
    required this.onResolution,
    required this.onFrameRate,
  });

  final List<AndroidCameraSpec> specs;
  final AndroidCameraSpec spec;
  final AndroidCameraResolution resolution;
  final AndroidCameraFrameRateRange frameRate;
  final ValueChanged<AndroidCameraSpec> onSpec;
  final ValueChanged<AndroidCameraResolution> onResolution;
  final ValueChanged<AndroidCameraFrameRateRange> onFrameRate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHead('This phone'),
        _PickerRow<AndroidCameraSpec>(
          title: 'Lens',
          value: spec,
          options: specs,
          labelOf: (s) => s.facingLabel,
          onChanged: onSpec,
        ),
        _PickerRow<AndroidCameraResolution>(
          title: 'Video quality',
          value: resolution,
          options: spec.resolutions,
          labelOf: (r) => r.label,
          onChanged: onResolution,
        ),
        _PickerRow<AndroidCameraFrameRateRange>(
          title: 'Frame rate',
          value: frameRate,
          options: spec.frameRateRanges,
          labelOf: (r) => r.label,
          onChanged: onFrameRate,
        ),
      ],
    );
  }
}

/// A settings row that opens a sheet of choices, rather than an inline dropdown.
class _PickerRow<T> extends StatelessWidget {
  const _PickerRow({
    required this.title,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
  });

  final String title;
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  Future<void> _choose(BuildContext context) async {
    final picked = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: CamRole.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                  child: Text(title, style: CamRoleText.title),
                ),
                for (final option in options)
                  SettingRow(
                    title: labelOf(option),
                    value: option == value ? 'Selected' : null,
                    onTap: () => Navigator.of(sheetContext).pop(option),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      title: title,
      value: labelOf(value),
      onTap: options.length > 1 ? () => _choose(context) : null,
    );
  }
}
