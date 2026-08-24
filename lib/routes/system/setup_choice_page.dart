//! SPDX-License-Identifier: GPL-3.0-or-later
//
// The two decisions at the start of setup,
//
//   Step 1  what is this phone for?   watch cameras / be a camera
//   Step 2  who runs your relay?      Secluso / self-hosted

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/system/system_marks.dart';
import 'package:secluso_flutter/routes/system/system_theme.dart';
import 'package:secluso_flutter/routes/system/system_widgets.dart';

/// "How will you use this phone?"
class RoleChoicePage extends StatelessWidget {
  const RoleChoicePage({
    required this.onWatchCameras,
    required this.onBeCamera,
    super.key,
  });

  final VoidCallback onWatchCameras;
  final VoidCallback onBeCamera;

  @override
  Widget build(BuildContext context) {
    final palette = SystemPalette.of(context);
    return _SetupScaffold(
      palette: palette,
      step: 1,
      title: 'How will you use this phone?',
      body:
          'Secluso runs on two phones: one you carry to watch, and a spare one '
          'you set down to be the camera. Which is this one?',
      footnote: 'You can change this later.',
      choices: [
        _Choice(
          mark: RoleViewerMark(palette: palette),
          tag: 'Most people start here',
          title: 'Watch my cameras',
          subtitle: 'The phone you carry. Alerts and live video arrive here.',
          onTap: onWatchCameras,
        ),
        _Choice(
          mark: RoleCameraMark(palette: palette),
          title: 'Turn it into a camera',
          subtitle: 'A spare Android phone you leave somewhere to keep watch.',
          onTap: onBeCamera,
        ),
      ],
    );
  }
}

/// "Who runs your relay?"
class RelayChoicePage extends StatelessWidget {
  const RelayChoicePage({
    required this.onSeclusoRelay,
    required this.onSelfHosted,
    this.hasRoleStep = true,
    super.key,
  });

  final VoidCallback onSeclusoRelay;
  final VoidCallback onSelfHosted;

  /// Whether step 1 (what is this phone for) exists on this platform.
  final bool hasRoleStep;

  @override
  Widget build(BuildContext context) {
    final palette = SystemPalette.of(context);
    return _SetupScaffold(
      palette: palette,
      step: hasRoleStep ? 2 : 1,
      totalSteps: hasRoleStep ? 2 : 1,
      title: 'Who runs your relay?',
      body:
          'It carries your encrypted clips from camera to phone, and it can never '
          'see inside.',
      footnote: 'Pick one. You can switch anytime.',
      choices: [
        _Choice(
          mark: RelayChoiceMark(palette: palette),
          tag: 'Recommended',
          title: 'Secluso Relay',
          subtitle: 'We run it for you. Free to start.',
          onTap: onSeclusoRelay,
        ),
        _Choice(
          mark: HostMark(palette: palette),
          title: 'Self-Hosted',
          subtitle: 'You run it on your server. No caps.',
          onTap: onSelfHosted,
        ),
      ],
    );
  }
}

class _SetupScaffold extends StatelessWidget {
  const _SetupScaffold({
    required this.palette,
    required this.step,
    required this.title,
    required this.footnote,
    required this.choices,
    this.body,
    this.totalSteps = 2,
  });

  final SystemPalette palette;

  /// Which of the setup steps this is, and how many there are.
  final int step;
  final int totalSteps;

  final String title;
  final String? body;
  final String footnote;
  final List<_Choice> choices;

  @override
  Widget build(BuildContext context) {
    final bodyText = body;
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 26),
          children: [
            const SizedBox(height: 10),
            _Stepper(step: step, totalSteps: totalSteps, palette: palette),
            const SizedBox(height: 14),
            Text(title, style: palette.title),
            if (bodyText != null) ...[
              const SizedBox(height: 14),
              Text(bodyText, style: palette.subtitle),
            ],
            const SizedBox(height: 30),
            for (final choice in choices) ...[
              choice,
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 10),
            Text(
              footnote,
              textAlign: TextAlign.center,
              style: palette.eyebrow.copyWith(
                fontSize: 11,
                letterSpacing: 11 * 0.04,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two bars and a label, so the pair of screens reads as one guided flow.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.step,
    required this.palette,
    this.totalSteps = 2,
  });

  final int step;
  final int totalSteps;
  final SystemPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= totalSteps; i++) ...[
          if (i > 1) const SizedBox(width: 6),
          Container(
            width: 26,
            height: 3,
            decoration: BoxDecoration(
              color:
                  i <= step
                      ? palette.blue
                      : palette.ink.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
        const SizedBox(width: 12),
        Text(
          totalSteps == 1 ? 'SETUP' : 'SETUP · STEP $step OF $totalSteps',
          style: palette.eyebrow.copyWith(letterSpacing: 10 * 0.2),
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.mark,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tag,
  });

  final Widget mark;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// A small gold pill above the title, on the option most people want.
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final palette = SystemPalette.of(context);
    final tagText = tag;
    return SystemTappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
        decoration: BoxDecoration(
          color: palette.dim(0.02),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                tagText == null
                    ? palette.ink.withValues(alpha: 0.10)
                    : palette.blue.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          children: [
            SizedBox(width: 64, height: 48, child: mark),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tagText != null) ...[
                    _RecommendedTag(label: tagText, palette: palette),
                    const SizedBox(height: 9),
                  ],
                  Text(
                    title,
                    style: palette.relayName.copyWith(
                      fontSize: 21,
                      letterSpacing: -0.3,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: palette.emptyBody.copyWith(
                      fontSize: 14,
                      height: 1.45,
                      color: palette.dim(0.55),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendedTag extends StatelessWidget {
  const _RecommendedTag({required this.label, required this.palette});

  /// Gold, the one warm accent in the palette, reserved for this.
  static const _gold = Color(0xFFF5E2A8);

  final String label;
  final SystemPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _gold,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: palette.eyebrow.copyWith(
          fontSize: 9,
          letterSpacing: 9 * 0.18,
          color: const Color(0xFF0A0A0A),
        ),
      ),
    );
  }
}
