//! SPDX-License-Identifier: GPL-3.0-or-later
//
// The relay's own page.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/system/system_marks.dart';
import 'package:secluso_flutter/routes/system/system_models.dart';
import 'package:secluso_flutter/routes/system/system_theme.dart';
import 'package:secluso_flutter/routes/system/system_widgets.dart';

class RelayDetailPage extends StatelessWidget {
  const RelayDetailPage({
    required this.relay,
    required this.cameraCount,
    required this.onSwitchRelay,
    this.onRemoveRelay,
    super.key,
  });

  final SystemRelay relay;
  final int cameraCount;

  /// Moves to the other kind of relay.
  final VoidCallback onSwitchRelay;

  /// Only a relay you run yourself can be removed outright.
  final VoidCallback? onRemoveRelay;

  bool get _selfHosted => relay.isSelfHosted;

  @override
  Widget build(BuildContext context) {
    final palette = SystemPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            DetailHeader(title: 'Your relay', palette: palette),

            Padding(
              padding: const EdgeInsets.only(top: 30, bottom: 18),
              child: _Scene(palette: palette, selfHosted: _selfHosted),
            ),

            Text(
              _selfHosted
                  ? 'You run the server, so there are no plans and nothing to '
                      "pay. Every frame is sealed before it arrives, so even "
                      "your own relay can't watch."
                  : 'Every frame is sealed on the camera before the relay ever '
                      'touches it. It delivers your video without seeing any of '
                      'it. Not even us.',
              style: palette.emptyBody.copyWith(fontSize: 14.5, height: 1.6),
            ),

            SectionHead(label: 'Status', palette: palette, topGap: 30),
            StatRow(label: 'Relay', value: relay.name, palette: palette),
            StatRow(
              label: 'Connection',
              value: relay.connected ? 'Connected' : 'Not connected',
              palette: palette,
              valueColor: relay.connected ? palette.success : palette.danger,
              dotColor: relay.connected ? palette.success : palette.danger,
            ),
            StatRow(label: 'Address', value: relay.endpoint, palette: palette),
            StatRow(
              label: 'Carrying',
              value: cameraCount == 1 ? '1 camera' : '$cameraCount cameras',
              palette: palette,
            ),

            LinkRow(
              label:
                  _selfHosted
                      ? 'Switch to the Secluso relay'
                      : 'Switch to a self-hosted relay',
              palette: palette,
              onTap: onSwitchRelay,
              topGap: 32,
            ),
            if (onRemoveRelay != null)
              LinkRow(
                label: 'Remove relay',
                palette: palette,
                onTap: onRemoveRelay!,
                danger: true,
                showChevron: false,
              ),
          ],
        ),
      ),
    );
  }
}

/// The scene, with the mono captions that ground its endpoints.
class _Scene extends StatelessWidget {
  const _Scene({required this.palette, required this.selfHosted});

  final SystemPalette palette;
  final bool selfHosted;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Captions sit at fixed points in the scene's own 300-unit space.
        double at(double x) => x / 300 * width;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: width / RelayCourierScene.aspect * 0.86,
              child:
                  selfHosted
                      ? SelfHostedScene(palette: palette)
                      : RelayCourierScene(palette: palette),
            ),
            SizedBox(
              height: 14,
              child: Stack(
                children: [
                  _Caption(
                    text: 'Your camera',
                    center: at(31),
                    palette: palette,
                  ),
                  if (selfHosted)
                    _Caption(
                      text: 'Your server',
                      center: at(150),
                      palette: palette,
                    ),
                  _Caption(
                    text: 'This phone',
                    center: at(266),
                    palette: palette,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({
    required this.text,
    required this.center,
    required this.palette,
  });

  final String text;
  final double center;
  final SystemPalette palette;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: center - 60,
      width: 120,
      top: 0,
      child: Text(
        text.toUpperCase(),
        textAlign: TextAlign.center,
        style: palette.eyebrow.copyWith(fontSize: 8, letterSpacing: 8 * 0.18),
      ),
    );
  }
}
