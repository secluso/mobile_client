//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Palette and type for the System tab.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/system/system_models.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';

@immutable
class SystemPalette {
  const SystemPalette({
    required this.bg,
    required this.text,
    required this.warmDim,
    required this.blue,
    required this.mint,
    required this.success,
    required this.danger,
    required this.hairline,
    required this.ink,
    required this.inkDim,
    required this.ghost,
  });

  /// The dark design, taken from the prototype.
  static const dark = SystemPalette(
    bg: Color(0xFF0A0A0A),
    text: Color(0xFFFAFAFA),
    warmDim: Color(0xFF9C958A),
    blue: Color(0xFF8BB3EE),
    mint: Color(0xFF88D7B2),
    success: Color(0xFF88D7B2),
    danger: Color(0xFFF29BA0),
    hairline: Color(0x14FFFFFF),
    ink: Color(0xFFEFE7D9),
    inkDim: Color(0xFFCDC6B8),
    ghost: Color(0xFF9C958A),
  );

  /// The same language on paper.
  static const light = SystemPalette(
    bg: Color(0xFFF7F4EE),
    text: Color(0xFF14110C),
    warmDim: Color(0xFF7A736A),
    blue: Color(0xFF3D6CB0),
    mint: Color(0xFF2E8B63),
    success: Color(0xFF2E8B63),
    danger: Color(0xFFB3454C),
    hairline: Color(0x1A14110C),
    ink: Color(0xFF4A4238),
    inkDim: Color(0xFF7A736A),
    ghost: Color(0xFF9A9186),
  );

  final Color bg;
  final Color text;
  final Color warmDim;
  final Color blue;
  final Color mint;
  final Color success;
  final Color danger;
  final Color hairline;

  /// Stroke colours for the hand-drawn marks.
  final Color ink;
  final Color inkDim;

  /// Outline for the "waiting to be filled" ghost shapes.
  final Color ghost;

  static SystemPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  Color dim(double opacity) => text.withValues(alpha: opacity);

  TextStyle get title => GoogleFonts.inter(
    color: text,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.55,
    height: 1.5,
  );

  TextStyle get subtitle => GoogleFonts.inter(
    color: dim(0.6),
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// Mono, uppercase, wide tracking.
  TextStyle get eyebrow => GoogleFonts.robotoMono(
    color: warmDim,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 10 * 0.26,
    height: 1.4,
  );

  TextStyle get relayName => GoogleFonts.inter(
    color: text,
    fontSize: 23,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.1,
  );

  TextStyle get relayStatus => GoogleFonts.inter(
    color: dim(0.6),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  TextStyle get relayEndpoint => GoogleFonts.inter(
    color: warmDim,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// Uppercase mono key in a ledger row.
  TextStyle get rowKey => GoogleFonts.robotoMono(
    color: warmDim,
    fontSize: 10.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 10.5 * 0.14,
    height: 1.4,
  );

  TextStyle get rowValue => GoogleFonts.inter(
    color: text,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  /// The plan name as a statement, e.g. "Anonymous".
  TextStyle get planName => GoogleFonts.inter(
    color: text,
    fontSize: 27,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1.2,
  );

  /// Mono line under a plan name: price, quality, renewal.
  TextStyle get planMeta => GoogleFonts.robotoMono(
    color: dim(0.52),
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 12.5 * 0.03,
    height: 1.4,
  );

  /// Colour a tier is written in.
  Color tierColor(PlanTier tier) => switch (tier) {
    PlanTier.free => warmDim,
    PlanTier.premium => blue,
    PlanTier.anonymous => mint,
  };

  /// Section header, e.g. CAMERAS & PLANS.
  TextStyle get sectionLabel => GoogleFonts.inter(
    color: dim(0.32),
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.8,
    height: 1.4,
  );

  /// The quiet counterpart on the right of a section header.
  TextStyle get sectionNote => GoogleFonts.inter(
    color: warmDim,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  TextStyle get action => GoogleFonts.inter(
    color: blue,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  TextStyle get cameraName => GoogleFonts.inter(
    color: text,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  /// One quiet mono line under a camera name: tier and usage.
  TextStyle get cameraMeta => GoogleFonts.robotoMono(
    color: dim(0.38),
    fontSize: 10.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 10.5 * 0.05,
    height: 1.4,
  );

  TextStyle get cameraState => GoogleFonts.inter(
    color: dim(0.52),
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  TextStyle get sharedTag => GoogleFonts.inter(
    color: dim(0.38),
    fontSize: 10,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  TextStyle get accountEmail => GoogleFonts.inter(
    color: text,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  TextStyle get linkRow => GoogleFonts.inter(
    color: text,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  TextStyle get emptyTitle => GoogleFonts.inter(
    color: text,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.3,
  );

  TextStyle get emptyBody => GoogleFonts.inter(
    color: dim(0.6),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.65,
  );

  /// The footnote that replaced the boxed encryption card.
  TextStyle get footnote => GoogleFonts.inter(
    color: dim(0.52),
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );
}
