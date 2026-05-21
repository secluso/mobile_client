//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:io' show Platform, Directory;

import 'dart:async';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/app_coordination_state.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/proprietary_camera_hotspot.dart';
import 'proprietary_camera_waiting.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:secluso_flutter/utilities/app_paths.dart';

/// Popup: User connects to camera's Wi-Fi hotspot.
class ProprietaryCameraConnectDialog extends StatefulWidget {
  const ProprietaryCameraConnectDialog({
    super.key,
    required this.hotspotPassword,
  });

  static bool pairingCompleted = false;
  static bool pairingInProgress = false;
  static int _sessionCounter = 0;
  static int currentSessionId = 0;
  static int? boundSessionId;
  final String hotspotPassword;

  @override
  State<ProprietaryCameraConnectDialog> createState() =>
      _ProprietaryCameraConnectDialogState();

  /// Call this to start the two-step popup flow.
  /// 1) Shows ProprietaryCameraConnectDialog.
  /// 2) If user clicks "Next", replaces it with ProprietaryCameraInfoDialo].
  /// Returns a map of final camera info if completed, or null if canceled.
  static Future<Map<String, Object>?> showProprietaryCameraSetupFlow(
    BuildContext context, {
    required Uint8List initialQrCode,
    required String hotspotPassword,
  }) async {
    pairingCompleted = false;
    pairingInProgress = true;
    currentSessionId = ++_sessionCounter;
    final dialogContext = Navigator.of(context, rootNavigator: true).context;

    try {
      final connectResult = await _showSetupDialog<bool>(
        context: dialogContext,
        builder:
            (ctx) => ProprietaryCameraConnectDialog(
              hotspotPassword: hotspotPassword,
            ),
      );

      if (connectResult == null || connectResult == false) {
        return null;
      }

      final infoResult = await _showSetupDialog<Map<String, Object>>(
        context: dialogContext,
        builder:
            (ctx) => ProprietaryCameraInfoDialog(
              initialQrCode: initialQrCode,
              hotspotPassword: hotspotPassword,
            ),
      );

      ProprietaryCameraConnectDialog.pairingCompleted = true;
      ProprietaryCameraConnectDialog.boundSessionId = null;
      ProprietaryCameraConnectDialog.pairingInProgress = false;

      // Returns null if user canceled or final data if user tapped "Add Camera"
      return infoResult;
    } finally {
      // Reset regardless of outcome
      pairingInProgress = false;
    }
  }

  static Future<T?> _showSetupDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: false,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Builder(builder: builder);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return child;
      },
    );
  }
}

