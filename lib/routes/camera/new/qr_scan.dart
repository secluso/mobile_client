//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:secluso_flutter/constants.dart';
import 'dart:async';
import 'package:secluso_flutter/routes/camera/new/android_camera_option.dart';
import 'package:secluso_flutter/routes/camera/new/ip_camera_option.dart';
import 'package:secluso_flutter/routes/camera/new/proprietary_camera_option.dart';
import 'package:secluso_flutter/routes/camera/new/proprietary_camera_waiting.dart';
import 'package:secluso_flutter/utilities/review_environment.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'dart:convert';
import 'package:secluso_flutter/ui/google_fonts.dart';
import 'package:secluso_flutter/ui/secluso_qr_reader.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_theme.dart';
import 'dart:typed_data';
import 'package:secluso_flutter/notifications/epoch.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/routes/camera/new/add_app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';

/// This dialog displays the camera preview and scans for a single QR code.
/// After the first successful scan, it prompts the user for a camera name
/// and then pops the entire flow with the final data.
class QrScanDialog extends StatefulWidget {
  final String? previewAssetPath;

  const QrScanDialog({super.key, this.previewAssetPath});

  @override
  State<QrScanDialog> createState() => _QrScanDialogState();

  static Future<Uint8List?> showQrScanDialog(BuildContext context) async {
    return showDialog<Uint8List?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const QrScanDialog(),
    );
  }
}

class QrScanPage extends StatelessWidget {
  const QrScanPage({super.key, this.previewAssetPath});

  final String? previewAssetPath;

  @override
  Widget build(BuildContext context) {
    return SeclusoQrScanScreen(
      title: 'Scan Camera QR',
      bottomMessage:
          'Pairing credentials are exchanged\ndirectly between your phone and\ncamera. Nothing is sent to any server.',
      background:
          previewAssetPath != null
              ? Image.asset(previewAssetPath!, fit: BoxFit.cover)
              : const ColoredBox(color: Color(0xFF050505)),
      onBack: () => Navigator.of(context).maybePop(),
    );
  }
}

class SeclusoQrScanScreen extends StatelessWidget {
  const SeclusoQrScanScreen({
    super.key,
    required this.title,
    required this.bottomMessage,
    required this.background,
    required this.onBack,
    this.belowFrameText,
    this.errorMessage,
    this.indicatorMessage,
    this.actionArea,
  });

  final String title;
  final String bottomMessage;
  final Widget background;
  final VoidCallback onBack;
  final String? belowFrameText;
  final String? errorMessage;
  final String? indicatorMessage;
  final Widget? actionArea;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryTextColor = Colors.white.withValues(alpha: 0.4);
    final securityCardColor = Colors.black.withValues(alpha: 0.52);
    final securityBorderColor = Colors.white.withValues(alpha: 0.12);
    final securityIconColor = Colors.white.withValues(alpha: 0.3);

