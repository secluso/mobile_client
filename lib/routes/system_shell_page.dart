//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';
import 'package:secluso_flutter/ui/secluso_shell_ui.dart';

/// The very first screen on a fresh install: pick what this phone's job is.
///
/// Choosing "Watch my cameras" continues into what the app used to be, pick a relay, then add a camera...
/// Choosing "Be a camera" enters the camera role flow (acts on its own as a camera)

class RoleSelectPage extends StatelessWidget {
  const RoleSelectPage({
    super.key,
    required this.onWatchCameras,
    required this.onBeCamera,
  });

  final VoidCallback onWatchCameras;
  final VoidCallback onBeCamera;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _SystemShellUnpairedMetrics.forWidth(
          constraints.maxWidth,
        );
        return Scaffold(
          backgroundColor: const Color(0xFF050505),
          body: SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                0,
                metrics.topPadding,
                0,
                metrics.bottomPadding,
              ),
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: metrics.pageInset),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Secluso',
                        style: shellTitleStyle(
                          context,
                          fontSize: metrics.titleSize,
                          designLetterSpacing: 0.55,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: metrics.subtitleTopGap),
                      Text(
                        "LET'S GET YOU SET UP",
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: metrics.subtitleSize,
                          fontWeight: FontWeight.w600,
                          letterSpacing: metrics.subtitleSize * 0.18,
                          height: 16.5 / 11,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: metrics.headerToCardGap),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                  child: _RoleSetupCard(
                    metrics: metrics,
                    onWatchCameras: onWatchCameras,
                    onBeCamera: onBeCamera,
                  ),
                ),
                SizedBox(height: metrics.cardGap),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                  child: _SystemDarkSecurityCard(metrics: metrics),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RoleSetupCard extends StatelessWidget {
  const _RoleSetupCard({
    required this.metrics,
    required this.onWatchCameras,
    required this.onBeCamera,
  });

  final _SystemShellUnpairedMetrics metrics;
  final VoidCallback onWatchCameras;
  final VoidCallback onBeCamera;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: ShellTopAccentBorderPainter(
        color: const Color(0xFF8BB3EE),
        strokeWidth: metrics.setupAccentStrokeWidth,
        radius: metrics.cardRadius,
        revealHeight: metrics.cardRadius * 0.92,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(metrics.cardRadius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        padding: EdgeInsets.all(metrics.cardInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "What's this phone's job?",
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: metrics.setupTitleSize,
                fontWeight: FontWeight.w600,
                height: 24 / 16,
              ),
            ),
            SizedBox(height: metrics.setupTitleGap),
            Text(
              'Pick a role for this device.\nYou can change it later.',
              style: GoogleFonts.inter(
                color: const Color(0xFF6D7077),
                fontSize: metrics.setupBodySize,
                fontWeight: FontWeight.w400,
                height: 17.88 / 11,
              ),
            ),
            SizedBox(height: metrics.setupBodyGap),
            _SystemDarkSetupOption(
              metrics: metrics,
              title: 'Watch my cameras',
              subtitle: 'See live and saved video.\nConnects to your relay.',
              icon: const SizedBox(
                width: 16,
                height: 16,
                child: CustomPaint(
                  painter: _RoleViewerIconPainter(Color(0xFF8BB3EE)),
                ),
              ),
              iconBackground: const Color(0x338BB3EE),
              backgroundColor: const Color(0x1A8BB3EE),
              borderColor: const Color(0x338BB3EE),
              onTap: onWatchCameras,
            ),
            SizedBox(height: metrics.optionGap),
            _SystemDarkSetupOption(
              metrics: metrics,
              title: 'Be a camera',
              subtitle: 'Leave a spare phone recording.\nPairs over Bluetooth.',
              icon: const SizedBox(
                width: 16,
                height: 16,
                child: CustomPaint(
                  painter: _RoleCameraIconPainter(Color(0xFF8BB3EE)),
                ),
              ),
              iconBackground: const Color(0x1A8BB3EE),
              backgroundColor: Colors.white.withValues(alpha: 0.04),
              borderColor: Colors.white.withValues(alpha: 0.08),
              onTap: onBeCamera,
            ),
          ],
        ),
      ),
    );
  }
}

class SystemShellUnpairedPage extends StatelessWidget {
  const SystemShellUnpairedPage({
    super.key,
    required this.onUseSeclusoRelay,
    required this.onUseSelfHosted,
    required this.onContactSupport,
    required this.onVisitWebsite,
  });

  final VoidCallback onUseSeclusoRelay;
  final VoidCallback onUseSelfHosted;
  final VoidCallback onContactSupport;
  final VoidCallback onVisitWebsite;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _SystemShellUnpairedMetrics.forWidth(
          constraints.maxWidth,
        );
        return ColoredBox(
          color: const Color(0xFF050505),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              0,
              metrics.topPadding,
              0,
              metrics.bottomPadding,
            ),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.pageInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System',
                      style: shellTitleStyle(
                        context,
                        fontSize: metrics.titleSize,
                        designLetterSpacing: 0.55,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: metrics.subtitleTopGap),
                    Text(
                      'Your private relay and connected devices.',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: metrics.subtitleSize,
                        fontWeight: FontWeight.w400,
                        height: 16.5 / 11,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: metrics.headerToCardGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child: _UnpairedRelaySetupDarkCard(
                  metrics: metrics,
                  onUseSeclusoRelay: onUseSeclusoRelay,
                  onUseSelfHosted: onUseSelfHosted,
                ),
              ),
              SizedBox(height: metrics.cardGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child: _SystemPairingInfoDarkCard(metrics: metrics),
              ),
              SizedBox(height: metrics.cardGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child: _SystemDarkSecurityCard(metrics: metrics),
              ),
              SizedBox(height: metrics.cardGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child: _SystemDarkNeedHelpCard(
                  metrics: metrics,
                  onContactSupport: onContactSupport,
                  onVisitWebsite: onVisitWebsite,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UnpairedRelaySetupDarkCard extends StatelessWidget {
  const _UnpairedRelaySetupDarkCard({
    required this.metrics,
    required this.onUseSeclusoRelay,
    required this.onUseSelfHosted,
  });

  final _SystemShellUnpairedMetrics metrics;
  final VoidCallback onUseSeclusoRelay;
  final VoidCallback onUseSelfHosted;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: ShellTopAccentBorderPainter(
        color: const Color(0xFF8BB3EE),
        strokeWidth: metrics.setupAccentStrokeWidth,
        radius: metrics.cardRadius,
        revealHeight: metrics.cardRadius * 0.92,
      ),
      child: Container(
        height: metrics.setupCardHeight,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(metrics.cardRadius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        padding: EdgeInsets.fromLTRB(
          metrics.cardInset,
          metrics.cardInset,
          metrics.cardInset,
          metrics.cardInset,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set up your relay server',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: metrics.setupTitleSize,
                fontWeight: FontWeight.w600,
                height: 24 / 16,
              ),
            ),
            SizedBox(height: metrics.setupTitleGap),
            Text(
              'The relay is the encrypted bridge\nbetween your cameras and this app.',
              style: GoogleFonts.inter(
                color: const Color(0xFF6D7077),
                fontSize: metrics.setupBodySize,
                fontWeight: FontWeight.w400,
                height: 17.88 / 11,
              ),
            ),
            SizedBox(height: metrics.setupBodyGap),
            _SystemDarkSetupOption(
              metrics: metrics,
              title: 'Secluso Relay',
              subtitle: 'Scan the QR code from your\nSecluso account',
              icon: const _SystemRelayGridIcon(
                size: 16,
                color: Color(0xFF8BB3EE),
              ),
              iconBackground: const Color(0x338BB3EE),
              backgroundColor: const Color(0x1A8BB3EE),
              borderColor: const Color(0x338BB3EE),
              onTap: onUseSeclusoRelay,
            ),
            SizedBox(height: metrics.optionGap),
            _SystemDarkSetupOption(
              metrics: metrics,
              title: 'Self-Hosted',
              subtitle: 'Run on your own server\n(VPS or dedicated host)',
              icon: const _SystemSelfHostedIcon(
                size: 16,
                color: Color(0xFF8BB3EE),
              ),
              iconBackground: const Color(0x1A8BB3EE),
              backgroundColor: Colors.white.withValues(alpha: 0.04),
              borderColor: Colors.white.withValues(alpha: 0.08),
              onTap: onUseSelfHosted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemDarkSetupOption extends StatelessWidget {
  const _SystemDarkSetupOption({
    required this.metrics,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBackground,
    required this.backgroundColor,
    required this.borderColor,
    required this.onTap,
  });

  final _SystemShellUnpairedMetrics metrics;
  final String title;
  final String subtitle;
  final Widget icon;
  final Color iconBackground;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(metrics.optionRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(metrics.optionRadius),
        onTap: onTap,
        child: Container(
          height: metrics.optionHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(metrics.optionRadius),
            border: Border.all(color: borderColor),
          ),
          child: Stack(
            children: [
              Positioned(
                left: metrics.optionInset,
                top: (metrics.optionHeight - metrics.optionIconWrapSize) / 2,
                child: Container(
                  width: metrics.optionIconWrapSize,
                  height: metrics.optionIconWrapSize,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(
                      metrics.optionIconRadius,
                    ),
                  ),
                  child: Center(child: icon),
                ),
              ),
              Positioned(
                left: metrics.optionTextLeft,
                top: metrics.optionTitleTop,
                right: metrics.optionInset,
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: metrics.optionTitleSize,
                    fontWeight: FontWeight.w600,
                    height: 19.5 / 13,
                  ),
                ),
              ),
              Positioned(
                left: metrics.optionTextLeft,
                top: metrics.optionSubtitleTop,
                right: metrics.optionInset,
                child: Text(
                  subtitle,
                  maxLines: 2,
                  softWrap: false,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: metrics.optionBodySize,
                    fontWeight: FontWeight.w400,
                    height: 15 / 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemPairingInfoDarkCard extends StatelessWidget {
  const _SystemPairingInfoDarkCard({required this.metrics});

  final _SystemShellUnpairedMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: metrics.infoCardHeight,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(metrics.infoCardRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      padding: EdgeInsets.symmetric(horizontal: metrics.infoInset),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: metrics.infoIconTopInset),
            child: _SystemPairingLockIcon(
              size: metrics.infoIconSize,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          SizedBox(width: metrics.infoIconGap),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: metrics.infoTextTopInset),
              child: Text(
                'Pairing credentials stay on this device. Nothing is\nsent to any server.',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: metrics.infoBodySize,
                  fontWeight: FontWeight.w400,
                  height: 14.63 / 9,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemDarkSecurityCard extends StatelessWidget {
  const _SystemDarkSecurityCard({required this.metrics});

  final _SystemShellUnpairedMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: metrics.securityCardHeight),
      decoration: BoxDecoration(
        color: const Color(0x0F10B981),
        borderRadius: BorderRadius.circular(metrics.infoCardRadius),
        border: Border.all(color: const Color(0x2610B981)),
      ),
      padding: EdgeInsets.fromLTRB(
        metrics.securityInset,
        metrics.securityInset,
        metrics.securityInset,
        metrics.securityBottomInset,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: metrics.securityIconTopInset),
            child: _SystemSecurityLockIcon(
              size: metrics.securityIconSize,
              color: const Color(0xFF10B981),
            ),
          ),
          SizedBox(width: metrics.securityIconGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'End-to-end encryption is always on',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF10B981),
                    fontSize: metrics.securityTitleSize,
                    fontWeight: FontWeight.w600,
                    height: 16.5 / 11,
                  ),
                ),
                SizedBox(height: metrics.securityTitleGap),
                Text(
                  'All credentials and encryption keys stay\non this device. Secluso cannot access\nyour footage or connection details.',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: metrics.securityBodySize,
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

class _SystemDarkNeedHelpCard extends StatelessWidget {
  const _SystemDarkNeedHelpCard({
    required this.metrics,
    required this.onContactSupport,
    required this.onVisitWebsite,
  });

  final _SystemShellUnpairedMetrics metrics;
  final VoidCallback onContactSupport;
  final VoidCallback onVisitWebsite;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: metrics.helpCardHeight),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(metrics.infoCardRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      padding: EdgeInsets.fromLTRB(
        metrics.helpInset,
        metrics.helpInset,
        metrics.helpInset,
        metrics.helpInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Need help?',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: metrics.helpTitleSize,
              fontWeight: FontWeight.w600,
              height: 16.5 / 11,
            ),
          ),
          SizedBox(height: metrics.helpTopGap),
          _SystemDarkHelpRow(
            metrics: metrics,
            label: 'Contact Support',
            icon: _SystemChevronRightIcon(
              size: metrics.helpRowIconSize,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            onTap: onContactSupport,
          ),
          SizedBox(height: metrics.helpRowGap),
          _SystemDarkHelpRow(
            metrics: metrics,
            label: 'Visit secluso.com',
            icon: _SystemExternalLinkIcon(
              size: metrics.helpRowIconSize,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            onTap: onVisitWebsite,
          ),
        ],
      ),
    );
  }
}

class _SystemDarkHelpRow extends StatelessWidget {
  const _SystemDarkHelpRow({
    required this.metrics,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final _SystemShellUnpairedMetrics metrics;
  final String label;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(metrics.helpRowRadius),
        onTap: onTap,
        child: SizedBox(
          height: metrics.helpRowHeight,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: metrics.helpRowSize,
                    fontWeight: FontWeight.w400,
                    height: 16.5 / 11,
                  ),
                ),
              ),
              icon,
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemRelayGridIcon extends StatelessWidget {
  const _SystemRelayGridIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SystemRelayGridIconPainter(color)),
    );
  }
}

class _SystemSelfHostedIcon extends StatelessWidget {
  const _SystemSelfHostedIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SystemSelfHostedIconPainter(color)),
    );
  }
}

class _SystemPairingLockIcon extends StatelessWidget {
  const _SystemPairingLockIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SystemPairingLockPainter(color)),
    );
  }
}

