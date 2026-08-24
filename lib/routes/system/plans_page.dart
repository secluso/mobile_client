//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Choosing a plan for one camera.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/system/system_marks.dart';
import 'package:secluso_flutter/routes/system/system_models.dart';
import 'package:secluso_flutter/routes/system/system_theme.dart';
import 'package:secluso_flutter/routes/system/system_widgets.dart';

class PlansPage extends StatelessWidget {
  const PlansPage({
    required this.offers,
    required this.onChoose,
    this.webBilling = false,
    super.key,
  });

  final List<PlanOffer> offers;
  final ValueChanged<PlanOffer> onChoose;

  /// This build can't sell through a store (F-Droid) so use the web
  final bool webBilling;

  @override
  Widget build(BuildContext context) {
    final palette = SystemPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            DetailHeader(
              title: 'Choose a plan',
              eyebrow: 'Your plan',
              palette: palette,
              compact: true,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Every plan is end-to-end encrypted.',
                style: palette.emptyBody.copyWith(
                  fontSize: 13,
                  height: 1.45,
                  color: palette.dim(0.52),
                ),
              ),
            ),
            if (webBilling) ...[
              const SizedBox(height: 12),
              _WebBillingNote(palette: palette),
            ],
            const SizedBox(height: 14),
            for (final offer in offers) ...[
              _PlanCard(
                offer: offer,
                palette: palette,
                onTap: () => onChoose(offer),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
            Text(
              'Add people to a camera later; they share your plan & bandwidth.',
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

/// Tells the user, before they tap, that picking a plan opens the web
class _WebBillingNote extends StatelessWidget {
  const _WebBillingNote({required this.palette});

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: palette.dim(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        children: [
          Icon(Icons.open_in_new_rounded, size: 15, color: palette.dim(0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Plans are set up on the web for this version. '
              'Choosing one opens secluso.net.',
              style: palette.emptyBody.copyWith(
                fontSize: 12.5,
                height: 1.4,
                color: palette.dim(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.offer,
    required this.palette,
    required this.onTap,
  });

  final PlanOffer offer;
  final SystemPalette palette;
  final VoidCallback onTap;

  /// The tier tints its own border. Free stays neutral.
  Color get _border => switch (offer.tier) {
    PlanTier.free => palette.hairline,
    PlanTier.premium => palette.blue.withValues(alpha: 0.26),
    PlanTier.anonymous => palette.mint.withValues(alpha: 0.26),
  };

  @override
  Widget build(BuildContext context) {
    return SystemTappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          offer.tier.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: palette.planName.copyWith(
                            fontSize: 32,
                            color:
                                offer.tier == PlanTier.free
                                    ? palette.text
                                    : palette.tierColor(offer.tier),
                            fontStyle:
                                offer.tier == PlanTier.anonymous
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                          ),
                        ),
                      ),
                      if (offer.popular) ...[
                        const SizedBox(width: 10),
                        _PopularTag(palette: palette),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: offer.cost,
                        style: palette.relayName.copyWith(fontSize: 20),
                      ),
                      if (offer.period.isNotEmpty)
                        TextSpan(
                          text: offer.period,
                          style: palette.relayEndpoint.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              offer.allowance,
              style: palette.cameraMeta.copyWith(
                fontSize: 11,
                color: palette.dim(0.6),
                letterSpacing: 11 * 0.01,
              ),
            ),
            if (offer.note != null) ...[
              const SizedBox(height: 5),
              Text(
                offer.note!,
                style: palette.emptyBody.copyWith(
                  fontSize: 12.5,
                  height: 1.4,
                  color: palette.dim(0.38),
                ),
              ),
            ],
            if (offer.tier == PlanTier.anonymous)
              _AnonymousCase(palette: palette),
          ],
        ),
      ),
    );
  }
}

class _PopularTag extends StatelessWidget {
  const _PopularTag({required this.palette});

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: palette.blue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'POPULAR',
        style: palette.eyebrow.copyWith(
          fontSize: 8.5,
          letterSpacing: 8.5 * 0.14,
          color: palette.bg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Why anonymity is worth paying for on top of encryption.
class _AnonymousCase extends StatelessWidget {
  const _AnonymousCase({required this.palette});

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 13),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
          decoration: BoxDecoration(
            color: palette.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.hairline),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 96,
                child: CrowdMark(palette: palette, roughness: 0.9),
              ),
              const SizedBox(height: 4),
              Text(
                'To the relay, you look like everyone else.',
                textAlign: TextAlign.center,
                style: palette.emptyBody.copyWith(
                  fontSize: 11,
                  height: 1.4,
                  color: palette.dim(0.55),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        _ContrastRow(
          palette: palette,
          icon: Icons.check_rounded,
          tint: palette.dim(0.08),
          iconColor: palette.dim(0.52),
          lead: 'Encryption hides ',
          emphasis: 'what you send',
        ),
        const SizedBox(height: 10),
        _ContrastRow(
          palette: palette,
          icon: Icons.star_rounded,
          tint: palette.mint.withValues(alpha: 0.16),
          iconColor: palette.mint,
          lead: 'Anonymous hides ',
          emphasis: "that it's you",
        ),
        const SizedBox(height: 11),
        Text(
          'No name, no account, no trail the relay can follow.',
          style: palette.emptyBody.copyWith(
            fontSize: 12,
            height: 1.4,
            color: palette.dim(0.6),
          ),
        ),
        const SizedBox(height: 4),
        // Named only for the curious, never as a headline.
        Text(
          'OBLIVIOUS HTTP · ANONYMOUS CREDENTIALS',
          style: palette.eyebrow.copyWith(
            fontSize: 9.5,
            letterSpacing: 9.5 * 0.14,
            color: palette.mint.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _ContrastRow extends StatelessWidget {
  const _ContrastRow({
    required this.palette,
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.lead,
    required this.emphasis,
  });

  final SystemPalette palette;
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String lead;
  final String emphasis;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Icon(icon, size: 13, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: lead),
                TextSpan(
                  text: emphasis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            style: palette.emptyBody.copyWith(fontSize: 13, height: 1.35),
          ),
        ),
      ],
    );
  }
}
