//! SPDX-License-Identifier: GPL-3.0-or-later
//
// On-device settings for a phone that is acting as a camera.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/camera-role/camera_role_settings.dart';
import 'package:secluso_flutter/routes/camera-role/theme.dart';
import 'package:secluso_flutter/routes/camera-role/widgets/editorial.dart';
import 'package:secluso_flutter/routes/camera-role/widgets/marks.dart';

class CameraRoleSettingsPage extends StatefulWidget {
  const CameraRoleSettingsPage({
    required this.cameraName,
    required this.settings,
    required this.onSettingsChanged,
    this.recording = false,
    this.onStopRecording,
    this.onUnpair,
    this.onSwitchRole,
    super.key,
  });

  /// Name this camera was given from the main phone.
  final String cameraName;

  final CameraRoleSettings settings;

  /// Called with the new settings whenever a toggle changes
  final ValueChanged<CameraRoleSettings> onSettingsChanged;

  final bool recording;

  /// Stops recording and leaves the camera role, keeping the pairing.
  final Future<void> Function()? onStopRecording;

  /// Deletes this phone's camera state, so it is no longer a camera at all.
  final Future<void> Function()? onUnpair;

  final Future<void> Function()? onSwitchRole;

  @override
  State<CameraRoleSettingsPage> createState() => _CameraRoleSettingsPageState();
}

class _CameraRoleSettingsPageState extends State<CameraRoleSettingsPage> {
  late CameraRoleSettings _settings = widget.settings;
  bool _busy = false;

  Future<void> _update(CameraRoleSettings next) async {
    setState(() => _settings = next);
    widget.onSettingsChanged(next);
    await next.save();
  }

  /// Runs a destructive action behind a confirmation, then leaves this screen.
  Future<void> _confirm({
    required String title,
    required String body,
    required String action,
    required Future<void> Function()? run,
  }) async {
    if (run == null || _busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF161616),
            title: Text(title, style: CamRoleText.title),
            content: Text(body, style: CamRoleText.body),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(
                  'Cancel',
                  style: CamRoleText.settingValue.copyWith(
                    color: CamRole.paper,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(
                  action,
                  style: CamRoleText.settingKey.copyWith(color: CamRole.danger),
                ),
              ),
            ],
          ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await run();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CamRole.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  RoundNavButton(
                    icon: Icons.chevron_left_rounded,
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Camera settings',
                      style: CamRoleText.display.copyWith(fontSize: 23),
                    ),
                  ),
                ],
              ),

              const SectionHead('This phone'),
              SettingRow(
                title: 'Name',
                subtitle: 'Rename it from your main phone',
                value: widget.cameraName,
              ),
              SettingRow(title: 'Lens', value: _settings.lens ?? 'Not set'),
              SettingRow(
                title: 'Video quality',
                value: _settings.quality ?? 'Not set',
              ),

              const SectionHead('While recording'),
              SettingRow(
                title: 'Keep the screen dark',
                subtitle: 'Saves battery and draws less attention',
                trailing: SeclusoToggle(
                  value: _settings.keepScreenDark,
                  semanticLabel: 'Keep the screen dark',
                  onChanged:
                      (v) => _update(_settings.copyWith(keepScreenDark: v)),
                ),
              ),
              SettingRow(
                title: 'Show a small REC light',
                trailing: SeclusoToggle(
                  value: _settings.showRecLight,
                  semanticLabel: 'Show a small REC light',
                  onChanged:
                      (v) => _update(_settings.copyWith(showRecLight: v)),
                ),
              ),
              if (widget.recording && widget.onStopRecording != null)
                SettingRow(
                  title: 'Stop recording',
                  subtitle: 'Stays paired, so you can start again later',
                  onTap:
                      () => _confirm(
                        title: 'Stop recording?',
                        body:
                            'This phone stops watching and returns to choosing '
                            'a role. It stays paired to your main phone.',
                        action: 'Stop',
                        run: widget.onStopRecording,
                      ),
                ),

              if (widget.onSwitchRole != null) ...[
                const SectionHead('This device'),
                SettingRow(
                  title: 'Switch role',
                  subtitle: 'Use this phone to watch cameras instead',
                  onTap: _busy ? null : () async => widget.onSwitchRole!(),
                ),
              ],

              const SizedBox(height: 30),
              InvitationRow(
                mark: const UnplugMark(),
                eyebrow: 'Done being a camera?',
                title: 'Stop and unpair',
                danger: true,
                onTap:
                    () => _confirm(
                      title: 'Stop and unpair?',
                      body:
                          "This deletes this camera's keys and recordings from "
                          'this phone. You cannot undo it, and you will need to '
                          'pair again from your main phone.',
                      action: 'Unpair',
                      run: widget.onUnpair,
                    ),
              ),

              const SizedBox(height: 22),
              const _SealedNote(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The quiet reassurance at the foot of the screen.
class _SealedNote extends StatelessWidget {
  const _SealedNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.lock_rounded, size: 15, color: CamRole.success),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'End-to-end encrypted. This phone seals every frame before it '
            'leaves.',
            style: CamRoleText.body.copyWith(fontSize: 14.5),
          ),
        ),
      ],
    );
  }
}