class _SystemSecurityLockIcon extends StatelessWidget {
  const _SystemSecurityLockIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SystemSecurityLockPainter(color)),
    );
  }
}

class _SystemChevronRightIcon extends StatelessWidget {
  const _SystemChevronRightIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SystemChevronRightPainter(color)),
    );
  }
}

class _SystemExternalLinkIcon extends StatelessWidget {
  const _SystemExternalLinkIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SystemExternalLinkPainter(color)),
    );
  }
}

class _SystemRelayGridIconPainter extends CustomPainter {
  const _SystemRelayGridIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.33333 / 16)
          ..color = color
          ..isAntiAlias = true;
    final rects = <Rect>[
      Rect.fromLTWH(
        size.width * (2 / 16),
        size.height * (2 / 16),
        size.width * (4.66667 / 16),
        size.height * (4.66667 / 16),
      ),
      Rect.fromLTWH(
        size.width * (9.33333 / 16),
        size.height * (2 / 16),
        size.width * (4.66667 / 16),
        size.height * (4.66667 / 16),
      ),
      Rect.fromLTWH(
        size.width * (9.33333 / 16),
        size.height * (9.33333 / 16),
        size.width * (4.66667 / 16),
        size.height * (4.66667 / 16),
      ),
      Rect.fromLTWH(
        size.width * (2 / 16),
        size.height * (9.33333 / 16),
        size.width * (4.66667 / 16),
        size.height * (4.66667 / 16),
      ),
    ];
    for (final rect in rects) {
      canvas.drawRect(rect, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _SystemRelayGridIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SystemSelfHostedIconPainter extends CustomPainter {
  const _SystemSelfHostedIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.33333 / 16)
          ..color = color
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.miter
          ..isAntiAlias = true;
    final chevron =
        Path()
          ..moveTo(size.width * (2.66667 / 16), size.height * (11.3333 / 16))
          ..lineTo(size.width * (6.66667 / 16), size.height * (7.33333 / 16))
          ..lineTo(size.width * (2.66667 / 16), size.height * (3.33333 / 16));
    canvas.drawPath(chevron, stroke);
    canvas.drawLine(
      Offset(size.width * (8 / 16), size.height * (12.6667 / 16)),
      Offset(size.width * (13.3333 / 16), size.height * (12.6667 / 16)),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _SystemSelfHostedIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Role icon: a monitor with a play glyph ("watch my cameras").
class _RoleViewerIconPainter extends CustomPainter {
  const _RoleViewerIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double u) => size.width * (u / 16);
    double y(double u) => size.height * (u / 16);
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.33333 / 16)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    // Screen frame.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x(2), y(2.6667), x(12), y(8)),
        Radius.circular(x(1.3333)),
      ),
      stroke,
    );
    // Stand.
    canvas.drawLine(Offset(x(8), y(10.6667)), Offset(x(8), y(12.8)), stroke);
    canvas.drawLine(
      Offset(x(5.3333), y(12.8)),
      Offset(x(10.6667), y(12.8)),
      stroke,
    );
    // Play glyph.
    final fill =
        Paint()
          ..style = PaintingStyle.fill
          ..color = color
          ..isAntiAlias = true;
    final play =
        Path()
          ..moveTo(x(6.9), y(4.9))
          ..lineTo(x(6.9), y(8.4))
          ..lineTo(x(9.9), y(6.65))
          ..close();
    canvas.drawPath(play, fill);
  }

  @override
  bool shouldRepaint(covariant _RoleViewerIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Role icon: a camcorder with a record dot ("be a camera").
class _RoleCameraIconPainter extends CustomPainter {
  const _RoleCameraIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double u) => size.width * (u / 16);
    double y(double u) => size.height * (u / 16);
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.33333 / 16)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    // Body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x(2), y(4.6667), x(8), y(6.6667)),
        Radius.circular(x(1.3333)),
      ),
      stroke,
    );
    // Lens barrel.
    final lens =
        Path()
          ..moveTo(x(10), y(7))
          ..lineTo(x(13.6667), y(5))
          ..lineTo(x(13.6667), y(11))
          ..lineTo(x(10), y(9))
          ..close();
    canvas.drawPath(lens, stroke);
    // Record dot.
    canvas.drawCircle(
      Offset(x(5), y(8)),
      x(1),
      Paint()
        ..style = PaintingStyle.fill
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _RoleCameraIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SystemPairingLockPainter extends CustomPainter {
  const _SystemPairingLockPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1 / 12)
          ..color = color
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (1.5 / 12),
        size.height * (5.5 / 12),
        size.width * (9 / 12),
        size.height * (5.5 / 12),
      ),
      Radius.circular(size.width * (1 / 12)),
    );
    canvas.drawRRect(body, stroke);
    final shackle =
        Path()
          ..moveTo(size.width * (3.5 / 12), size.height * (5.5 / 12))
          ..lineTo(size.width * (3.5 / 12), size.height * (3.5 / 12))
          ..cubicTo(
            size.width * (3.5 / 12),
            size.height * (2.83696 / 12),
            size.width * (3.76339 / 12),
            size.height * (2.20107 / 12),
            size.width * (4.23223 / 12),
            size.height * (1.73223 / 12),
          )
          ..cubicTo(
            size.width * (4.70107 / 12),
            size.height * (1.26339 / 12),
            size.width * (5.33696 / 12),
            size.height * (1 / 12),
            size.width * (6 / 12),
            size.height * (1 / 12),
          )
          ..cubicTo(
            size.width * (6.66304 / 12),
            size.height * (1 / 12),
            size.width * (7.29893 / 12),
            size.height * (1.26339 / 12),
            size.width * (7.76777 / 12),
            size.height * (1.73223 / 12),
          )
          ..cubicTo(
            size.width * (8.23661 / 12),
            size.height * (2.20107 / 12),
            size.width * (8.5 / 12),
            size.height * (2.83696 / 12),
            size.width * (8.5 / 12),
            size.height * (3.5 / 12),
          )
          ..lineTo(size.width * (8.5 / 12), size.height * (5.5 / 12));
    canvas.drawPath(shackle, stroke);
  }

  @override
  bool shouldRepaint(covariant _SystemPairingLockPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SystemSecurityLockPainter extends CustomPainter {
  const _SystemSecurityLockPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.33333 / 16)
          ..color = color
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (2 / 16),
        size.height * (7.33333 / 16),
        size.width * (12 / 16),
        size.height * (7.33334 / 16),
      ),
      Radius.circular(size.width * (1.33333 / 16)),
    );
    canvas.drawRRect(body, stroke);
    final shackle =
        Path()
          ..moveTo(size.width * (4.66667 / 16), size.height * (7.33333 / 16))
          ..lineTo(size.width * (4.66667 / 16), size.height * (4.66667 / 16))
          ..cubicTo(
            size.width * (4.66667 / 16),
            size.height * (3.78261 / 16),
            size.width * (5.01786 / 16),
            size.height * (2.93477 / 16),
            size.width * (5.64298 / 16),
            size.height * (2.30964 / 16),
          )
          ..cubicTo(
            size.width * (6.2681 / 16),
            size.height * (1.68452 / 16),
            size.width * (7.11594 / 16),
            size.height * (1.33333 / 16),
            size.width * (8 / 16),
            size.height * (1.33333 / 16),
          )
          ..cubicTo(
            size.width * (8.88405 / 16),
            size.height * (1.33333 / 16),
            size.width * (9.7319 / 16),
            size.height * (1.68452 / 16),
            size.width * (10.357 / 16),
            size.height * (2.30964 / 16),
          )
          ..cubicTo(
            size.width * (10.9821 / 16),
            size.height * (2.93477 / 16),
            size.width * (11.3333 / 16),
            size.height * (3.78261 / 16),
            size.width * (11.3333 / 16),
            size.height * (4.66667 / 16),
          )
          ..lineTo(size.width * (11.3333 / 16), size.height * (7.33333 / 16));
    canvas.drawPath(shackle, stroke);
  }

  @override
  bool shouldRepaint(covariant _SystemSecurityLockPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SystemChevronRightPainter extends CustomPainter {
  const _SystemChevronRightPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1 / 12)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (4.5 / 12), size.height * (9 / 12))
          ..lineTo(size.width * (7.5 / 12), size.height * (6 / 12))
          ..lineTo(size.width * (4.5 / 12), size.height * (3 / 12));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _SystemChevronRightPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SystemExternalLinkPainter extends CustomPainter {
  const _SystemExternalLinkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1 / 12)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final frame =
        Path()
          ..moveTo(size.width * (9 / 12), size.height * (6.5 / 12))
          ..lineTo(size.width * (9 / 12), size.height * (9.5 / 12))
          ..cubicTo(
            size.width * (9 / 12),
            size.height * (9.76522 / 12),
            size.width * (8.89464 / 12),
            size.height * (10.0196 / 12),
            size.width * (8.70711 / 12),
            size.height * (10.2071 / 12),
          )
          ..cubicTo(
            size.width * (8.51957 / 12),
            size.height * (10.3946 / 12),
            size.width * (8.26522 / 12),
            size.height * (10.5 / 12),
            size.width * (8 / 12),
            size.height * (10.5 / 12),
          )
          ..lineTo(size.width * (2.5 / 12), size.height * (10.5 / 12))
          ..cubicTo(
            size.width * (2.23478 / 12),
            size.height * (10.5 / 12),
            size.width * (1.98043 / 12),
            size.height * (10.3946 / 12),
            size.width * (1.79289 / 12),
            size.height * (10.2071 / 12),
          )
          ..cubicTo(
            size.width * (1.60536 / 12),
            size.height * (10.0196 / 12),
            size.width * (1.5 / 12),
            size.height * (9.76522 / 12),
            size.width * (1.5 / 12),
            size.height * (9.5 / 12),
          )
          ..lineTo(size.width * (1.5 / 12), size.height * (4 / 12))
          ..cubicTo(
            size.width * (1.5 / 12),
            size.height * (3.73478 / 12),
            size.width * (1.60536 / 12),
            size.height * (3.48043 / 12),
            size.width * (1.79289 / 12),
            size.height * (3.29289 / 12),
          )
          ..cubicTo(
            size.width * (1.98043 / 12),
            size.height * (3.10536 / 12),
            size.width * (2.23478 / 12),
            size.height * (3 / 12),
            size.width * (2.5 / 12),
            size.height * (3 / 12),
          )
          ..lineTo(size.width * (5.5 / 12), size.height * (3 / 12));
    canvas.drawPath(frame, stroke);
    canvas.drawLine(
      Offset(size.width * (7.5 / 12), size.height * (1.5 / 12)),
      Offset(size.width * (10.5 / 12), size.height * (1.5 / 12)),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * (10.5 / 12), size.height * (1.5 / 12)),
      Offset(size.width * (10.5 / 12), size.height * (4.5 / 12)),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * (5 / 12), size.height * (7 / 12)),
      Offset(size.width * (10.5 / 12), size.height * (1.5 / 12)),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _SystemExternalLinkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class SystemShellUnpairedLightPage extends StatelessWidget {
  const SystemShellUnpairedLightPage({
    super.key,
    required this.onUseSeclusoRelay,
    required this.onUseSelfHosted,
    required this.onContactSupport,
    required this.onVisitWebsite,
  });

  final VoidCallback onUseSeclusoRelay;
  final VoidCallback onUseSelfHosted;
  final VoidCallback onContactSupport;
  final VoidCallback onVisitWebsite;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _SystemShellUnpairedMetrics.forWidth(
          constraints.maxWidth,
        );
        return ColoredBox(
          color: const Color(0xFFF2F2F7),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              0,
              metrics.topPadding,
              0,
              metrics.bottomPadding,
            ),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.pageInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System',
                      style: shellTitleStyle(
                        context,
                        fontSize: metrics.titleSize,
                        designLetterSpacing: 0.55,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: metrics.subtitleTopGap),
                    Text(
                      'Your private relay and connected devices.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6B7280),
                        fontSize: metrics.subtitleSize,
                        height: 16.5 / 11,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: metrics.headerToCardGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child: _UnpairedRelaySetupCard(
                  metrics: metrics,
                  onUseSeclusoRelay: onUseSeclusoRelay,
                  onUseSelfHosted: onUseSelfHosted,
                ),
              ),
              SizedBox(height: metrics.cardGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child: _SystemPairingInfoCard(metrics: metrics),
              ),
              SizedBox(height: metrics.cardGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child: _SystemLightSecurityCard(metrics: metrics),
              ),
              SizedBox(height: metrics.cardGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child: _SystemLightNeedHelpCard(
                  metrics: metrics,
                  onContactSupport: onContactSupport,
                  onVisitWebsite: onVisitWebsite,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UnpairedRelaySetupCard extends StatelessWidget {
  const _UnpairedRelaySetupCard({
    required this.metrics,
    required this.onUseSeclusoRelay,
    required this.onUseSelfHosted,
  });

  final _SystemShellUnpairedMetrics metrics;
  final VoidCallback onUseSeclusoRelay;
  final VoidCallback onUseSelfHosted;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: ShellTopAccentBorderPainter(
        color: const Color(0xFF8BB3EE),
        strokeWidth: metrics.setupAccentStrokeWidth,
        radius: metrics.cardRadius,
        revealHeight: metrics.cardRadius * 0.92,
      ),
      child: Container(
        height: metrics.setupCardHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(metrics.cardRadius),
          border: Border.all(color: const Color(0x14000000)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
          metrics.cardInset,
          metrics.cardInset,
          metrics.cardInset,
          metrics.cardInset,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set up your relay server',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF111827),
                fontSize: metrics.setupTitleSize,
                fontWeight: FontWeight.w600,
                height: 24 / 16,
              ),
            ),
            SizedBox(height: metrics.setupTitleGap),
            Text(
              'The relay is the encrypted bridge\nbetween your cameras and this app.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7280),
                fontSize: metrics.setupBodySize,
                height: 17.88 / 11,
              ),
            ),
            SizedBox(height: metrics.setupBodyGap),
            _SystemSetupOption(
              metrics: metrics,
              title: 'Secluso Relay',
              subtitle: 'Scan the QR code from your\nSecluso account',
              icon: Icons.qr_code_2_rounded,
              iconBackground: const Color(0x338BB3EE),
              backgroundColor: const Color(0xFFF8FAFC),
              borderColor: const Color(0x338BB3EE),
              onTap: onUseSeclusoRelay,
            ),
            SizedBox(height: metrics.optionGap),
            _SystemSetupOption(
              metrics: metrics,
              title: 'Self-Hosted',
              subtitle: 'Run on your own server\n(VPS or dedicated host)',
              icon: Icons.terminal_rounded,
              iconBackground: const Color(0xFFEFF6FF),
              backgroundColor: const Color(0xFFF9FAFB),
              borderColor: const Color(0xFFE5E7EB),
              onTap: onUseSelfHosted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemSetupOption extends StatelessWidget {
  const _SystemSetupOption({
    required this.metrics,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBackground,
    required this.backgroundColor,
    required this.borderColor,
    required this.onTap,
  });

  final _SystemShellUnpairedMetrics metrics;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBackground;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(metrics.optionRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(metrics.optionRadius),
        onTap: onTap,
        child: Container(
          height: metrics.optionHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(metrics.optionRadius),
            border: Border.all(color: borderColor),
          ),
          child: Stack(
            children: [
              Positioned(
                left: metrics.optionInset,
                top: (metrics.optionHeight - metrics.optionIconWrapSize) / 2,
                child: Container(
                  width: metrics.optionIconWrapSize,
                  height: metrics.optionIconWrapSize,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(
                      metrics.optionIconRadius,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: metrics.optionIconSize,
                    color: const Color(0xFF8BB3EE),
                  ),
                ),
              ),
              Positioned(
                left: metrics.optionTextLeft,
                top: metrics.optionTitleTop,
                right: metrics.optionInset,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF111827),
                    fontSize: metrics.optionTitleSize,
                    fontWeight: FontWeight.w600,
                    height: 19.5 / 13,
                  ),
                ),
              ),
              Positioned(
                left: metrics.optionTextLeft,
                top: metrics.optionSubtitleTop,
                right: metrics.optionInset,
                child: Text(
                  subtitle,
                  maxLines: 2,
                  softWrap: false,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontSize: metrics.optionBodySize,
                    height: 15 / 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemPairingInfoCard extends StatelessWidget {
  const _SystemPairingInfoCard({required this.metrics});

  final _SystemShellUnpairedMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: metrics.infoCardHeight,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(metrics.infoCardRadius),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      padding: EdgeInsets.symmetric(horizontal: metrics.infoInset),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: metrics.infoIconTopInset),
            child: Icon(
              Icons.lock_outline_rounded,
              size: metrics.infoIconSize,
              color: const Color(0xFF9CA3AF),
            ),
          ),
          SizedBox(width: metrics.infoIconGap),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: metrics.infoTextTopInset),
              child: Text(
                'Pairing credentials stay on this device. Nothing is\nsent to any server.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF9CA3AF),
                  fontSize: metrics.infoBodySize,
                  height: 14.63 / 9,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemLightSecurityCard extends StatelessWidget {
  const _SystemLightSecurityCard({required this.metrics});

  final _SystemShellUnpairedMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: metrics.securityCardHeight),
      decoration: BoxDecoration(
        color: const Color(0x0F10B981),
        borderRadius: BorderRadius.circular(metrics.infoCardRadius),
        border: Border.all(color: const Color(0x4D10B981)),
      ),
      padding: EdgeInsets.fromLTRB(
        metrics.securityInset,
        metrics.securityInset,
        metrics.securityInset,
        metrics.securityBottomInset,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: metrics.securityIconTopInset),
            child: Icon(
              Icons.lock_outline_rounded,
              size: metrics.securityIconSize,
              color: const Color(0xFF10B981),
            ),
          ),
          SizedBox(width: metrics.securityIconGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'End-to-end encryption is always on',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF10B981),
                    fontSize: metrics.securityTitleSize,
                    fontWeight: FontWeight.w600,
                    height: 16.5 / 11,
                  ),
                ),
                SizedBox(height: metrics.securityTitleGap),
                Text(
                  'All credentials and encryption keys stay\non this device. Secluso cannot access\nyour footage or connection details.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontSize: metrics.securityBodySize,
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

class _SystemLightNeedHelpCard extends StatelessWidget {
  const _SystemLightNeedHelpCard({
    required this.metrics,
    required this.onContactSupport,
    required this.onVisitWebsite,
  });

  final _SystemShellUnpairedMetrics metrics;
  final VoidCallback onContactSupport;
  final VoidCallback onVisitWebsite;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: metrics.helpCardHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(metrics.infoCardRadius),
        border: Border.all(color: const Color(0x0A000000)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        metrics.helpInset,
        metrics.helpInset,
        metrics.helpInset,
        metrics.helpInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Need help?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF111827),
              fontSize: metrics.helpTitleSize,
              fontWeight: FontWeight.w600,
              height: 16.5 / 11,
            ),
          ),
          SizedBox(height: metrics.helpTopGap),
          _SystemLightHelpRow(
            metrics: metrics,
            label: 'Contact Support',
            onTap: onContactSupport,
          ),
          SizedBox(height: metrics.helpRowGap),
          _SystemLightHelpRow(
            metrics: metrics,
            label: 'Visit secluso.com',
            onTap: onVisitWebsite,
          ),
        ],
      ),
    );
  }
}

