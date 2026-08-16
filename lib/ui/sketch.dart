//! SPDX-License-Identifier: GPL-3.0-or-later
//

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pen settings for one hand-drawn shape.
@immutable
class SketchPen {
  const SketchPen({
    required this.color,
    this.width = 1.5,
    this.roughness = 1,
    this.bowing = 1,
    this.seed = 1,
    this.dash,
  });

  final Color color;
  final double width;

  /// How far strokes wander off the true path.
  final double roughness;

  /// How much a straight line bends on its way between the endpoints.
  final double bowing;

  /// Fixes the jitter, so the same pen always draws the same wobble.
  final int seed;

  /// On/off lengths for a dashed stroke,
  final List<double>? dash;

  /// Same pen, different wobble
  SketchPen reseed(int delta) => SketchPen(
    color: color,
    width: width,
    roughness: roughness,
    bowing: bowing,
    seed: seed + delta,
    dash: dash,
  );

  SketchPen copyWith({
    Color? color,
    double? width,
    double? roughness,
    double? bowing,
    int? seed,
  }) => SketchPen(
    color: color ?? this.color,
    width: width ?? this.width,
    roughness: roughness ?? this.roughness,
    bowing: bowing ?? this.bowing,
    seed: seed ?? this.seed,
    dash: dash,
  );
}

/// Draws hand-drawn shapes onto a canvas.
class Sketch {
  Sketch(this._canvas);

  final Canvas _canvas;

  /// Scales the canvas so a [designWidth] x [designHeight] drawing fits inside [size] without distortion
  static void fit(
    Canvas canvas,
    Size size,
    double designWidth,
    double designHeight,
  ) {
    final scale = math.min(
      size.width / designWidth,
      size.height / designHeight,
    );
    canvas.translate(
      (size.width - designWidth * scale) / 2,
      (size.height - designHeight * scale) / 2,
    );
    canvas.scale(scale);
  }

  /// A straight line, drawn twice.
  void line(Offset a, Offset b, SketchPen pen) {
    final rng = _Jitter(pen.seed);
    _stroke(_line(a, b, pen, rng, wander: 2), pen);
    _stroke(_line(a, b, pen, rng, wander: 1), pen);
  }

  /// Four lines, each with its own wobble.
  void rect(Rect r, SketchPen pen) {
    line(r.topLeft, r.topRight, pen);
    line(r.topRight, r.bottomRight, pen.reseed(1));
    line(r.bottomRight, r.bottomLeft, pen.reseed(2));
    line(r.bottomLeft, r.topLeft, pen.reseed(3));
  }

  void circle(Offset center, double diameter, SketchPen pen) =>
      ellipse(center, diameter, diameter, pen);

  /// A closed run of straight edges, each with its own wobble.
  void polygon(List<Offset> points, SketchPen pen) {
    for (var i = 0; i < points.length; i++) {
      line(points[i], points[(i + 1) % points.length], pen.reseed(i));
    }
  }

  /// A closed loop through jittered points around the ellipse, drawn twice.
  void ellipse(Offset center, double width, double height, SketchPen pen) {
    final rng = _Jitter(pen.seed);
    _stroke(_ellipse(center, width, height, pen, rng), pen);
    _stroke(_ellipse(center, width, height, pen, rng), pen);
  }

  /// A quadratic curve, sampled then drawn freehand.
  void quadratic(Offset start, Offset control, Offset end, SketchPen pen) {
    _curve([
      for (var i = 0; i <= _curveSamples; i++)
        _quadraticAt(start, control, end, i / _curveSamples),
    ], pen);
  }

  /// A cubic curve, sampled then drawn freehand.
  void cubic(
    Offset start,
    Offset control1,
    Offset control2,
    Offset end,
    SketchPen pen,
  ) {
    _curve([
      for (var i = 0; i <= _curveSamples; i++)
        _cubicAt(start, control1, control2, end, i / _curveSamples),
    ], pen);
  }

  /// a body with a shackle arching over it.
  void lock(Offset center, double width, SketchPen pen) {
    rect(
      Rect.fromLTWH(center.dx - width / 2, center.dy, width, width * 0.8),
      pen,
    );
    final shoulder = width * 0.32;
    final top = center.dy - width * 0.55;
    final left = Offset(center.dx - shoulder, center.dy);
    final apex = Offset(center.dx, top);
    final right = Offset(center.dx + shoulder, center.dy);
    quadratic(left, Offset(left.dx, top), apex, pen);
    quadratic(apex, Offset(right.dx, top), right, pen);
  }

