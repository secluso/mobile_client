//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Hand-drawn marks for the System tab,

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/system/system_theme.dart';
import 'package:secluso_flutter/ui/sketch.dart';

/// The Secluso relay: a gate you pass through, with a blinded eye above it.
/// It carries sealed traffic and cannot look inside.
class RelayGateMark extends StatelessWidget {
  const RelayGateMark({required this.palette, super.key});

  static const aspect = 64 / 52;

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _RelayGatePainter(palette), size: Size.infinite);
}

class _RelayGatePainter extends CustomPainter {
  const _RelayGatePainter(this.palette);

  final SystemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64);
    final sketch = Sketch(canvas);

    final warm = SketchPen(
      color: palette.ink,
      width: 1.4,
      roughness: 0.85,
      bowing: 0.7,
      seed: 7,
    );
    final dim = SketchPen(
      color: palette.inkDim,
      width: 1,
      roughness: 1,
      bowing: 0.8,
      seed: 4,
    );
    final blue = SketchPen(
      color: palette.blue,
      width: 1.4,
      roughness: 0.7,
      bowing: 0.6,
      seed: 9,
    );

    sketch.line(
      const Offset(8, 47),
      const Offset(56, 47),
      dim.copyWith(width: 0.8, roughness: 0.5, seed: 2),
    );
    sketch.rect(const Rect.fromLTWH(15, 17, 6, 30), warm);
    sketch.rect(const Rect.fromLTWH(43, 17, 6, 30), warm);
    sketch.quadratic(
      const Offset(17, 19),
      const Offset(32, 4),
      const Offset(47, 19),
      warm,
    );

    // The eye above the gate, drawn shut by a slash
    sketch.quadratic(
      const Offset(26, 13),
      const Offset(32, 10),
      const Offset(38, 13),
      dim,
    );
    sketch.quadratic(
      const Offset(38, 13),
      const Offset(32, 16),
      const Offset(26, 13),
      dim,
    );
    sketch.circle(const Offset(32, 13), 1.6, dim);
    sketch.line(
      const Offset(24, 16),
      const Offset(40, 9),
      dim.copyWith(width: 1.1, roughness: 0.4, seed: 3),
    );

    sketch.lock(const Offset(32, 30), 10, blue);
  }

  @override
  bool shouldRepaint(_RelayGatePainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// A self-hosted relay
class SelfHostedMark extends StatelessWidget {
  const SelfHostedMark({required this.palette, super.key});

  static const aspect = 64 / 52;

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SelfHostedPainter(palette), size: Size.infinite);
}

class _SelfHostedPainter extends CustomPainter {
  const _SelfHostedPainter(this.palette);

  final SystemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64);
    final sketch = Sketch(canvas);

    final warm = SketchPen(
      color: palette.ink,
      width: 1.4,
      roughness: 0.85,
      bowing: 0.6,
      seed: 7,
    );
    final dim = SketchPen(
      color: palette.inkDim,
      width: 1,
      roughness: 1,
      bowing: 0.8,
      seed: 4,
    );

    sketch.rect(const Rect.fromLTWH(18, 8, 28, 34), warm);
    sketch.line(const Offset(18, 20), const Offset(46, 20), dim);
    sketch.line(const Offset(18, 31), const Offset(46, 31), dim);
    sketch.dot(const Offset(23, 14), 1.4, palette.blue);
    sketch.line(const Offset(28, 14), const Offset(40, 14), dim);
    sketch.lock(
      const Offset(32, 24),
      8,
      SketchPen(
        color: palette.blue,
        width: 1.4,
        roughness: 0.7,
        bowing: 0.6,
        seed: 9,
      ),
    );
  }

  @override
  bool shouldRepaint(_SelfHostedPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// A dashed slot where another camera could stand. Keeps a one-camera list
/// reading as a ledger rather than a stub.
class GhostSlotMark extends StatelessWidget {
  const GhostSlotMark({required this.palette, super.key});

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _GhostSlotPainter(palette), size: Size.infinite);
}

class _GhostSlotPainter extends CustomPainter {
  const _GhostSlotPainter(this.palette);

  final SystemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 44);
    final sketch = Sketch(canvas);

    sketch.rect(
      const Rect.fromLTWH(5, 6, 34, 32),
      SketchPen(
        color: palette.ghost,
        width: 1.1,
        roughness: 1.3,
        bowing: 1.1,
        seed: 5,
        dash: const [4, 3],
      ),
    );
    final plus = SketchPen(
      color: palette.ghost,
      width: 1.2,
      roughness: 0.6,
      bowing: 0.4,
      seed: 8,
    );
    sketch.line(const Offset(17, 22), const Offset(27, 22), plus);
    sketch.line(const Offset(22, 17), const Offset(22, 27), plus);
  }

  @override
  bool shouldRepaint(_GhostSlotPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// A bookshelf indoors with the top spot cleared
class EmptyWatchScene extends StatelessWidget {
  const EmptyWatchScene({required this.palette, super.key});

  static const aspect = 220 / 150;

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _EmptyWatchPainter(palette), size: Size.infinite);
}