class _SystemLightHelpRow extends StatelessWidget {
  const _SystemLightHelpRow({
    required this.metrics,
    required this.label,
    required this.onTap,
  });

  final _SystemShellUnpairedMetrics metrics;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(metrics.helpRowRadius),
        onTap: onTap,
        child: SizedBox(
          height: metrics.helpRowHeight,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B5563),
                    fontSize: metrics.helpRowSize,
                    fontWeight: FontWeight.w400,
                    height: 16.5 / 11,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_outward_rounded,
                size: metrics.helpRowIconSize,
                color: const Color(0xFF4B5563),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemShellUnpairedMetrics {
  const _SystemShellUnpairedMetrics({
    required this.scale,
    required this.topPadding,
    required this.bottomPadding,
    required this.pageInset,
    required this.railInset,
    required this.titleSize,
    required this.subtitleTopGap,
    required this.subtitleSize,
    required this.headerToCardGap,
    required this.cardGap,
    required this.cardRadius,
    required this.cardInset,
    required this.setupAccentStrokeWidth,
    required this.setupCardHeight,
    required this.setupTitleSize,
    required this.setupTitleGap,
    required this.setupBodySize,
    required this.setupBodyGap,
    required this.optionHeight,
    required this.optionRadius,
    required this.optionInset,
    required this.optionIconWrapSize,
    required this.optionIconRadius,
    required this.optionIconSize,
    required this.optionTextLeft,
    required this.optionTitleSize,
    required this.optionTitleTop,
    required this.optionSubtitleTop,
    required this.optionBodySize,
    required this.optionGap,
    required this.infoCardHeight,
    required this.infoCardRadius,
    required this.infoInset,
    required this.infoIconTopInset,
    required this.infoIconSize,
    required this.infoIconGap,
    required this.infoTextTopInset,
    required this.infoBodySize,
    required this.securityCardHeight,
    required this.securityInset,
    required this.securityBottomInset,
    required this.securityIconTopInset,
    required this.securityIconSize,
    required this.securityIconGap,
    required this.securityTitleSize,
    required this.securityTitleGap,
    required this.securityBodySize,
    required this.helpCardHeight,
    required this.helpInset,
    required this.helpTitleSize,
    required this.helpTopGap,
    required this.helpRowGap,
    required this.helpRowHeight,
    required this.helpRowSize,
    required this.helpRowIconSize,
    required this.helpRowRadius,
  });

  final double scale;
  final double topPadding;
  final double bottomPadding;
  final double pageInset;
  final double railInset;
  final double titleSize;
  final double subtitleTopGap;
  final double subtitleSize;
  final double headerToCardGap;
  final double cardGap;
  final double cardRadius;
  final double cardInset;
  final double setupAccentStrokeWidth;
  final double setupCardHeight;
  final double setupTitleSize;
  final double setupTitleGap;
  final double setupBodySize;
  final double setupBodyGap;
  final double optionHeight;
  final double optionRadius;
  final double optionInset;
  final double optionIconWrapSize;
  final double optionIconRadius;
  final double optionIconSize;
  final double optionTextLeft;
  final double optionTitleSize;
  final double optionTitleTop;
  final double optionSubtitleTop;
  final double optionBodySize;
  final double optionGap;
  final double infoCardHeight;
  final double infoCardRadius;
  final double infoInset;
  final double infoIconTopInset;
  final double infoIconSize;
  final double infoIconGap;
  final double infoTextTopInset;
  final double infoBodySize;
  final double securityCardHeight;
  final double securityInset;
  final double securityBottomInset;
  final double securityIconTopInset;
  final double securityIconSize;
  final double securityIconGap;
  final double securityTitleSize;
  final double securityTitleGap;
  final double securityBodySize;
  final double helpCardHeight;
  final double helpInset;
  final double helpTitleSize;
  final double helpTopGap;
  final double helpRowGap;
  final double helpRowHeight;
  final double helpRowSize;
  final double helpRowIconSize;
  final double helpRowRadius;

  factory _SystemShellUnpairedMetrics.forWidth(double width) {
    final scale = width / 290;
    double scaled(double value) => value * scale;
    return _SystemShellUnpairedMetrics(
      scale: scale,
      topPadding: scaled(12),
      bottomPadding: scaled(18),
      pageInset: scaled(20),
      railInset: scaled(16),
      titleSize: scaled(22),
      subtitleTopGap: scaled(6),
      subtitleSize: scaled(11),
      headerToCardGap: scaled(13),
      cardGap: scaled(16),
      cardRadius: scaled(16),
      cardInset: scaled(20),
      setupAccentStrokeWidth: scaled(1),
      setupCardHeight: scaled(296.75),
      setupTitleSize: scaled(16),
      setupTitleGap: scaled(10),
      setupBodySize: scaled(11),
      setupBodyGap: scaled(18),
      optionHeight: scaled(77.5),
      optionRadius: scaled(12),
      optionInset: scaled(12),
      optionIconWrapSize: scaled(32),
      optionIconRadius: scaled(8),
      optionIconSize: scaled(16),
      optionTextLeft: scaled(56),
      optionTitleSize: scaled(13),
      optionTitleTop: scaled(12),
      optionSubtitleTop: scaled(35),
      optionBodySize: scaled(10),
      optionGap: scaled(12),
      infoCardHeight: scaled(55.25),
      infoCardRadius: scaled(12),
      infoInset: scaled(12),
      infoIconTopInset: scaled(14),
      infoIconSize: scaled(12),
      infoIconGap: scaled(10),
      infoTextTopInset: scaled(11),
      infoBodySize: scaled(9),
      securityCardHeight: scaled(103.25),
      securityInset: scaled(16),
      securityBottomInset: scaled(16),
      securityIconTopInset: scaled(2),
      securityIconSize: scaled(16),
      securityIconGap: scaled(12),
      securityTitleSize: scaled(11),
      securityTitleGap: scaled(8),
      securityBodySize: scaled(10),
      helpCardHeight: scaled(103.5),
      helpInset: scaled(16),
      helpTitleSize: scaled(11),
      helpTopGap: scaled(12),
      helpRowGap: scaled(12),
      helpRowHeight: scaled(16.5),
      helpRowSize: scaled(11),
      helpRowIconSize: scaled(12),
      helpRowRadius: scaled(6),
    );
  }
}

class SystemShellNoCamerasLightPage extends StatelessWidget {
  const SystemShellNoCamerasLightPage({
    super.key,
    required this.endpoint,
    required this.onRestartRelay,
    required this.onCheckForUpdates,
    required this.onAddCamera,
    this.onOpenCamera,
    required this.onContactSupport,
    required this.onVisitWebsite,
    this.restartRelayLabel = 'Remove Relay',
    this.checkForUpdatesLabel = 'Check for Updates',
    this.cameraNames = const [],
  });

