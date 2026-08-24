//! SPDX-License-Identifier: GPL-3.0-or-later
//
// The relay account and its plan.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/system/system_marks.dart';
import 'package:secluso_flutter/routes/system/system_models.dart';
import 'package:secluso_flutter/routes/system/system_theme.dart';
import 'package:secluso_flutter/routes/system/system_widgets.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({
    required this.email,
    required this.plan,
    required this.onOpenCamera,
    required this.onChangePlan,
    required this.onCancel,
    required this.onSignOut,
    super.key,
  });

  final String email;

  /// The one plan on this account.
  final AccountPlanSummary plan;

  final ValueChanged<AccountCamera> onOpenCamera;
  final VoidCallback onChangePlan;
  final VoidCallback onCancel;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final palette = SystemPalette.of(context);
    final cameras = plan.cameras;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            DetailHeader(title: 'Account', palette: palette),

            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SIGNED IN', style: palette.eyebrow),
                  const SizedBox(height: 6),
                  Text(
                    email,
                    overflow: TextOverflow.ellipsis,
                    style: palette.relayName.copyWith(
                      fontSize: 19,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            _PlanCard(plan: plan, palette: palette),

            SectionHead(
              label: 'Your cameras',
              palette: palette,
              note:
                  cameras.length == 1
                      ? '1 camera'
                      : '${cameras.length} cameras',
              topGap: 26,
            ),
            if (cameras.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Cameras you add share this plan.',
                  style: palette.emptyBody.copyWith(fontSize: 13, height: 1.4),
                ),
              )
            else
              for (final camera in cameras)
                _CameraRow(
                  camera: camera,
                  palette: palette,
                  onTap: () => onOpenCamera(camera),
                ),

            LinkRow(
              label: 'Change plan',
              palette: palette,
              onTap: onChangePlan,
              topGap: 30,
            ),
            LinkRow(
              label: 'Cancel subscription',
              palette: palette,
              onTap: onCancel,
              danger: true,
              showChevron: false,
            ),

            InvitationRow(
              mark: DoorMark(palette: palette),
              eyebrow: 'Done on this phone?',
              title: 'Sign out',
              palette: palette,
              danger: true,
              onTap: onSignOut,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.palette});

  final AccountPlanSummary plan;
  final SystemPalette palette;

  Color get _border => switch (plan.tier) {
    PlanTier.free => palette.hairline,
    PlanTier.premium => palette.blue.withValues(alpha: 0.26),
    PlanTier.anonymous => palette.mint.withValues(alpha: 0.26),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: palette.dim(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  plan.tier.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: palette.planName.copyWith(
                    fontSize: 30,
                    color:
                        plan.tier == PlanTier.free
                            ? palette.text
                            : palette.tierColor(plan.tier),
                    fontStyle:
                        plan.tier == PlanTier.anonymous
                            ? FontStyle.italic
                            : FontStyle.normal,
                  ),
                ),
              ),
              if (plan.price.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  plan.price,
                  style: palette.relayName.copyWith(fontSize: 18),
                ),
              ],
            ],
          ),
          if (plan.renewal.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(plan.renewal, style: palette.planMeta),
          ],
          const SizedBox(height: 16),
          _UsageMeter(plan: plan, palette: palette),
          const SizedBox(height: 12),
          Text(
            'Shared across your cameras · ${plan.viewersNote}',
            style: palette.emptyBody.copyWith(
              fontSize: 12.5,
              height: 1.4,
              color: palette.dim(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageMeter extends StatelessWidget {
  const _UsageMeter({required this.plan, required this.palette});

  final AccountPlanSummary plan;
  final SystemPalette palette;

  @override
  Widget build(BuildContext context) {
    final fill =
        plan.tier == PlanTier.free
            ? palette.text
            : palette.tierColor(plan.tier);
    final fraction = plan.usedFraction.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              plan.usedLabel,
              style: palette.rowValue.copyWith(fontSize: 15),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Text(
                'of ${plan.limitLabel}',
                style: palette.cameraMeta.copyWith(color: palette.dim(0.45)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 6, color: palette.dim(0.09)),
              FractionallySizedBox(
                widthFactor: fraction,
                child: Container(height: 6, color: fill),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CameraRow extends StatelessWidget {
  const _CameraRow({
    required this.camera,
    required this.palette,
    required this.onTap,
  });

  final AccountCamera camera;
  final SystemPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SystemTappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          camera.name,
                          overflow: TextOverflow.ellipsis,
                          style: palette.cameraName,
                        ),
                      ),
                      if (camera.shared) ...[
                        const SizedBox(width: 7),
                        SystemDot(size: 4, color: palette.dim(0.38)),
                        const SizedBox(width: 4),
                        Text('shared', style: palette.sharedTag),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    camera.usage != null
                        ? '${camera.usage} of the plan'
                        : 'Shares this plan',
                    style: palette.cameraMeta,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SystemChevron(palette: palette, size: 20),
          ],
        ),
      ),
    );
  }
}
