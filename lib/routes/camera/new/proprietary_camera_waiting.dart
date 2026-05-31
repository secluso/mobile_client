//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:io';
import 'dart:async';

import 'package:uuid/data.dart';
import 'package:uuid/uuid.dart';
import 'package:uuid/rng.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/firebase.dart';
import 'package:secluso_flutter/notifications/ios_notification_relay.dart';
import 'package:secluso_flutter/routes/camera/list_cameras.dart';
import 'package:secluso_flutter/routes/camera/camera_ui_bridge.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';
import 'package:secluso_flutter/routes/camera/new/show_new_camera_options.dart';
import 'package:secluso_flutter/routes/home_page.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/app_coordination_state.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/utilities/camera_version_info.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/proprietary_camera_hotspot.dart';
import 'package:secluso_flutter/utilities/review_environment.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/utilities/result.dart';
import 'package:secluso_flutter/notifications/notification_permissions.dart';
import 'proprietary_camera_option.dart';

class ProprietaryCameraWaitingDialog extends StatefulWidget {
  final String cameraName;
  final String wifiSsid;
  final String wifiPassword;
  final String hotspotPassword;
  final Uint8List? qrCode;
  final bool previewMode;
  final ProprietaryPairingPreviewState previewState;

  const ProprietaryCameraWaitingDialog({
    required this.cameraName,
    required this.wifiSsid,
    required this.wifiPassword,
    required this.hotspotPassword,
    this.qrCode,
    this.previewMode = false,
    this.previewState = ProprietaryPairingPreviewState.progress,
    super.key,
  });

  @override
  State<ProprietaryCameraWaitingDialog> createState() =>
      _ProprietaryCameraWaitingDialogState();
}

enum ProprietaryPairingPreviewState { progress, failure }

