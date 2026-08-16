//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Home with the relay up but no cameras yet.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/system/system_marks.dart';
import 'package:secluso_flutter/routes/system/system_theme.dart';
import 'package:secluso_flutter/routes/system/system_widgets.dart';

class HomeEmptyPage extends StatelessWidget {
  const HomeEmptyPage({
    required this.relayConnected,
    required this.onAddCamera,
    super.key,
  });

  final bool relayConnected;
  final VoidCallback onAddCamera;

  @override
  Widget build(BuildContext context) {
    final palette = SystemPalette.of(context);
    return Material(
      color: palette.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Row(
            children: [
              Expanded(child: Text('Secluso', style: palette.title)),
              _AddButton(palette: palette, onTap: onAddCamera),
            ],
          ),

          const SizedBox(height: 8),
          Row(
            children: [
              SystemDot(
                size: 9,
                color: relayConnected ? palette.success : palette.danger,
              ),
              const SizedBox(width: 9),
              Text(
                relayConnected ? 'RELAY CONNECTED' : 'RELAY OFFLINE',
                style: palette.cameraState.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.only(top: 26),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = (constraints.maxWidth * 0.86).clamp(
                      0.0,
                      268.0,
                    );
                    return SizedBox(
                      width: width,
                      height: width / EmptyFeedMark.aspect,
                      child: EmptyFeedMark(palette: palette),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Text('No cameras yet.', style: palette.emptyTitle),
                const SizedBox(height: 8),
                Text('Your relay is ready.', style: palette.emptyBody),
                const SizedBox(height: 30),
                _SketchButton(palette: palette, onTap: onAddCamera),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(top: 34),
            child: LayoutBuilder(
              builder:
                  (context, constraints) => SizedBox(
                    height: constraints.maxWidth / GhostRowsMark.aspect,
                    child: GhostRowsMark(palette: palette),
                  ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'A spare Android phone is all it takes.',
              textAlign: TextAlign.center,
              style: palette.eyebrow.copyWith(
                fontSize: 11,
                letterSpacing: 11 * 0.04,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.palette, required this.onTap});

  final SystemPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.text.withValues(alpha: 0.03),
      shape: CircleBorder(side: BorderSide(color: palette.hairline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Tooltip(
          message: 'Add a camera',
          child: SizedBox.square(
            dimension: 44,
            child: Icon(Icons.add_rounded, color: palette.text, size: 22),
          ),
        ),
      ),
    );
  }
}

/// The one action on the screen, drawn by hand so it does not read as chrome.
class _SketchButton extends StatelessWidget {
  const _SketchButton({required this.palette, required this.onTap});

  final SystemPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SystemTappable(
        onTap: onTap,
        child: SizedBox(
          width: 236,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(child: SketchButtonFrame(palette: palette)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 18, color: palette.blue),
                  const SizedBox(width: 9),
                  Text(
                    'Add your first camera',
                    style: palette.linkRow.copyWith(
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
