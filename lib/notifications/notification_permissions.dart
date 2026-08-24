//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/routes/camera/camera_ui_bridge.dart';

/// The in-app ask that comes before the OS permission dialog
Future<bool> askToEnableAlerts(BuildContext context) async {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  final bg = dark ? const Color(0xFF111214) : Colors.white;
  final fg = dark ? Colors.white : const Color(0xFF111214);
  final muted =
      dark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF6B7280);
  const accent = Color(0xFF8BB3EE);

  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: bg,
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0x268BB3EE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: accent,
                  size: 26,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Know the moment something moves',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your camera is paired. Next, let Secluso alert you when it '
                'detects motion. An alert only says that something happened; '
                'the clip stays encrypted until you open it on this phone.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: muted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: const Color(0xFF0A0A0A),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: const Text(
                  'Turn on alerts',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: Text(
                  'Not now',
                  style: TextStyle(color: muted, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

/// A first camera was just paired. Home asks about alerts (explainer first)
/// the moment it is back on screen; asking here would put the dialogs over
/// the pairing card that is still closing.
Future<void> requestNotificationsAfterFirstCameraAdd() async {
  final prefs = await SharedPreferences.getInstance();
  final notificationsRequested =
      prefs.getBool(PrefKeys.notificationsEnabled) ?? true;
  if (!notificationsRequested) {
    return;
  }
  CameraUiBridge.pendingFirstCameraAlertAsk = true;
}
