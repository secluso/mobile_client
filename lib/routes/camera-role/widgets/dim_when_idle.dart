//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Backs the "Keep the screen dark" setting.

import 'dart:async';

import 'package:flutter/material.dart';

class DimWhenIdle extends StatefulWidget {
  const DimWhenIdle({
    required this.enabled,
    required this.child,
    this.after = const Duration(seconds: 20),
    super.key,
  });

  final bool enabled;
  final Widget child;

  /// How long the screen stays lit after the last touch.
  final Duration after;

  @override
  State<DimWhenIdle> createState() => _DimWhenIdleState();
}

class _DimWhenIdleState extends State<DimWhenIdle> {
  Timer? _timer;
  bool _dim = false;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(DimWhenIdle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if (!widget.enabled) {
      if (_dim) setState(() => _dim = false);
      return;
    }
    _timer = Timer(widget.after, () {
      if (mounted) setState(() => _dim = true);
    });
  }

  /// Any touch lights the screen again and restarts the countdown.
  void _wake(PointerDownEvent _) {
    if (_dim) setState(() => _dim = false);
    _restart();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _wake,
      child: AnimatedOpacity(
        opacity: _dim ? 0 : 1,
        duration: Duration(milliseconds: _dim ? 1200 : 180),
        curve: Curves.easeOut,
        // While dark, the first touch only wakes the screen. It must not also
        // press whatever happens to be under the finger.
        child: AbsorbPointer(absorbing: _dim, child: widget.child),
      ),
    );
  }
}