class _ProprietaryCameraConnectDialogState
    extends State<ProprietaryCameraConnectDialog>
    with SingleTickerProviderStateMixin {
  bool _isConnected = false;
  bool _connectivityError = false;
  bool _isConnecting = true;
  bool _exitingToNext = false;

  late final int localSessionId;
  late final AnimationController _spinnerController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  final platform = MethodChannel("secluso.com/wifi");

  @override
  void initState() {
    super.initState();
    localSessionId = ProprietaryCameraConnectDialog.currentSessionId;
    if (ProprietaryCameraConnectDialog.pairingInProgress) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _connectToCamera(widget.hotspotPassword);
      });
    }
  }

  @override
  void dispose() {
    _spinnerController.dispose();
    super.dispose();
  }

  Future<bool> _verifyCameraHotspotReadiness() async {
    try {
      final connected = await ProprietaryCameraHotspot.waitUntilReady(
        cameraIp: Constants.proprietaryCameraIp,
        timeout: const Duration(seconds: 30),
        reconnectIfNeeded: Platform.isIOS,
        password: widget.hotspotPassword,
      );
      if (!mounted) return false;

      if (!connected) {
        Log.w("Camera hotspot never became reachable after connect");
        setState(() {
          _connectivityError = true;
          _isConnected = false;
          _isConnecting = false;
        });
        return false;
      } else {
        Log.d("Camera hotspot connectivity confirmed");
        return true;
      }
    } catch (e) {
      Log.e(e);
      if (!mounted) return false;
      setState(() {
        _connectivityError = true;
        _isConnected = false;
        _isConnecting = false;
      });
      return false;
    }
  }

  Future<void> _connectToCamera(String wifiPassword) async {
    Log.d("Entered method");
    setState(() {
      _connectivityError = false;
      _isConnecting = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!await _ensureWifiPairingPermissions()) {
      if (!mounted) return;
      setState(() {
        _connectivityError = true;
        _isConnecting = false;
      });
      return;
    }
    try {
      final result = await ProprietaryCameraHotspot.connect(wifiPassword);
      Log.d("First result from Wifi Connect Attempt: $result");

      if (result == "connected" &&
          !ProprietaryCameraConnectDialog.pairingInProgress) {
        try {
          const platform = MethodChannel("secluso.com/wifi");
          await platform.invokeMethod<String>(
            'disconnectFromWifi',
            <String, dynamic>{'ssid': "Secluso"},
          );
        } catch (e) {
          Log.w("WiFi disconnect failed from InfoDialog: $e");
        }

        return;
      }

      if (result == "connected") {
        if (localSessionId == ProprietaryCameraConnectDialog.currentSessionId) {
          ProprietaryCameraConnectDialog.boundSessionId = localSessionId;
          if (!mounted) return;
          setState(() {
            _connectivityError = false;
            _isConnected = true;
            _isConnecting = false;
          });
          final hotspotReady = await _verifyCameraHotspotReadiness();
          if (!mounted || !hotspotReady) return;
          if (ProprietaryCameraConnectDialog.pairingInProgress) {
            Future<void>.delayed(const Duration(milliseconds: 280), () {
              if (!mounted || !_isConnected) return;
              _onNext();
            });
          }
        } else {
          if (!mounted) return;
          if (!_isConnected) {
            setState(() {
              _connectivityError = true;
              _isConnecting = false;
            });
          }
        }
      } else {
        if (!mounted) return;
        if (!_isConnected) {
          setState(() {
            _connectivityError = true;
            _isConnecting = false;
          });
        }
      }
    } on PlatformException catch (e) {
      Log.e("Platform exception - $e");
      if (!_isConnected) {
        setState(() {
          _connectivityError = true;
          _isConnecting = false;
        });
      }
    }
  }

  Future<bool> _ensureWifiPairingPermissions() async {
    if (!Platform.isAndroid) {
      return true;
    }

    final nearbyStatus = await Permission.nearbyWifiDevices.request();
    if (nearbyStatus.isGranted) {
      return true;
    }

    final locationStatus = await Permission.location.request();
    if (locationStatus.isGranted) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    final needsSettings =
        nearbyStatus.isPermanentlyDenied || locationStatus.isPermanentlyDenied;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          needsSettings
              ? 'Allow Nearby Wi-Fi Devices or Location in Settings to pair with the camera.'
              : 'Allow Nearby Wi-Fi Devices or Location to pair with the camera.',
        ),
      ),
    );
    return false;
  }

  Future<void> _maybeDisconnect() async {
    Log.d("Possibly disconnecting");

    if (_isConnected &&
        ProprietaryCameraConnectDialog.boundSessionId == localSessionId &&
        !ProprietaryCameraConnectDialog.pairingCompleted &&
        !_exitingToNext) {
      Log.d("Disconnecting from WiFi (owned by session $localSessionId)");
      try {
        await platform.invokeMethod<String>(
          'disconnectFromWifi',
          <String, dynamic>{'ssid': "Secluso"},
        );
      } catch (e) {
        Log.w("WiFi disconnect failed: $e");
      } finally {
        ProprietaryCameraConnectDialog.boundSessionId = null;
      }
    }
  }

  Future<void> _onNext() async {
    _exitingToNext = true;
    Navigator.of(context).pop(true);
  }

  void _onCancel() async {
    await _maybeDisconnect();
    ProprietaryCameraConnectDialog.pairingInProgress = false;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          _maybeDisconnect();
        }
      },
      child: _ProprietaryCameraConnectPage(
        dark: dark,
        isConnected: _isConnected,
        isConnecting: _isConnecting,
        connectivityError: _connectivityError,
        spinnerRotation: _spinnerController,
        onBack: _onCancel,
        onRetry: () => _connectToCamera(widget.hotspotPassword),
      ),
    );
  }
}

class _ProprietaryCameraConnectPage extends StatelessWidget {
  const _ProprietaryCameraConnectPage({
    required this.dark,
    required this.isConnected,
    required this.isConnecting,
    required this.connectivityError,
    required this.spinnerRotation,
    required this.onBack,
    required this.onRetry,
  });