class _ProprietaryCameraWaitingDialogState
    extends State<ProprietaryCameraWaitingDialog> {
  static const MethodChannel _wifiChannel = MethodChannel("secluso.com/wifi");
  static const String _cameraHotspotSsid = 'Secluso';
  static const Duration _cameraReadGracePeriod = Duration(seconds: 3);
  static const Duration _networkPollInterval = Duration(seconds: 1);
  static const Duration _networkReconnectTimeout = Duration(seconds: 20);
  static const Duration _pairingRetryTimeout = Duration(seconds: 20);

  bool _timedOut = false;
  bool _pairingCompleted = false;
  String? _errorMessage;
  bool _wifiDisconnected = false;

  @override
  void initState() {
    super.initState();
    if (!widget.previewMode) {
      _startInitialPairing();
    }
  }

  @override
  void dispose() {
    unawaited(_disconnectWifiOnce());
    super.dispose();
  }

  Future<void> _disconnectWifiOnce() async {
    if (_wifiDisconnected) return;

    try {
      final result = await _wifiChannel.invokeMethod<String>(
        'disconnectFromWifi',
        <String, dynamic>{'ssid': _cameraHotspotSsid},
      );
      Log.d("WiFi disconnect result: ${result ?? '<null>'}");
      _wifiDisconnected = true;
    } catch (e) {
      Log.w("WiFi disconnect failed: $e");
    }
  }

  Future<String> _currentSsid() async {
    if (!Platform.isIOS) {
      return '';
    }

    try {
      final response = await _wifiChannel.invokeMethod<String>(
        'getCurrentSSID',
        <String, dynamic>{'ssid': _cameraHotspotSsid},
      );
      return response?.trim() ?? '';
    } catch (e) {
      Log.w("WiFi fetch SSID failed: $e");
      return '';
    }
  }

  Future<Uri?> _configuredServerUri() async {
    final prefs = await SharedPreferences.getInstance();
    final rawServerAddr = prefs.getString(PrefKeys.serverAddr);
    if (rawServerAddr == null || rawServerAddr.isEmpty) {
      Log.w('Server address is unavailable for reachability probe');
      return null;
    }

    try {
      return Uri.parse(rawServerAddr);
    } catch (e) {
      Log.w(
        'Invalid server address for reachability probe: $rawServerAddr ($e)',
      );
      return null;
    }
  }

  Uri _relayReachabilityUri() =>
      Uri.parse(Constants.iosNotificationRelayBaseUrl);

  String _summarizeUri(Uri uri) {
    final buffer =
        StringBuffer()
          ..write(uri.scheme)
          ..write('://')
          ..write(uri.host);
    if (uri.hasPort) {
      buffer.write(':${uri.port}');
    }
    return buffer.toString();
  }

  Future<bool> _probeTcpReachability(Uri uri) async {
    final port =
        uri.hasPort
            ? uri.port
            : (uri.scheme.toLowerCase() == 'https' ? 443 : 80);
    Socket? socket;
    try {
      socket = await Socket.connect(
        uri.host,
        port,
        timeout: const Duration(seconds: 3),
      );
      return true;
    } catch (e) {
      Log.d(
        'Reachability probe failed '
        '(target=${_summarizeUri(uri)}, error=$e)',
      );
      return false;
    } finally {
      socket?.destroy();
    }
  }

  Future<({bool serverReachable, bool relayReachable})>
  _probeRequiredNetworkTargets() async {
    final serverUri = await _configuredServerUri();
    final relayUri = Platform.isIOS ? _relayReachabilityUri() : null;
    final results = await Future.wait<bool>([
      serverUri == null
          ? Future<bool>.value(false)
          : _probeTcpReachability(serverUri),
      relayUri == null
          ? Future<bool>.value(true)
          : _probeTcpReachability(relayUri),
    ]);
    return (serverReachable: results[0], relayReachable: results[1]);
  }

  bool _shouldRetryNetworkRequest(Object? error) {
    if (error == null) {
      return false;
    }

    final message = error.toString();
    return message.contains('SocketException') ||
        message.contains('Network is unreachable') ||
        message.contains('Failed host lookup') ||
        message.contains('Connection refused') ||
        message.contains('timed out');
  }

  Future<String?> _iosRelayPairingBlocker() async {
    if (!Platform.isIOS) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final binding = loadStoredIosRelayBinding(prefs);
    if (!isStoredIosRelayBindingUsable(prefs: prefs, binding: binding)) {
      return 'iOS notification relay is not ready yet. Wait a few minutes and try pairing again.';
    }
    return null;
  }

  Future<void> _waitForPostPairConnectivity() async {
    final deadline = DateTime.now().add(_networkReconnectTimeout);
    var stablePolls = 0;

    while (DateTime.now().isBefore(deadline)) {
      final ssid = await _currentSsid();
      final probes = await _probeRequiredNetworkTargets();
      final onCameraHotspot = ssid == _cameraHotspotSsid;
      final hasReachability = probes.serverReachable && probes.relayReachable;

      if (!onCameraHotspot && hasReachability) {
        stablePolls += 1;
        if (stablePolls >= 2) {
          Log.d(
            'Network handoff completed after pairing '
            '(ssid=${ssid.isEmpty ? '<empty>' : ssid}, '
            'serverReachable=${probes.serverReachable}, '
            'relayReachable=${probes.relayReachable})',
          );
          return;
        }
      } else {
        stablePolls = 0;
      }

      Log.d(
        'Waiting for post-pair connectivity '
        '(ssid=${ssid.isEmpty ? '<empty>' : ssid}, '
        'onCameraHotspot=$onCameraHotspot, '
        'serverReachable=${probes.serverReachable}, '
        'relayReachable=${probes.relayReachable}, '
        'stablePolls=$stablePolls)',
      );
      await Future.delayed(_networkPollInterval);
    }

    final ssid = await _currentSsid();
    final probes = await _probeRequiredNetworkTargets();
    Log.w(
      'Timed out waiting for post-pair connectivity '
      '(ssid=${ssid.isEmpty ? '<empty>' : ssid}, '
      'serverReachable=${probes.serverReachable}, '
      'relayReachable=${probes.relayReachable})',
    );
  }

  Future<Result<String>> _waitForPairingStatusWithRetries({
    required String pairingToken,
  }) async {
    final deadline = DateTime.now().add(_pairingRetryTimeout);
    Result<String>? lastResult;
    var attempt = 0;

    while (true) {
      attempt += 1;
      lastResult = await HttpClientService.instance.waitForPairingStatus(
        pairingToken: pairingToken,
      );
      if (lastResult.isSuccess ||
          !_shouldRetryNetworkRequest(lastResult.error) ||
          DateTime.now().isAfter(deadline)) {
        return lastResult;
      }

      final probes = await _probeRequiredNetworkTargets();
      final ssid = await _currentSsid();
      Log.w(
        'Pairing status request failed during network handoff; retrying '
        '(attempt=$attempt, '
        'ssid=${ssid.isEmpty ? '<empty>' : ssid}, '
        'serverReachable=${probes.serverReachable}, '
        'relayReachable=${probes.relayReachable}, '
        'error=${lastResult.error})',
      );
      await Future.delayed(_networkPollInterval);
    }
  }

  void _startInitialPairing() async {
    Log.d(
      'Starting proprietary pairing '
      '(camera=${widget.cameraName}, wifiSsid=${widget.wifiSsid})',
    );
    setState(() {
      _errorMessage = null;
      _timedOut = false;
      _pairingCompleted = false;
    });

    try {
      var pairingToken = Uuid().v4(config: V4Options(null, CryptoRNG()));

      final hotspotReady = await ProprietaryCameraHotspot.waitUntilReady(
        cameraIp: Constants.proprietaryCameraIp,
        timeout: const Duration(seconds: 12),
        reconnectIfNeeded: Platform.isIOS,
        password: widget.hotspotPassword,
      );
      if (!hotspotReady) {
        if (!mounted) return;
        Log.w('Pairing failed before addCamera: camera hotspot not ready');
        setState(
          () =>
              _errorMessage =
                  "Lost connection to the camera hotspot. Reconnect to the camera and try again.",
        );
        return;
      }

      final versionInfoJson = await addCamera(
        widget.cameraName,
        Constants.proprietaryCameraIp,
        List<int>.from(widget.qrCode!),
        true,
        widget.wifiSsid,
        widget.wifiPassword,
        pairingToken,
      );

      Log.d('addCamera returned: $versionInfoJson');
      if (versionInfoJson.startsWith("Error")) {
        Log.w('Pairing failed: addCamera returned error ($versionInfoJson)');
        setState(
          () => _errorMessage = "Failed to send pairing data to camera.",
        );
        return;
      } else if (versionInfoJson == "PairVersionIncompatible") {
        Log.w('Pairing failed: incompatible firmware version');
        setState(() => _errorMessage = "Incompatible firmware version.");
        return;
      }
      final versionInfo = CameraVersionInfo.fromJsonString(versionInfoJson);

      // Give the camera time to read the encrypted Wi-Fi payload before
      // tearing down the phone-side hotspot association.
      Log.d(
        'Waiting $_cameraReadGracePeriod before disconnecting camera hotspot',
      );
      await Future.delayed(_cameraReadGracePeriod);

      Log.d('Disconnecting from camera hotspot after sending Wi-Fi info');
      await _disconnectWifiOnce();
      Log.d(
        'Waiting for phone network reachability after camera hotspot disconnect',
      );
      await _waitForPostPairConnectivity();

      if (!mounted) return;

      Log.d('Uploading notification target before pairing status wait');
      await PushNotificationService.tryUploadIfNeeded(true);
      final iosRelayBlocker = await _iosRelayPairingBlocker();
      if (iosRelayBlocker != null) {
        if (!mounted) return;
        Log.w('Pairing failed: iOS relay blocker ($iosRelayBlocker)');
        setState(() => _errorMessage = iosRelayBlocker);
        return;
      }

      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PrefKeys.lastCameraAdd, widget.cameraName);
      final status = await _waitForPairingStatusWithRetries(
        pairingToken: pairingToken,
      );

      Log.d("Returned status: $status");

      if (!mounted) return;

      if (status.isSuccess && status.value! == "paired") {
        Log.d('Pairing confirmed by relay');
        _onPairingConfirmed(versionInfo);
      } else {
        Log.w('Pairing failed: relay status did not confirm paired ($status)');
        setState(() => _timedOut = true);
      }

      // Backup
      Future.delayed(const Duration(seconds: 45), () {
        if (mounted && !_pairingCompleted) {
          Log.w('Pairing failed: backup timeout fired after 45s');
          setState(() => _timedOut = true);
        }
      });
    } catch (e) {
      Log.w('Pairing failed with unexpected exception: $e');
      setState(() => _errorMessage = "Unexpected error: $e");
    }
  }

  void _onPairingConfirmed(CameraVersionInfo versionInfo) async {
    if (!mounted || _pairingCompleted) return;
    // TODO: should these two lines go before the mounted check? what happens if this occurs?

    ProprietaryCameraConnectDialog.pairingCompleted =
        true; // So we don't attempt a WiFi disconnect when we pop()
    ProprietaryCameraConnectDialog.pairingInProgress = false;

    Log.d("Entered method");
    _pairingCompleted = true;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool("first_time_${widget.cameraName}", true);
    prefs.remove(PrefKeys.lastCameraAdd);

    final existingSet = await AppCoordinationState.getCameraSet();
    final wasFirstCamera = existingSet.isEmpty;
    if (await AppCoordinationState.addCamera(widget.cameraName)) {
      await prefs.setInt(
        PrefKeys.numIgnoredHeartbeatsPrefix + widget.cameraName,
        0,
      );
      await prefs.setInt(
        PrefKeys.cameraStatusPrefix + widget.cameraName,
        CameraStatus.online,
      );
      await prefs.setInt(
        PrefKeys.numHeartbeatNotificationsPrefix + widget.cameraName,
        0,
      );
      await prefs.setInt(
        PrefKeys.lastHeartbeatTimestampPrefix + widget.cameraName,
        0,
      );
      await prefs.setString(
        PrefKeys.firmwareVersionPrefix + widget.cameraName,
        versionInfo.firmwareVersion,
      );
      await prefs.setString(
        PrefKeys.cameraOsVersionPrefix + widget.cameraName,
        versionInfo.osVersion,
      );
    }

    final camera = Camera(widget.cameraName);
    await AppStores.instance.cameraStore.put(camera);

    CameraListNotifier.instance.refreshCallback?.call();

    if (!mounted) return;

    if (wasFirstCamera) {
      await requestNotificationsAfterFirstCameraAdd();
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder:
            (_) => ProprietaryCameraPairedPage(cameraName: widget.cameraName),
      ),
      (route) => route.isFirst,
    );
  }

  void _onRetry() async {
    var cameraName = widget.cameraName;

    // We don't know for sure if they'll try again or not.
    await _disconnectWifiOnce();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await deregisterCamera(cameraName: cameraName);
    invalidateCameraInit(cameraName);
    HttpClientService.instance.clearGroupNameCache(cameraName);
    prefs.remove(PrefKeys.lastCameraAdd);

    final camDir = await AppPaths.cameraDirectory(cameraName);
    if (await camDir.exists()) {
      try {
        await camDir.delete(recursive: true);
        Log.d('Deleted camera folder: ${camDir.path}');
      } catch (e) {
        Log.e('Error deleting folder: $e');
      }
    }

    if (!mounted) return;
    int count = 0;
    Navigator.popUntil(context, (route) {
      count++;
      return count == 3;
    });
  }

  void _onBackHome() {
    if (widget.previewMode) {
      Navigator.of(context).maybePop();
      return;
    }

    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (widget.previewMode &&
        widget.previewState == ProprietaryPairingPreviewState.failure) {
      return _ProprietaryCameraFailurePage(
        dark: dark,
        onRetry: () {},
        onBackHome: () => Navigator.of(context).maybePop(),
      );
    }

    if (_errorMessage == null && !_timedOut) {
      return _ProprietaryCameraPairingPage(
        dark: dark,
        progress: dark ? 0.69 : 0.66,
        statusText: 'Sending configuration to camera...',
      );
    }

    return _ProprietaryCameraFailurePage(
      dark: dark,
      onRetry: _onRetry,
      onBackHome: _onBackHome,
    );
  }
}

