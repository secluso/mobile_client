//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/camera-role/theme.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';

class CameraRoleFlowHeading extends StatelessWidget {
  const CameraRoleFlowHeading({
    required this.scale,
    required this.title,
    required this.body,
    super.key,
  });

  final double scale;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: scale * 20,
            fontWeight: FontWeight.w600,
            height: 30 / 20,
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: scale * 12),
        SizedBox(
          width: scale * 240,
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: cameraRoleWhite40,
              fontSize: scale * 12,
              fontWeight: FontWeight.w400,
              height: 19.5 / 12,
            ),
          ),
        ),
      ],
    );
  }
}

class CameraRoleRingOrb extends StatefulWidget {
  const CameraRoleRingOrb({
    required this.scale,
    required this.icon,
    this.pulse = false,
    super.key,
  });

  final double scale;
  final IconData icon;
  final bool pulse;

  @override
  State<CameraRoleRingOrb> createState() => _CameraRoleRingOrbState();
}

class _CameraRoleRingOrbState extends State<CameraRoleRingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double sz(double v) => v * widget.scale;
    Widget ring(double d, Color color) => Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: sz(2)),
      ),
    );
    final orb = SizedBox(
      width: sz(80),
      height: sz(80),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ring(sz(80), const Color(0x4D10B981)),
          ring(sz(64), const Color(0x3310B981)),
          Container(
            width: sz(56),
            height: sz(56),
            decoration: BoxDecoration(
              color: cameraRoleEmerald,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: const Color(0x6622C55E), blurRadius: sz(24)),
              ],
            ),
            child: Icon(widget.icon, color: Colors.white, size: sz(26)),
          ),
        ],
      ),
    );
    if (!widget.pulse) return orb;
    return SizedBox(
      width: sz(80) * 1.8,
      height: sz(80) * 1.8,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: sz(80) * (1 + t * 0.8),
                height: sz(80) * (1 + t * 0.8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cameraRoleEmerald.withValues(alpha: (1 - t) * 0.22),
                    width: sz(1.5),
                  ),
                ),
              ),
              orb,
            ],
          );
        },
      ),
    );
  }
}

class CameraRoleInfoCard extends StatelessWidget {
  const CameraRoleInfoCard({
    required this.scale,
    required this.rows,
    super.key,
  });

  final double scale;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(scale * 12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(children: rows),
    );
  }
}

class CameraRoleInfoRow extends StatelessWidget {
  const CameraRoleInfoRow({
    required this.scale,
    required this.label,
    required this.value,
    this.leading,
    this.valueColor = Colors.white,
    this.mono = false,
    this.showDivider = true,
    super.key,
  });

  final double scale;
  final String label;
  final String value;
  final Widget? leading;
  final Color valueColor;
  final bool mono;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final base = mono ? GoogleFonts.robotoMono() : GoogleFonts.inter();
    return Container(
      height: scale * 47,
      padding: EdgeInsets.symmetric(horizontal: scale * 14),
      decoration: BoxDecoration(
        border:
            showDivider
                ? Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                )
                : null,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: cameraRoleWhite40,
              fontSize: scale * 11,
              fontWeight: FontWeight.w400,
              height: 16.5 / 11,
            ),
          ),
          const Spacer(),
          if (leading != null) ...[leading!, SizedBox(width: scale * 6)],
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: base.copyWith(
                color: valueColor,
                fontSize: scale * 12,
                fontWeight: FontWeight.w500,
                height: 18 / 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CameraRoleTintedCard extends StatelessWidget {
  const CameraRoleTintedCard({
    required this.scale,
    required this.accent,
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final double scale;
  final Color accent;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(scale * 12),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
      ),
      padding: EdgeInsets.all(scale * 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: scale * 2),
            child: Icon(icon, color: accent, size: scale * 16),
          ),
          SizedBox(width: scale * 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: accent,
                    fontSize: scale * 11,
                    fontWeight: FontWeight.w600,
                    height: 16.5 / 11,
                  ),
                ),
                SizedBox(height: scale * 8),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    color: cameraRoleWhite40,
                    fontSize: scale * 10,
                    fontWeight: FontWeight.w400,
                    height: 16.25 / 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
