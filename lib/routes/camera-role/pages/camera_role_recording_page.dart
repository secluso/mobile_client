//! SPDX-License-Identifier: GPL-3.0-or-later
//
// We've already paired. Now we just show the current state of what this "camera" (the disposable phone) is doing.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/camera-role/camera_role_settings.dart';
import 'package:secluso_flutter/routes/camera-role/pages/camera_role_settings_page.dart';
import 'package:secluso_flutter/routes/camera-role/theme.dart';
import 'package:secluso_flutter/routes/camera-role/widgets/dim_when_idle.dart';
import 'package:secluso_flutter/routes/camera-role/widgets/editorial.dart';
import 'package:secluso_flutter/routes/camera-role/widgets/marks.dart';

class CameraRoleRecordingPage extends StatefulWidget {
  const CameraRoleRecordingPage({
    super.key,
    this.initialRunning = false,
    this.cameraName,
    this.onStart,
    this.onStop,
    this.onResetCamera,
    this.onSwitchRole,
  });

  final bool initialRunning;

  /// Name given to this camera from the main phone, when this phone knows it.
  final String? cameraName;

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
  late DateTime? _watchingSince = widget.initialRunning ? DateTime.now() : null;
  bool _starting = false;
  CameraRoleSettings _settings = const CameraRoleSettings();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await CameraRoleSettings.load();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  Future<void> _start() async {
    final start = widget.onStart;
    if (start == null || _running || _starting) return;

    setState(() => _starting = true);
    try {
      await start();
      if (!mounted) return;
      setState(() {
        _running = true;
        _watchingSince = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to start recording: $e')));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder:
            (_) => CameraRoleSettingsPage(
              cameraName: widget.cameraName ?? 'This phone',
              settings: _settings,
              recording: _running,
              onSettingsChanged:
                  (settings) => setState(() => _settings = settings),
              onStopRecording: widget.onStop,
              onUnpair: widget.onResetCamera,
              onSwitchRole: widget.onSwitchRole,
            ),
      ),
    );
  }

  String get _title {
    if (!_running) return 'Ready when you are';
    final name = widget.cameraName;
    return name == null ? 'On watch' : '$name, on watch';
  }

  String get _body =>
      _running
          ? 'Everything it sees is encrypted right here, then sent to your relay. '
              'Only your main phone can open it.'
          : 'Put this phone where it should watch, then start. Everything it '
              'records is encrypted here before it leaves.';

  String get _footnote =>
      _running
          ? 'Leave it plugged in. The screen can go dark, recording keeps going.'
          : 'Nothing is being recorded right now.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CamRole.bg,
      body: DimWhenIdle(
        enabled: _running && _settings.keepScreenDark,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  recording: _running && _settings.showRecLight,
                  onSettings: _openSettings,
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: _Stage(
                        recording: _running,
                        title: _title,
                        body: _body,
                      ),
                    ),
                  ),
                ),
                if (!_running) ...[
                  EditorialButton(
                    label: _starting ? 'Starting...' : 'Start recording',
                    onPressed: _starting ? null : _start,
                    primary: true,
                  ),
                  const SizedBox(height: 22),
                ],
                StatRows(
                  children: [
                    StatRow(
                      label: 'Status',
                      value: _statusLabel,
                      valueColor: _statusColor,
                      dotColor: _statusColor,
                    ),
                    StatRow(
                      label: 'Watching since',
                      value: _formatSince(_watchingSince),
                    ),
                    // Placeholders
                    StatRow(
                      label: 'Sent to relay',
                      value: _watchingSince == null ? '—' : '1.2 MB',
                    ),
                    StatRow(
                      label: 'Waiting to send',
                      value: _watchingSince == null ? '—' : '0 clips',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                EditorialFootnote(_footnote),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _statusLabel {
    if (_running) return 'Recording';
    return _starting ? 'Starting' : 'Stopped';
  }

  Color get _statusColor => _running ? CamRole.success : CamRole.warning;

  static String _formatSince(DateTime? time) {
    if (time == null) return 'Not started';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour < 12 ? 'AM' : 'PM';
    return '${days[time.weekday - 1]} $hour:$minute $period';
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.recording, required this.onSettings});

  final bool recording;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (recording) const _RecLight() else const SizedBox.shrink(),
        const Spacer(),
        IconButton(
          onPressed: onSettings,
          icon: const Icon(Icons.settings_outlined),
          color: CamRole.dim(0.52),
          iconSize: 21,
          tooltip: 'Camera settings',
        ),
      ],
    );
  }
}

/// The small breathing REC indicator.
class _RecLight extends StatefulWidget {
  const _RecLight();

  @override
  State<_RecLight> createState() => _RecLightState();
}

class _RecLightState extends State<_RecLight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        still
            ? const _Dot(opacity: 0.7)
            : AnimatedBuilder(
              animation: _c,
              builder: (context, _) => _Dot(opacity: 1 - _c.value * 0.78),
            ),
        const SizedBox(width: 8),
        Text(
          'REC',
          style: CamRoleText.eyebrow.copyWith(
            color: CamRole.danger,
            fontSize: 11,
            letterSpacing: 11 * 0.22,
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      color: CamRole.danger.withValues(alpha: opacity),
      shape: BoxShape.circle,
    ),
  );
}

/// The mark and the copy that explains what this phone is doing.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.recording,
    required this.title,
    required this.body,
  });

  final bool recording;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 210,
          height: 138,
          child: CameraKeeperMark(recording: recording),
        ),
        const SizedBox(height: 18),
        Text('THIS PHONE IS A CAMERA', style: CamRoleText.eyebrow),
        const SizedBox(height: 8),
        Text(title, textAlign: TextAlign.center, style: CamRoleText.display),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: CamRoleText.bodyTight,
          ),
        ),
      ],
    );
  }
}