class _ProprietaryCameraFailurePage extends StatelessWidget {
  const _ProprietaryCameraFailurePage({
    required this.dark,
    required this.onRetry,
    required this.onBackHome,
  });

  final bool dark;
  final VoidCallback onRetry;
  final VoidCallback onBackHome;

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7);
    final titleColor = dark ? Colors.white : const Color(0xFF111827);
    final bodyColor =
        dark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF6B7280);
    final cardColor =
        dark ? Colors.white.withValues(alpha: 0.03) : Colors.white;
    final cardBorderColor =
        dark ? Colors.white.withValues(alpha: 0.05) : const Color(0x0A000000);
    final sectionLabelColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final bulletColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final bulletTextColor =
        dark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF4B5563);
    final primaryFill = dark ? Colors.white : const Color(0xFF0A0A0A);
    final primaryText = dark ? const Color(0xFF050505) : Colors.white;
    final secondaryText =
        dark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF6B7280);
    final footerColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFD1D5DB);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = math.min(
              constraints.maxWidth / 290,
              constraints.maxHeight / 652,
            );
            double scaled(double value) => value * scale;

            return Center(
              child: SizedBox(
                width: scaled(290),
                height: scaled(652),
                child: Stack(
                  children: [
                    Positioned(
                      left: scaled(105),
                      top: scaled(56),
                      width: scaled(80),
                      height: scaled(80),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0x33EF4444),
                            width: scaled(2),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: scaled(117),
                      top: scaled(68),
                      width: scaled(56),
                      height: scaled(56),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0x66EF4444),
                              blurRadius: scaled(24),
                            ),
                          ],
                        ),
                        child: Center(
                          child: SizedBox(
                            width: scaled(22),
                            height: scaled(22),
                            child: const CustomPaint(
                              painter: _PairingFailureCrossPainter(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: scaled(159.5),
                      child: Center(
                        child: SizedBox(
                          width: scaled(130.495),
                          child: Text(
                            'Pairing Failed',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: titleColor,
                              fontSize: scaled(20),
                              fontWeight: FontWeight.w600,
                              height: 30 / 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: scaled(200.5),
                      child: Center(
                        child: SizedBox(
                          width: scaled(226.14),
                          child: Text(
                            "We couldn't complete the connection to\nyour camera.",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: bodyColor,
                              fontSize: scaled(12),
                              fontWeight: FontWeight.w400,
                              height: 19.5 / 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: scaled(24),
                      top: scaled(261),
                      width: scaled(242),
                      height: scaled(198.25),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(scaled(12)),
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
                              left: scaled(16),
                              top: scaled(16),
                              child: Text(
                                'POSSIBLE CAUSES',
                                style: GoogleFonts.inter(
                                  color: sectionLabelColor,
                                  fontSize: scaled(10),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: scaled(1),
                                  height: 15 / 10,
                                ),
                              ),
                            ),
                            _PairingFailureBullet(
                              scale: scale,
                              bulletColor: bulletColor,
                              textColor: bulletTextColor,
                              bulletTop: 49,
                              textTop: 45,
                              textWidth: 187.54,
                              text: 'Camera may have lost power during\nsetup',
                            ),
                            _PairingFailureBullet(
                              scale: scale,
                              bulletColor: bulletColor,
                              textColor: bulletTextColor,
                              bulletTop: 94.75,
                              textTop: 88.75,
                              textWidth: 174.187,
                              text: 'WiFi credentials may be incorrect',
                            ),
                            _PairingFailureBullet(
                              scale: scale,
                              bulletColor: bulletColor,
                              textColor: bulletTextColor,
                              bulletTop: 122.63,
                              textTop: 118.63,
                              textWidth: 159.96,
                              text: 'Camera firmware may need an\nupdate',
                            ),
                            _PairingFailureBullet(
                              scale: scale,
                              bulletColor: bulletColor,
                              textColor: bulletTextColor,
                              bulletTop: 168.38,
                              textTop: 162.38,
                              textWidth: 146.437,
                              text: 'Relay may have gone offline',
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: scaled(24),
                      top: scaled(491.25),
                      width: scaled(242),
                      height: scaled(46),
                      child: FilledButton(
                        onPressed: onRetry,
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryFill,
                          foregroundColor: primaryText,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(scaled(12)),
                          ),
                          padding: EdgeInsets.zero,
                          textStyle: GoogleFonts.inter(
                            fontSize: scaled(12),
                            fontWeight: FontWeight.w600,
                            letterSpacing: scaled(0.6),
                            height: 18 / 12,
                          ),
                        ),
                        child: const Text('TRY AGAIN'),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: scaled(549.25),
                      child: Center(
                        child: TextButton(
                          onPressed: onBackHome,
                          style: TextButton.styleFrom(
                            foregroundColor: secondaryText,
                            padding: EdgeInsets.symmetric(
                              horizontal: scaled(8),
                              vertical: scaled(8),
                            ),
                            textStyle: GoogleFonts.inter(
                              fontSize: scaled(11),
                              fontWeight: FontWeight.w500,
                              height: 16.5 / 11,
                            ),
                          ),
                          child: const Text('Back to Home'),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: scaled(606.5),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: scaled(10),
                              height: scaled(10),
                              child: CustomPaint(
                                painter: _PairingFooterLockPainter(footerColor),
                              ),
                            ),
                            SizedBox(width: scaled(8)),
                            Text(
                              'No credentials were stored remotely',
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
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PairingFailureBullet extends StatelessWidget {
  const _PairingFailureBullet({
    required this.scale,
    required this.bulletColor,
    required this.textColor,
    required this.bulletTop,
    required this.textTop,
    required this.textWidth,
    required this.text,
  });

  final double scale;
  final Color bulletColor;
  final Color textColor;
  final double bulletTop;
  final double textTop;
  final double textWidth;
  final String text;

  @override
  Widget build(BuildContext context) {
    double scaled(double value) => value * scale;

    return Stack(
      children: [
        Positioned(
          left: scaled(16),
          top: scaled(bulletTop),
          child: Container(
            width: scaled(4),
            height: scaled(4),
            decoration: BoxDecoration(
              color: bulletColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          left: scaled(30),
          top: scaled(textTop),
          width: scaled(textWidth),
          child: Text(
            text,
            style: GoogleFonts.inter(
              color: textColor,
              fontSize: scaled(11),
              fontWeight: FontWeight.w400,
              height: 17.88 / 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProprietaryCameraPairingPage extends StatefulWidget {
  const _ProprietaryCameraPairingPage({
    required this.dark,
    required this.progress,
    required this.statusText,
  });

  final bool dark;
  final double progress;
  final String statusText;

  @override
  State<_ProprietaryCameraPairingPage> createState() =>
      _ProprietaryCameraPairingPageState();
}

class _ProprietaryCameraPairingPageState
    extends State<_ProprietaryCameraPairingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final backgroundColor =
        dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7);
    final titleColor = dark ? Colors.white : const Color(0xFF111827);
    final subtitleColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final primaryStepColor = dark ? Colors.white : const Color(0xFF111827);
    final secondaryStepColor =
        dark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF4B5563);
    final tertiaryStepColor =
        dark ? Colors.white.withValues(alpha: 0.28) : const Color(0xFF6B7280);
    final footerColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFD1D5DB);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = math.min(
              constraints.maxWidth / 290,
              constraints.maxHeight / 652,
            );
            double scaled(double value) => value * scale;
            final canvasWidth = scaled(290);
            final canvasHeight = scaled(652);

            return Center(
              child: SizedBox(
                width: canvasWidth,
                height: canvasHeight,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final overallProgress = _controller.value.clamp(0.0, 1.0);
                    final progressLabel = '${(overallProgress * 100).round()}%';
                    final firstStepProgress = (overallProgress / (1 / 3)).clamp(
                      0.0,
                      1.0,
                    );
                    final secondStepProgress =
                        ((overallProgress - (1 / 3)) / (1 / 3)).clamp(0.0, 1.0);
                    final haloOpacity = dark ? 1.0 : 0.85;

                    _PairingStepState stateForStep(int index) {
                      final start = index / 3;
                      final end = (index + 1) / 3;
                      if (overallProgress >= end) {
                        return _PairingStepState.complete;
                      }
                      if (overallProgress >= start) {
                        return _PairingStepState.active;
                      }
                      return _PairingStepState.pending;
                    }

                    final firstState = stateForStep(0);
                    final secondState = stateForStep(1);
                    final thirdState = stateForStep(2);

                    Color titleColorFor(_PairingStepState state) {
                      switch (state) {
                        case _PairingStepState.complete:
                          return secondaryStepColor;
                        case _PairingStepState.active:
                          return primaryStepColor;
                        case _PairingStepState.pending:
                          return tertiaryStepColor;
                      }
                    }

                    Color subtitleColorFor(_PairingStepState state) {
                      switch (state) {
                        case _PairingStepState.complete:
                          return subtitleColor;
                        case _PairingStepState.active:
                          return tertiaryStepColor;
                        case _PairingStepState.pending:
                          return subtitleColor;
                      }
                    }

                    return Stack(
                      children: [
                        if (!dark)
                          Positioned(
                            left: scaled(17),
                            top: scaled(35),
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: haloOpacity,
                                child: Container(
                                  width: scaled(256),
                                  height: scaled(256),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        Color(0x26B45309),
                                        Color(0x00B45309),
                                      ],
                                      stops: [0.0, 0.7],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: scaled(56),
                          child: Center(
                            child: SizedBox(
                              width: scaled(111.26),
                              child: Text(
                                'Pairing Camera',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: titleColor,
                                  fontSize: scaled(15),
                                  fontWeight: FontWeight.w600,
                                  height: 22.5 / 15,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: scaled(82.5),
                          child: Center(
                            child: SizedBox(
                              width: scaled(63.923),
                              child: Text(
                                'STEP 3 OF 3',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: subtitleColor,
                                  fontSize: scaled(9),
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: scaled(0.9),
                                  height: 13.5 / 9,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: scaled(102),
                          child: Center(
                            child: Container(
                              width: scaled(8),
                              height: scaled(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8BB3EE),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0x99B45309),
                                    blurRadius: scaled(8),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: scaled(65),
                          top: scaled(104),
                          width: scaled(160),
                          height: scaled(160),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color:
                                          dark
                                              ? Colors.white.withValues(
                                                alpha: 0.03,
                                              )
                                              : Colors.white,
                                      width: scaled(1.1),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _PairingProgressRingPainter(
                                    progress: overallProgress,
                                    dark: dark,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: scaled(56),
                                top: scaled(35.5),
                                child: Container(
                                  width: scaled(48),
                                  height: scaled(48),
                                  decoration: BoxDecoration(
                                    color: const Color(0x338DB4EE),
                                    borderRadius: BorderRadius.circular(
                                      scaled(16),
                                    ),
                                    border: Border.all(
                                      color: const Color(0x4C8CB3EE),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0x66B45309),
                                        blurRadius: scaled(14),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: SizedBox(
                                      width: scaled(20),
                                      height: scaled(20),
                                      child: CustomPaint(
                                        painter: _PairingLockGlyphPainter(
                                          const Color(0xFF8BB3EE),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: scaled(55),
                                top: scaled(94.5),
                                width: scaled(50.343),
                                child: Text(
                                  progressLabel,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    color: titleColor,
                                    fontSize: scaled(22),
                                    fontWeight: FontWeight.w700,
                                    height: 33 / 22,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: scaled(39),
                          top: scaled(298),
                          child: _PairingProgressStep(
                            scale: scale,
                            title: 'Encrypted channel',
                            subtitle:
                                firstState == _PairingStepState.complete
                                    ? 'Complete'
                                    : firstState == _PairingStepState.active
                                    ? 'Establishing secure link'
                                    : 'Waiting',
                            state: firstState,
                            dark: dark,
                            titleColor: titleColorFor(firstState),
                            subtitleColor: subtitleColorFor(firstState),
                            connectorProgress: firstStepProgress,
                          ),
                        ),
                        Positioned(
                          left: scaled(39),
                          top: scaled(353),
                          child: _PairingProgressStep(
                            scale: scale,
                            title: 'Key exchange',
                            subtitle:
                                secondState == _PairingStepState.complete
                                    ? 'Complete'
                                    : secondState == _PairingStepState.active
                                    ? 'Exchanging keys'
                                    : 'Waiting',
                            state: secondState,
                            dark: dark,
                            titleColor: titleColorFor(secondState),
                            subtitleColor: subtitleColorFor(secondState),
                            connectorProgress: secondStepProgress,
                          ),
                        ),
                        Positioned(
                          left: scaled(39),
                          top: scaled(408),
                          child: _PairingProgressStep(
                            scale: scale,
                            title: 'Camera config',
                            subtitle:
                                thirdState == _PairingStepState.complete
                                    ? 'Complete'
                                    : thirdState == _PairingStepState.active
                                    ? 'Applying your settings'
                                    : 'Waiting',
                            state: thirdState,
                            dark: dark,
                            titleColor: titleColorFor(thirdState),
                            subtitleColor: subtitleColorFor(thirdState),
                            showConnector: false,
                          ),
                        ),
                        Positioned(
                          left: scaled(53.42),
                          top: scaled(485.75),
                          child: SizedBox(
                            width: scaled(12),
                            height: scaled(12),
                            child: const CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFF8BB3EE),
                            ),
                          ),
                        ),
                        Positioned(
                          left: scaled(73.42),
                          top: scaled(484.75),
                          child: SizedBox(
                            width: scaled(163.494),
                            child: Text(
                              widget.statusText,
                              style: GoogleFonts.inter(
                                color: tertiaryStepColor,
                                fontSize: scaled(10),
                                fontWeight: FontWeight.w400,
                                height: 15 / 10,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: scaled(73),
                          top: scaled(606.5),
                          child: Row(
                            children: [
                              SizedBox(
                                width: scaled(10),
                                height: scaled(10),
                                child: CustomPaint(
                                  painter: _PairingFooterLockPainter(
                                    footerColor,
                                  ),
                                ),
                              ),
                              SizedBox(width: scaled(8)),
                              Text(
                                'End-to-end encrypted pairing',
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
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _PairingStepState { pending, active, complete }

class _PairingProgressStep extends StatelessWidget {
  const _PairingProgressStep({
    required this.scale,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.dark,
    required this.titleColor,
    required this.subtitleColor,
    this.connectorProgress = 0,
    this.showConnector = true,
  });

  final double scale;
  final String title;
  final String subtitle;
  final _PairingStepState state;
  final bool dark;
  final Color titleColor;
  final Color subtitleColor;
  final double connectorProgress;
  final bool showConnector;

  @override
  Widget build(BuildContext context) {
    double scaled(double value) => value * scale;
    final connectorTrackColor =
        dark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.06);
    final connectorFillColor =
        state == _PairingStepState.complete
            ? const Color(0x4D10B981)
            : state == _PairingStepState.active
            ? const Color(0x4D8BB3EE)
            : Colors.transparent;

    return SizedBox(
      width: scaled(184),
      height: scaled(55),
      child: Stack(
        children: [
          if (showConnector)
            Positioned(
              left: scaled(11.25),
              top: scaled(24),
              child: Stack(
                children: [
                  Container(
                    width: scaled(1.5),
                    height: scaled(31),
                    color: connectorTrackColor,
                  ),
                  Container(
                    width: scaled(1.5),
                    height: scaled(31) * connectorProgress.clamp(0.0, 1.0),
                    color: connectorFillColor,
                  ),
                ],
              ),
            ),
          Positioned(
            left: 0,
            top: 0,
            child: _PairingStepBadge(scale: scale, state: state, dark: dark),
          ),
          Positioned(
            left: scaled(37),
            top: scaled(0.5),
            child: Text(
              title,
              style: GoogleFonts.inter(
                color: titleColor,
                fontSize: scaled(12),
                fontWeight:
                    state == _PairingStepState.active
                        ? FontWeight.w500
                        : FontWeight.w500,
                height: 15 / 12,
              ),
            ),
          ),
          Positioned(
            left: scaled(37),
            top: scaled(22.5),
            child: Text(
              subtitle,
              style: GoogleFonts.inter(
                color: subtitleColor,
                fontSize: scaled(10),
                fontWeight: FontWeight.w400,
                height: 13.75 / 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingStepBadge extends StatelessWidget {
  const _PairingStepBadge({
    required this.scale,
    required this.state,
    required this.dark,
  });

  final double scale;
  final _PairingStepState state;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    double scaled(double value) => value * scale;
    if (state == _PairingStepState.complete) {
      return Container(
        width: scaled(24),
        height: scaled(24),
        decoration: BoxDecoration(
          color: const Color(0x2610B981),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x4D10B981)),
        ),
        child: Center(
          child: SizedBox(
            width: scaled(10),
            height: scaled(10),
            child: const CustomPaint(painter: _PairingStepCheckPainter()),
          ),
        ),
      );
    }
    if (state == _PairingStepState.pending) {
      return Container(
        width: scaled(24),
        height: scaled(24),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color:
                dark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.10),
            width: scaled(2),
          ),
        ),
        child: Center(
          child: Container(
            width: scaled(8),
            height: scaled(8),
            decoration: BoxDecoration(
              color:
                  dark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }
    return Container(
      width: scaled(24),
      height: scaled(24),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x808BB3EE), width: scaled(2)),
      ),
      child: Center(
        child: Container(
          width: scaled(10),
          height: scaled(10),
          decoration: const BoxDecoration(
            color: Color(0xFF8BB3EE),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _PairingProgressRingPainter extends CustomPainter {
  const _PairingProgressRingPainter({
    required this.progress,
    required this.dark,
  });

  final double progress;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final trackRadius = size.width * (62 / 160);
    final trackStroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = size.width * (4 / 160)
          ..color =
              dark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06);
    canvas.drawCircle(center, trackRadius, trackStroke);

    final progressRadius = size.width * (62 / 160);
    final progressStroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = size.width * (3.5 / 160)
          ..color = const Color(0xFFB45309);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: progressRadius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressStroke,
    );
  }

  @override
  bool shouldRepaint(covariant _PairingProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.dark != dark;
}

class _PairingLockGlyphPainter extends CustomPainter {
  const _PairingLockGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.2 / 20)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (4.2 / 20),
        size.height * (8.2 / 20),
        size.width * (11.6 / 20),
        size.height * (8.2 / 20),
      ),
      Radius.circular(size.width * (1.4 / 20)),
    );
    canvas.drawRRect(body, stroke);
    final shackle =
        Path()
          ..moveTo(size.width * (6.5 / 20), size.height * (8.2 / 20))
          ..lineTo(size.width * (6.5 / 20), size.height * (5.3 / 20))
          ..arcToPoint(
            Offset(size.width * (13.5 / 20), size.height * (5.3 / 20)),
            radius: Radius.circular(size.width * (3.8 / 20)),
          )
          ..lineTo(size.width * (13.5 / 20), size.height * (8.2 / 20));
    canvas.drawPath(shackle, stroke);
  }

  @override
  bool shouldRepaint(covariant _PairingLockGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _PairingStepCheckPainter extends CustomPainter {
  const _PairingStepCheckPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.6 / 10)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF10B981);
    final path =
        Path()
          ..moveTo(size.width * (2.0 / 10), size.height * (5.2 / 10))
          ..lineTo(size.width * (4.3 / 10), size.height * (7.3 / 10))
          ..lineTo(size.width * (8.0 / 10), size.height * (2.7 / 10));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PairingFailureCrossPainter extends CustomPainter {
  const _PairingFailureCrossPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (2 / 22)
          ..strokeCap = StrokeCap.round
          ..color = Colors.white;
    canvas.drawLine(
      Offset(size.width * (6.2 / 22), size.height * (6.2 / 22)),
      Offset(size.width * (15.8 / 22), size.height * (15.8 / 22)),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * (15.8 / 22), size.height * (6.2 / 22)),
      Offset(size.width * (6.2 / 22), size.height * (15.8 / 22)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PairingFooterLockPainter extends CustomPainter {
  const _PairingFooterLockPainter(this.color);

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
  bool shouldRepaint(covariant _PairingFooterLockPainter oldDelegate) =>
      oldDelegate.color != color;
}

class ProprietaryCameraPairedPage extends StatelessWidget {
  const ProprietaryCameraPairedPage({
    super.key,
    required this.cameraName,
    this.onGoHome,
    this.onAddAnotherCamera,
  });

  final String cameraName;
  final VoidCallback? onGoHome;
  final VoidCallback? onAddAnotherCamera;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    void defaultGoHome() {
      rootNavigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
        (route) => false,
      );
    }

    void defaultAddAnotherCamera() {
      rootNavigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const ShowNewCameraOptions()),
        (route) => route.isFirst,
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor:
            dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = math.min(
                constraints.maxWidth / 290,
                constraints.maxHeight / 652,
              );
              double scaled(double value) => value * scale;
              final titleColor = dark ? Colors.white : const Color(0xFF111827);
              final bodyColor =
                  dark
                      ? Colors.white.withValues(alpha: 0.4)
                      : const Color(0xFF6B7280);
              final cardColor =
                  dark ? Colors.white.withValues(alpha: 0.03) : Colors.white;
              final cardBorderColor =
                  dark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0x0A000000);
              final rowDividerColor =
                  dark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFE5E7EB);
              final primaryButtonFill =
                  dark ? Colors.white : const Color(0xFF0A0A0A);
              final primaryButtonText =
                  dark ? const Color(0xFF050505) : Colors.white;
              final secondaryButtonText =
                  dark
                      ? Colors.white.withValues(alpha: 0.4)
                      : const Color(0xFF6B7280);

              return Padding(
                padding: EdgeInsets.fromLTRB(
                  scaled(24),
                  scaled(56),
                  scaled(24),
                  scaled(24),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: scaled(80),
                      height: scaled(80),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: scaled(80),
                            height: scaled(80),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0x4D10B981),
                                width: scaled(2),
                              ),
                            ),
                          ),
                          Container(
                            width: scaled(64),
                            height: scaled(64),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0x3310B981),
                                width: scaled(2),
                              ),
                            ),
                          ),
                          Container(
                            width: scaled(56),
                            height: scaled(56),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x6622C55E),
                                  blurRadius: 24,
                                ),
                              ],
                            ),
                            child: Center(
                              child: SizedBox(
                                width: scaled(24),
                                height: scaled(24),
                                child: const CustomPaint(
                                  painter: _PairedCheckPainter(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: scaled(32)),
                    Text(
                      'Camera Paired',
                      style: GoogleFonts.inter(
                        color: titleColor,
                        fontSize: scaled(20),
                        fontWeight: FontWeight.w600,
                        height: 30 / 20,
                      ),
                    ),
                    SizedBox(height: scaled(12)),
                    SizedBox(
                      width: scaled(228),
                      child: Text(
                        'Your camera is now securely connected\nto your relay.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: bodyColor,
                          fontSize: scaled(12),
                          fontWeight: FontWeight.w400,
                          height: 19.5 / 12,
                        ),
                      ),
                    ),
                    SizedBox(height: scaled(32)),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(scaled(12)),
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
                      child: Column(
                        children: [
                          _PairedInfoRow(
                            label: 'Camera',
                            value: cameraName,
                            scale: scale,
                            dark: dark,
                            dividerColor: rowDividerColor,
                            valueColor:
                                dark ? Colors.white : const Color(0xFF111827),
                          ),
                          _PairedInfoRow(
                            label: 'Status',
                            value: 'Connected',
                            valueColor: const Color(0xFF10B981),
                            leadingValue: Container(
                              width: scaled(6),
                              height: scaled(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            scale: scale,
                            dark: dark,
                            dividerColor: rowDividerColor,
                          ),
                          _PairedInfoRow(
                            label: 'Encryption',
                            value: 'E2EE Active',
                            leadingValue: SizedBox(
                              width: scaled(10),
                              height: scaled(10),
                              child: CustomPaint(
                                painter: _PairedLockPainter(
                                  dark
                                      ? const Color(0xFF8BB3EE)
                                      : const Color(0xFF8BB3EE),
                                ),
                              ),
                            ),
                            scale: scale,
                            dark: dark,
                            dividerColor: rowDividerColor,
                            valueColor:
                                dark ? Colors.white : const Color(0xFF111827),
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: scaled(32)),
                    SizedBox(
                      width: double.infinity,
                      height: scaled(46),
                      child: FilledButton(
                        onPressed: onGoHome ?? defaultGoHome,
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryButtonFill,
                          foregroundColor: primaryButtonText,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(scaled(12)),
                          ),
                          textStyle: GoogleFonts.inter(
                            fontSize: scaled(12),
                            fontWeight: FontWeight.w600,
                            letterSpacing: scaled(0.6),
                            height: 14.5 / 12,
                          ),
                        ),
                        child: const Text('GO TO HOME'),
                      ),
                    ),
                    SizedBox(height: scaled(12)),
                    TextButton(
                      onPressed: onAddAnotherCamera ?? defaultAddAnotherCamera,
                      style: TextButton.styleFrom(
                        foregroundColor: secondaryButtonText,
                        textStyle: GoogleFonts.inter(
                          fontSize: scaled(11),
                          fontWeight: FontWeight.w500,
                          height: 16.5 / 11,
                        ),
                      ),
                      child: const Text('Add Another Camera'),
                    ),
                    const Spacer(),
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

class ReviewCameraPairingFlowPage extends StatefulWidget {
  const ReviewCameraPairingFlowPage({super.key, required this.reviewPayload});

  final ReviewCameraQrPayload reviewPayload;

  @override
  State<ReviewCameraPairingFlowPage> createState() =>
      _ReviewCameraPairingFlowPageState();
}

class _ReviewCameraPairingFlowPageState
    extends State<ReviewCameraPairingFlowPage> {
  String _statusText = 'Validating App Review camera QR...';
  String? _errorMessage;
  bool _pairingCompleted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_runPairingFlow());
  }

  Future<void> _runPairingFlow() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() {
      _statusText = 'Establishing secure pairing...';
    });

    await Future<void>.delayed(const Duration(milliseconds: 950));
    if (!mounted) return;
    if (!ReviewEnvironment.instance.isActive) {
      setState(() {
        _errorMessage =
            'Scan the App Review relay QR before pairing the review camera.';
      });
      return;
    }

    setState(() {
      _statusText = 'Finalizing camera setup...';
    });

    final added = await ReviewEnvironment.instance.addCamera(
      widget.reviewPayload,
    );
    if (!mounted) return;
    if (!added) {
      setState(() {
        _errorMessage =
            'That App Review camera is already paired on this install.';
      });
      return;
    }

    CameraListNotifier.instance.refreshCallback?.call();
    CameraUiBridge.refreshActivityCallback?.call();

    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() {
      _pairingCompleted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_pairingCompleted) {
      return ProprietaryCameraPairedPage(
        cameraName: widget.reviewPayload.cameraName,
      );
    }
    if (_errorMessage != null) {
      return _ReviewCameraPairingErrorPage(
        message: _errorMessage!,
        onBack: () => Navigator.of(context).maybePop(),
      );
    }
    return _ProprietaryCameraPairingPage(
      dark: dark,
      progress: dark ? 0.69 : 0.66,
      statusText: _statusText,
    );
  }
}

class _ReviewCameraPairingErrorPage extends StatelessWidget {
  const _ReviewCameraPairingErrorPage({
    required this.message,
    required this.onBack,
  });

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = dark ? Colors.white : const Color(0xFF111827);
    final bodyColor =
        dark ? Colors.white.withValues(alpha: 0.46) : const Color(0xFF6B7280);
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.32),
                    ),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFFEF4444),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Camera Pairing Unavailable',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: titleColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: bodyColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: onBack,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        dark ? Colors.white : const Color(0xFF0A0A0A),
                    foregroundColor:
                        dark ? const Color(0xFF050505) : Colors.white,
                    minimumSize: const Size(180, 46),
                  ),
                  child: const Text('BACK'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PairedInfoRow extends StatelessWidget {
  const _PairedInfoRow({
    required this.label,
    required this.value,
    required this.scale,
    required this.dark,
    required this.dividerColor,
    this.leadingValue,
    this.valueColor = const Color(0xFF111827),
    this.showDivider = true,
  });

  final String label;
  final String value;
  final double scale;
  final bool dark;
  final Color dividerColor;
  final Widget? leadingValue;
  final Color valueColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    double scaled(double value) => value * scale;

    return Container(
      height: scaled(47),
      decoration: BoxDecoration(
        border:
            showDivider
                ? Border(bottom: BorderSide(color: dividerColor))
                : null,
      ),
      padding: EdgeInsets.symmetric(horizontal: scaled(14)),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color:
                  dark
                      ? Colors.white.withValues(alpha: 0.4)
                      : const Color(0xFF6B7280),
              fontSize: scaled(11),
              fontWeight: FontWeight.w400,
              height: 16.5 / 11,
            ),
          ),
          const Spacer(),
          if (leadingValue != null) ...[
            leadingValue!,
            SizedBox(width: scaled(6)),
          ],
          Text(
            value,
            style: GoogleFonts.inter(
              color: valueColor,
              fontSize: scaled(12),
              fontWeight: FontWeight.w500,
              height: 18 / 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PairedCheckPainter extends CustomPainter {
  const _PairedCheckPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (2.5 / 24)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white;
    final path =
        Path()
          ..moveTo(size.width * (5.2 / 24), size.height * (12.5 / 24))
          ..lineTo(size.width * (10.0 / 24), size.height * (17.0 / 24))
          ..lineTo(size.width * (18.8 / 24), size.height * (7.2 / 24));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PairedLockPainter extends CustomPainter {
  const _PairedLockPainter(this.color);

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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