  final String endpoint;
  final VoidCallback onRestartRelay;
  final VoidCallback onCheckForUpdates;
  final VoidCallback onAddCamera;
  final ValueChanged<String>? onOpenCamera;
  final VoidCallback onContactSupport;
  final VoidCallback onVisitWebsite;
  final String restartRelayLabel;
  final String checkForUpdatesLabel;
  final List<String> cameraNames;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _SystemShellConnectedLightMetrics.forWidth(
          constraints.maxWidth,
        );
        return ColoredBox(
          color: const Color(0xFFF2F2F7),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              0,
              metrics.topPadding,
              0,
              metrics.bottomPadding,
            ),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.pageInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System',
                      style: shellTitleStyle(
                        context,
                        fontSize: metrics.titleSize,
                        designLetterSpacing: 0.55,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: metrics.subtitleTopGap),
                    Text(
                      'Your private relay and connected devices.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6B7280),
                        fontSize: metrics.subtitleSize,
                        height: 16.5 / 11,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: metrics.headerToRelayGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child: _RelayConnectedLightCard(
                  metrics: metrics,
                  endpoint: endpoint,
                  onRestartRelay: onRestartRelay,
                  onCheckForUpdates: onCheckForUpdates,
                  restartRelayLabel: restartRelayLabel,
                  checkForUpdatesLabel: checkForUpdatesLabel,
                ),
              ),
              SizedBox(height: metrics.sectionTopGap),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  metrics.pageInset,
                  0,
                  metrics.pageInset,
                  0,
                ),
                child: Row(
                  children: [
                    Text(
                      'CAMERAS',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF9CA3AF),
                        fontSize: metrics.sectionLabelSize,
                        fontWeight: FontWeight.w600,
                        letterSpacing: metrics.sectionLabelLetterSpacing,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: onAddCamera,
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: const Color(0xFF8BB3EE),
                      ),
                      child: Text(
                        '+ Add',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF8BB3EE),
                          fontSize: metrics.addActionSize,
                          fontWeight: FontWeight.w500,
                          height: 15 / 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: metrics.sectionBottomGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child:
                    cameraNames.isEmpty
                        ? _NoCamerasLightCard(
                          metrics: metrics,
                          onAddCamera: onAddCamera,
                        )
                        : _CameraListLightCard(
                          metrics: metrics,
                          cameraNames: cameraNames,
                          onOpenCamera: onOpenCamera,
                        ),
              ),
              SizedBox(height: metrics.cardGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child: _SecurityLightCard(metrics: metrics),
              ),
              SizedBox(height: metrics.cardGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child: _NeedHelpLightCard(
                  metrics: metrics,
                  onContactSupport: onContactSupport,
                  onVisitWebsite: onVisitWebsite,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RelayConnectedLightCard extends StatelessWidget {
  const _RelayConnectedLightCard({
    required this.metrics,
    required this.endpoint,
    required this.onRestartRelay,
    required this.onCheckForUpdates,
    required this.restartRelayLabel,
    required this.checkForUpdatesLabel,
  });

  final _SystemShellConnectedLightMetrics metrics;
  final String endpoint;
  final VoidCallback onRestartRelay;
  final VoidCallback onCheckForUpdates;
  final String restartRelayLabel;
  final String checkForUpdatesLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: metrics.relayCardHeight,
      decoration: BoxDecoration(
        color: const Color(0x0F10B981),
        borderRadius: BorderRadius.circular(metrics.relayCardRadius),
        border: Border.all(color: const Color(0x4D10B981)),
      ),
      padding: EdgeInsets.all(metrics.relayCardInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: metrics.relayIconWrapSize,
                height: metrics.relayIconWrapSize,
                decoration: const BoxDecoration(
                  color: Color(0x2610B981),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.check_circle_outline_rounded,
                    size: metrics.relayIconSize,
                    color: const Color(0xFF34D399),
                  ),
                ),
              ),
              SizedBox(width: metrics.relayHeaderGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Relay Connected',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF34D399),
                        fontSize: metrics.relayTitleSize,
                        fontWeight: FontWeight.w600,
                        height: 19.5 / 13,
                      ),
                    ),
                    SizedBox(height: metrics.relayMetaTopGap),
                    Text(
                      'Phone linked · System ready',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6B7280),
                        fontSize: metrics.relayMetaSize,
                        height: 15 / 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.relayBodyGap),
          Container(
            height: metrics.metaPanelHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(metrics.metaPanelRadius),
            ),
            padding: EdgeInsets.fromLTRB(
              metrics.metaPanelInset,
              metrics.metaPanelInset,
              metrics.metaPanelInset,
              metrics.metaPanelInset,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _LightMetaRow(
                  metrics: metrics,
                  label: 'Endpoint',
                  value: endpoint,
                  monospace: true,
                ),
                _LightMetaRow(
                  metrics: metrics,
                  label: 'Protocol',
                  value: 'MLS v1.0 (RFC 9420)',
                ),
                _LightMetaRow(
                  metrics: metrics,
                  label: 'Last Sync',
                  value: 'Just now',
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.relayActionsGap),
          Row(
            children: [
              Expanded(
                child: _LightActionButton(
                  metrics: metrics,
                  label: restartRelayLabel,
                  onTap: onRestartRelay,
                ),
              ),
              SizedBox(width: metrics.actionButtonGap),
              Expanded(
                child: _LightActionButton(
                  metrics: metrics,
                  label: checkForUpdatesLabel,
                  onTap: onCheckForUpdates,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LightMetaRow extends StatelessWidget {
  const _LightMetaRow({
    required this.metrics,
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final _SystemShellConnectedLightMetrics metrics;
  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final valueStyle =
        monospace
            ? GoogleFonts.robotoMono(
              color: const Color(0xFF4B5563),
              fontSize: metrics.metaValueSize,
              height: 15 / 10,
              fontWeight: FontWeight.w400,
            )
            : Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF4B5563),
              fontSize: metrics.metaValueSize,
              height: 15 / 10,
              fontWeight: FontWeight.w400,
            );
    return Row(
      children: [
        SizedBox(
          width: metrics.metaLabelWidth,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
              fontSize: metrics.metaLabelSize,
              height: 15 / 10,
            ),
          ),
        ),
        SizedBox(width: metrics.metaValueGap),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: valueStyle,
          ),
        ),
      ],
    );
  }
}

class _LightActionButton extends StatelessWidget {
  const _LightActionButton({
    required this.metrics,
    required this.label,
    required this.onTap,
  });