class _EmptyWatchPainter extends CustomPainter {
  const _EmptyWatchPainter(this.palette);

  final SystemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 220);
    final sketch = Sketch(canvas);

    final warm = SketchPen(
      color: palette.ink,
      width: 1.4,
      roughness: 0.85,
      bowing: 0.7,
      seed: 7,
    );
    final dim = SketchPen(
      color: palette.inkDim,
      width: 1,
      roughness: 1,
      bowing: 0.8,
      seed: 4,
    );

    sketch.line(
      const Offset(42, 134),
      const Offset(178, 134),
      dim.copyWith(width: 0.8, seed: 2),
    );

    // The shelf, with books on the lower rows and the top left clear.
    sketch.rect(const Rect.fromLTWH(76, 76, 68, 58), warm);
    sketch.line(
      const Offset(78, 106),
      const Offset(142, 106),
      warm.copyWith(width: 1.1, seed: 9),
    );
    sketch.rect(const Rect.fromLTWH(84, 84, 7, 20), dim.copyWith(seed: 10));
    sketch.rect(const Rect.fromLTWH(93, 86, 6, 18), dim.copyWith(seed: 11));
    sketch.polygon(const [
      Offset(104, 105),
      Offset(114, 85),
      Offset(120, 88),
      Offset(112, 106),
    ], dim.copyWith(seed: 12));
    sketch.rect(const Rect.fromLTWH(85, 112, 7, 19), dim.copyWith(seed: 13));
    sketch.rect(const Rect.fromLTWH(94, 110, 6, 21), dim.copyWith(seed: 14));
    sketch.rect(const Rect.fromLTWH(103, 114, 8, 17), dim.copyWith(seed: 15));

    // A crescent of night through the room, and a couple of sparks.
    sketch.cubic(
      const Offset(158, 34),
      const Offset(149, 41),
      const Offset(155, 50),
      const Offset(163.5, 45.2),
      dim.copyWith(seed: 20),
    );
    sketch.cubic(
      const Offset(163.5, 45.2),
      const Offset(157, 42),
      const Offset(154, 38),
      const Offset(158, 34),
      dim.copyWith(seed: 21),
    );
    _spark(sketch, const Offset(52, 44), dim, 22);
    _spark(sketch, const Offset(146, 22), dim, 24);

    // The phone that isn't there yet.
    final ghost = SketchPen(
      color: palette.ghost,
      width: 1.1,
      roughness: 1.1,
      bowing: 0.9,
      seed: 5,
      dash: const [5, 4],
    );
    sketch.rect(const Rect.fromLTWH(97, 28, 26, 46), ghost);
    final lens = SketchPen(
      color: palette.ghost,
      width: 1,
      roughness: 0.6,
      bowing: 0.5,
      seed: 6,
    );
    sketch.circle(const Offset(110, 46), 13, lens);
    sketch.circle(
      const Offset(110, 46),
      3,
      lens.copyWith(roughness: 0.5, seed: 7),
    );
  }

  void _spark(Sketch sketch, Offset at, SketchPen pen, int seed) {
    sketch.line(
      at - const Offset(3, 0),
      at + const Offset(3, 0),
      pen.copyWith(width: 0.9, seed: seed),
    );
    sketch.line(
      at - const Offset(0, 3),
      at + const Offset(0, 3),
      pen.copyWith(width: 0.9, seed: seed + 1),
    );
  }

  @override
  bool shouldRepaint(_EmptyWatchPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// The blind courier at work
class RelayCourierScene extends StatefulWidget {
  const RelayCourierScene({required this.palette, super.key});

  static const aspect = 300 / 100;

  final SystemPalette palette;

  @override
  State<RelayCourierScene> createState() => _RelayCourierSceneState();
}

class _RelayCourierSceneState extends State<RelayCourierScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return CustomPaint(
        painter: _CourierPainter(palette: widget.palette, t: null),
        size: Size.infinite,
      );
    }
    return AnimatedBuilder(
      animation: _clock,
      builder:
          (context, _) => CustomPaint(
            painter: _CourierPainter(palette: widget.palette, t: _clock.value),
            size: Size.infinite,
          ),
    );
  }
}

class _CourierPainter extends CustomPainter {
  const _CourierPainter({required this.palette, required this.t});

  final SystemPalette palette;

  /// Position in the 7s loop, or null for the still frame.
  final double? t;

