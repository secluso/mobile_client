//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Palette and type for the camera-role screens.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';

/// Colours for the camera-role screens.
abstract final class CamRole {
  /// Warm dark, a shade off the shell's #0A0A0A.
  static const bg = Color(0xFF0A0908);
  static const paper = Color(0xFFFAFAFA);

  /// Mono eyebrows and row labels.
  static const warmDim = Color(0xFF9C958A);

  static const blue = Color(0xFF8BB3EE);
  static const success = Color(0xFF88D7B2);
  static const warning = Color(0xFFF0C08A);
  static const danger = Color(0xFFF29BA0);

  static const hairline = Color(0x14FFFFFF);

  /// Ink for the hand-drawn marks.
  static const ink = Color(0xFFEFE7D9);
  static const inkDim = Color(0xFFCDC6B8);

  /// The warm paper a QR code is printed on.
  static const qrPaper = Color(0xFFF2ECDF);

  static Color dim(double opacity) => paper.withValues(alpha: opacity);
}

/// Type for the camera-role screens.
abstract final class CamRoleText {
  /// Mono, uppercase, wide tracking. Sits above a title.
  static TextStyle get eyebrow => GoogleFonts.robotoMono(
    color: CamRole.warmDim,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 10 * 0.26,
    height: 1.4,
  );

  /// Screen title, matching the app's shellTitleStyle.
  static TextStyle get title => GoogleFonts.inter(
    color: CamRole.paper,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.55,
    height: 1.5,
  );

  /// The larger, heavier title the running screen leads with.
  static TextStyle get display => GoogleFonts.inter(
    color: CamRole.paper,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static TextStyle get body => GoogleFonts.inter(
    color: CamRole.dim(0.6),
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// Body copy under the running screen's mark, a touch smaller and quieter.
  static TextStyle get bodyTight => GoogleFonts.inter(
    color: CamRole.dim(0.55),
    fontSize: 14.5,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  /// Mono footnote, centred at the foot of a screen.
  static TextStyle get footnote => GoogleFonts.robotoMono(
    color: CamRole.warmDim,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 11 * 0.04,
    height: 1.5,
  );

  /// Uppercase mono key in a stat row.
  static TextStyle get rowKey => GoogleFonts.robotoMono(
    color: CamRole.warmDim,
    fontSize: 10.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 10.5 * 0.14,
    height: 1.4,
  );

  static TextStyle get rowValue => GoogleFonts.inter(
    color: CamRole.paper,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  /// Section header on the settings screen.
  static TextStyle get sectionLabel => GoogleFonts.inter(
    color: CamRole.dim(0.32),
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.8,
    height: 1.4,
  );

  /// Settings row title.
  static TextStyle get settingKey => GoogleFonts.inter(
    color: CamRole.paper,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Explanatory line under a settings row title.
  static TextStyle get settingSub => GoogleFonts.inter(
    color: CamRole.dim(0.38),
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  /// Right-hand value on a settings row.
  static TextStyle get settingValue => GoogleFonts.inter(
    color: CamRole.dim(0.52),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );
}