  final _SystemShellConnectedLightMetrics metrics;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(metrics.actionButtonRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(metrics.actionButtonRadius),
        onTap: onTap,
        child: SizedBox(
          height: metrics.actionButtonHeight,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                textStyle: Theme.of(context).textTheme.labelSmall,
                color: const Color(0xFF111827),
                fontSize: metrics.actionButtonSize,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                height: 15 / 10,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoCamerasLightCard extends StatelessWidget {
  const _NoCamerasLightCard({required this.metrics, required this.onAddCamera});

  final _SystemShellConnectedLightMetrics metrics;
  final VoidCallback onAddCamera;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: metrics.noCameraCardHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(metrics.panelRadius),
        border: Border.all(color: const Color(0x0A000000)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'No cameras connected yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF9CA3AF),
              fontSize: metrics.emptyTitleSize,
              height: 16.5 / 11,
            ),
          ),
          SizedBox(height: metrics.emptyActionGap),
          TextButton(
            onPressed: onAddCamera,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: const Color(0xFF8BB3EE),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Add your first camera',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF8BB3EE),
                    fontSize: metrics.emptyActionSize,
                    fontWeight: FontWeight.w500,
                    height: 16.5 / 11,
                  ),
                ),
                SizedBox(width: 2 * metrics.scale),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: metrics.emptyArrowSize,
                  color: const Color(0xFF8BB3EE),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraListLightCard extends StatelessWidget {
  const _CameraListLightCard({
    required this.metrics,
    required this.cameraNames,
    this.onOpenCamera,
  });

  final _SystemShellConnectedLightMetrics metrics;
  final List<String> cameraNames;
  final ValueChanged<String>? onOpenCamera;

  @override
  Widget build(BuildContext context) {
    final rowHeight = 51 * metrics.scale;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(metrics.panelRadius),
        border: Border.all(color: const Color(0x0A000000)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < cameraNames.length; i++) ...[
            _CameraListLightRow(
              metrics: metrics,
              name: cameraNames[i],
              height: rowHeight,
              onTap:
                  onOpenCamera == null
                      ? null
                      : () => onOpenCamera!(cameraNames[i]),
            ),
            if (i != cameraNames.length - 1)
              Divider(height: 1, thickness: 1, color: const Color(0x0A000000)),
          ],
        ],
      ),
    );
  }
}

