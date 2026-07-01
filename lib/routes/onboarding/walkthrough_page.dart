//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';

/// Onboarding walkthrough
///
/// Shown once on first launch (gated by [PrefKeys.walkthroughSeen]) and re-openable from Settings via [WalkthroughPage.markSeen] / [open].
class WalkthroughPage extends StatefulWidget {
  /// Called when the user finishes, skips, or taps the Get Started button
  final VoidCallback onDone;

  /// Panel to open on first build
  final int initialIndex;

  const WalkthroughPage({
    super.key,
    required this.onDone,
    this.initialIndex = 0,
  });

  /// Records that the walkthrough has been seen so it does not appear again.
  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefKeys.walkthroughSeen, true);
  }

  /// True once the walkthrough has been completed at least once.
  static Future<bool> hasBeenSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(PrefKeys.walkthroughSeen) ?? false;
  }

  /// Pushes the walkthrough as a standalone route (used for replay walkthrough button from Settings)
  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder:
            (context, _, __) =>
                WalkthroughPage(onDone: () => Navigator.of(context).maybePop()),
        transitionsBuilder:
            (context, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<WalkthroughPage> createState() => _WalkthroughPageState();
}

class _WalkthroughPageState extends State<WalkthroughPage> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i < 0 || i >= _kPanels.length) return;
    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    await WalkthroughPage.markSeen();
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Wt.bg,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: _kPanels.length,
              itemBuilder:
                  (context, i) => _WalkthroughPanelView(
                    panel: _kPanels[i],
                    index: i,
                    total: _kPanels.length,
                    onNext: () => _go(i + 1),
                    onJump: _go,
                    onDone: _finish,
                  ),
            ),
            Positioned(top: 14, right: 22, child: _SkipButton(onTap: _finish)),
          ],
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SkipButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Text(
          'Skip',
          style: GoogleFonts.inter(
            color: _Wt.paper.withValues(alpha: 0.52),
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class _WalkthroughPanelView extends StatelessWidget {
  final _Panel panel;
  final int index;
  final int total;
  final VoidCallback onNext;
  final ValueChanged<int> onJump;
  final VoidCallback onDone;

  const _WalkthroughPanelView({
    required this.panel,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onJump,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = index == total - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: Center(child: _Illustration(panel: panel)),
            ),
          ),
          // Copy.
          Text(
            panel.eyebrow.toUpperCase(),
            style: GoogleFonts.robotoMono(
              color: _Wt.blue.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 11 * 0.22,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Text.rich(
            panel.titleSpan,
            style: GoogleFonts.inter(
              color: _Wt.paper,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              height: 1.18,
            ),
          ),
          const SizedBox(height: 12),
          Text.rich(
            panel.bodySpan,
            style: GoogleFonts.inter(
              color: _Wt.paper.withValues(alpha: 0.6),
              fontSize: 15.5,
              fontWeight: FontWeight.w400,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Dots(count: total, active: index, onJump: onJump),
              if (isLast) _Cta(onTap: onDone) else _NextButton(onTap: onNext),
            ],
          ),
        ],
      ),
    );
  }
}

class _Illustration extends StatelessWidget {
  final _Panel panel;
  const _Illustration({required this.panel});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = (constraints.maxWidth * panel.widthPct).clamp(
          0.0,
          panel.maxWidth,
        );
        final h = w / panel.aspect;
        return SizedBox(width: w, height: h, child: _LoopingClip(panel.asset));
      },
    );
  }
}

/// A muted, auto-looping video that fills its box (cover).
/// Until the first frame is ready it shows the scaffold color, so there is no flash on entry.
class _LoopingClip extends StatefulWidget {
  final String asset;
  const _LoopingClip(this.asset);

  @override
  State<_LoopingClip> createState() => _LoopingClipState();
}

