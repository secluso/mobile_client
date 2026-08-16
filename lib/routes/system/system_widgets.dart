//! SPDX-License-Identifier: GPL-3.0-or-later
//
// The rows the System-area screens are built from

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/system/system_theme.dart';

/// Back button and title, the standard head for a pushed System screen.
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    required this.title,
    required this.palette,
    this.eyebrow,
    this.compact = false,
    super.key,
  });

  final String title;
  final SystemPalette palette;

  /// Sits above the title, e.g. "PLAN · FRONT DOOR".
  final String? eyebrow;

  /// A 44pt button instead of 50pt, when an eyebrow makes the head taller.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final eyebrowText = eyebrow;
    final size = compact ? 44.0 : 50.0;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            color: palette.text.withValues(alpha: 0.05),
            shape: CircleBorder(side: BorderSide(color: palette.hairline)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              child: SizedBox.square(
                dimension: size,
                child: Icon(
                  Icons.chevron_left_rounded,
                  color: palette.text,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrowText != null) ...[
                  Text(eyebrowText.toUpperCase(), style: palette.eyebrow),
                  const SizedBox(height: 4),
                ],
                Text(title, style: palette.relayName.copyWith(fontSize: 23)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header with an optional counterpart on the right.
class SectionHead extends StatelessWidget {
  const SectionHead({
    required this.label,
    required this.palette,
    this.note,
    this.action,
    this.onAction,
    this.topGap = 22,
    super.key,
  });

  final String label;
  final SystemPalette palette;

  /// Quiet text on the right, e.g. "2 in use · 1 open".
  final String? note;

  /// Blue call to action on the right. Takes precedence over [note].
  final String? action;
  final VoidCallback? onAction;

  final double topGap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: topGap),
      padding: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label.toUpperCase(), style: palette.sectionLabel),
          ),
          if (action != null)
            SystemTappable(
              onTap: onAction,
              child: Text(action!, style: palette.action),
            )
          else if (note != null)
            Text(note!, style: palette.sectionNote),
        ],
      ),
    );
  }
}

/// A key against its value, for the quiet ledger blocks.
class StatRow extends StatelessWidget {
  const StatRow({
    required this.label,
    required this.value,
    required this.palette,
    this.valueColor,
    this.dotColor,
    this.trailing,
    super.key,
  });

  final String label;
  final String value;
  final SystemPalette palette;
  final Color? valueColor;

  /// A small status dot before the value.
  final Color? dotColor;

  /// Dimmer text after the value, e.g. "of 2 TB".
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label.toUpperCase(), style: palette.rowKey)),
          const SizedBox(width: 12),
          if (dotColor != null) ...[
            SystemDot(size: 6, color: dotColor!),
            const SizedBox(width: 8),
          ],
          Text(
            value,
            style:
                valueColor == null
                    ? palette.rowValue
                    : palette.rowValue.copyWith(color: valueColor),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 5),
            Text(
              trailing!,
              style: palette.rowValue.copyWith(color: palette.dim(0.38)),
            ),
          ],
        ],
      ),
    );
  }
}

/// A full-width row that leads somewhere, e.g. "Change plan".
class LinkRow extends StatelessWidget {
  const LinkRow({
    required this.label,
    required this.palette,
    required this.onTap,
    this.danger = false,
    this.showChevron = true,
    this.topGap = 0,
    super.key,
  });

  final String label;
  final SystemPalette palette;
  final VoidCallback onTap;
  final bool danger;

  /// Destructive rows in the design carry no chevron.
  final bool showChevron;

  final double topGap;

  @override
  Widget build(BuildContext context) {
    return SystemTappable(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(top: topGap + 13, bottom: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: palette.linkRow.copyWith(
                  color: danger ? palette.danger : palette.text,
                ),
              ),
            ),
            if (showChevron) SystemChevron(palette: palette, size: 18),
          ],
        ),
      ),
    );
  }
}

/// A closing invitation: a hand-drawn mark, a question, and where it leads.
class InvitationRow extends StatelessWidget {
  const InvitationRow({
    required this.mark,
    required this.eyebrow,
    required this.title,
    required this.palette,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final Widget mark;
  final String eyebrow;
  final String title;
  final SystemPalette palette;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return SystemTappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 30, bottom: 8),
        child: Row(
          children: [
            SizedBox(width: 46, height: 38, child: mark),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow.toUpperCase(), style: palette.eyebrow),
                  const SizedBox(height: 5),
                  Text(
                    title,
                    style: palette.linkRow.copyWith(
                      color: danger ? palette.danger : palette.text,
                    ),
                  ),
                ],
              ),
            ),
            SystemChevron(palette: palette, size: 18),
          ],
        ),
      ),
    );
  }
}

/// The lock footnote that closes several of these screens.
class EncryptionNote extends StatelessWidget {
  const EncryptionNote({
    required this.text,
    required this.palette,
    this.topGap = 22,
    super.key,
  });

  final String text;
  final SystemPalette palette;
  final double topGap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.lock_rounded,
              size: 14,
              color: palette.success.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: palette.footnote)),
        ],
      ),
    );
  }
}

class SystemChevron extends StatelessWidget {
  const SystemChevron({required this.palette, required this.size, super.key});

  final SystemPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.chevron_right_rounded, size: size, color: palette.dim(0.38));
}

class SystemDot extends StatelessWidget {
  const SystemDot({required this.size, required this.color, super.key});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Keeps rows flush to the page edges
class SystemTappable extends StatefulWidget {
  const SystemTappable({required this.onTap, required this.child, super.key});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<SystemTappable> createState() => _SystemTappableState();
}

class _SystemTappableState extends State<SystemTappable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedOpacity(
        opacity: _down ? 0.6 : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

/// Full-width filled button, for the one action a screen is really asking for.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.palette,
    required this.onPressed,
    super.key,
  });

  final String label;
  final SystemPalette palette;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.blue,
      borderRadius: BorderRadius.circular(14),
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
              style: palette.linkRow.copyWith(
                fontWeight: FontWeight.w700,
                color: palette.bg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The outlined second path. A real option, not fine print.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.palette,
    required this.onPressed,
    super.key,
  });

  final String label;
  final SystemPalette palette;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.ink.withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: palette.linkRow.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

/// The third way out of a screen, deliberately quiet.
class QuietLink extends StatelessWidget {
  const QuietLink({
    required this.label,
    required this.palette,
    required this.onTap,
    super.key,
  });

  final String label;
  final SystemPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SystemTappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: palette.relayEndpoint.copyWith(letterSpacing: -0.1),
        ),
      ),
    );
  }
}