class _CameraListLightRow extends StatelessWidget {
  const _CameraListLightRow({
    required this.metrics,
    required this.name,
    required this.height,
    this.onTap,
  });

  final _SystemShellConnectedLightMetrics metrics;
  final String name;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: metrics.cardInset),
        child: Row(
          children: [
            Container(
              width: 6 * metrics.scale,
              height: 6 * metrics.scale,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 12 * metrics.scale),
            Expanded(
              child: Text(
                name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF111827),
                  fontSize: 11 * metrics.scale,
                  fontWeight: FontWeight.w500,
                  height: 16.5 / 11,
                ),
              ),
            ),
            Text(
              'Online',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF9CA3AF),
                fontSize: 10 * metrics.scale,
                height: 15 / 10,
              ),
            ),
            SizedBox(width: 4 * metrics.scale),
            Icon(
              Icons.chevron_right_rounded,
              size: 16 * metrics.scale,
              color: const Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

class _SecurityLightCard extends StatelessWidget {
  const _SecurityLightCard({required this.metrics});

  final _SystemShellConnectedLightMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: metrics.securityCardHeight),
      decoration: BoxDecoration(
        color: const Color(0x0F10B981),
        borderRadius: BorderRadius.circular(metrics.panelRadius),
        border: Border.all(color: const Color(0x4D10B981)),
      ),
      padding: EdgeInsets.fromLTRB(
        metrics.cardInset,
        metrics.securityTopInset,
        metrics.cardInset,
        metrics.cardInset,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: metrics.securityIconTopInset),
            child: Icon(
              Icons.lock_outline_rounded,
              size: metrics.securityIconSize,
              color: const Color(0xFF10B981),
            ),
          ),
          SizedBox(width: metrics.securityIconGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'End-to-end encryption is always on',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF10B981),
                    fontSize: metrics.securityTitleSize,
                    fontWeight: FontWeight.w600,
                    height: 16.5 / 11,
                  ),
                ),
                SizedBox(height: metrics.securityBodyGap),
                Text(
                  'All credentials and encryption keys stay\non this device. Secluso cannot access\nyour footage or connection details.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontSize: metrics.securityBodySize,
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

class _NeedHelpLightCard extends StatelessWidget {
  const _NeedHelpLightCard({
    required this.metrics,
    required this.onContactSupport,
    required this.onVisitWebsite,
  });

  final _SystemShellConnectedLightMetrics metrics;
  final VoidCallback onContactSupport;
  final VoidCallback onVisitWebsite;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: metrics.helpCardHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(metrics.panelRadius),
        border: Border.all(color: const Color(0x0A000000)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        metrics.cardInset,
        metrics.cardInset,
        metrics.cardInset,
        metrics.cardInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Need help?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF111827),
              fontSize: metrics.helpTitleSize,
              fontWeight: FontWeight.w600,
              height: 16.5 / 11,
            ),
          ),
          SizedBox(height: metrics.helpTopGap),
          _LightHelpRow(
            metrics: metrics,
            label: 'Contact Support',
            onTap: onContactSupport,
          ),
          SizedBox(height: metrics.helpRowGap),
          _LightHelpRow(
            metrics: metrics,
            label: 'Visit secluso.com',
            onTap: onVisitWebsite,
          ),
        ],
      ),
    );
  }
}

class _LightHelpRow extends StatelessWidget {
  const _LightHelpRow({
    required this.metrics,
    required this.label,
    required this.onTap,
  });

  final _SystemShellConnectedLightMetrics metrics;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(metrics.helpRowRadius),
        onTap: onTap,
        child: SizedBox(
          height: metrics.helpRowHeight,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B5563),
                    fontSize: metrics.helpRowSize,
                    height: 16.5 / 11,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_outward_rounded,
                size: metrics.helpRowIconSize,
                color: const Color(0xFF4B5563),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemShellConnectedLightMetrics {
  const _SystemShellConnectedLightMetrics({
    required this.scale,
    required this.topPadding,
    required this.bottomPadding,
    required this.pageInset,
    required this.railInset,
    required this.titleSize,
    required this.subtitleTopGap,
    required this.subtitleSize,
    required this.headerToRelayGap,
    required this.sectionTopGap,
    required this.sectionBottomGap,
    required this.cardGap,
    required this.relayCardRadius,
    required this.panelRadius,
    required this.cardInset,
    required this.relayCardInset,
    required this.relayCardHeight,
    required this.relayIconWrapSize,
    required this.relayIconSize,
    required this.relayHeaderGap,
    required this.relayTitleSize,
    required this.relayMetaTopGap,
    required this.relayMetaSize,
    required this.relayBodyGap,
    required this.metaPanelHeight,
    required this.metaPanelRadius,
    required this.metaPanelInset,
    required this.metaRowGap,
    required this.metaLabelWidth,
    required this.metaValueGap,
    required this.metaLabelSize,
    required this.metaValueSize,
    required this.relayActionsGap,
    required this.actionButtonGap,
    required this.actionButtonHeight,
    required this.actionButtonRadius,
    required this.actionButtonSize,
    required this.sectionLabelSize,
    required this.sectionLabelLetterSpacing,
    required this.addActionSize,
    required this.noCameraCardHeight,
    required this.emptyTitleSize,
    required this.emptyActionGap,
    required this.emptyActionSize,
    required this.emptyArrowSize,
    required this.securityCardHeight,
    required this.securityTopInset,
    required this.securityIconTopInset,
    required this.securityIconSize,
    required this.securityIconGap,
    required this.securityTitleSize,
    required this.securityBodyGap,
    required this.securityBodySize,
    required this.helpCardHeight,
    required this.helpTitleSize,
    required this.helpTopGap,
    required this.helpRowGap,
    required this.helpRowHeight,
    required this.helpRowSize,
    required this.helpRowIconSize,
    required this.helpRowRadius,
  });

  final double scale;
  final double topPadding;
  final double bottomPadding;
  final double pageInset;
  final double railInset;
  final double titleSize;
  final double subtitleTopGap;
  final double subtitleSize;
  final double headerToRelayGap;
  final double sectionTopGap;
  final double sectionBottomGap;
  final double cardGap;
  final double relayCardRadius;
  final double panelRadius;
  final double cardInset;
  final double relayCardInset;
  final double relayCardHeight;
  final double relayIconWrapSize;
  final double relayIconSize;
  final double relayHeaderGap;
  final double relayTitleSize;
  final double relayMetaTopGap;
  final double relayMetaSize;
  final double relayBodyGap;
  final double metaPanelHeight;
  final double metaPanelRadius;
  final double metaPanelInset;
  final double metaRowGap;
  final double metaLabelWidth;
  final double metaValueGap;
  final double metaLabelSize;
  final double metaValueSize;
  final double relayActionsGap;
  final double actionButtonGap;
  final double actionButtonHeight;
  final double actionButtonRadius;
  final double actionButtonSize;
  final double sectionLabelSize;
  final double sectionLabelLetterSpacing;
  final double addActionSize;
  final double noCameraCardHeight;
  final double emptyTitleSize;
  final double emptyActionGap;
  final double emptyActionSize;
  final double emptyArrowSize;
  final double securityCardHeight;
  final double securityTopInset;
  final double securityIconTopInset;
  final double securityIconSize;
  final double securityIconGap;
  final double securityTitleSize;
  final double securityBodyGap;
  final double securityBodySize;
  final double helpCardHeight;
  final double helpTitleSize;
  final double helpTopGap;
  final double helpRowGap;
  final double helpRowHeight;
  final double helpRowSize;
  final double helpRowIconSize;
  final double helpRowRadius;

  factory _SystemShellConnectedLightMetrics.forWidth(double width) {
    final scale = width / 290;
    double scaled(double value) => value * scale;
    return _SystemShellConnectedLightMetrics(
      scale: scale,
      topPadding: scaled(12),
      bottomPadding: scaled(18),
      pageInset: scaled(20),
      railInset: scaled(16),
      titleSize: scaled(22),
      subtitleTopGap: scaled(6),
      subtitleSize: scaled(11),
      headerToRelayGap: scaled(12.75),
      sectionTopGap: scaled(16),
      sectionBottomGap: scaled(8),
      cardGap: scaled(16),
      relayCardRadius: scaled(16),
      panelRadius: scaled(12),
      cardInset: scaled(16),
      relayCardInset: scaled(16),
      relayCardHeight: scaled(214),
      relayIconWrapSize: scaled(40),
      relayIconSize: scaled(20),
      relayHeaderGap: scaled(12),
      relayTitleSize: scaled(13),
      relayMetaTopGap: scaled(2),
      relayMetaSize: scaled(10),
      relayBodyGap: scaled(12),
      metaPanelHeight: scaled(85),
      metaPanelRadius: scaled(8),
      metaPanelInset: scaled(12),
      metaRowGap: scaled(8),
      metaLabelWidth: scaled(64),
      metaValueGap: scaled(12),
      metaLabelSize: scaled(10),
      metaValueSize: scaled(10),
      relayActionsGap: scaled(12),
      actionButtonGap: scaled(6),
      actionButtonHeight: scaled(31),
      actionButtonRadius: scaled(8),
      actionButtonSize: scaled(10),
      sectionLabelSize: scaled(10),
      sectionLabelLetterSpacing: scaled(1),
      addActionSize: scaled(10),
      noCameraCardHeight: scaled(102.5),
      emptyTitleSize: scaled(11),
      emptyActionGap: scaled(14),
      emptyActionSize: scaled(11),
      emptyArrowSize: scaled(11),
      securityCardHeight: scaled(103.25),
      securityTopInset: scaled(18),
      securityIconTopInset: 0,
      securityIconSize: scaled(16),
      securityIconGap: scaled(12),
      securityTitleSize: scaled(11),
      securityBodyGap: scaled(8),
      securityBodySize: scaled(10),
      helpCardHeight: scaled(103.5),
      helpTitleSize: scaled(11),
      helpTopGap: scaled(12),
      helpRowGap: scaled(12),
      helpRowHeight: scaled(16.5),
      helpRowSize: scaled(11),
      helpRowIconSize: scaled(12),
      helpRowRadius: scaled(6),
    );
  }
}

class SystemShellNoCamerasPage extends StatelessWidget {
  const SystemShellNoCamerasPage({
    super.key,
    required this.endpoint,
    required this.onRestartRelay,
    required this.onCheckForUpdates,
    required this.onAddCamera,
    this.onOpenCamera,
    required this.onContactSupport,
    required this.onVisitWebsite,
    this.restartRelayLabel = 'Remove Relay',
    this.checkForUpdatesLabel = 'Check for Updates',
    this.cameraNames = const [],
  });