  static const _designWidth = 300.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _designWidth);
    final sketch = Sketch(canvas);

    final props = SketchPen(
      color: palette.inkDim,
      width: 1,
      roughness: 1.1,
      bowing: 0.9,
      seed: 4,
    );
    final fig = SketchPen(
      color: palette.ink,
      width: 1.2,
      roughness: 1,
      bowing: 1,
      seed: 7,
    );
    final enc = SketchPen(
      color: palette.blue,
      width: 1.3,
      roughness: 0.8,
      bowing: 0.8,
      seed: 9,
    );

    sketch.line(
      const Offset(14, 80),
      const Offset(286, 80),
      props.copyWith(width: 0.8, roughness: 0.6, seed: 2),
    );

    // The camera on the left, lens toward the courier.
    sketch.line(const Offset(30, 14), const Offset(30, 27), props);
    sketch.rect(const Rect.fromLTWH(16, 27, 30, 16), props);
    sketch.circle(const Offset(22, 35), 8, props);
    sketch.circle(const Offset(22, 35), 3, props.copyWith(seed: 5));

    // The phone on the right.
    sketch.rect(const Rect.fromLTWH(250, 26, 32, 46), props);
    sketch.line(const Offset(258, 68), const Offset(274, 68), props);

    // The frame, once it has been handed over.
    final delivered = _deliveredOpacity;
    if (delivered > 0) {
      final pen = enc.copyWith(
        color: palette.blue.withValues(alpha: delivered),
      );
      sketch.rect(const Rect.fromLTWH(256, 36, 20, 18), pen);
      sketch.lock(const Offset(264, 44), 8, pen);
    }

    // The courier, mid-journey.
    final walk = _walk;
    if (walk.opacity > 0) {
      canvas.save();
      canvas.translate(walk.x, walk.bob);
      final pen = fig.copyWith(
        color: palette.ink.withValues(alpha: walk.opacity),
      );
      final head = pen.copyWith(roughness: 0.7, bowing: 0.8);
      final carry = enc.copyWith(
        color: palette.blue.withValues(alpha: walk.opacity),
      );
      sketch.circle(const Offset(0, 32), 9, head);
      sketch.line(const Offset(0, 41), const Offset(0, 60), pen);
      sketch.line(const Offset(0, 46), const Offset(13, 50), pen);
      sketch.line(const Offset(0, 46), const Offset(-8, 52), pen);
      sketch.line(const Offset(0, 60), const Offset(-7, 76), pen);
      sketch.line(const Offset(0, 60), const Offset(8, 76), pen);
      // What it carries is visibly sealed.
      sketch.rect(const Rect.fromLTWH(8, 38, 18, 18), carry);
      sketch.lock(const Offset(17, 47), 8, carry);
      canvas.restore();
    }
  }

  /// Follows the prototype's courier-x keyframes: waits, walks, waits, exits.
  ({double x, double bob, double opacity}) get _walk {
    final phase = t;
    if (phase == null) return (x: 150, bob: 0, opacity: 1);

    final bob = -3 * (0.5 - (phase * 7 / 0.55 % 1 - 0.5).abs()) * 2;
    final (x, opacity) = switch (phase) {
      < 0.05 => (40.0, phase / 0.05),
      < 0.12 => (40.0, 1.0),
      < 0.68 => (40 + (phase - 0.12) / 0.56 * 188, 1.0),
      < 0.78 => (228.0, 1.0),
      < 0.85 => (228 + (phase - 0.78) / 0.07 * 72, 1 - (phase - 0.78) / 0.07),
      _ => (40.0, 0.0),
    };
    return (x: x, bob: bob, opacity: opacity.clamp(0.0, 1.0));
  }

  /// The delivered frame fades in on arrival and clears before the next trip.
  double get _deliveredOpacity {
    final phase = t;
    if (phase == null) return 0;
    if (phase < 0.68) return 0;
    if (phase < 0.74) return (phase - 0.68) / 0.06;
    if (phase < 0.84) return 1;
    if (phase < 0.90) return 1 - (phase - 0.84) / 0.06;
    return 0;
  }

  @override
  bool shouldRepaint(_CourierPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.palette != palette;
}

/// The self-hosted story
class SelfHostedScene extends StatefulWidget {
  const SelfHostedScene({required this.palette, super.key});

  static const aspect = 300 / 100;

  final SystemPalette palette;

  @override
  State<SelfHostedScene> createState() => _SelfHostedSceneState();
}

class _SelfHostedSceneState extends State<SelfHostedScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6500),
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return CustomPaint(
        painter: _SelfHostedScenePainter(palette: widget.palette, t: null),
        size: Size.infinite,
      );
    }
    return AnimatedBuilder(
      animation: _clock,
      builder:
          (context, _) => CustomPaint(
            painter: _SelfHostedScenePainter(
              palette: widget.palette,
              t: _clock.value,
            ),
            size: Size.infinite,
          ),
    );
  }
}

