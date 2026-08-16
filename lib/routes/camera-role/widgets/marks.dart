//! SPDX-License-Identifier: GPL-3.0-or-later
//
// The hand-drawn marks used by the camera-role screens.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/camera-role/theme.dart';
import 'package:secluso_flutter/ui/sketch.dart';

/// A sketched square drawn around something, used to frame the pairing QR.
class SketchFrame extends StatelessWidget {
  const SketchFrame({super.key});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _FramePainter(), size: Size.infinite);
}

class _FramePainter extends CustomPainter {
  static const _design = 216.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _design);
    Sketch(canvas).rect(
      const Rect.fromLTWH(6, 6, 204, 204),
      const SketchPen(
        color: CamRole.ink,
        width: 1.6,
        roughness: 1.7,
        bowing: 1.5,
        seed: 11,
      ),
    );
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => false;
}

/// The spare phone stood up on watch, broadcasting a encrypted clip.
class CameraKeeperMark extends StatefulWidget {
  const CameraKeeperMark({required this.recording, super.key});

  final bool recording;

  @override
  State<CameraKeeperMark> createState() => _CameraKeeperMarkState();
}

class _CameraKeeperMarkState extends State<CameraKeeperMark>
    with SingleTickerProviderStateMixin {
  /// One clock for both loops.
  static const _periodSeconds = 33;

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _periodSeconds),
  );

  @override
  void initState() {
    super.initState();
    if (widget.recording) _clock.repeat();
  }

  @override
  void didUpdateWidget(CameraKeeperMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recording == oldWidget.recording) return;
    if (widget.recording) {
      _clock.repeat();
    } else {
      _clock.stop();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = !widget.recording || MediaQuery.of(context).disableAnimations;
    if (still) {
      return CustomPaint(
        painter: _CameraKeeperPainter(elapsed: null),
        size: Size.infinite,
      );
    }
    return AnimatedBuilder(
      animation: _clock,
      builder:
          (context, _) => CustomPaint(
            painter: _CameraKeeperPainter(
              elapsed: _clock.value * _periodSeconds,
            ),
            size: Size.infinite,
          ),
    );
  }
}

class _CameraKeeperPainter extends CustomPainter {
  const _CameraKeeperPainter({required this.elapsed});

  /// Seconds into the loop, or null to draw the still frame.
  final double? elapsed;

  static const _designWidth = 140.0;

  static const _warm = SketchPen(
    color: CamRole.ink,
    width: 1.5,
    roughness: 0.85,
    bowing: 0.7,
    seed: 7,
  );
  static const _dim = SketchPen(
    color: CamRole.inkDim,
    width: 1.1,
    roughness: 1,
    bowing: 0.8,
    seed: 4,
  );
  static const _blue = SketchPen(
    color: CamRole.blue,
    width: 1.3,
    roughness: 0.7,
    bowing: 0.6,
    seed: 9,
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _designWidth);
    final sketch = Sketch(canvas);

    // The phone, standing on its legs.
    sketch.rect(const Rect.fromLTWH(38, 8, 26, 40), _warm);

    // Small circles scribble unless the pen is held steady.
    final lens = _dim.copyWith(roughness: 0.45, bowing: 0.4);
    sketch.circle(const Offset(51, 25), 7.5, lens);
    sketch.circle(const Offset(51, 25), 3, lens);

    sketch.line(const Offset(46, 48), const Offset(39, 64), _warm);
    sketch.line(const Offset(56, 48), const Offset(63, 64), _warm);
    sketch.line(const Offset(36, 64), const Offset(66, 64), _dim);

    // Signal leaving the lens, each arc pulsing a beat after the one before it.
    _arc(
      sketch,
      const Offset(72, 20),
      const Offset(77, 27),
      const Offset(72, 34),
      width: 1.2,
      seed: 3,
      beat: 0,
    );
    _arc(
      sketch,
      const Offset(79, 15),
      const Offset(88, 27),
      const Offset(79, 39),
      width: 1,
      seed: 6,
      beat: 1,
    );
    _arc(
      sketch,
      const Offset(86, 10),
      const Offset(99, 27),
      const Offset(86, 44),
      width: 0.8,
      seed: 8,
      beat: 2,
    );

    // What actually leaves the phone: a small, locked frame.
    sketch.rect(const Rect.fromLTWH(104, 20, 22, 16), _warm);
    sketch.lock(const Offset(115, 28), 8, _blue);

    // The REC light, breathing.
    sketch.dot(
      const Offset(51, 40),
      2.2,
      CamRole.danger.withValues(alpha: _blink),
    );
  }

  /// Opacity of the REC light: full, dipping to .22 halfway through 2.2s.
  double get _blink {
    final t = elapsed;
    if (t == null) return 1;
    final phase = (t % 2.2) / 2.2;
    final away = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return 1 - away * 0.78;
  }

  /// Opacity of an arc: rests at .18, swells to .9 a third of the way through
  /// its 3s cycle. Each arc starts .45s after the last.
  double _arcOpacity(int beat) {
    final t = elapsed;
    if (t == null) return 0.7;
    final phase = ((t - beat * 0.45) % 3 + 3) % 3 / 3;
    final swell = phase < 0.35 ? phase / 0.35 : (1 - phase) / 0.65;
    return 0.18 + swell * 0.72;
  }

  void _arc(
    Sketch sketch,
    Offset start,
    Offset control,
    Offset end, {
    required double width,
    required int seed,
    required int beat,
  }) {
    sketch.quadratic(
      start,
      control,
      end,
      SketchPen(
        color: CamRole.inkDim.withValues(alpha: _arcOpacity(beat)),
        width: width,
        roughness: 1,
        bowing: 0.8,
        seed: seed,
      ),
    );
  }

  @override
  bool shouldRepaint(_CameraKeeperPainter oldDelegate) =>
      oldDelegate.elapsed != elapsed;
}

/// Unpairing as unplugging: a cable and plug pulled just shy of the socket.
class UnplugMark extends StatelessWidget {
  const UnplugMark({super.key});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _UnplugPainter(), size: Size.infinite);
}

class _UnplugPainter extends CustomPainter {
  static const _designWidth = 64.0;

  static const _warm = SketchPen(
    color: CamRole.ink,
    width: 1.2,
    roughness: 0.8,
    bowing: 0.7,
    seed: 5,
  );
  static const _dim = SketchPen(
    color: CamRole.inkDim,
    width: 1,
    roughness: 0.7,
    bowing: 0.6,
    seed: 8,
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _designWidth);
    final sketch = Sketch(canvas);

    // The wall socket and its slots.
    sketch.rect(const Rect.fromLTWH(46, 15, 13, 22), _dim);
    sketch.line(const Offset(50.5, 23), const Offset(50.5, 27), _dim);
    sketch.line(const Offset(54.5, 23), const Offset(54.5, 27), _dim);

    // Slack cable, plug body, and prongs stopping short of the socket.
    sketch.cubic(
      const Offset(4, 42),
      const Offset(14, 45),
      const Offset(23, 39),
      const Offset(26, 30),
      _warm,
    );
    sketch.rect(const Rect.fromLTWH(23, 19, 10, 12), _warm);
    sketch.line(const Offset(33, 23), const Offset(39, 22.5), _warm);
    sketch.line(const Offset(33, 27.5), const Offset(39, 27), _warm);
  }

  @override
  bool shouldRepaint(_UnplugPainter oldDelegate) => false;
}