  final String endpoint;
  final VoidCallback onRestartRelay;
  final VoidCallback onCheckForUpdates;
  final VoidCallback onAddCamera;
  final ValueChanged<String>? onOpenCamera;
  final VoidCallback onContactSupport;
  final VoidCallback onVisitWebsite;
  final String restartRelayLabel;
  final String checkForUpdatesLabel;
  final List<String> cameraNames;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _SystemShellMetrics.forWidth(constraints.maxWidth);
        return ColoredBox(
          color: const Color(0xFF050505),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              0,
              metrics.topPadding,
              0,
              metrics.bottomPadding,
            ),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.pageInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System',
                      style: shellTitleStyle(
                        context,
                        fontSize: metrics.titleSize,
                        designLetterSpacing: 0.55 * metrics.scale,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: metrics.subtitleTopGap),
                    Text(
                      'Your private relay and connected devices.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: metrics.subtitleSize,
                        height: 16.5 / 11,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: metrics.headerToRelayGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child: _RelayConnectedCard(
                  metrics: metrics,
                  endpoint: endpoint,
                  onRestartRelay: onRestartRelay,
                  onCheckForUpdates: onCheckForUpdates,
                  restartRelayLabel: restartRelayLabel,
                  checkForUpdatesLabel: checkForUpdatesLabel,
                ),
              ),
              SizedBox(height: metrics.sectionTopGap),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  metrics.pageInset,
                  0,
                  metrics.pageInset,
                  0,
                ),
                child: Row(
                  children: [
                    Text(
                      'CAMERAS',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.2),
                        fontSize: metrics.sectionLabelSize,
                        fontWeight: FontWeight.w600,
                        letterSpacing: metrics.sectionLabelLetterSpacing,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: onAddCamera,
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: const Color(0xFF8BB3EE),
                      ),
                      child: Text(
                        '+ Add',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF8BB3EE),
                          fontSize: metrics.addActionSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: metrics.sectionBottomGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child:
                    cameraNames.isEmpty
                        ? _NoCamerasCard(
                          metrics: metrics,
                          onAddCamera: onAddCamera,
                        )
                        : _CameraListCard(
                          metrics: metrics,
                          cameraNames: cameraNames,
                          onOpenCamera: onOpenCamera,
                        ),
              ),
              SizedBox(height: metrics.cardGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child: _SecurityCard(metrics: metrics),
              ),
              SizedBox(height: metrics.cardGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                child: _NeedHelpCard(
                  metrics: metrics,
                  onContactSupport: onContactSupport,
                  onVisitWebsite: onVisitWebsite,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RelayConnectedCard extends StatelessWidget {
  const _RelayConnectedCard({
    required this.metrics,
    required this.endpoint,
    required this.onRestartRelay,
    required this.onCheckForUpdates,
    required this.restartRelayLabel,
    required this.checkForUpdatesLabel,
  });

  final _SystemShellMetrics metrics;
  final String endpoint;
  final VoidCallback onRestartRelay;
  final VoidCallback onCheckForUpdates;
  final String restartRelayLabel;
  final String checkForUpdatesLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: metrics.relayCardHeight,
      decoration: BoxDecoration(
        color: const Color(0x0F10B981),
        borderRadius: BorderRadius.circular(metrics.cardRadius),
        border: Border.all(color: const Color(0x3310B981)),
      ),
      padding: EdgeInsets.all(metrics.cardInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: metrics.relayIconOuterSize,
                height: metrics.relayIconOuterSize,
                decoration: BoxDecoration(
                  color: const Color(0x2610B981),
                  borderRadius: BorderRadius.circular(
                    metrics.relayIconOuterSize / 2,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: metrics.relayIconInnerSize,
                    height: metrics.relayIconInnerSize,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFF34D399),
                        width: metrics.relayIconStrokeWidth,
                      ),
                      borderRadius: BorderRadius.circular(
                        metrics.relayIconInnerSize / 2,
                      ),
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: metrics.relayCheckSize,
                      color: const Color(0xFF34D399),
                    ),
                  ),
                ),
              ),
              SizedBox(width: metrics.relayHeaderGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Relay Connected',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF34D399),
                        fontSize: metrics.relayTitleSize,
                        fontWeight: FontWeight.w600,
                        height: 19.5 / 13,
                      ),
                    ),
                    SizedBox(height: metrics.relayMetaTopGap),
                    Text(
                      'Phone linked · System ready',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: metrics.relayMetaSize,
                        height: 15 / 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.relayBodyGap),
          Container(
            height: metrics.metaPanelHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(metrics.metaPanelRadius),
            ),
            padding: EdgeInsets.fromLTRB(
              metrics.metaPanelInset,
              metrics.metaPanelInset,
              metrics.metaPanelInset,
              metrics.metaPanelInset - (2 * metrics.scale),
            ),
            child: Column(
              children: [
                _MetaRow(
                  metrics: metrics,
                  label: 'Endpoint',
                  value: endpoint,
                  monospace: true,
                ),
                SizedBox(height: metrics.metaRowGap),
                _MetaRow(
                  metrics: metrics,
                  label: 'Protocol',
                  value: 'MLS v1.0 (RFC 9420)',
                ),
                SizedBox(height: metrics.metaRowGap),
                _MetaRow(
                  metrics: metrics,
                  label: 'Last Sync',
                  value: 'Just now',
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.relayActionsGap),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  metrics: metrics,
                  label: restartRelayLabel,
                  onTap: onRestartRelay,
                ),
              ),
              SizedBox(width: metrics.actionButtonGap),
              Expanded(
                child: _ActionButton(
                  metrics: metrics,
                  label: checkForUpdatesLabel,
                  onTap: onCheckForUpdates,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.metrics,
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final _SystemShellMetrics metrics;
  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final valueStyle =
        monospace
            ? GoogleFonts.robotoMono(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: metrics.metaValueSize,
              height: 15 / 10,
              fontWeight: FontWeight.w400,
            )
            : Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: metrics.metaValueSize,
              height: 15 / 10,
              fontWeight: FontWeight.w400,
            );
    return Row(
      children: [
        SizedBox(
          width: metrics.metaLabelWidth,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: metrics.metaLabelSize,
              height: 15 / 10,
            ),
          ),
        ),
        SizedBox(width: metrics.metaValueGap),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: valueStyle,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.metrics,
    required this.label,
    required this.onTap,
  });

  final _SystemShellMetrics metrics;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x0FFFFFFF),
      borderRadius: BorderRadius.circular(metrics.actionButtonRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(metrics.actionButtonRadius),
        onTap: onTap,
        child: SizedBox(
          height: metrics.actionButtonHeight,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                textStyle: Theme.of(context).textTheme.labelSmall,
                color: Colors.white,
                fontSize: metrics.actionButtonSize,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                height: 15 / 10,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoCamerasCard extends StatelessWidget {
  const _NoCamerasCard({required this.metrics, required this.onAddCamera});

  final _SystemShellMetrics metrics;
  final VoidCallback onAddCamera;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: metrics.noCameraCardHeight,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(metrics.noCameraCardRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'No cameras connected yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.2),
              fontSize: metrics.emptyTitleSize,
              height: 16.5 / 11,
            ),
          ),
          SizedBox(height: metrics.emptyActionGap),
          TextButton(
            onPressed: onAddCamera,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: const Color(0xFF8BB3EE),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Add your first camera',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF8BB3EE),
                    fontSize: metrics.emptyActionSize,
                    fontWeight: FontWeight.w500,
                    height: 16.5 / 11,
                  ),
                ),
                SizedBox(width: 2 * metrics.scale),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: metrics.emptyArrowSize,
                  color: const Color(0xFF8BB3EE),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraListCard extends StatelessWidget {
  const _CameraListCard({
    required this.metrics,
    required this.cameraNames,
    this.onOpenCamera,
  });

  final _SystemShellMetrics metrics;
  final List<String> cameraNames;
  final ValueChanged<String>? onOpenCamera;

  @override
  Widget build(BuildContext context) {
    final rowHeight = 51 * metrics.scale;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(metrics.noCameraCardRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < cameraNames.length; i++) ...[
            _CameraListRow(
              metrics: metrics,
              name: cameraNames[i],
              height: rowHeight,
              onTap:
                  onOpenCamera == null
                      ? null
                      : () => onOpenCamera!(cameraNames[i]),
            ),
            if (i != cameraNames.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: Colors.white.withValues(alpha: 0.05),
              ),
          ],
        ],
      ),
    );
  }
}

class _CameraListRow extends StatelessWidget {
  const _CameraListRow({
    required this.metrics,
    required this.name,
    required this.height,
    this.onTap,
  });