class _SelfHostedScenePainter extends CustomPainter {
  const _SelfHostedScenePainter({required this.palette, required this.t});

  final SystemPalette palette;
  final double? t;

  static const _designWidth = 300.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _designWidth);
    final sketch = Sketch(canvas);

    final props = SketchPen(
      color: palette.inkDim,
      width: 1,
      roughness: 1.1,
      bowing: 0.9,
      seed: 4,
    );
    final warm = SketchPen(
      color: palette.ink,
      width: 1.3,
      roughness: 0.9,
      bowing: 0.8,
      seed: 7,
    );
    final wire = SketchPen(
      color: palette.inkDim,
      width: 0.9,
      roughness: 0.7,
      bowing: 0.6,
      seed: 6,
      dash: const [5, 7],
    );
    final enc = SketchPen(
      color: palette.blue,
      width: 1.3,
      roughness: 0.8,
      bowing: 0.8,
      seed: 9,
    );

    sketch.line(
      const Offset(14, 80),
      const Offset(286, 80),
      props.copyWith(width: 0.8, roughness: 0.6, seed: 2),
    );

    // Camera, your server, this phone.
    sketch.line(const Offset(30, 14), const Offset(30, 27), props);
    sketch.rect(const Rect.fromLTWH(16, 27, 30, 16), props);
    sketch.circle(const Offset(22, 35), 8, props);
    sketch.circle(const Offset(22, 35), 3, props.copyWith(seed: 5));

    sketch.rect(const Rect.fromLTWH(133, 38, 34, 42), warm);
    sketch.line(const Offset(133, 53), const Offset(167, 53), props);
    sketch.line(const Offset(133, 67), const Offset(167, 67), props);
    sketch.dot(const Offset(139, 45), 2, palette.blue);
    sketch.line(const Offset(145, 45), const Offset(161, 45), props);

    sketch.rect(const Rect.fromLTWH(250, 26, 32, 46), props);
    sketch.line(const Offset(258, 68), const Offset(274, 68), props);

    // The hops it travels, drawn as dashed arcs.
    sketch.cubic(
      const Offset(50, 36),
      const Offset(82, 26),
      const Offset(106, 38),
      const Offset(129, 50),
      wire,
    );
    sketch.cubic(
      const Offset(171, 50),
      const Offset(196, 36),
      const Offset(224, 30),
      const Offset(246, 40),
      wire,
    );

    final packet = _packet;
    if (packet.opacity > 0) {
      canvas.save();
      canvas.translate(packet.x, packet.y);
      final pen = enc.copyWith(
        color: palette.blue.withValues(alpha: packet.opacity),
      );
      sketch.rect(const Rect.fromLTWH(0, 0, 18, 18), pen);
      sketch.lock(const Offset(9, 9), 8, pen);
      canvas.restore();
    }
  }

  /// Follows the prototype
  ({double x, double y, double opacity}) get _packet {
    final phase = t;
    if (phase == null) return (x: 141, y: 52, opacity: 1);

    double lerp(double a, double b, double u) => a + (b - a) * u;
    return switch (phase) {
      < 0.07 => (x: 48, y: 24, opacity: phase / 0.07),
      < 0.38 => (
        x: lerp(48, 141, (phase - 0.07) / 0.31),
        y: lerp(24, 52, (phase - 0.07) / 0.31),
        opacity: 1,
      ),
      < 0.52 => (x: 141, y: 52, opacity: 1),
      < 0.84 => (
        x: lerp(141, 252, (phase - 0.52) / 0.32),
        y: lerp(52, 34, (phase - 0.52) / 0.32),
        opacity: 1,
      ),
      < 0.93 => (x: 252, y: 34, opacity: 1 - (phase - 0.84) / 0.09),
      _ => (x: 252, y: 34, opacity: 0),
    };
  }

  @override
  bool shouldRepaint(_SelfHostedScenePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.palette != palette;
}

/// Five identical figures. To the relay, you look like everyone else.
class CrowdMark extends StatelessWidget {
  const CrowdMark({required this.palette, this.roughness = 1.5, super.key});

  static const aspect = 100 / 52;

  final SystemPalette palette;

  /// Small renders need calmer strokes or the figures scribble.
  final double roughness;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _CrowdPainter(palette, roughness),
    size: Size.infinite,
  );
}

class _CrowdPainter extends CustomPainter {
  const _CrowdPainter(this.palette, this.roughness);

  final SystemPalette palette;
  final double roughness;

