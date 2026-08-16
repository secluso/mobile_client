//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:secluso_flutter/routes/camera-role/android_camera_hub_launcher.dart';
import 'package:secluso_flutter/routes/camera-role/theme.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';

class CameraRolePreviewPage extends StatefulWidget {
  const CameraRolePreviewPage({super.key, required this.settings});

  final AndroidCameraSettings settings;

  @override
  State<CameraRolePreviewPage> createState() => _CameraRolePreviewPageState();
}

class _CameraRolePreviewPageState extends State<CameraRolePreviewPage>
    with WidgetsBindingObserver {
  String? _error;
  MethodChannel? _previewChannel;
  bool _previewActive = false;
  int _previewGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _previewActive =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_previewActive && mounted) {
          setState(() {
            _previewActive = true;
            _previewGeneration++;
            _error = null;
          });
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_stopPreview());
        if (_previewActive && mounted) {
          setState(() => _previewActive = false);
        }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopPreview());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final label =
        '${settings.facingLabel} • ${settings.width}x${settings.height} • '
        '${settings.frameRateRange.label}';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: settings.height / settings.width,
                child:
                    Platform.isAndroid && _previewActive
                        ? AndroidView(
                          key: ValueKey<int>(_previewGeneration),
                          viewType: 'secluso_camera_preview',
                          creationParams: <String, Object>{
                            'facing': settings.facing,
                            'width': settings.width,
                            'height': settings.height,
                            'fpsMin': settings.frameRateRange.min,
                            'fpsMax': settings.frameRateRange.max,
                          },
                          creationParamsCodec: const StandardMessageCodec(),
                          onPlatformViewCreated: _onPlatformViewCreated,
                        )
                        : const SizedBox.shrink(),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Text(
                    _error ?? label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: _error == null ? Colors.white : CamRole.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: FilledButton.icon(
                onPressed: _exitPreview,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Exit Preview'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('secluso_camera_preview_$viewId');
    _previewChannel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'onError' || !mounted) return;
      setState(() {
        _error = call.arguments?.toString() ?? 'Camera preview failed.';
      });
    });
  }

  Future<void> _exitPreview() async {
    await _stopPreview();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _stopPreview() async {
    final previewChannel = _previewChannel;
    _previewChannel = null;
    try {
      await previewChannel?.invokeMethod<void>('stop');
    } on PlatformException {
      // The platform may already have disposed the native preview.
    }
  }
}
