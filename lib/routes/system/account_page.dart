//! SPDX-License-Identifier: GPL-3.0-or-later
//
// The relay account and the plans on it.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/system/system_marks.dart';
import 'package:secluso_flutter/routes/system/system_models.dart';
import 'package:secluso_flutter/routes/system/system_theme.dart';
import 'package:secluso_flutter/routes/system/system_widgets.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({
    required this.email,
    required this.monthlyTotal,
    required this.plans,
    required this.onOpenPlan,
    required this.onAttachPlan,
    required this.onCancelPlan,
    required this.onSignOut,
    super.key,
  });

  final String email;

  /// Headline total, e.g. "$22".
  final String monthlyTotal;

  final List<AccountPlan> plans;

  final ValueChanged<AccountPlan> onOpenPlan;
  final ValueChanged<AccountPlan> onAttachPlan;
  final ValueChanged<AccountPlan> onCancelPlan;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final palette = SystemPalette.of(context);
    final inUse = plans.where((p) => !p.isOpenSlot).length;
    final open = plans.length - inUse;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            DetailHeader(title: 'Account', palette: palette),

            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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
                  const SizedBox(width: 12),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: monthlyTotal,
                          style: palette.relayName.copyWith(fontSize: 21),
                        ),
                        TextSpan(
                          text: '/mo',
                          style: palette.relayStatus.copyWith(
                            fontSize: 13,
                            color: palette.dim(0.52),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                'Each plan is a slot. Remove a camera and its plan frees up for '
                'the next one.',
                style: palette.emptyBody.copyWith(fontSize: 13.5, height: 1.5),
              ),
            ),

            SectionHead(
              label: 'Your plans',
              palette: palette,
              note: '$inUse in use · $open open',
            ),

            for (final plan in plans)
              _PlanRow(
                plan: plan,
                palette: palette,
                onTap: plan.isOpenSlot ? null : () => onOpenPlan(plan),
                onAttach: () => onAttachPlan(plan),
                onCancel: () => onCancelPlan(plan),
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

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.plan,
    required this.palette,
    required this.onTap,
    required this.onAttach,
    required this.onCancel,
  });

  final AccountPlan plan;
  final SystemPalette palette;

  /// Null on an open slot, which offers its own actions instead.
  final VoidCallback? onTap;

  final VoidCallback onAttach;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SystemTappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (plan.isOpenSlot) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: 36,
                  height: 30,
                  child: OpenSlotMark(palette: palette),
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          plan.cameraName ?? 'Open slot',
                          overflow: TextOverflow.ellipsis,
                          style: palette.cameraName.copyWith(
                            color:
                                plan.isOpenSlot
                                    ? palette.dim(0.52)
                                    : palette.text,
                          ),
                        ),
                      ),
                      if (plan.shared) ...[
                        const SizedBox(width: 7),
                        SystemDot(size: 4, color: palette.dim(0.38)),
                        const SizedBox(width: 4),
                        Text('shared', style: palette.sharedTag),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: plan.tier.label.toUpperCase(),
                          style: TextStyle(color: palette.tierColor(plan.tier)),
                        ),
                        TextSpan(
                          text:
                              '  ·  ${plan.price.toUpperCase()}'
                              '  ·  ${plan.renewal.toUpperCase()}',
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: palette.cameraMeta,
                  ),
                  if (plan.isOpenSlot) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _PlanLink(
                          label: 'Attach to a camera',
                          palette: palette,
                          onTap: onAttach,
                        ),
                        const SizedBox(width: 24),
                        _PlanLink(
                          label: 'Cancel plan',
                          palette: palette,
                          onTap: onCancel,
                          danger: true,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (!plan.isOpenSlot) ...[
              const SizedBox(width: 12),
              SystemChevron(palette: palette, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanLink extends StatelessWidget {
  const _PlanLink({
    required this.label,
    required this.palette,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final SystemPalette palette;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return SystemTappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          label,
          style: palette.action.copyWith(
            color: danger ? palette.danger : palette.blue,
          ),
        ),
      ),
    );
  }
}