  @override
  void paint(Canvas canvas, Size size) {
    // The crowd is placed in boxes of varying proportions
    Sketch.fit(canvas, size, 100, 52);
    final sketch = Sketch(canvas);
    final pen = SketchPen(
      color: palette.ink,
      width: 1,
      roughness: roughness,
      bowing: roughness * 0.75,
      seed: 7,
    );

    for (final x in const [16.0, 33.0, 50.0, 67.0, 84.0]) {
      sketch.circle(Offset(x, 15), 9, pen);
      sketch.line(Offset(x, 19.5), Offset(x, 35), pen);
      sketch.line(Offset(x - 7, 25), Offset(x + 7, 25), pen);
      sketch.line(Offset(x, 35), Offset(x - 5, 45), pen);
      sketch.line(Offset(x, 35), Offset(x + 5, 45), pen);
    }
    sketch.line(
      const Offset(6, 47),
      const Offset(94, 47),
      pen.copyWith(width: 0.8, roughness: 0.5),
    );
  }

  @override
  bool shouldRepaint(_CrowdPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.roughness != roughness;
}

/// A dashed frame for a plan that is paid for but not yet on a camera.
class OpenSlotMark extends StatelessWidget {
  const OpenSlotMark({required this.palette, super.key});

  static const aspect = 36 / 30;

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _OpenSlotPainter(palette), size: Size.infinite);
}

class _OpenSlotPainter extends CustomPainter {
  const _OpenSlotPainter(this.palette);

  final SystemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 36);
    Sketch(canvas).rect(
      const Rect.fromLTWH(4, 3, 28, 24),
      SketchPen(
        color: palette.ghost,
        width: 1.1,
        roughness: 1.3,
        bowing: 1.1,
        seed: 5,
        dash: const [4, 3],
      ),
    );
  }

  @override
  bool shouldRepaint(_OpenSlotPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// Signing out as stepping out: a door frame with the door swung open.
class DoorMark extends StatelessWidget {
  const DoorMark({required this.palette, super.key});

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DoorPainter(palette), size: Size.infinite);
}

class _DoorPainter extends CustomPainter {
  const _DoorPainter(this.palette);

  final SystemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64);
    final sketch = Sketch(canvas);
    final warm = SketchPen(
      color: palette.ink,
      width: 1.2,
      roughness: 0.8,
      bowing: 0.7,
      seed: 5,
    );
    final dim = SketchPen(
      color: palette.inkDim,
      width: 1,
      roughness: 0.7,
      bowing: 0.6,
      seed: 8,
    );

    sketch.rect(const Rect.fromLTWH(28, 7, 22, 38), dim);
    // The door itself, ajar toward you.
    sketch.line(const Offset(28, 7), const Offset(14, 13), warm);
    sketch.line(const Offset(14, 13), const Offset(14, 51), warm);
    sketch.line(const Offset(14, 51), const Offset(28, 45), warm);
    sketch.circle(
      const Offset(18, 30),
      2.4,
      warm.copyWith(roughness: 0.45, bowing: 0.4),
    );
  }

  @override
  bool shouldRepaint(_DoorPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// A viewfinder with a few code modules inside: the phone-to-phone key handoff.
class ScanMark extends StatelessWidget {
  const ScanMark({required this.palette, super.key});

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ScanPainter(palette), size: Size.infinite);
}

class _ScanPainter extends CustomPainter {
  const _ScanPainter(this.palette);

  final SystemPalette palette;

  static const _modules = [
    Offset(22, 17),
    Offset(30, 14),
    Offset(38, 19),
    Offset(25, 25),
    Offset(35, 27),
    Offset(41, 33),
    Offset(21, 33),
    Offset(30, 36),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64);
    final sketch = Sketch(canvas);
    final warm = SketchPen(
      color: palette.ink,
      width: 1.2,
      roughness: 0.8,
      bowing: 0.7,
      seed: 6,
    );

    // Four corner brackets.
    sketch.line(const Offset(22, 8), const Offset(14, 8), warm);
    sketch.line(const Offset(14, 8), const Offset(14, 16), warm.reseed(1));
    sketch.line(const Offset(42, 8), const Offset(50, 8), warm.reseed(2));
    sketch.line(const Offset(50, 8), const Offset(50, 16), warm.reseed(3));
    sketch.line(const Offset(14, 36), const Offset(14, 44), warm.reseed(4));
    sketch.line(const Offset(14, 44), const Offset(22, 44), warm.reseed(5));
    sketch.line(const Offset(50, 36), const Offset(50, 44), warm.reseed(6));
    sketch.line(const Offset(50, 44), const Offset(42, 44), warm.reseed(7));