class _LoopingClipState extends State<_LoopingClip> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(widget.asset);
    _controller.initialize().then((_) {
      if (!mounted) return;
      _controller
        ..setLooping(true)
        ..setVolume(0)
        ..play();
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      // Match the baked clip background so entry is seamless.
      return const ColoredBox(color: _Wt.bg);
    }
    final size = _controller.value.size;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int active;
  final ValueChanged<int> onJump;
  const _Dots({
    required this.count,
    required this.active,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onJump(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              width: i == active ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: i == active ? null : _Wt.paper.withValues(alpha: 0.18),
                gradient:
                    i == active
                        ? const LinearGradient(colors: [_Wt.blue, _Wt.mint])
                        : null,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NextButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NextButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _Wt.paper.withValues(alpha: 0.04),
          border: Border.all(color: _Wt.paper.withValues(alpha: 0.08)),
        ),
        alignment: Alignment.center,
        child: Text(
          '→',
          style: GoogleFonts.inter(
            color: _Wt.paper,
            fontSize: 20,
            fontWeight: FontWeight.w400,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class _Cta extends StatelessWidget {
  final VoidCallback onTap;
  const _Cta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
        decoration: BoxDecoration(
          color: _Wt.blue,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'Get started',
          style: GoogleFonts.inter(
            color: const Color(0xFF06121F),
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

/// Palette constants for the walkthrough
class _Wt {
  static const Color bg = Color(0xFF050505);
  static const Color paper = Color(0xFFFAFAFA);
  static const Color blue = Color(0xFF8BB3EE);
  static const Color mint = Color(0xFF9BD6C3);
}

class _Panel {
  final String asset;
  final double widthPct;
  final double maxWidth;
  final double aspect;
  final String eyebrow;
  final InlineSpan titleSpan;
  final InlineSpan bodySpan;

  const _Panel({
    required this.asset,
    required this.widthPct,
    required this.maxWidth,
    required this.aspect,
    required this.eyebrow,
    required this.titleSpan,
    required this.bodySpan,
  });
}

TextSpan _b(String text) => TextSpan(
  text: text,
  style: const TextStyle(color: _Wt.paper, fontWeight: FontWeight.w700),
);

const double _wide = 1.6;
const double _crowd = 100 / 52;

final List<_Panel> _kPanels = [
  _Panel(
    asset: 'assets/walkthrough/wt_1.mp4',
    widthPct: 0.86,
    maxWidth: 280,
    aspect: _wide,
    eyebrow: 'Welcome to Secluso',
    titleSpan: const TextSpan(text: "Home security that can't watch you back."),
    bodySpan: TextSpan(
      children: [
        const TextSpan(text: "Hi, I'm "),
        _b('Nobody'),
        const TextSpan(
          text:
              ", your guide. Fitting, since to everyone but you, that's exactly who you'll stay.",
        ),
      ],
    ),
  ),
  _Panel(
    asset: 'assets/walkthrough/wt_2.mp4',
    widthPct: 0.96,
    maxWidth: 320,
    aspect: _wide,
    eyebrow: 'Why we built this',
    titleSpan: const TextSpan(
      text: "Your camera shouldn't report to strangers.",
    ),
    bodySpan: const TextSpan(
      text:
          "Most smart cameras stream your home to a company's servers, where footage can be mined, shared, handed over, or breached. You pay to be watched.",
    ),
  ),
  _Panel(
    asset: 'assets/walkthrough/wt_3.mp4',
    widthPct: 0.86,
    maxWidth: 280,
    aspect: _wide,
    eyebrow: 'How it works',
    titleSpan: const TextSpan(text: 'End-to-end encrypted. Carried blind.'),
    bodySpan: const TextSpan(
      text:
          "Every frame is encrypted the moment it's captured, so only your phone can open it. The relay that carries it to you can never see what's inside.",
    ),
  ),
  _Panel(
    asset: 'assets/walkthrough/wt_4.mp4',
    widthPct: 0.96,
    maxWidth: 320,
    aspect: _wide,
    eyebrow: 'Your camera',
    titleSpan: const TextSpan(text: 'Bring your own camera.'),
    bodySpan: const TextSpan(
      text:
          'Use a spare Android phone as a camera, or use a Raspberry Pi with a camera module! Either one becomes a Secluso camera that captures and encrypts right where it sits. No proprietary hardware to buy.',
    ),
  ),
  _Panel(
    asset: 'assets/walkthrough/wt_5.mp4',
    widthPct: 0.94,
    maxWidth: 300,
    aspect: _crowd,
    eyebrow: 'Optional plan',
    titleSpan: const TextSpan(text: "Even our relay can't tell you apart."),
    bodySpan: const TextSpan(
      text:
          "Want more privacy than encryption alone? The Anonymous plan blends you in with everyone else, so our relay can't tell who is who. This includes anonymous credentials and masking your IP.",
    ),
  ),
];