  final _SystemShellMetrics metrics;
  final String name;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: metrics.cardInset),
        child: Row(
          children: [
            Container(
              width: 6 * metrics.scale,
              height: 6 * metrics.scale,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 12 * metrics.scale),
            Expanded(
              child: Text(
                name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontSize: 11 * metrics.scale,
                  fontWeight: FontWeight.w500,
                  height: 16.5 / 11,
                ),
              ),
            ),
            Text(
              'Online',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10 * metrics.scale,
                height: 15 / 10,
              ),
            ),
            SizedBox(width: 4 * metrics.scale),
            Icon(
              Icons.chevron_right_rounded,
              size: 16 * metrics.scale,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.metrics});

  final _SystemShellMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: metrics.securityCardHeight),
      decoration: BoxDecoration(
        color: const Color(0x0F10B981),
        borderRadius: BorderRadius.circular(metrics.noCameraCardRadius),
        border: Border.all(color: const Color(0x2610B981)),
      ),
      padding: EdgeInsets.fromLTRB(
        metrics.cardInset,
        metrics.securityCardTopInset,
        metrics.cardInset,
        metrics.cardInset,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: metrics.securityIconTopInset),
            child: Icon(
              Icons.lock_outline_rounded,
              size: metrics.securityIconSize,
              color: const Color(0xFF10B981),
            ),
          ),
          SizedBox(width: metrics.securityIconGap),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'End-to-end encryption is always on',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF10D39A),
                    fontSize: metrics.securityTitleSize,
                    fontWeight: FontWeight.w600,
                    height: 16.5 / 11,
                  ),
                ),
                SizedBox(height: metrics.securityBodyGap),
                Text(
                  'All credentials and encryption keys stay\non this device. Secluso cannot access\nyour footage or connection details.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: metrics.securityBodySize,
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

class _NeedHelpCard extends StatelessWidget {
  const _NeedHelpCard({
    required this.metrics,
    required this.onContactSupport,
    required this.onVisitWebsite,
  });

  final _SystemShellMetrics metrics;
  final VoidCallback onContactSupport;
  final VoidCallback onVisitWebsite;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: metrics.helpCardHeight),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(metrics.noCameraCardRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      padding: EdgeInsets.fromLTRB(
        metrics.cardInset,
        metrics.helpCardTopInset,
        metrics.cardInset,
        metrics.cardInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Need help?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontSize: metrics.helpTitleSize,
              fontWeight: FontWeight.w600,
              height: 16.5 / 11,
            ),
          ),
          SizedBox(height: metrics.helpTopGap),
          _HelpLinkRow(
            metrics: metrics,
            label: 'Contact Support',
            onTap: onContactSupport,
          ),
          SizedBox(height: metrics.helpRowGap),
          _HelpLinkRow(
            metrics: metrics,
            label: 'Visit secluso.com',
            onTap: onVisitWebsite,
          ),
        ],
      ),
    );
  }
}

class _HelpLinkRow extends StatelessWidget {
  const _HelpLinkRow({
    required this.metrics,
    required this.label,
    required this.onTap,
  });

  final _SystemShellMetrics metrics;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(metrics.helpRowRadius),
        onTap: onTap,
        child: SizedBox(
          height: metrics.helpRowHeight,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: metrics.helpRowSize,
                    height: 16.5 / 11,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_outward_rounded,
                size: metrics.helpRowIconSize,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemShellMetrics {
  const _SystemShellMetrics({
    required this.scale,
    required this.topPadding,
    required this.bottomPadding,
    required this.pageInset,
    required this.railInset,
    required this.titleSize,
    required this.subtitleSize,
    required this.subtitleTopGap,
    required this.headerToRelayGap,
    required this.cardGap,
    required this.cardRadius,
    required this.cardInset,
    required this.relayCardHeight,
    required this.relayIconOuterSize,
    required this.relayIconInnerSize,
    required this.relayIconStrokeWidth,
    required this.relayCheckSize,
    required this.relayHeaderGap,
    required this.relayTitleSize,
    required this.relayMetaSize,
    required this.relayMetaTopGap,
    required this.relayBodyGap,
    required this.metaPanelHeight,
    required this.metaPanelRadius,
    required this.metaPanelInset,
    required this.metaRowGap,
    required this.metaLabelSize,
    required this.metaLabelWidth,
    required this.metaValueSize,
    required this.metaValueGap,
    required this.relayActionsGap,
    required this.actionButtonGap,
    required this.actionButtonHeight,
    required this.actionButtonRadius,
    required this.actionButtonSize,
    required this.sectionTopGap,
    required this.sectionBottomGap,
    required this.sectionLabelSize,
    required this.sectionLabelLetterSpacing,
    required this.addActionSize,
    required this.noCameraCardHeight,
    required this.noCameraCardRadius,
    required this.emptyTitleSize,
    required this.emptyActionGap,
    required this.emptyActionSize,
    required this.emptyArrowSize,
    required this.securityCardHeight,
    required this.securityCardTopInset,
    required this.securityIconTopInset,
    required this.securityIconSize,
    required this.securityIconGap,
    required this.securityTitleSize,
    required this.securityBodyGap,
    required this.securityBodySize,
    required this.helpCardHeight,
    required this.helpCardTopInset,
    required this.helpTitleSize,
    required this.helpTopGap,
    required this.helpRowGap,
    required this.helpRowHeight,
    required this.helpRowSize,
    required this.helpRowIconSize,
    required this.helpRowRadius,
  });

  final double scale;
  final double topPadding;
  final double bottomPadding;
  final double pageInset;
  final double railInset;
  final double titleSize;
  final double subtitleSize;
  final double subtitleTopGap;
  final double headerToRelayGap;
  final double cardGap;
  final double cardRadius;
  final double cardInset;
  final double relayCardHeight;
  final double relayIconOuterSize;
  final double relayIconInnerSize;
  final double relayIconStrokeWidth;
  final double relayCheckSize;
  final double relayHeaderGap;
  final double relayTitleSize;
  final double relayMetaSize;
  final double relayMetaTopGap;
  final double relayBodyGap;
  final double metaPanelHeight;
  final double metaPanelRadius;
  final double metaPanelInset;
  final double metaRowGap;
  final double metaLabelSize;
  final double metaLabelWidth;
  final double metaValueSize;
  final double metaValueGap;
  final double relayActionsGap;
  final double actionButtonGap;
  final double actionButtonHeight;
  final double actionButtonRadius;
  final double actionButtonSize;
  final double sectionTopGap;
  final double sectionBottomGap;
  final double sectionLabelSize;
  final double sectionLabelLetterSpacing;
  final double addActionSize;
  final double noCameraCardHeight;
  final double noCameraCardRadius;
  final double emptyTitleSize;
  final double emptyActionGap;
  final double emptyActionSize;
  final double emptyArrowSize;
  final double securityCardHeight;
  final double securityCardTopInset;
  final double securityIconTopInset;
  final double securityIconSize;
  final double securityIconGap;
  final double securityTitleSize;
  final double securityBodyGap;
  final double securityBodySize;
  final double helpCardHeight;
  final double helpCardTopInset;
  final double helpTitleSize;
  final double helpTopGap;
  final double helpRowGap;
  final double helpRowHeight;
  final double helpRowSize;
  final double helpRowIconSize;
  final double helpRowRadius;

  factory _SystemShellMetrics.forWidth(double width) {
    final scale = width / 290;
    double scaled(double value) => value * scale;

    return _SystemShellMetrics(
      scale: scale,
      topPadding: scaled(12),
      bottomPadding: scaled(16),
      pageInset: scaled(20),
      railInset: scaled(16),
      titleSize: scaled(22),
      subtitleSize: scaled(11),
      subtitleTopGap: scaled(7),
      headerToRelayGap: scaled(14),
      cardGap: scaled(16),
      cardRadius: scaled(16),
      cardInset: scaled(16),
      relayCardHeight: scaled(214),
      relayIconOuterSize: scaled(40),
      relayIconInnerSize: scaled(20),
      relayIconStrokeWidth: scaled(1.5),
      relayCheckSize: scaled(12),
      relayHeaderGap: scaled(12),
      relayTitleSize: scaled(13),
      relayMetaSize: scaled(10),
      relayMetaTopGap: scaled(2),
      relayBodyGap: scaled(12),
      metaPanelHeight: scaled(85),
      metaPanelRadius: scaled(8),
      metaPanelInset: scaled(12),
      metaRowGap: scaled(8),
      metaLabelSize: scaled(10),
      metaLabelWidth: scaled(58),
      metaValueSize: scaled(10),
      metaValueGap: scaled(8),
      relayActionsGap: scaled(12),
      actionButtonGap: scaled(6),
      actionButtonHeight: scaled(31),
      actionButtonRadius: scaled(8),
      actionButtonSize: scaled(10),
      sectionTopGap: scaled(16),
      sectionBottomGap: scaled(10),
      sectionLabelSize: scaled(10),
      sectionLabelLetterSpacing: scaled(1),
      addActionSize: scaled(10),
      noCameraCardHeight: scaled(102.5),
      noCameraCardRadius: scaled(12),
      emptyTitleSize: scaled(11),
      emptyActionGap: scaled(12),
      emptyActionSize: scaled(11),
      emptyArrowSize: scaled(13),
      securityCardHeight: scaled(103.25),
      securityCardTopInset: scaled(18),
      securityIconTopInset: scaled(0),
      securityIconSize: scaled(16),
      securityIconGap: scaled(12),
      securityTitleSize: scaled(11),
      securityBodyGap: scaled(8),
      securityBodySize: scaled(10),
      helpCardHeight: scaled(103.5),
      helpCardTopInset: scaled(16),
      helpTitleSize: scaled(11),
      helpTopGap: scaled(12),
      helpRowGap: scaled(12),
      helpRowHeight: scaled(16.5),
      helpRowSize: scaled(11),
      helpRowIconSize: scaled(12),
      helpRowRadius: scaled(6),
    );
  }
}