    final paint = Paint()..color = palette.inkDim;
    for (final module in _modules) {
      canvas.drawRect(module & const Size(4, 4), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// A head and shoulders, for the people a camera is shared with.
class PortraitMark extends StatelessWidget {
  const PortraitMark({
    required this.palette,
    required this.seed,
    this.isYou = false,
    super.key,
  });

  final SystemPalette palette;
  final int seed;

  /// You are drawn in the brighter ink than the people you have added.
  final bool isYou;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PortraitPainter(palette, seed, isYou),
    size: Size.infinite,
  );
}

class _PortraitPainter extends CustomPainter {
  const _PortraitPainter(this.palette, this.seed, this.isYou);

  final SystemPalette palette;
  final int seed;
  final bool isYou;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 34);
    final sketch = Sketch(canvas);
    final pen = SketchPen(
      color: isYou ? palette.ink : palette.inkDim,
      width: 1.2,
      roughness: 0.55,
      bowing: 0.5,
      seed: 5 + seed * 7,
    );
    sketch.circle(const Offset(17, 12), 13, pen);
    sketch.quadratic(
      const Offset(4, 32),
      const Offset(17, 19),
      const Offset(30, 32),
      pen,
    );
  }

  @override
  bool shouldRepaint(_PortraitPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.isYou != isYou;
}

/// What a relay account actually is
class RelayAccountScene extends StatelessWidget {
  const RelayAccountScene({required this.palette, super.key});

  static const aspect = 240 / 100;

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _RelayAccountPainter(palette), size: Size.infinite);
}

class _RelayAccountPainter extends CustomPainter {
  const _RelayAccountPainter(this.palette);

  final SystemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    Sketch.fit(canvas, size, 240, 100);
    final sketch = Sketch(canvas);

    final dim = SketchPen(
      color: palette.inkDim,
      width: 1.1,
      roughness: 0.9,
      bowing: 0.8,
      seed: 4,
    );
    final thin = dim.copyWith(width: 0.8);
    final warm = SketchPen(
      color: palette.ink,
      width: 1.3,
      roughness: 0.8,
      bowing: 0.7,
      seed: 7,
    );
    final blue = SketchPen(
      color: palette.blue,
      width: 1.4,
      roughness: 0.7,
      bowing: 0.6,
      seed: 9,
    );

    sketch.line(
      const Offset(16, 90),
      const Offset(224, 90),
      dim.copyWith(width: 0.8, roughness: 0.5, seed: 2),
    );

    // The camera, facing the gate.
    sketch.rect(const Rect.fromLTWH(15, 71, 24, 14), dim);
    sketch.rect(const Rect.fromLTWH(38, 74, 6, 7), dim);
    sketch.circle(const Offset(44, 77.5), 1.8, thin);
    sketch.line(const Offset(20, 71), const Offset(26, 67), thin);
    sketch.line(const Offset(27, 85), const Offset(27, 90), thin);

    // The gate, blinded by a slash across its eye.
    sketch.rect(const Rect.fromLTWH(96, 46, 7, 44), dim);
    sketch.rect(const Rect.fromLTWH(137, 46, 7, 44), dim);
    sketch.quadratic(
      const Offset(99, 48),
      const Offset(120, 28),
      const Offset(141, 48),
      dim,
    );
    sketch.quadratic(
      const Offset(112, 41),
      const Offset(120, 37),
      const Offset(128, 41),
      thin,
    );
    sketch.quadratic(
      const Offset(128, 41),
      const Offset(120, 45),
      const Offset(112, 41),
      thin,
    );
    sketch.circle(const Offset(120, 41), 2, thin);
    sketch.line(
      const Offset(110, 45),
      const Offset(130, 37),
      dim.copyWith(width: 1.1, roughness: 0.4, seed: 3),
    );

    // The account itself
    sketch.circle(const Offset(87, 74), 4, warm);
    sketch.line(const Offset(90, 74), const Offset(101, 74), warm);
    sketch.line(const Offset(98, 74), const Offset(98, 78), warm);
    sketch.line(const Offset(101, 74), const Offset(101, 79), warm);

    // The phone that receives encrypted vids
    sketch.rect(const Rect.fromLTWH(190, 40, 34, 50), dim);
    sketch.line(const Offset(200, 84), const Offset(214, 84), thin);

    // The encrypted packet, waiting between camera and gate.
    canvas.translate(52, 62);
    sketch.rect(const Rect.fromLTWH(-8, -8, 16, 16), blue);
    sketch.lock(const Offset(0, -1), 8, blue);
  }

  @override
  bool shouldRepaint(_RelayAccountPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// Camera to blind cloud to phone. The relay Secluso runs
class RelayChoiceMark extends StatelessWidget {
  const RelayChoiceMark({required this.palette, super.key});

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _RelayChoicePainter(palette), size: Size.infinite);
}

class _RelayChoicePainter extends CustomPainter {
  const _RelayChoicePainter(this.palette);

  final SystemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    Sketch.fit(canvas, size, 64, 48);
    final sketch = Sketch(canvas);
    final pen = SketchPen(
      color: palette.ink,
      width: 1,
      roughness: 1.4,
      bowing: 1.2,
      seed: 5,
    );
    final dash = pen.copyWith(width: 0.9);