    final overlayStyle = const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: const Color(0xFF050505),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final metrics = _QrScanMetrics.forWidth(constraints.maxWidth);
            return Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFF050505)),
                background,
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.24),
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.18),
                      ],
                      stops: const [0.0, 0.42, 1.0],
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      metrics.sideInset,
                      metrics.topInset,
                      metrics.sideInset,
                      metrics.bottomInset,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: metrics.headerHeight,
                          child: Row(
                            children: [
                              _BackCircle(
                                size: metrics.backButtonSize,
                                iconSize: metrics.backIconSize,
                                fillColor: Colors.white.withValues(alpha: 0.06),
                                iconColor: Colors.white,
                                onTap: onBack,
                              ),
                              SizedBox(width: metrics.headerGap),
                              Text(
                                title,
                                style: GoogleFonts.inter(
                                  textStyle: theme.textTheme.titleLarge,
                                  color: Colors.white,
                                  fontSize: metrics.headerTitleSize,
                                  fontWeight: FontWeight.w600,
                                  height: 28 / 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: metrics.headerToFrameGap),
                        const Spacer(),
                        Center(
                          child: SizedBox(
                            width: metrics.frameSize,
                            height: metrics.frameSize,
                            child: _QrScanPageFrame(
                              metrics: metrics,
                              cornerColor: const Color(0xFF8BB3EE),
                              scanLineColor: const Color(0xFF8BB3EE),
                            ),
                          ),
                        ),
                        if (belowFrameText != null) ...[
                          SizedBox(height: metrics.frameToTitleGap),
                          Center(
                            child: SizedBox(
                              width: metrics.titleBlockWidth,
                              child: Text(
                                belowFrameText!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  textStyle: theme.textTheme.titleLarge,
                                  color: Colors.white,
                                  fontSize: metrics.titleSize,
                                  fontWeight: FontWeight.w600,
                                  height: 22.5 / 15,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: metrics.titleToBodyGap * 0.35),
                        ] else ...[
                          SizedBox(height: metrics.frameToTitleGap * 0.45),
                        ],
                        const Spacer(),
                        Container(
                          constraints: BoxConstraints(
                            minHeight: metrics.securityCardHeight,
                          ),
                          decoration: BoxDecoration(
                            color: securityCardColor,
                            borderRadius: BorderRadius.circular(
                              metrics.securityCardRadius,
                            ),
                            border: Border.all(color: securityBorderColor),
                          ),
                          padding: EdgeInsets.fromLTRB(
                            metrics.securityCardInset,
                            metrics.securityCardInset,
                            metrics.securityCardInset,
                            metrics.securityCardInset,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                  top: metrics.securityIconTopInset,
                                ),
                                child: _QrSecurityLockIcon(
                                  size: metrics.securityIconSize,
                                  color: securityIconColor,
                                ),
                              ),
                              SizedBox(width: metrics.securityTextGap),
                              Expanded(
                                child: Text(
                                  bottomMessage,
                                  style: GoogleFonts.inter(
                                    textStyle: theme.textTheme.bodySmall,
                                    color: secondaryTextColor,
                                    fontSize: metrics.securityTextSize,
                                    fontWeight: FontWeight.w400,
                                    height: 16.25 / 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (indicatorMessage != null) ...[
                          SizedBox(height: 12 * metrics.scale),
                          Center(
                            child: Text(
                              indicatorMessage!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                textStyle: theme.textTheme.bodySmall,
                                color: const Color(0xFFF59E0B),
                                fontSize: metrics.bodySize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ] else if (errorMessage != null) ...[
                          SizedBox(height: 12 * metrics.scale),
                          Center(
                            child: Text(
                              errorMessage!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                textStyle: theme.textTheme.bodySmall,
                                color: const Color(0xFFEF4444),
                                fontSize: metrics.bodySize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        if (actionArea != null) ...[
                          SizedBox(height: 12 * metrics.scale),
                          actionArea!,
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum GenericCameraQrKind { proprietary, ip, android, review, addApp }

class GenericCameraQrPayload {
  const GenericCameraQrPayload._({
    required this.kind,
    this.rawQrBytes,
    this.initialCameraName,
    this.initialCameraIp,
    this.reviewPayload,
    this.hotspotPassword,
    this.addAppSecret,
    this.addAppServerAddr,
    this.addAppServerUsername,
  });

  final GenericCameraQrKind kind;
  final Uint8List? rawQrBytes;
  final String? initialCameraName;
  final String? initialCameraIp;
  final ReviewCameraQrPayload? reviewPayload;
  final String? hotspotPassword;
  final Uint8List? addAppSecret;
  final String? addAppServerAddr;
  final String? addAppServerUsername;

  factory GenericCameraQrPayload.proprietary(
    Uint8List rawQrBytes,
    String hotspotPassword,
  ) {
    return GenericCameraQrPayload._(
      kind: GenericCameraQrKind.proprietary,
      rawQrBytes: rawQrBytes,
      hotspotPassword: hotspotPassword,
    );
  }

  factory GenericCameraQrPayload.android({required Uint8List rawQrBytes}) {
    return GenericCameraQrPayload._(
      kind: GenericCameraQrKind.android,
      rawQrBytes: rawQrBytes,
    );
  }

  factory GenericCameraQrPayload.ip({
    String? initialCameraName,
    String? initialCameraIp,
  }) {
    return GenericCameraQrPayload._(
      kind: GenericCameraQrKind.ip,
      initialCameraName: initialCameraName,
      initialCameraIp: initialCameraIp,
    );
  }

  factory GenericCameraQrPayload.review(ReviewCameraQrPayload reviewPayload) {
    return GenericCameraQrPayload._(
      kind: GenericCameraQrKind.review,
      reviewPayload: reviewPayload,
    );
  }

  factory GenericCameraQrPayload.addApp(
    Uint8List addAppSecret, {
    required String serverAddr,
    required String serverUsername,
  }) {
    return GenericCameraQrPayload._(
      kind: GenericCameraQrKind.addApp,
      addAppSecret: addAppSecret,
      addAppServerAddr: serverAddr,
      addAppServerUsername: serverUsername,
    );
  }
}

class GenericCameraQrScanPage extends StatefulWidget {
  const GenericCameraQrScanPage({super.key});

  static Future<Map<String, Object>?> show(BuildContext context) {
    return Navigator.of(
      context,
      rootNavigator: true,
    ).push<Map<String, Object>?>(
      MaterialPageRoute<Map<String, Object>?>(
        builder: (_) => const GenericCameraQrScanPage(),
      ),
    );
  }

  @override
  State<GenericCameraQrScanPage> createState() =>
      _GenericCameraQrScanPageState();
}

class _GenericCameraQrScanPageState extends State<GenericCameraQrScanPage>
    with WidgetsBindingObserver {
  PermissionStatus? _cameraPermissionStatus;
  bool _handlingScan = false;
  String? _indicatorMessage;
  String? _scannerErrorMessage;
  Timer? _indicatorTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshCameraPermission(requestIfNeeded: true);
  }

  @override
  void dispose() {
    _indicatorTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshCameraPermission();
    }
  }

  Future<void> _refreshCameraPermission({bool requestIfNeeded = false}) async {
    PermissionStatus status = await Permission.camera.status;
    if (requestIfNeeded &&
        !status.isGranted &&
        !status.isPermanentlyDenied &&
        !status.isRestricted) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    setState(() {
      _cameraPermissionStatus = status;
    });
  }

  void _handleScannerControllerCreated(
    CameraController? controller,
    Exception? error,
  ) {
    if (!mounted) return;
    if (error != null) {
      Log.w('QR scanner error: $error');
    }
    setState(() {
      // TODO: Make this debug mode only.
      _scannerErrorMessage =
          error == null
              ? null
              : "This phone's camera can't be used right now. You can enter "
                  'the code instead.';
    });
  }

  String? _cameraPermissionMessage() {
    final status = _cameraPermissionStatus;
    if (status == null || status.isGranted) {
      return null;
    }
    if (status.isPermanentlyDenied) {
      return 'Camera access is required to scan QR codes. Enable it in Settings.';
    }
    if (status.isRestricted) {
      return 'Camera access is restricted on this device.';
    }
    return 'Camera access is required to scan QR codes.';
  }

  Uint8List? _decodeCameraSecret(String encoded) {
    final candidates = <String>[
      encoded.trim(),
      base64Url.normalize(encoded.trim()),
      base64.normalize(encoded.trim()),
    ];

    for (final candidate in candidates) {
      try {
        return Uint8List.fromList(base64Url.decode(candidate));
      } catch (_) {}

      try {
        return Uint8List.fromList(base64.decode(candidate));
      } catch (_) {}
    }

    return null;
  }

  String? _stringFromAny(Map decoded, List<String> keys) {
    for (final key in keys) {
      final value = decoded[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  Widget? _cameraPermissionActions(BuildContext context) {
    final status = _cameraPermissionStatus;
    if (status == null || status.isGranted) {
      return null;
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Back'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed:
                status.isPermanentlyDenied
                    ? openAppSettings
                    : () => _refreshCameraPermission(requestIfNeeded: true),
            child: Text(
              status.isPermanentlyDenied ? 'Open Settings' : 'Try Again',
            ),
          ),
        ),
      ],
    );
  }

  Future<String?> _validateAddAppRelay(GenericCameraQrPayload payload) async {
    final prefs = await SharedPreferences.getInstance();

    final localServerAddr = prefs.getString(PrefKeys.serverAddr)?.trim();
    final localServerUsername =
        prefs.getString(PrefKeys.serverUsername)?.trim();

    if (localServerAddr != payload.addAppServerAddr ||
        localServerUsername != payload.addAppServerUsername) {
      return 'Both phones need to be connected to the same relay with the same account in order to add the phone.';
    }

    return null;
  }

  Future<void> _handleDetectedBarcode(Code barcode) async {
    if (_handlingScan || !barcode.isValid) return;

    final text = barcode.text?.trim();
    if (text == null || text.isEmpty) {
      return;
    }
    await _handleScannedText(text);
  }

  /// For phones whose camera can't be used (no permission, etc).
  /// Mainly testing purposes.
  /// TODO: Remove this in production.
  Future<void> _enterCodeManually() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Enter the camera code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'On the camera phone, the code is shown under the QR. Paste '
                'or type it here.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: '{"v":"v1.2","cs":"..."}',
                  suffixIcon: IconButton(
                    tooltip: 'Paste',
                    icon: const Icon(Icons.content_paste),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      final pasted = data?.text?.trim();
                      if (pasted != null && pasted.isNotEmpty) {
                        controller.text = pasted;
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    if (text == null || text.isEmpty || !mounted) return;
    await _handleScannedText(text);
  }

  Future<void> _handleScannedText(String text) async {
    if (_handlingScan) return;

    final payload = _parseCameraQr(text);
    if (payload == null) {
      _showNonSeclusoQrIndicator(
        'QR code detected, but it is not a Secluso camera QR code.',
      );
      return;
    }

    setState(() {
      _handlingScan = true; // mark as handled
    });
    if (!context.mounted) return;

    Map<String, Object>? result;
    switch (payload.kind) {
      case GenericCameraQrKind.proprietary:
        result =
            await ProprietaryCameraConnectDialog.showProprietaryCameraSetupFlow(
              context,
              initialQrCode: payload.rawQrBytes!,
              hotspotPassword: payload.hotspotPassword!,
            );
      case GenericCameraQrKind.ip:
        result = await IpCameraDialog.showIpCameraPopup(
          context,
          initialCameraName: payload.initialCameraName,
          initialCameraIp: payload.initialCameraIp,
        );
      case GenericCameraQrKind.android:
        result = await AndroidCameraDialog.showAndroidCameraPopup(
          context,
          initialQrCode: payload.rawQrBytes!,
        );
      case GenericCameraQrKind.review:
        final reviewPayload = payload.reviewPayload;
        if (reviewPayload == null) {
          result = null;
          break;
        }
        final session = ReviewEnvironment.instance.session;
        final alreadyAdded =
            session?.cameras.any(
              (camera) =>
                  camera.id == reviewPayload.cameraId ||
                  camera.name == reviewPayload.cameraName,
            ) ??
            false;
        if (!ReviewEnvironment.instance.isActive) {
          _showNonSeclusoQrIndicator(
            'Scan the App Review relay QR before scanning the review camera QR.',
          );
          break;
        }
        if (alreadyAdded) {
          _showNonSeclusoQrIndicator(
            'That App Review camera is already added.',
          );
          break;
        }
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder:
                (_) =>
                    ReviewCameraPairingFlowPage(reviewPayload: reviewPayload),
          ),
        );
      case GenericCameraQrKind.addApp:
        final relayError = await _validateAddAppRelay(payload);
        if (relayError != null) {
          _showNonSeclusoQrIndicator(relayError);
          break;
        }

        result = await AddAppFlow.show(
          context,
          addAppSecret: payload.addAppSecret!,
        );
    }

    if (!mounted) return;

    if (result != null) {
      Navigator.of(context).pop(result);
      return;
    }

    setState(() {
      _handlingScan = false;
    });
  }

  GenericCameraQrPayload? _parseCameraQr(String rawValue) {
    dynamic decoded;
    try {
      decoded = jsonDecode(rawValue);
    } catch (_) {
      decoded = null;
    }

    if (decoded is Map) {
      final reviewPayload = ReviewCameraQrPayload.tryParseMap(decoded);
      if (reviewPayload != null) {
        return GenericCameraQrPayload.review(reviewPayload);
      }

      final versionKey = decoded['v'];
      final cameraSecret = decoded['cs'];
      if (versionKey is String &&
          cameraSecret is String &&
          versionKey == Constants.cameraQrCodeVersion) {
        try {
          final rawBytes = _decodeCameraSecret(cameraSecret);
          final hotspotPassword = decoded['wp'];
          if (rawBytes != null &&
              rawBytes.length == Constants.numCameraSecretBytes) {
            if (hotspotPassword is String && hotspotPassword.isNotEmpty) {
              return GenericCameraQrPayload.proprietary(
                rawBytes,
                hotspotPassword,
              );
            }

            final serverAddr = decoded['sa'];
            final serverUsername = decoded['su'];

            if (serverAddr is String &&
                serverAddr.trim().isNotEmpty &&
                serverUsername is String &&
                serverUsername.trim().isNotEmpty) {
              return GenericCameraQrPayload.addApp(
                rawBytes,
                serverAddr: serverAddr.trim(),
                serverUsername: serverUsername.trim(),
              );
            }

            return GenericCameraQrPayload.android(rawQrBytes: rawBytes);
          }
        } catch (_) {}

        // Placeholder for future generic QR support:
        // when camera QR payloads include a dedicated type/IP field,
        // route that branch into GenericCameraQrPayload.ip(...).
        //
        // Example future shape:
        // final type = decoded['type'];
        // final cameraIp = decoded['cameraIp'];
        // if (type == 'ip' && cameraIp is String && cameraIp.isNotEmpty) {
        //   return GenericCameraQrPayload.ip(initialCameraIp: cameraIp);
        // }
      }

      final androidSecret = _stringFromAny(decoded, [
        'secret',
        'camera_secret',
        'cameraSecret',
      ]);

      if (androidSecret != null) {
        final rawBytes = _decodeCameraSecret(androidSecret);

        if (rawBytes != null && rawBytes.isNotEmpty) {
          return GenericCameraQrPayload.android(rawQrBytes: rawBytes);
        }
      }
    }

    return null;
  }

  void _showNonSeclusoQrIndicator(String message) {
    if (_indicatorMessage == message) return;

    setState(() {
      _indicatorMessage = message;
    });
    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _indicatorMessage = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasCameraPermission = _cameraPermissionStatus?.isGranted ?? false;
    return SeclusoQrScanScreen(
      title: 'Scan Camera QR',
      bottomMessage:
          hasCameraPermission
              ? 'Supported QR types are interpreted locally on this phone. Unsupported QR codes are ignored and never sent to any server.'
              : 'Camera access is used only to scan QR codes on this phone.',
      background:
          !hasCameraPermission
              ? const ColoredBox(color: Color(0xFF050505))
              : Stack(
                fit: StackFit.expand,
                children: [
                  SeclusoQrReader(
                    onScan: _handleDetectedBarcode,
                    onControllerCreated: _handleScannerControllerCreated,
                    codeFormat: Format.qrCode,
                    cropPercent: 1.0,
                    tryHarder: true,
                    loading: const ColoredBox(color: Color(0xFF050505)),
                  ),
                  if (_handlingScan)
                    const IgnorePointer(
                      child: ColoredBox(color: Color(0xFF050505)),
                    ),
                ],
              ),
      onBack: () => Navigator.of(context).maybePop(),
      indicatorMessage:
          _cameraPermissionStatus == null
              ? 'Checking camera access…'
              : _indicatorMessage,
      errorMessage: _scannerErrorMessage ?? _cameraPermissionMessage(),
      actionArea: _actionArea(context),
    );
  }

  /// Permission buttons when needed
  Widget _actionArea(BuildContext context) {
    final permissionActions = _cameraPermissionActions(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (permissionActions != null) ...[
          permissionActions,
          const SizedBox(height: 8),
        ],
        TextButton(
          onPressed: _handlingScan ? null : _enterCodeManually,
          child: const Text("Can't scan? Enter the code instead"),
        ),
      ],
    );
  }
}

class _QrScanMetrics {
  const _QrScanMetrics({
    required this.scale,
    required this.sideInset,
    required this.topInset,
    required this.bottomInset,
    required this.headerHeight,
    required this.backButtonSize,
    required this.backIconSize,
    required this.headerGap,
    required this.headerTitleSize,
    required this.headerToFrameGap,
    required this.frameSize,
    required this.cornerSize,
    required this.cornerRadius,
    required this.cornerStroke,
    required this.scanLineInset,
    required this.scanLineTopInset,
    required this.scanLineHeight,
    required this.frameToTitleGap,
    required this.titleBlockWidth,
    required this.titleSize,
    required this.titleToBodyGap,
    required this.bodyBlockWidth,
    required this.bodySize,
    required this.securityCardHeight,
    required this.securityCardRadius,
    required this.securityCardInset,
    required this.securityIconSize,
    required this.securityIconTopInset,
    required this.securityTextGap,
    required this.securityTextSize,
  });

  final double scale;
  final double sideInset;
  final double topInset;
  final double bottomInset;
  final double headerHeight;
  final double backButtonSize;
  final double backIconSize;
  final double headerGap;
  final double headerTitleSize;
  final double headerToFrameGap;
  final double frameSize;
  final double cornerSize;
  final double cornerRadius;
  final double cornerStroke;
  final double scanLineInset;
  final double scanLineTopInset;
  final double scanLineHeight;
  final double frameToTitleGap;
  final double titleBlockWidth;
  final double titleSize;
  final double titleToBodyGap;
  final double bodyBlockWidth;
  final double bodySize;
  final double securityCardHeight;
  final double securityCardRadius;
  final double securityCardInset;
  final double securityIconSize;
  final double securityIconTopInset;
  final double securityTextGap;
  final double securityTextSize;

  factory _QrScanMetrics.forWidth(double width) {
    final scale = width / 290;
    double scaled(double value) => value * scale;
    return _QrScanMetrics(
      scale: scale,
      sideInset: scaled(24),
      topInset: scaled(12),
      bottomInset: scaled(18),
      headerHeight: scaled(32),
      backButtonSize: scaled(32),
      backIconSize: scaled(16),
      headerGap: scaled(12),
      headerTitleSize: scaled(18),
      headerToFrameGap: scaled(60),
      frameSize: scaled(192),
      cornerSize: scaled(32),
      cornerRadius: scaled(8),
      cornerStroke: scaled(2),
      scanLineInset: scaled(16),
      scanLineTopInset: scaled(95.0),
      scanLineHeight: scaled(2),
      frameToTitleGap: scaled(34),
      titleBlockWidth: scaled(188),
      titleSize: scaled(15),
      titleToBodyGap: scaled(16),
      bodyBlockWidth: scaled(210),
      bodySize: scaled(11),
      securityCardHeight: scaled(74.75),
      securityCardRadius: scaled(12),
      securityCardInset: scaled(12),
      securityIconSize: scaled(14),
      securityIconTopInset: scaled(2),
      securityTextGap: scaled(12),
      securityTextSize: scaled(10),
    );
  }
}

class _QrScanPageFrame extends StatefulWidget {
  const _QrScanPageFrame({
    required this.metrics,
    required this.cornerColor,
    required this.scanLineColor,
  });

  final _QrScanMetrics metrics;
  final Color cornerColor;
  final Color scanLineColor;

  @override
  State<_QrScanPageFrame> createState() => _QrScanPageFrameState();
}

class _QrScanPageFrameState extends State<_QrScanPageFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.metrics;
    final cornerColor = widget.cornerColor;
    final scanLineColor = widget.scanLineColor;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse =
            CurvedAnimation(parent: _controller, curve: Curves.easeInOut).value;
        return Stack(
          children: [
            for (final alignment in const [
              Alignment.topLeft,
              Alignment.topRight,
              Alignment.bottomLeft,
              Alignment.bottomRight,
            ])
              Align(
                alignment: alignment,
                child: Container(
                  width: metrics.cornerSize,
                  height: metrics.cornerSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft:
                          alignment == Alignment.topLeft
                              ? Radius.circular(metrics.cornerRadius)
                              : Radius.zero,
                      topRight:
                          alignment == Alignment.topRight
                              ? Radius.circular(metrics.cornerRadius)
                              : Radius.zero,
                      bottomLeft:
                          alignment == Alignment.bottomLeft
                              ? Radius.circular(metrics.cornerRadius)
                              : Radius.zero,
                      bottomRight:
                          alignment == Alignment.bottomRight
                              ? Radius.circular(metrics.cornerRadius)
                              : Radius.zero,
                    ),
                    border: Border(
                      top:
                          alignment.y == -1
                              ? BorderSide(
                                color: cornerColor,
                                width: metrics.cornerStroke,
                              )
                              : BorderSide.none,
                      bottom:
                          alignment.y == 1
                              ? BorderSide(
                                color: cornerColor,
                                width: metrics.cornerStroke,
                              )
                              : BorderSide.none,
                      left:
                          alignment.x == -1
                              ? BorderSide(
                                color: cornerColor,
                                width: metrics.cornerStroke,
                              )
                              : BorderSide.none,
                      right:
                          alignment.x == 1
                              ? BorderSide(
                                color: cornerColor,
                                width: metrics.cornerStroke,
                              )
                              : BorderSide.none,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: metrics.scanLineInset,
              right: metrics.scanLineInset,
              top: metrics.scanLineTopInset,
              child: Opacity(
                opacity: 0.35 + (0.35 * pulse),
                child: Container(
                  height: metrics.scanLineHeight,
                  decoration: BoxDecoration(
                    color: scanLineColor.withValues(alpha: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: scanLineColor.withValues(
                          alpha: 0.10 + (0.18 * pulse),
                        ),
                        blurRadius: 6 * metrics.scale,
                        spreadRadius: 0.5 * metrics.scale,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QrScanDialogState extends State<QrScanDialog>
    with WidgetsBindingObserver {
  bool _hasScannedCode = false; // ensure we only handle the first QR code
  PermissionStatus? _cameraPermissionStatus;

  String? _errorMessage;
  Timer? _errorTimer;
  bool get _isPreviewMode => widget.previewAssetPath != null;

  @override
  void initState() {
    super.initState();
    if (!_isPreviewMode) {
      WidgetsBinding.instance.addObserver(this);
      _refreshCameraPermission(requestIfNeeded: true);
    }
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    if (!_isPreviewMode) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isPreviewMode && state == AppLifecycleState.resumed) {
      _refreshCameraPermission();
    }
  }

  Future<void> _refreshCameraPermission({bool requestIfNeeded = false}) async {
    PermissionStatus status = await Permission.camera.status;
    if (requestIfNeeded &&
        !status.isGranted &&
        !status.isPermanentlyDenied &&
        !status.isRestricted) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    setState(() {
      _cameraPermissionStatus = status;
    });
  }

  String? _cameraPermissionMessage() {
    final status = _cameraPermissionStatus;
    if (_isPreviewMode || status == null || status.isGranted) {
      return null;
    }
    if (status.isPermanentlyDenied) {
      return 'Camera access is required to scan QR codes. Enable it in Settings.';
    }
    if (status.isRestricted) {
      return 'Camera access is restricted on this device.';
    }
    return 'Camera access is required to scan QR codes.';
  }

  Widget _cameraPermissionPlaceholder(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          _cameraPermissionMessage() ?? 'Checking camera access…',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.78),
            height: 1.45,
          ),
        ),
      ),
    );
  }

  Widget _cameraPermissionActions() {
    final status = _cameraPermissionStatus;
    if (_isPreviewMode || status == null || status.isGranted) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _onCloseDialog,
            child: const Text('Back'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed:
                status.isPermanentlyDenied
                    ? openAppSettings
                    : () => _refreshCameraPermission(requestIfNeeded: true),
            child: Text(
              status.isPermanentlyDenied ? 'Open Settings' : 'Try Again',
            ),
          ),
        ),
      ],
    );
  }

  void _onCloseDialog() {
    // Cancel the entire QR scanning process
    Navigator.of(context).pop(null);
  }

  void _onDetectBarcode(Code barcode) {
    if (_hasScannedCode || !barcode.isValid) return; // already handled

    final text = barcode.text;
    if (text == null || text.isEmpty) {
      return;
    }

    dynamic jsonData;
    try {
      jsonData = jsonDecode(text);
    } catch (_) {
      _showInvalidQrCode("Invalid QR code shown");
      return;
    }

    if (jsonData is! Map ||
        !jsonData.containsKey("v") ||
        !jsonData.containsKey("cs")) {
      _showInvalidQrCode("Invalid QR code shown");
      return;
    }

    final versionKey = jsonData["v"];
    if (versionKey != Constants.cameraQrCodeVersion) {
      _showInvalidQrCode("Unsupported QR code version: $versionKey");
      return;
    }

    final rawBytes = base64Decode(jsonData["cs"]);
    if (rawBytes.length != Constants.numCameraSecretBytes) {
      _showInvalidQrCode("Invalid QR code shown");
      return;
    }

    setState(() {
      _hasScannedCode = true; // mark as handled
    });
    Navigator.of(context).pop(rawBytes);
  }

  void _showInvalidQrCode(String message) {
    if (_errorMessage != null) return; // Don't re-show until cleared

    setState(() {
      _errorMessage = message;
    });

    _errorTimer?.cancel(); // Cancel any previous timer
    _errorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCameraPermission =
        _isPreviewMode || (_cameraPermissionStatus?.isGranted ?? false);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFF0D0E11),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF111216), Color(0xFF0B0B0D)],
            ),
          ),
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            height: 540,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: SeclusoStatusChip(
                          label: 'Camera QR',
                          color: SeclusoColors.blueSoft,
                          icon: Icons.qr_code_scanner_rounded,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _onCloseDialog,
                        tooltip: 'Cancel',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan the camera code.',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontSize: 28,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hold the QR code inside the frame and keep the phone steady until the app confirms a valid scan.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.74),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child:
                              _isPreviewMode
                                  ? Image.asset(
                                    widget.previewAssetPath!,
                                    fit: BoxFit.cover,
                                  )
                                  : !hasCameraPermission
                                  ? _cameraPermissionPlaceholder(theme)
                                  : SeclusoQrReader(
                                    onScan: _onDetectBarcode,
                                    codeFormat: Format.qrCode,
                                    cropPercent: 1.0,
                                    tryHarder: true,
                                    loading: const ColoredBox(
                                      color: Color(0xFF050505),
                                    ),
                                  ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.24),
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.42),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: IgnorePointer(
                            child: _ScannerFrame(showScanLine: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_isPreviewMode && !hasCameraPermission) ...[
                    _cameraPermissionActions(),
                    const SizedBox(height: 12),
                  ],
                  if (_errorMessage != null)
                    Text(
                      _errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: SeclusoColors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    Text(
                      !hasCameraPermission
                          ? 'Camera access is used only to scan Secluso QR codes on this phone.'
                          : 'Only Secluso camera QR codes are accepted here.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.58),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScannerFrame extends StatefulWidget {
  const _ScannerFrame({required this.showScanLine});

  final bool showScanLine;

  @override
  State<_ScannerFrame> createState() => _ScannerFrameState();
}

class _ScannerFrameState extends State<_ScannerFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final y = 18 + (_controller.value * 184);
          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: SeclusoColors.blue.withValues(alpha: 0.12),
                        blurRadius: 26,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
              for (final alignment in const [
                Alignment.topLeft,
                Alignment.topRight,
                Alignment.bottomLeft,
                Alignment.bottomRight,
              ])
                Align(
                  alignment: alignment,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.only(
                        topLeft:
                            alignment == Alignment.topLeft
                                ? const Radius.circular(22)
                                : Radius.zero,
                        topRight:
                            alignment == Alignment.topRight
                                ? const Radius.circular(22)
                                : Radius.zero,
                        bottomLeft:
                            alignment == Alignment.bottomLeft
                                ? const Radius.circular(22)
                                : Radius.zero,
                        bottomRight:
                            alignment == Alignment.bottomRight
                                ? const Radius.circular(22)
                                : Radius.zero,
                      ),
                      border: Border(
                        top:
                            alignment.y == -1
                                ? const BorderSide(
                                  color: SeclusoColors.blueSoft,
                                  width: 3,
                                )
                                : BorderSide.none,
                        bottom:
                            alignment.y == 1
                                ? const BorderSide(
                                  color: SeclusoColors.blueSoft,
                                  width: 3,
                                )
                                : BorderSide.none,
                        left:
                            alignment.x == -1
                                ? const BorderSide(
                                  color: SeclusoColors.blueSoft,
                                  width: 3,
                                )
                                : BorderSide.none,
                        right:
                            alignment.x == 1
                                ? const BorderSide(
                                  color: SeclusoColors.blueSoft,
                                  width: 3,
                                )
                                : BorderSide.none,
                      ),
                    ),
                  ),
                ),
              if (widget.showScanLine)
                Positioned(
                  left: 14,
                  right: 14,
                  top: y,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          SeclusoColors.blueSoft,
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: SeclusoColors.blue.withValues(alpha: 0.48),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BackCircle extends StatelessWidget {
  const _BackCircle({
    required this.onTap,
    required this.size,
    required this.iconSize,
    required this.fillColor,
    required this.iconColor,
  });

  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final Color fillColor;
  final Color iconColor;

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
          child: Center(child: _QrBackIcon(size: iconSize, color: iconColor)),
        ),
      ),
    );
  }
}

class _QrBackIcon extends StatelessWidget {
  const _QrBackIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _QrBackIconPainter(color)),
    );
  }
}

