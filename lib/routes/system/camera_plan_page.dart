//! SPDX-License-Identifier: GPL-3.0-or-later
//
// One camera's subscription

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/system/system_marks.dart';
import 'package:secluso_flutter/routes/system/system_models.dart';
import 'package:secluso_flutter/routes/system/system_theme.dart';
import 'package:secluso_flutter/routes/system/system_widgets.dart';

class CameraPlanPage extends StatelessWidget {
  const CameraPlanPage({
    required this.detail,
    required this.onShare,
    required this.onChangePlan,
    required this.onCancel,
    super.key,
  });

  final CameraPlanDetail detail;
  final VoidCallback onShare;
  final VoidCallback onChangePlan;
  final VoidCallback onCancel;

  String get _sharedSummary {
    final others = detail.people.where((p) => !p.isOwner).toList();
    if (others.isEmpty) return 'Only you';
    if (others.length == 1) return 'You and ${others.first.name}';
    return 'You and ${others.length} others';
  }

  @override
  Widget build(BuildContext context) {
    final palette = SystemPalette.of(context);
    final people = detail.people.length;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            DetailHeader(title: detail.cameraName, palette: palette),

            Padding(
              padding: const EdgeInsets.only(top: 26),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("THIS CAMERA'S PLAN", style: palette.eyebrow),
                        const SizedBox(height: 9),
                        Text(
                          detail.tier.label,
                          style: palette.planName.copyWith(
                            color: palette.tierColor(detail.tier),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  // The tier's own mark. Only Anonymous has one to show.
                  if (detail.tier == PlanTier.anonymous)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: SizedBox(
                        width: 80,
                        height: 42,
                        child: CrowdMark(palette: palette, roughness: 0.8),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(detail.meta, style: palette.planMeta),
            const SizedBox(height: 16),
            Text(
              detail.line,
              style: palette.emptyBody.copyWith(fontSize: 13, height: 1.5),
            ),

            SectionHead(label: 'This month', palette: palette, topGap: 26),
            StatRow(
              label: 'Stored on relay',
              value: detail.storedOnRelay,
              trailing: 'of ${detail.storedLimit}',
              palette: palette,
            ),
            StatRow(
              label: 'Motion clips',
              value: detail.motionClips,
              palette: palette,
            ),
            StatRow(
              label: 'Livestream',
              value: detail.livestream,
              palette: palette,
            ),

            SectionHead(
              label: 'Shared with',
              palette: palette,
              note: people == 1 ? '1 person' : '$people people',
              topGap: 26,
            ),
            SystemTappable(
              onTap: onShare,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_sharedSummary, style: palette.linkRow),
                          const SizedBox(height: 4),
                          Text(
                            'They watch free. It never touches your plan.',
                            style: palette.emptyBody.copyWith(
                              fontSize: 12.5,
                              height: 1.35,
                              color: palette.dim(0.38),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    SystemChevron(palette: palette, size: 18),
                  ],
                ),
              ),
            ),

            LinkRow(
              label: 'Change plan',
              palette: palette,
              onTap: onChangePlan,
              topGap: 32,
            ),
            LinkRow(
              label: 'Cancel subscription',
              palette: palette,
              onTap: onCancel,
              danger: true,
              showChevron: false,
            ),
          ],
        ),
      ),
    );
  }
}