    sketch.rect(const Rect.fromLTWH(4, 16, 14, 11), pen);
    sketch.circle(const Offset(11, 21.5), 4, pen);

    // The cloud, with a slash through it: it carries, it cannot look.
    final cloud = pen.copyWith(seed: 9);
    sketch.cubic(
      const Offset(26, 24),
      const Offset(23, 18),
      const Offset(29, 17),
      const Offset(29, 17),
      cloud,
    );
    sketch.cubic(
      const Offset(29, 17),
      const Offset(31, 13),
      const Offset(36, 15),
      const Offset(36, 15),
      cloud,
    );
    sketch.cubic(
      const Offset(36, 15),
      const Offset(41, 13),
      const Offset(41, 19),
      const Offset(41, 19),
      cloud,
    );
    sketch.cubic(
      const Offset(41, 19),
      const Offset(45, 20),
      const Offset(42, 24),
      const Offset(26, 24),
      cloud,
    );
    sketch.line(
      const Offset(28, 16),
      const Offset(40, 28),
      SketchPen(color: palette.ghost, width: 0.8, roughness: 1, seed: 3),
    );

    sketch.rect(const Rect.fromLTWH(48, 14, 12, 18), pen);
    sketch.line(
      const Offset(18, 21.5),
      const Offset(26, 21.5),
      dash.copyWith(seed: 11),
    );
    sketch.line(
      const Offset(42, 21.5),
      const Offset(48, 21.5),
      dash.copyWith(seed: 12),
    );
  }

  @override
  bool shouldRepaint(_RelayChoicePainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// A terminal prompt: the relay you run yourself.
class HostMark extends StatelessWidget {
  const HostMark({required this.palette, super.key});

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _HostPainter(palette), size: Size.infinite);
}

class _HostPainter extends CustomPainter {
  const _HostPainter(this.palette);

  final SystemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    Sketch.fit(canvas, size, 64, 48);
    final sketch = Sketch(canvas);
    final pen = SketchPen(
      color: palette.inkDim,
      width: 1,
      roughness: 1.4,
      bowing: 1.2,
      seed: 8,
    );
    sketch.rect(const Rect.fromLTWH(16, 10, 32, 26), pen);
    sketch.line(const Offset(23, 18), const Offset(28, 23), pen.reseed(1));
    sketch.line(const Offset(28, 23), const Offset(23, 28), pen.reseed(2));
    sketch.line(const Offset(31, 28), const Offset(39, 28), pen.reseed(3));
  }

  @override
  bool shouldRepaint(_HostPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// The phone you carry: a live feed playing, with signal coming in.
class RoleViewerMark extends StatelessWidget {
  const RoleViewerMark({required this.palette, super.key});

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _RoleViewerPainter(palette), size: Size.infinite);
}

class _RoleViewerPainter extends CustomPainter {
  const _RoleViewerPainter(this.palette);

  final SystemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    Sketch.fit(canvas, size, 64, 48);
    final sketch = Sketch(canvas);
    final warm = SketchPen(
      color: palette.ink,
      width: 1.3,
      roughness: 0.85,
      bowing: 0.7,
      seed: 7,
    );
    final dim = SketchPen(
      color: palette.inkDim,
      width: 1,
      roughness: 1,
      bowing: 0.8,
      seed: 4,
    );

    sketch.rect(const Rect.fromLTWH(21, 6, 22, 36), warm);
    sketch.rect(const Rect.fromLTWH(24, 10, 16, 24), dim);
    // The play triangle is the one filled shape, so it reads as the subject.
    canvas.drawPath(
      Path()
        ..moveTo(30, 17)
        ..lineTo(30, 27)
        ..lineTo(38, 22)
        ..close(),
      Paint()..color = palette.blue,
    );
    sketch.circle(const Offset(32, 38), 1.1, dim);
    sketch.quadratic(
      const Offset(46, 12),
      const Offset(50, 16),
      const Offset(46, 20),
      dim,
    );
    sketch.quadratic(
      const Offset(49, 9),
      const Offset(56, 16),
      const Offset(49, 23),
      dim.copyWith(width: 0.8, seed: 6),
    );
  }

  @override
  bool shouldRepaint(_RoleViewerPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// A spare phone stood up on a little stand, recording.
class RoleCameraMark extends StatelessWidget {
  const RoleCameraMark({required this.palette, super.key});

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _RoleCameraPainter(palette), size: Size.infinite);
}

class _RoleCameraPainter extends CustomPainter {
  const _RoleCameraPainter(this.palette);

  final SystemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    Sketch.fit(canvas, size, 64, 48);
    final sketch = Sketch(canvas);
    final warm = SketchPen(
      color: palette.ink,
      width: 1.3,
      roughness: 0.85,
      bowing: 0.7,
      seed: 7,
    );
    final dim = SketchPen(
      color: palette.inkDim,
      width: 1,
      roughness: 1,
      bowing: 0.8,
      seed: 4,
    );

