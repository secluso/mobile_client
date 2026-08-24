part of 'shell_home_page.dart';

class _NoCameraCard extends StatelessWidget {
  const _NoCameraCard({required this.metrics, required this.onAdd});

  final _ShellHomeMetrics metrics;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RelayReadyBanner(metrics: metrics),
        SizedBox(height: metrics.scaled(16)),
        if (dark)
          _ScanningForCamerasCard(metrics: metrics, onAdd: onAdd)
        else
          _LightScanningState(metrics: metrics, onAdd: onAdd),
        SizedBox(height: metrics.scaled(10)),
        // The tabs stay hidden until the first camera is paired
        Center(
          child: TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder:
                      (_) => Scaffold(
                        appBar: AppBar(title: const Text('Relay & account')),
                        body: const ServerPage(
                          showBackButton: false,
                          showShellChrome: true,
                        ),
                      ),
                ),
              );
            },
            child: Text(
              'Relay & account settings',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color:
                    dark
                        ? Colors.white.withValues(alpha: 0.45)
                        : const Color(0xFF6B7280),
                fontSize: metrics.scaled(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RelayReadyBanner extends StatelessWidget {
  const _RelayReadyBanner({required this.metrics});

  final _ShellHomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: metrics.scaled(63.5),
      decoration: BoxDecoration(
        color: const Color(0x1410B981),
        borderRadius: BorderRadius.circular(metrics.scaled(12)),
        border: Border.all(color: const Color(0x3310B981)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: metrics.scaled(16)),
        child: Row(
          children: [
            Container(
              width: metrics.scaled(28),
              height: metrics.scaled(28),
              decoration: BoxDecoration(
                color: const Color(0x3310B981),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(
                Icons.check_rounded,
                size: metrics.scaled(14),
                color: const Color(0xFF34D399),
              ),
            ),
            SizedBox(width: metrics.scaled(12)),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Relay connected',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF34D399),
                      fontSize: metrics.scaled(12),
                      fontWeight: FontWeight.w600,
                      height: 18 / 12,
                    ),
                  ),
                  SizedBox(height: metrics.scaled(2)),
                  Text(
                    'Your account is ready. Next: add a camera.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.4)
                              : const Color(0xFF6B7280),
                      fontSize: metrics.scaled(9),
                      height: 13.5 / 9,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanningForCamerasCard extends StatelessWidget {
  const _ScanningForCamerasCard({required this.metrics, required this.onAdd});

  final _ShellHomeMetrics metrics;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRoundedRectPainter(
        color: const Color(0x4D8BB3EE),
        strokeWidth: metrics.scaled(2),
        radius: metrics.scaled(16),
        dashLength: metrics.scaled(6),
        gapLength: metrics.scaled(4),
      ),
      child: Container(
        height: metrics.scaled(298),
        decoration: BoxDecoration(
          color: const Color(0x08000000),
          borderRadius: BorderRadius.circular(metrics.scaled(16)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(metrics.scaled(16)),
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.28),
                    radius: 0.52,
                    colors: [
                      Colors.white.withValues(alpha: 0.06),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: metrics.scaled(24),
              child: _ScanningBeaconGraphic(metrics: metrics),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: metrics.scaled(167),
              child: Text(
                'No cameras yet',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: metrics.scaled(11),
                  fontWeight: FontWeight.w500,
                  height: 16.5 / 11,
                ),
              ),
            ),
            Positioned(
              left: metrics.scaled(20),
              right: metrics.scaled(20),
              top: metrics.scaled(187),
              child: Text(
                'Set up your spare phone as a camera, then scan its code here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: metrics.scaled(10),
                  height: 15 / 10,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: metrics.scaled(232),
              child: Center(
                child: Material(
                  color: const Color(0xFF8BB3EE),
                  borderRadius: BorderRadius.circular(metrics.scaled(12)),
                  child: InkWell(
                    onTap: onAdd,
                    borderRadius: BorderRadius.circular(metrics.scaled(12)),
                    child: Container(
                      width: metrics.scaled(127.98),
                      height: metrics.scaled(36.5),
                      alignment: Alignment.center,
                      child: Text(
                        'ADD CAMERA',
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                          fontSize: metrics.scaled(11),
                          fontWeight: FontWeight.w600,
                          letterSpacing: metrics.scaled(0.55),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LightScanningState extends StatelessWidget {
  const _LightScanningState({required this.metrics, required this.onAdd});

  final _ShellHomeMetrics metrics;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: metrics.scaled(298),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: CustomPaint(
              painter: _DashedRoundedRectPainter(
                color: const Color(0xFFFDE68A),
                strokeWidth: metrics.scaled(2),
                radius: metrics.scaled(16),
                dashLength: metrics.scaled(6),
                gapLength: metrics.scaled(4),
              ),
              child: Container(
                height: metrics.scaled(298),
                decoration: BoxDecoration(
                  color: const Color(0x80FFFBEB),
                  borderRadius: BorderRadius.circular(metrics.scaled(16)),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            metrics.scaled(16),
                          ),
                          gradient: RadialGradient(
                            center: const Alignment(0, -0.18),
                            radius: 0.58,
                            colors: [
                              Colors.black.withValues(alpha: 0.04),
                              Colors.black.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: metrics.scaled(24),
                      child: _ScanningBeaconGraphic(metrics: metrics),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: metrics.scaled(167),
                      child: Text(
                        'No cameras yet',
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF374151),
                          fontSize: metrics.scaled(11),
                          fontWeight: FontWeight.w500,
                          height: 16.5 / 11,
                        ),
                      ),
                    ),
                    Positioned(
                      left: metrics.scaled(20),
                      right: metrics.scaled(20),
                      top: metrics.scaled(187),
                      child: Text(
                        'Set up your spare phone as a camera, then scan its code here.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6B7280),
                          fontSize: metrics.scaled(10),
                          height: 15 / 10,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: metrics.scaled(232),
                      child: Center(
                        child: Material(
                          color: const Color(0xFF8BB3EE),
                          borderRadius: BorderRadius.circular(
                            metrics.scaled(12),
                          ),
                          elevation: 0,
                          shadowColor: const Color(0x4DB45309),
                          child: InkWell(
                            onTap: onAdd,
                            borderRadius: BorderRadius.circular(
                              metrics.scaled(12),
                            ),
                            child: Container(
                              width: metrics.scaled(127.98),
                              height: metrics.scaled(36.5),
                              alignment: Alignment.center,
                              child: Text(
                                'ADD CAMERA',
                                style: Theme.of(
                                  context,
                                ).textTheme.labelMedium?.copyWith(
                                  color: Colors.white,
                                  fontSize: metrics.scaled(11),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: metrics.scaled(0.55),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanningBeaconGraphic extends StatefulWidget {
  const _ScanningBeaconGraphic({required this.metrics});

  final _ShellHomeMetrics metrics;

  @override
  State<_ScanningBeaconGraphic> createState() => _ScanningBeaconGraphicState();
}

class _ScanningBeaconGraphicState extends State<_ScanningBeaconGraphic>
    with TickerProviderStateMixin {
  late final AnimationController _sweepController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _sweepController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.metrics;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: metrics.scaled(112),
      child: AnimatedBuilder(
        animation: Listenable.merge([_sweepController, _pulseController]),
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final size in [128.0, 96.0, 64.0, 32.0])
                Container(
                  width: metrics.scaled(size),
                  height: metrics.scaled(size),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          dark
                              ? Colors.white.withValues(
                                alpha:
                                    size == 32
                                        ? 0.18
                                        : (0.06 + ((128 - size) / 400)),
                              )
                              : const Color(0xFFE5E7EB),
                    ),
                  ),
                ),
              for (final delay in [0.0, 0.35, 0.7])
                _RadarPulseRing(
                  progress: (_pulseController.value + delay) % 1,
                  metrics: metrics,
                ),
              CustomPaint(
                size: Size.square(metrics.scaled(128)),
                painter: _RadarSweepPainter(
                  progress: _sweepController.value,
                  lineLength: metrics.scaled(64),
                  lineThickness: metrics.scaled(4),
                  dark: dark,
                ),
              ),
              Container(
                width: metrics.scaled(32),
                height: metrics.scaled(32),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        dark
                            ? const Color(0x668BB3EE)
                            : const Color(0x668BB3EE),
                    width: metrics.scaled(2),
                  ),
                ),
              ),
              Container(
                width: metrics.scaled(12),
                height: metrics.scaled(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF8BB3EE),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          dark
                              ? const Color(0x99B45309)
                              : const Color(0x99B45309),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RadarPulseRing extends StatelessWidget {
  const _RadarPulseRing({required this.progress, required this.metrics});

  final double progress;
  final _ShellHomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final eased = Curves.easeOut.transform(progress);
    final diameter = metrics.scaled(32 + (80 * eased));
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opacity = (0.32 * (1 - progress)).clamp(0.0, 0.32);
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: (dark ? const Color(0xFFB45309) : const Color(0xFF8BB3EE))
              .withValues(alpha: opacity),
          width: metrics.scaled(2),
        ),
      ),
    );
  }
}

class _RadarSweepPainter extends CustomPainter {
  const _RadarSweepPainter({
    required this.progress,
    required this.lineLength,
    required this.lineThickness,
    required this.dark,
  });

  final double progress;
  final double lineLength;
  final double lineThickness;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final angle = progress * math.pi * 2;
    final end = Offset(
      center.dx + math.cos(angle) * lineLength,
      center.dy + math.sin(angle) * lineLength,
    );

    final linePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lineThickness
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors:
                dark
                    ? const [Color(0xCCB45309), Color(0x00B45309)]
                    : const [Color(0x99E5CBA6), Color(0x00E5CBA6)],
          ).createShader(Rect.fromPoints(center, end));
    canvas.drawLine(center, end, linePaint);
  }

  @override
  bool shouldRepaint(covariant _RadarSweepPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.lineLength != lineLength ||
        oldDelegate.lineThickness != lineThickness ||
        oldDelegate.dark != dark;
  }
}

class _DashedRoundedRectPainter extends CustomPainter {
  const _DashedRoundedRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dashLength,
    required this.gapLength,
  });

  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
        );
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashLength;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.gapLength != gapLength;
  }
}