  final bool dark;
  final bool isConnected;
  final bool isConnecting;
  final bool connectivityError;
  final Animation<double> spinnerRotation;
  final VoidCallback onBack;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7);
    final titleColor = dark ? Colors.white : const Color(0xFF111827);
    final subtitleColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final bodyColor =
        dark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF6B7280);
    final accentTextColor =
        dark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF374151);
    final footerColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFD1D5DB);
    final scanningColor =
        connectivityError ? const Color(0xFFDC2626) : const Color(0xFF8BB3EE);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = constraints.maxWidth / 290;
              double scaled(double value) => value * scale;
              final title =
                  connectivityError
                      ? 'Unable to Reach Camera'
                      : 'Connecting to Camera WiFi';
              final scanningLabel =
                  connectivityError
                      ? 'CONNECTION FAILED'
                      : isConnected
                      ? 'CONNECTED'
                      : 'SCANNING';
              final statusLineText =
                  connectivityError
                      ? 'Camera not reachable.'
                      : isConnected
                      ? 'Searching for camera...'
                      : 'Searching for camera...';

              return Padding(
                padding: EdgeInsets.fromLTRB(
                  scaled(20),
                  scaled(12),
                  scaled(20),
                  scaled(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: scaled(40),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ConnectBackButton(
                            size: scaled(32),
                            iconSize: scaled(16),
                            fillColor:
                                dark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : const Color(0xFFE5E7EB),
                            iconColor:
                                dark ? Colors.white : const Color(0xFF6B7280),
                            onTap: onBack,
                          ),
                          SizedBox(width: scaled(12)),
                          Padding(
                            padding: EdgeInsets.only(top: scaled(1)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Connect to Camera',
                                  style: GoogleFonts.inter(
                                    color: titleColor,
                                    fontSize: scaled(15),
                                    fontWeight: FontWeight.w600,
                                    height: 22.5 / 15,
                                  ),
                                ),
                                SizedBox(height: scaled(1.5)),
                                Text(
                                  'STEP 1 OF 3',
                                  style: GoogleFonts.inter(
                                    color: subtitleColor,
                                    fontSize: scaled(9),
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: scaled(0.9),
                                    height: 13.5 / 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: dark ? scaled(24) : scaled(42)),
                    Center(
                      child: _ProprietaryConnectRadarGraphic(
                        scale: scale,
                        dark: dark,
                      ),
                    ),
                    SizedBox(height: dark ? scaled(20) : scaled(30)),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: spinnerRotation,
                            builder:
                                (context, _) => Opacity(
                                  opacity:
                                      0.65 +
                                      (0.35 *
                                          math
                                              .sin(
                                                spinnerRotation.value *
                                                    math.pi *
                                                    2,
                                              )
                                              .abs()),
                                  child: Container(
                                    width: scaled(6),
                                    height: scaled(6),
                                    decoration: BoxDecoration(
                                      color: scanningColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                          ),
                          SizedBox(width: scaled(8)),
                          Text(
                            scanningLabel,
                            style: GoogleFonts.inter(
                              color: scanningColor.withValues(
                                alpha: dark ? 0.7 : 0.6,
                              ),
                              fontSize: scaled(9),
                              fontWeight: FontWeight.w600,
                              letterSpacing: scaled(1.8),
                              height: 13.5 / 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: dark ? scaled(16) : scaled(21)),
                    Center(
                      child: SizedBox(
                        width: scaled(230),
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: titleColor,
                            fontSize: scaled(17),
                            fontWeight: FontWeight.w600,
                            height: 25.5 / 17,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: scaled(8)),
                    Center(
                      child: SizedBox(
                        width: scaled(230),
                        child:
                            connectivityError
                                ? Text(
                                  'A direct connection could not be created. Stay near the camera and try again.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    color: bodyColor,
                                    fontSize: scaled(11),
                                    fontWeight: FontWeight.w400,
                                    height: 17.88 / 11,
                                  ),
                                )
                                : Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text:
                                            'A WiFi prompt will appear shortly. Tap ',
                                        style: GoogleFonts.inter(
                                          color: bodyColor,
                                          fontSize: scaled(11),
                                          fontWeight: FontWeight.w400,
                                          height: 17.88 / 11,
                                        ),
                                      ),
                                      TextSpan(
                                        text: '"Join"',
                                        style: GoogleFonts.inter(
                                          color: accentTextColor,
                                          fontSize: scaled(11),
                                          fontWeight: FontWeight.w600,
                                          height: 17.88 / 11,
                                        ),
                                      ),
                                      TextSpan(
                                        text:
                                            ' to create a direct link with your camera.',
                                        style: GoogleFonts.inter(
                                          color: bodyColor,
                                          fontSize: scaled(11),
                                          fontWeight: FontWeight.w400,
                                          height: 17.88 / 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                      ),
                    ),
                    SizedBox(height: dark ? scaled(22) : scaled(32)),
                    Center(
                      child: SizedBox(
                        width: scaled(156),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!connectivityError)
                              _ConnectSpinner(
                                size: scaled(14),
                                color: scanningColor,
                                rotation: spinnerRotation,
                              )
                            else
                              Icon(
                                Icons.refresh_rounded,
                                size: scaled(14),
                                color: const Color(0xFFDC2626),
                              ),
                            SizedBox(width: scaled(10)),
                            Text(
                              statusLineText,
                              style: GoogleFonts.inter(
                                color: bodyColor,
                                fontSize: scaled(10),
                                fontWeight: FontWeight.w500,
                                height: 15 / 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (connectivityError) ...[
                      SizedBox(height: scaled(10)),
                      Center(
                        child: TextButton(
                          onPressed: onRetry,
                          style: TextButton.styleFrom(
                            foregroundColor:
                                dark
                                    ? Colors.white.withValues(alpha: 0.72)
                                    : const Color(0xFF374151),
                            padding: EdgeInsets.symmetric(
                              horizontal: scaled(12),
                              vertical: scaled(6),
                            ),
                            textStyle: GoogleFonts.inter(
                              fontSize: scaled(10),
                              fontWeight: FontWeight.w600,
                              height: 15 / 10,
                            ),
                          ),
                          child: const Text('Try again'),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ConnectFooterLockIcon(
                            size: scaled(10),
                            color: footerColor,
                          ),
                          SizedBox(width: scaled(8)),
                          Text(
                            'Direct encrypted connection',
                            style: GoogleFonts.inter(
                              color: footerColor,
                              fontSize: scaled(9),
                              fontWeight: FontWeight.w400,
                              letterSpacing: scaled(0.225),
                              height: 13.5 / 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: scaled(6)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ConnectBackButton extends StatelessWidget {
  const _ConnectBackButton({
    required this.size,
    required this.iconSize,
    required this.fillColor,
    required this.iconColor,
    required this.onTap,
  });

  final double size;
  final double iconSize;
  final Color fillColor;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fillColor,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: SizedBox(
              width: iconSize,
              height: iconSize,
              child: CustomPaint(painter: _ConnectBackIconPainter(iconColor)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectSpinner extends StatelessWidget {
  const _ConnectSpinner({
    required this.size,
    required this.color,
    required this.rotation,
  });

  final double size;
  final Color color;
  final Animation<double> rotation;

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: rotation,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _ConnectSpinnerPainter(color)),
      ),
    );
  }
}

class _ProprietaryConnectRadarGraphic extends StatefulWidget {
  const _ProprietaryConnectRadarGraphic({
    required this.scale,
    required this.dark,
  });

  final double scale;
  final bool dark;

  @override
  State<_ProprietaryConnectRadarGraphic> createState() =>
      _ProprietaryConnectRadarGraphicState();
}

class _ProprietaryConnectRadarGraphicState
    extends State<_ProprietaryConnectRadarGraphic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beamController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _beamController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final scale = widget.scale;
    double scaled(double value) => value * scale;
    final centerFill = dark ? const Color(0xFF0A0A0A) : Colors.white;
    final centerBorder =
        dark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE5E7EB);
    final centerGlyph =
        dark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF6B7280);
    final badgeColor = const Color(0xFF8BB3EE);
    final badgeFill = dark ? const Color(0x338BB3EE) : const Color(0x26D97706);
    final badgeBorder =
        dark ? const Color(0x668BB3EE) : const Color(0x4DD97706);
    final orbitBorder = const Color(0x338BB3EE);

    return AnimatedBuilder(
      animation: _beamController,
      builder:
          (context, _) => SizedBox(
            width: scaled(192),
            height: scaled(192),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.02)
                              : const Color(0x99FFFBEB),
                      shape: BoxShape.circle,
                    ),
                    child: CustomPaint(
                      painter: _ConnectRadarPainter(dark: dark),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: ClipOval(
                    child: Transform.rotate(
                      angle: _beamController.value * math.pi * 2,
                      alignment: Alignment.center,
                      child: Stack(
                        children: [
                          Positioned(
                            left: scaled(96),
                            top: 0,
                            width: scaled(96),
                            height: scaled(96),
                            child: CustomPaint(
                              painter: _ConnectRadarSectorPainter(dark: dark),
                            ),
                          ),
                          Positioned(
                            left: scaled(95.5),
                            top: 0,
                            width: scaled(1),
                            height: scaled(96),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    dark
                                        ? const Color(0x99B45309)
                                        : const Color(0x4DB45309),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (final position in const [
                  Offset(0.20, 0.35),
                  Offset(0.75, 0.60),
                  Offset(0.30, 0.72),
                  Offset(0.65, 0.25),
                  Offset(0.15, 0.50),
                  Offset(0.55, 0.80),
                ])
                  Positioned(
                    left: scaled(192 * position.dx),
                    top: scaled(192 * position.dy),
                    child: Container(
                      width: scaled(3),
                      height: scaled(3),
                      decoration: BoxDecoration(
                        color:
                            dark
                                ? Colors.white.withValues(alpha: 0.12)
                                : const Color(0x268BB3EE),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                Positioned(
                  left: scaled(76),
                  top: scaled(76),
                  child: Container(
                    width: scaled(40),
                    height: scaled(40),
                    decoration: BoxDecoration(
                      color: centerFill,
                      shape: BoxShape.circle,
                      border: Border.all(color: centerBorder),
                      boxShadow:
                          dark
                              ? null
                              : const [
                                BoxShadow(
                                  color: Color(0x0D000000),
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                ),
                              ],
                    ),
                    child: Center(
                      child: SizedBox(
                        width: scaled(15),
                        height: scaled(15),
                        child: CustomPaint(
                          painter: _ConnectPhoneGlyphPainter(centerGlyph),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: scaled(121.45),
                  top: scaled(34.23),
                  width: scaled(44),
                  height: scaled(44),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: orbitBorder),
                    ),
                  ),
                ),
                Positioned(
                  left: scaled(129.45),
                  top: scaled(42.23),
                  child: Container(
                    width: scaled(28),
                    height: scaled(28),
                    decoration: BoxDecoration(
                      color: badgeFill,
                      shape: BoxShape.circle,
                      border: Border.all(color: badgeBorder),
                      boxShadow: [
                        BoxShadow(
                          color:
                              dark
                                  ? const Color(0x4DB45309)
                                  : const Color(0x26B45309),
                          blurRadius: scaled(12),
                        ),
                      ],
                    ),
                    child: Center(
                      child: SizedBox(
                        width: scaled(11),
                        height: scaled(11),
                        child: CustomPaint(
                          painter: _ConnectCameraGlyphPainter(badgeColor),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            dark
                                ? Colors.white.withValues(alpha: 0.06)
                                : const Color(0x1A8BB3EE),
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

class _ConnectFooterLockIcon extends StatelessWidget {
  const _ConnectFooterLockIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ConnectFooterLockPainter(color)),
    );
  }
}

class _ConnectBackIconPainter extends CustomPainter {
  const _ConnectBackIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.5 / 16)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (10 / 16), size.height * (3 / 16))
          ..lineTo(size.width * (5 / 16), size.height * (8 / 16))
          ..lineTo(size.width * (10 / 16), size.height * (13 / 16));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _ConnectBackIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ConnectSpinnerPainter extends CustomPainter {
  const _ConnectSpinnerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (2 / 14)
          ..strokeCap = StrokeCap.round
          ..color = color;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawArc(
      rect.deflate(size.width * 0.1),
      -math.pi * 1.1,
      math.pi * 1.4,
      false,
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _ConnectSpinnerPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ConnectRadarPainter extends CustomPainter {
  const _ConnectRadarPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final ringColors =
        dark
            ? [
              Colors.white.withValues(alpha: 0.05),
              Colors.white.withValues(alpha: 0.07),
              Colors.white.withValues(alpha: 0.09),
            ]
            : const [Color(0x14B45309), Color(0x1AB45309), Color(0x1FB45309)];
    final crosshairColor =
        dark ? Colors.white.withValues(alpha: 0.03) : const Color(0x0DB45309);
    final border =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color =
              dark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0x1A8BB3EE);
    canvas.drawLine(
      Offset(center.dx, 16),
      Offset(center.dx, size.height - 16),
      Paint()
        ..color = crosshairColor
        ..strokeWidth = 0.5,
    );
    canvas.drawLine(
      Offset(16, center.dy),
      Offset(size.width - 16, center.dy),
      Paint()
        ..color = crosshairColor
        ..strokeWidth = 0.5,
    );

    for (final entry in [
      (size.width * (80 / 192), ringColors[0], 4.0, 4.0),
      (size.width * (56 / 192), ringColors[1], 3.0, 5.0),
      (size.width * (32 / 192), ringColors[2], 2.0, 4.0),
    ]) {
      _drawDashedCircle(canvas, center, entry.$1, entry.$2, entry.$3, entry.$4);
    }
    canvas.drawCircle(center, size.width / 2, border);
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double dashLength,
    double gapLength,
  ) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color
          ..strokeCap = StrokeCap.butt
          ..isAntiAlias = true;
    final circumference = 2 * math.pi * radius;
    final unitSweep = (dashLength + gapLength) / circumference * 2 * math.pi;
    final dashSweep = dashLength / circumference * 2 * math.pi;
    for (double angle = 0; angle < math.pi * 2; angle += unitSweep) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        dashSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectRadarPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class _ConnectRadarSectorPainter extends CustomPainter {
  const _ConnectRadarSectorPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(0, size.height);
    final radius = size.width;
    final path =
        Path()
          ..moveTo(origin.dx, origin.dy)
          ..arcTo(
            Rect.fromCircle(center: origin, radius: radius),
            -math.pi / 2,
            math.pi / 3,
            false,
          )
          ..close();

    final glowPaint =
        Paint()
          ..shader = RadialGradient(
            center: Alignment.bottomLeft,
            radius: 1.1,
            colors: [
              dark ? const Color(0x55B45309) : const Color(0x33B45309),
              dark ? const Color(0x33B45309) : const Color(0x20B45309),
              Colors.transparent,
            ],
            stops: const [0.0, 0.42, 1.0],
          ).createShader(Offset.zero & size)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    final sectorPaint =
        Paint()
          ..shader = RadialGradient(
            center: Alignment.bottomLeft,
            radius: 1.05,
            colors: [
              dark ? const Color(0x40B45309) : const Color(0x24B45309),
              dark ? const Color(0x24B45309) : const Color(0x14B45309),
              Colors.transparent,
            ],
            stops: const [0.0, 0.38, 1.0],
          ).createShader(Offset.zero & size);

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, sectorPaint);
  }

  @override
  bool shouldRepaint(covariant _ConnectRadarSectorPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class _ConnectPhoneGlyphPainter extends CustomPainter {
  const _ConnectPhoneGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.3 / 15)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (4.25 / 15),
        size.height * (1.75 / 15),
        size.width * (6.5 / 15),
        size.height * (11.5 / 15),
      ),
      Radius.circular(size.width * (1.35 / 15)),
    );
    canvas.drawRRect(body, stroke);
  }

  @override
  bool shouldRepaint(covariant _ConnectPhoneGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ConnectCameraGlyphPainter extends CustomPainter {
  const _ConnectCameraGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.2 / 11)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (1.1 / 11),
        size.height * (3.1 / 11),
        size.width * (8.8 / 11),
        size.height * (5.8 / 11),
      ),
      Radius.circular(size.width * (1.6 / 11)),
    );
    canvas.drawRRect(body, stroke);
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.5),
      size.width * (1.9 / 11),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * (2.7 / 11), size.height * (3.1 / 11)),
      Offset(size.width * (3.8 / 11), size.height * (2.0 / 11)),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _ConnectCameraGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ConnectFooterLockPainter extends CustomPainter {
  const _ConnectFooterLockPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (0.85 / 10)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (1.6 / 10),
        size.height * (4.7 / 10),
        size.width * (6.8 / 10),
        size.height * (4.0 / 10),
      ),
      Radius.circular(size.width * (0.8 / 10)),
    );
    canvas.drawRRect(body, stroke);
    final shackle =
        Path()
          ..moveTo(size.width * (3.0 / 10), size.height * (4.7 / 10))
          ..lineTo(size.width * (3.0 / 10), size.height * (3.0 / 10))
          ..arcToPoint(
            Offset(size.width * (7.0 / 10), size.height * (3.0 / 10)),
            radius: Radius.circular(size.width * (2.1 / 10)),
          )
          ..lineTo(size.width * (7.0 / 10), size.height * (4.7 / 10));
    canvas.drawPath(shackle, stroke);
  }

  @override
  bool shouldRepaint(covariant _ConnectFooterLockPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Second popup: user enters camera name, Wi-Fi details, and optional QR code.
class ProprietaryCameraInfoDialog extends StatefulWidget {
  const ProprietaryCameraInfoDialog({
    super.key,
    this.previewMode = false,
    this.initialQrCode,
    this.hotspotPassword,
  });

  final bool previewMode;
  final Uint8List? initialQrCode;
  final String? hotspotPassword;

  @override
  State<ProprietaryCameraInfoDialog> createState() =>
      _ProprietaryCameraInfoDialogState();
}

class _ProprietaryCameraInfoDialogState
    extends State<ProprietaryCameraInfoDialog> {
  final _cameraNameController = TextEditingController();
  final _wifiSsidController = TextEditingController();
  final _wifiPasswordController = TextEditingController();
  final _cameraNameFocusNode = FocusNode();
  final _wifiSsidFocusNode = FocusNode();
  final _wifiPasswordFocusNode = FocusNode();

  Uint8List? _qrCode;
  String? _hotspotPassword;
  bool _showWifiPassword = false;

  @override
  void initState() {
    super.initState();
    ProprietaryCameraConnectDialog.pairingCompleted = false;
    _qrCode = widget.initialQrCode;
    _hotspotPassword = widget.hotspotPassword;
    _cameraNameFocusNode.addListener(_handleFocusChange);
    _wifiSsidFocusNode.addListener(_handleFocusChange);
    _wifiPasswordFocusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _cameraNameController.dispose();
    _wifiSsidController.dispose();
    _wifiPasswordController.dispose();
    _cameraNameFocusNode.dispose();
    _wifiSsidFocusNode.dispose();
    _wifiPasswordFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  double? _focusedFieldBottom(double scale) {
    if (_cameraNameFocusNode.hasFocus) {
      return 193.0 * scale;
    }
    if (_wifiSsidFocusNode.hasFocus) {
      return 296.0 * scale;
    }
    if (_wifiPasswordFocusNode.hasFocus) {
      return 399.0 * scale;
    }
    return null;
  }

  double _keyboardLift({
    required double viewportHeight,
    required double keyboardHeight,
    required double scale,
  }) {
    final focusedBottom = _focusedFieldBottom(scale);
    if (focusedBottom == null || keyboardHeight <= 0) {
      return 0;
    }

    final desiredGap = 24 * scale;
    final availableBottom = viewportHeight - keyboardHeight - desiredGap;
    final overlap = focusedBottom - availableBottom;
    if (overlap <= 0) {
      return 0;
    }

    return math.min(overlap, 120 * scale);
  }

  void _onCancel() async {
    Log.d("Cancelling");
    if (!ProprietaryCameraConnectDialog.pairingCompleted &&
        ProprietaryCameraConnectDialog.pairingInProgress) {
      try {
        const platform = MethodChannel("secluso.com/wifi");
        await platform.invokeMethod<String>(
          'disconnectFromWifi',
          <String, dynamic>{'ssid': "Secluso"},
        );
      } catch (e) {
        Log.w("WiFi disconnect failed from InfoDialog: $e");
      }
    }
    if (!mounted) {
      return;
    }
    ProprietaryCameraConnectDialog.pairingInProgress = false;
    Navigator.of(context).pop();
  }

  Future<void> _onAddCamera() async {
    final cameraName = _cameraNameController.text.trim();

    var sharedPreferences = await SharedPreferences.getInstance();
    var existingCameraSet = await AppCoordinationState.getCameraSet();

    // Reset these as they are no longer needed.
    if (sharedPreferences.containsKey(PrefKeys.lastCameraAdd)) {
      Log.d("Deleting extra last camera");
      var lastCameraAdd = sharedPreferences.getString(PrefKeys.lastCameraAdd)!;
      await deregisterCamera(cameraName: lastCameraAdd);
      invalidateCameraInit(lastCameraAdd);
      HttpClientService.instance.clearGroupNameCache(lastCameraAdd);
      await sharedPreferences.remove(PrefKeys.lastCameraAdd);

      final docsDir = await AppPaths.dataDirectory();
      final camDir = Directory(
        p.join(docsDir.path, 'camera_dir_$lastCameraAdd'),
      );
      if (await camDir.exists()) {
        try {
          await camDir.delete(recursive: true);
          Log.d('Deleted camera folder: ${camDir.path}');
        } catch (e) {
          Log.e('Error deleting folder: $e');
        }
      }
    }

    if (existingCameraSet.contains(cameraName.toLowerCase())) {
      if (!mounted) {
        return;
      }
      FocusManager.instance.primaryFocus?.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            "Please use a unique name for the camera",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }
    final wifiSsid = _wifiSsidController.text.trim();
    final wifiPassword = _wifiPasswordController.text;

    if (_qrCode == null || _hotspotPassword == null) {
      FocusManager.instance.primaryFocus?.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scan the camera QR code before continuing.'),
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder:
            (ctx) => ProprietaryCameraWaitingDialog(
              cameraName: cameraName,
              wifiSsid: wifiSsid,
              wifiPassword: wifiPassword,
              hotspotPassword: _hotspotPassword!,
              qrCode: _qrCode!,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isFormComplete =
        _cameraNameController.text.trim().isNotEmpty &&
        _wifiSsidController.text.trim().isNotEmpty &&
        _wifiPasswordController.text.isNotEmpty;
    final backgroundColor =
        dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7);
    final titleColor = dark ? Colors.white : const Color(0xFF111827);
    final sectionLabelColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final cardColor =
        dark ? Colors.white.withValues(alpha: 0.03) : Colors.white;
    final cardBorderColor =
        dark ? Colors.white.withValues(alpha: 0.05) : const Color(0x0A000000);
    final dividerColor =
        dark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFE5E7EB);
    final inputColor =
        dark ? Colors.white.withValues(alpha: 0.04) : Colors.white;
    final inputBorderColor =
        dark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E7EB);
    final fieldLabelColor =
        dark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF4B5563);
    final hintColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final noteColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final buttonFill =
        isFormComplete
            ? (dark ? Colors.white : const Color(0xFF0A0A0A))
            : (dark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFE5E7EB));
    final buttonTextColor =
        isFormComplete
            ? (dark ? const Color(0xFF050505) : Colors.white)
            : (dark
                ? Colors.white.withValues(alpha: 0.2)
                : const Color(0xFF9CA3AF));
    final eyeColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);

    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const designWidth = 290.0;
            const designHeight = 580.0;
            final scale = math.min(
              constraints.maxWidth / designWidth,
              constraints.maxHeight / designHeight,
            );
            double scaled(double value) => value * scale;
            final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
            final contentLift = _keyboardLift(
              viewportHeight: constraints.maxHeight,
              keyboardHeight: keyboardHeight,
              scale: scale,
            );

            final contentHeight = scaled(580);
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: SizedBox(
                  height:
                      constraints.maxHeight > contentHeight
                          ? constraints.maxHeight
                          : contentHeight,
                  child: Stack(
                    children: [
                      Positioned(
                        left: scaled(20),
                        top: scaled(22),
                        child: _ConnectBackButton(
                          size: scaled(32),
                          iconSize: scaled(16),
                          fillColor:
                              dark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : const Color(0xFFE5E7EB),
                          iconColor:
                              dark ? Colors.white : const Color(0xFF6B7280),
                          onTap: _onCancel,
                        ),
                      ),
                      Positioned(
                        left: scaled(64),
                        top: scaled(24),
                        child: Text(
                          'Camera Setup',
                          style: GoogleFonts.inter(
                            color: titleColor,
                            fontSize: scaled(18),
                            fontWeight: FontWeight.w600,
                            height: 28 / 18,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: contentLift),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          builder:
                              (context, lift, child) => Transform.translate(
                                offset: Offset(0, -lift),
                                child: child,
                              ),
                          child: Stack(
                            children: [
                              Positioned(
                                left: scaled(20),
                                top: scaled(88),
                                child: Text(
                                  'CAMERA DETAILS',
                                  style: GoogleFonts.inter(
                                    color: sectionLabelColor,
                                    fontSize: scaled(9),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: scaled(0.9),
                                    height: 13.5 / 9,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: scaled(16),
                                top: scaled(107.5),
                                width: constraints.maxWidth - scaled(32),
                                height: scaled(310),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: cardColor,
                                    borderRadius: BorderRadius.circular(
                                      scaled(12),
                                    ),
                                    border: Border.all(color: cardBorderColor),
                                    boxShadow:
                                        dark
                                            ? null
                                            : const [
                                              BoxShadow(
                                                color: Color(0x0D000000),
                                                blurRadius: 2,
                                                offset: Offset(0, 1),
                                              ),
                                            ],
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        top: scaled(103),
                                        child: Container(
                                          height: 1,
                                          color: dividerColor,
                                        ),
                                      ),
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        top: scaled(206),
                                        child: Container(
                                          height: 1,
                                          color: dividerColor,
                                        ),
                                      ),
                                      Positioned(
                                        left: scaled(16),
                                        top: scaled(16),
                                        child: Text(
                                          'Camera Name',
                                          style: GoogleFonts.inter(
                                            color: fieldLabelColor,
                                            fontSize: scaled(11),
                                            fontWeight: FontWeight.w500,
                                            height: 16.5 / 11,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: scaled(16),
                                        right: scaled(16),
                                        top: scaled(40.5),
                                        child: _ProprietarySetupInput(
                                          controller: _cameraNameController,
                                          focusNode: _cameraNameFocusNode,
                                          hintText: 'e.g. Front Door',
                                          scale: scale,
                                          borderColor: inputBorderColor,
                                          fillColor: inputColor,
                                          hintColor: hintColor,
                                          keyboardType: TextInputType.text,
                                          obscureText: false,
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ),
                                      Positioned(
                                        left: scaled(16),
                                        top: scaled(119),
                                        child: Text(
                                          'WiFi Network',
                                          style: GoogleFonts.inter(
                                            color: fieldLabelColor,
                                            fontSize: scaled(11),
                                            fontWeight: FontWeight.w500,
                                            height: 16.5 / 11,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: scaled(16),
                                        right: scaled(16),
                                        top: scaled(143.5),
                                        child: _ProprietarySetupInput(
                                          controller: _wifiSsidController,
                                          focusNode: _wifiSsidFocusNode,
                                          hintText: 'Your home network name',
                                          scale: scale,
                                          borderColor: inputBorderColor,
                                          fillColor: inputColor,
                                          hintColor: hintColor,
                                          keyboardType: TextInputType.text,
                                          obscureText: false,
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ),
                                      Positioned(
                                        left: scaled(16),
                                        top: scaled(222),
                                        child: Text(
                                          'WiFi Password',
                                          style: GoogleFonts.inter(
                                            color: fieldLabelColor,
                                            fontSize: scaled(11),
                                            fontWeight: FontWeight.w500,
                                            height: 16.5 / 11,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: scaled(16),
                                        right: scaled(16),
                                        top: scaled(246.5),
                                        child: _ProprietarySetupInput(
                                          controller: _wifiPasswordController,
                                          focusNode: _wifiPasswordFocusNode,
                                          hintText: 'Network password',
                                          scale: scale,
                                          borderColor: inputBorderColor,
                                          fillColor: inputColor,
                                          hintColor: hintColor,
                                          keyboardType:
                                              TextInputType.visiblePassword,
                                          obscureText: !_showWifiPassword,
                                          onChanged: (_) => setState(() {}),
                                          trailing: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              setState(() {
                                                _showWifiPassword =
                                                    !_showWifiPassword;
                                              });
                                            },
                                            child: SizedBox(
                                              width: scaled(24),
                                              height: scaled(24),
                                              child: Center(
                                                child: SizedBox(
                                                  width: scaled(16),
                                                  height: scaled(16),
                                                  child: CustomPaint(
                                                    painter:
                                                        _ProprietarySetupEyePainter(
                                                          eyeColor,
                                                          open:
                                                              _showWifiPassword,
                                                        ),
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
                              Positioned(
                                left: scaled(20),
                                top: scaled(439.5),
                                child: SizedBox(
                                  width: scaled(12),
                                  height: scaled(12),
                                  child: CustomPaint(
                                    painter: _ConnectFooterLockPainter(
                                      noteColor,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: scaled(42),
                                top: scaled(439.5),
                                width: scaled(223.72),
                                child: Text(
                                  'Your WiFi credentials are sent directly to the\ncamera over the encrypted link. They are never\nstored on your phone or any server.',
                                  style: GoogleFonts.inter(
                                    color: noteColor,
                                    fontSize: scaled(10),
                                    fontWeight: FontWeight.w400,
                                    height: 16.25 / 10,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: scaled(16),
                                top: scaled(518.25),
                                width: constraints.maxWidth - scaled(32),
                                height: scaled(46),
                                child: FilledButton(
                                  onPressed:
                                      isFormComplete ? _onAddCamera : null,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: buttonFill,
                                    foregroundColor: buttonTextColor,
                                    disabledBackgroundColor: buttonFill,
                                    disabledForegroundColor: buttonTextColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        scaled(12),
                                      ),
                                    ),
                                    padding: EdgeInsets.zero,
                                    textStyle: GoogleFonts.inter(
                                      fontSize: scaled(12),
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: scaled(0.6),
                                      height: 18 / 12,
                                    ),
                                  ),
                                  child: const Text('CONTINUE'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProprietarySetupInput extends StatelessWidget {
  const _ProprietarySetupInput({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.scale,
    required this.borderColor,
    required this.fillColor,
    required this.hintColor,
    required this.keyboardType,
    required this.obscureText,
    required this.onChanged,
    this.trailing,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final double scale;
  final Color borderColor;
  final Color fillColor;
  final Color hintColor;
  final TextInputType keyboardType;
  final bool obscureText;
  final ValueChanged<String> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    double scaled(double value) => value * scale;
    final textColor =
        Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : const Color(0xFF111827);

    return SizedBox(
      height: scaled(45.5),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        obscureText: obscureText,
        onChanged: onChanged,
        style: GoogleFonts.inter(
          color: textColor,
          fontSize: scaled(13),
          fontWeight: FontWeight.w400,
          height: 15.5 / 13,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.inter(
            color: hintColor,
            fontSize: scaled(13),
            fontWeight: FontWeight.w400,
            height: 15.5 / 13,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: scaled(16),
            vertical: scaled(14),
          ),
          filled: true,
          fillColor: fillColor,
          suffixIcon:
              trailing == null
                  ? null
                  : Padding(
                    padding: EdgeInsets.only(right: scaled(12)),
                    child: trailing,
                  ),
          suffixIconConstraints: BoxConstraints(
            minWidth: scaled(36),
            minHeight: scaled(24),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(scaled(12)),
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(scaled(12)),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(scaled(12)),
            borderSide: BorderSide(
              color: const Color(0xFF8BB3EE),
              width: scaled(1.2),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProprietarySetupEyePainter extends CustomPainter {
  const _ProprietarySetupEyePainter(this.color, {required this.open});

  final Color color;
  final bool open;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.35 / 16)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color;
    final eyePath =
        Path()
          ..moveTo(size.width * (2 / 16), size.height * (8 / 16))
          ..quadraticBezierTo(
            size.width * (4.8 / 16),
            size.height * (3.3 / 16),
            size.width * (8 / 16),
            size.height * (3.3 / 16),
          )
          ..quadraticBezierTo(
            size.width * (11.2 / 16),
            size.height * (3.3 / 16),
            size.width * (14 / 16),
            size.height * (8 / 16),
          )
          ..quadraticBezierTo(
            size.width * (11.2 / 16),
            size.height * (12.7 / 16),
            size.width * (8 / 16),
            size.height * (12.7 / 16),
          )
          ..quadraticBezierTo(
            size.width * (4.8 / 16),
            size.height * (12.7 / 16),
            size.width * (2 / 16),
            size.height * (8 / 16),
          );
    canvas.drawPath(eyePath, stroke);
    if (open) {
      canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.5),
        size.width * (2 / 16),
        stroke,
      );
    } else {
      canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.5),
        size.width * (1.4 / 16),
        Paint()..color = color,
      );
      canvas.drawLine(
        Offset(size.width * (3 / 16), size.height * (13 / 16)),
        Offset(size.width * (13 / 16), size.height * (3 / 16)),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProprietarySetupEyePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.open != open;
}