    sketch.rect(const Rect.fromLTWH(22, 5, 20, 30), warm);
    sketch.circle(const Offset(32, 17), 4, dim);
    sketch.circle(const Offset(32, 17), 1.6, dim.copyWith(seed: 6));
    sketch.dot(const Offset(32, 27), 1.7, palette.danger);
    sketch.line(const Offset(28, 35), const Offset(23, 45), warm);
    sketch.line(const Offset(36, 35), const Offset(41, 45), warm.reseed(1));
    sketch.line(const Offset(21, 45), const Offset(43, 45), dim);
  }

  @override
  bool shouldRepaint(_RoleCameraPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// A dashed feed card with a play triangle, waiting for its first camera.
class EmptyFeedMark extends StatelessWidget {
  const EmptyFeedMark({required this.palette, super.key});

  static const aspect = 220 / 150;

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _EmptyFeedPainter(palette), size: Size.infinite);
}

class _EmptyFeedPainter extends CustomPainter {
  const _EmptyFeedPainter(this.palette);

  final SystemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    Sketch.fit(canvas, size, 220, 150);
    final sketch = Sketch(canvas);
    final dim = SketchPen(
      color: palette.inkDim,
      width: 1,
      roughness: 1,
      bowing: 0.8,
      seed: 4,
    );

    // The same night grammar as the System empty scene.
    for (final (at, seed) in const [
      (Offset(16, 34), 22),
      (Offset(204, 118), 24),
      (Offset(198, 16), 26),
    ]) {
      sketch.line(
        at - const Offset(3, 0),
        at + const Offset(3, 0),
        dim.copyWith(width: 0.9, seed: seed),
      );
      sketch.line(
        at - const Offset(0, 3),
        at + const Offset(0, 3),
        dim.copyWith(width: 0.9, seed: seed + 1),
      );
    }

    sketch.rect(
      const Rect.fromLTWH(30, 22, 160, 106),
      SketchPen(
        color: palette.ghost,
        width: 1.1,
        roughness: 1.1,
        bowing: 0.9,
        seed: 5,
        dash: const [6, 5],
      ),
    );
    sketch.polygon(
      const [Offset(98, 58), Offset(98, 92), Offset(126, 75)],
      SketchPen(
        color: palette.ghost,
        width: 1,
        roughness: 0.7,
        bowing: 0.5,
        seed: 6,
      ),
    );
  }

  @override
  bool shouldRepaint(_EmptyFeedPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// A whisper of the activity list that will fill this tab once a camera is on.
class GhostRowsMark extends StatelessWidget {
  const GhostRowsMark({required this.palette, super.key});

  static const aspect = 240 / 122;

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _GhostRowsPainter(palette), size: Size.infinite);
}

class _GhostRowsPainter extends CustomPainter {
  const _GhostRowsPainter(this.palette);

  final SystemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    Sketch.fit(canvas, size, 240, 122);
    final sketch = Sketch(canvas);

    // The second row is fainter, so the list reads as trailing off.
    void row(double y, double fade, int seed) {
      final ghost = palette.ghost.withValues(alpha: fade);
      sketch.rect(
        Rect.fromLTWH(2, y, 82, 46),
        SketchPen(
          color: ghost,
          width: 1,
          roughness: 0.9,
          bowing: 0.8,
          seed: seed,
          dash: const [5, 5],
        ),
      );
      final line = SketchPen(
        color: ghost,
        width: 1,
        roughness: 0.8,
        bowing: 0.7,
        seed: seed + 1,
      );
      sketch.line(Offset(100, y + 16), Offset(238, y + 16), line);
      sketch.line(
        Offset(100, y + 33),
        Offset(188, y + 33),
        line.copyWith(width: 0.8, seed: seed + 2),
      );
    }

    row(6, 1, 31);
    row(70, 0.55, 34);
  }

  @override
  bool shouldRepaint(_GhostRowsPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// A hand-drawn button frame, for the one action an empty screen offers.
class SketchButtonFrame extends StatelessWidget {
  const SketchButtonFrame({required this.palette, super.key});

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SketchButtonPainter(palette), size: Size.infinite);
}

class _SketchButtonPainter extends CustomPainter {
  const _SketchButtonPainter(this.palette);

  final SystemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    Sketch.fit(canvas, size, 236, 56);
    Sketch(canvas).rect(
      const Rect.fromLTWH(5, 5, 226, 46),
      SketchPen(
        color: palette.ink,
        width: 1.5,
        roughness: 1.3,
        bowing: 1.4,
        seed: 12,
      ),
    );
  }

  @override
  bool shouldRepaint(_SketchButtonPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