  /// A solid dot. The only filled mark the illustrations use.
  void dot(Offset center, double diameter, Color color) {
    _canvas.drawCircle(
      center,
      diameter / 2,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  static const _curveSamples = 12;

  void _curve(List<Offset> points, SketchPen pen) {
    final rng = _Jitter(pen.seed);
    _stroke(_through(points, pen, rng, closed: false), pen);
    _stroke(_through(points, pen, rng, closed: false), pen);
  }

  void _stroke(Path path, SketchPen pen) {
    final dash = pen.dash;
    _canvas.drawPath(
      dash == null ? path : _dashed(path, dash),
      Paint()
        ..color = pen.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = pen.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  /// One freehand pass over a straight line.
  Path _line(
    Offset a,
    Offset b,
    SketchPen pen,
    _Jitter rng, {
    required double wander,
  }) {
    final d = b - a;
    final length = d.distance;
    final gain =
        length < 200
            ? 1.0
            : length > 500
            ? 0.4
            : -0.0016228 * length + 1.32;

    // Never wander so far that a short line loses its shape.
    var spread = 2.0;
    if (spread * spread * 100 > length * length) spread = length / 10;
    spread *= wander / 2;

    double j() => pen.roughness * gain * rng.symmetric(spread);
    double bow(double v) => pen.roughness * gain * rng.symmetric(v);

    final diverge = 0.2 + rng.next() * 0.2;
    final bowX = bow(pen.bowing * 2 * d.dy / 200);
    final bowY = bow(pen.bowing * 2 * -d.dx / 200);

    return Path()
      ..moveTo(a.dx + j(), a.dy + j())
      ..cubicTo(
        bowX + a.dx + d.dx * diverge + j(),
        bowY + a.dy + d.dy * diverge + j(),
        bowX + a.dx + d.dx * diverge * 2 + j(),
        bowY + a.dy + d.dy * diverge * 2 + j(),
        b.dx + j(),
        b.dy + j(),
      );
  }

  Path _ellipse(
    Offset center,
    double width,
    double height,
    SketchPen pen,
    _Jitter rng,
  ) {
    const steps = 18;
    final spread = pen.roughness * 0.6;
    final start = rng.next() * math.pi * 2;
    return _through(
      [
        for (var i = 0; i < steps; i++)
          () {
            final t = start + i / steps * math.pi * 2;
            return Offset(
              center.dx + math.cos(t) * width / 2 + rng.symmetric(spread),
              center.dy + math.sin(t) * height / 2 + rng.symmetric(spread),
            );
          }(),
      ],
      pen,
      rng,
      closed: true,
      jitter: false,
    );
  }

  /// A smooth Catmull-Rom curve through the points, optionally jittering each one first.
  Path _through(
    List<Offset> points,
    SketchPen pen,
    _Jitter rng, {
    required bool closed,
    bool jitter = true,
  }) {
    final spread = pen.roughness * 0.5;
    final p =
        jitter
            ? [
              for (final o in points)
                Offset(
                  o.dx + rng.symmetric(spread),
                  o.dy + rng.symmetric(spread),
                ),
            ]
            : points;

    final path = Path()..moveTo(p.first.dx, p.first.dy);
    final last = closed ? p.length : p.length - 1;
    for (var i = 0; i < last; i++) {
      Offset at(int k) =>
          closed ? p[(k + p.length) % p.length] : p[k.clamp(0, p.length - 1)];
      final p0 = at(i - 1);
      final p1 = at(i);
      final p2 = at(i + 1);
      final p3 = at(i + 2);
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    if (closed) path.close();
    return path;
  }

  /// Cuts a path into alternating on/off runs. (no flutter dash support)
  static Path _dashed(Path path, List<double> pattern) {
    final out = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var step = 0;
      while (distance < metric.length) {
        final run = pattern[step % pattern.length];
        if (step.isEven) {
          out.addPath(
            metric.extractPath(
              distance,
              math.min(distance + run, metric.length),
            ),
            Offset.zero,
          );
        }
        distance += run;
        step++;
      }
    }
    return out;
  }

  static Offset _quadraticAt(Offset a, Offset c, Offset b, double t) {
    final u = 1 - t;
    return Offset(
      u * u * a.dx + 2 * u * t * c.dx + t * t * b.dx,
      u * u * a.dy + 2 * u * t * c.dy + t * t * b.dy,
    );
  }

  static Offset _cubicAt(Offset a, Offset c1, Offset c2, Offset b, double t) {
    final u = 1 - t;
    final uu = u * u;
    final tt = t * t;
    return Offset(
      uu * u * a.dx + 3 * uu * t * c1.dx + 3 * u * tt * c2.dx + tt * t * b.dx,
      uu * u * a.dy + 3 * uu * t * c1.dy + 3 * u * tt * c2.dy + tt * t * b.dy,
    );
  }
}

/// Reproducible pseudo-random source, so a mark never re-wobbles on rebuild.
class _Jitter {
  _Jitter(int seed) : _state = seed * 9301 + 49297;

  int _state;

  double next() {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state / 0x7FFFFFFF;
  }

  /// Uniform in [-magnitude, magnitude].
  double symmetric(double magnitude) => (next() * 2 - 1) * magnitude;
}