class _QrSecurityLockIcon extends StatelessWidget {
  const _QrSecurityLockIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _QrSecurityLockPainter(color)),
    );
  }
}

class _QrBackIconPainter extends CustomPainter {
  const _QrBackIconPainter(this.color);

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
  bool shouldRepaint(covariant _QrBackIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _QrSecurityLockPainter extends CustomPainter {
  const _QrSecurityLockPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * (0.833333 / 10);
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (1.25 / 10),
        size.height * (4.58333 / 10),
        size.width * (7.5 / 10),
        size.height * (4.58334 / 10),
      ),
      Radius.circular(size.width * (0.83333 / 10)),
    );
    canvas.drawRRect(body, stroke);

    final shackle =
        Path()
          ..moveTo(size.width * (2.91667 / 10), size.height * (4.58333 / 10))
          ..lineTo(size.width * (2.91667 / 10), size.height * (2.91667 / 10))
          ..arcToPoint(
            Offset(size.width * (7.08333 / 10), size.height * (2.91667 / 10)),
            radius: Radius.circular(size.width * (2.08333 / 10)),
            clockwise: true,
          )
          ..lineTo(size.width * (7.08333 / 10), size.height * (4.58333 / 10));
    canvas.drawPath(shackle, stroke);
  }

  @override
  bool shouldRepaint(covariant _QrSecurityLockPainter oldDelegate) =>
      oldDelegate.color != color;
}
