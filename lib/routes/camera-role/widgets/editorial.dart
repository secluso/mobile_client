//! SPDX-License-Identifier: GPL-3.0-or-later
//
// The pieces the camera-role screens are built from.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/camera-role/theme.dart';

/// Mono eyebrow, title, and a paragraph of explanation. Left aligned.
class EditorialHeader extends StatelessWidget {
  const EditorialHeader({
    required this.eyebrow,
    required this.title,
    required this.body,
    this.action,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String body;

  /// Sits opposite the eyebrow, for a close or dismiss control.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(eyebrow.toUpperCase(), style: CamRoleText.eyebrow),
            ),
            if (action != null) action!,
          ],
        ),
        const SizedBox(height: 6),
        Text(title, style: CamRoleText.title),
        const SizedBox(height: 14),
        Text(body, style: CamRoleText.body),
      ],
    );
  }
}

/// Centred mono line at the foot of a screen.
class EditorialFootnote extends StatelessWidget {
  const EditorialFootnote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, textAlign: TextAlign.center, style: CamRoleText.footnote);
}

/// Full-width action button.
class EditorialButton extends StatelessWidget {
  const EditorialButton({
    required this.label,
    required this.onPressed,
    this.primary = false,
    super.key,
  });

  /// Hairline in the warm ink, not plain white, so outlines sit on the ground.
  static const _outline = Color(0x1AF5ECDE);

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: primary ? CamRole.blue : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: primary ? BorderSide.none : const BorderSide(color: _outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 17),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: CamRoleText.settingKey.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: primary ? const Color(0xFF0A0A0A) : CamRole.paper,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 50pt circular button for back and close.
class RoundNavButton extends StatelessWidget {
  const RoundNavButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CamRole.paper.withValues(alpha: 0.05),
      shape: CircleBorder(side: BorderSide(color: CamRole.hairline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: SizedBox.square(
            dimension: 50,
            child: Icon(icon, color: CamRole.paper, size: 22),
          ),
        ),
      ),
    );
  }
}

/// A group of key/value rows under a single hairline.
class StatRows extends StatelessWidget {
  const StatRows({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CamRole.hairline)),
      ),
      child: Column(children: children),
    );
  }
}

/// One uppercase key against its value, optionally led by a status dot.
class StatRow extends StatelessWidget {
  const StatRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.dotColor,
    super.key,
  });

  final String label;
  final String value;
  final Color? valueColor;

  /// Draws a small dot before the value, for live status.
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Expanded(child: Text(label.toUpperCase(), style: CamRoleText.rowKey)),
          const SizedBox(width: 12),
          if (dotColor != null) ...[
            _Dot(color: dotColor!),
            const SizedBox(width: 8),
          ],
          Text(
            value,
            style:
                valueColor == null
                    ? CamRoleText.rowValue
                    : CamRoleText.rowValue.copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Section header on a settings screen, with the rule that separates it from
/// the rows beneath.
class SectionHead extends StatelessWidget {
  const SectionHead(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 24, bottom: 14),
      padding: const EdgeInsets.only(bottom: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CamRole.hairline)),
      ),
      child: Text(label.toUpperCase(), style: CamRoleText.sectionLabel),
    );
  }
}

/// A settings row: a title, an optional explanation, and something on the
/// right (a value, a chevron, or a toggle).
class SettingRow extends StatelessWidget {
  const SettingRow({
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Right-hand text. A chevron is added alongside it when [onTap] is set.
  final String? value;

  /// Replaces [value] entirely, for a toggle.
  final Widget? trailing;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CamRoleText.settingKey),
                if (sub != null) ...[
                  const SizedBox(height: 4),
                  Text(sub, style: CamRoleText.settingSub),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          if (trailing != null)
            trailing!
          else ...[
            if (value != null) Text(value!, style: CamRoleText.settingValue),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: CamRole.dim(0.38),
              ),
            ],
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// The app's pill toggle.
class SeclusoToggle extends StatelessWidget {
  const SeclusoToggle({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    super.key,
  });

  static const _track = Size(50, 30);
  static const _knob = 24.0;
  static const _padding = 3.0;

  final bool value;
  final ValueChanged<bool> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: _track.width,
          height: _track.height,
          decoration: BoxDecoration(
            color:
                value
                    ? const Color(0xFF8FB5F4)
                    : CamRole.paper.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: _padding),
          child: Container(
            width: _knob,
            height: _knob,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// A closing invitation rather than a settings row
class InvitationRow extends StatelessWidget {
  const InvitationRow({
    required this.mark,
    required this.eyebrow,
    required this.title,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final Widget mark;
  final String eyebrow;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Row(
          children: [
            SizedBox(width: 46, height: 38, child: mark),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow.toUpperCase(), style: CamRoleText.eyebrow),
                  const SizedBox(height: 5),
                  Text(
                    title,
                    style: CamRoleText.settingKey.copyWith(
                      color: danger ? CamRole.danger : CamRole.paper,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: CamRole.dim(0.38),
            ),
          ],
        ),
      ),
    );
  }
}
