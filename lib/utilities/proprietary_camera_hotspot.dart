//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/utilities/camera_proxy.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';

class ProprietaryCameraHotspot {
  static const MethodChannel _wifiChannel = MethodChannel("secluso.com/wifi");
  static const String ssid = 'Secluso';
  // connect() is destructive on iOS
  // iOS needs ~10-15s to bring the route up
  static const Duration _reconnectThrottle = Duration(seconds: 15);

  static Future<String?> connect(String password) {
    return _wifiChannel.invokeMethod<String>('connectToWifi', <String, dynamic>{
      'ssid': ssid,
      'password': password,
    });
  }

  static Future<String> currentSsid() async {
    if (!Platform.isIOS) {
      return '';
    }

    try {
      final response = await _wifiChannel.invokeMethod<String>(
        'getCurrentSSID',
        <String, dynamic>{'ssid': ssid},
      );
      return response?.trim() ?? '';
    } catch (e) {
      Log.w("WiFi fetch SSID failed: $e");
      return '';
    }
  }

  static Future<bool> probeReachability({
    String cameraIp = Constants.proprietaryCameraIp,
  }) async {
    try {
      // probe on iOS via Network.framework, which honors the Local Network grant and Wi-Fi.
      if (Platform.isIOS) {
        return await CameraProxyBridge.probe();
      }
      return await pingProprietaryDevice(cameraIp: cameraIp);
    } catch (e) {
      Log.w("Camera hotspot probe failed: $e");
      return false;
    }
  }

  static Future<bool> waitUntilReady({
    String cameraIp = Constants.proprietaryCameraIp,
    Duration timeout = const Duration(seconds: 20),
    Duration pollInterval = const Duration(seconds: 1),
    bool reconnectIfNeeded = false,
    int requiredStablePolls = 1,
    Duration settleDelay = const Duration(milliseconds: 250),
    required String password,
  }) async {
    final deadline = DateTime.now().add(timeout);
    // Seed the reconnect clock to now() so the first poll doesn't immediately tear down the connection connect() just established
    DateTime? lastReconnectAttempt = DateTime.now();
    var stablePolls = 0;

    while (DateTime.now().isBefore(deadline)) {
      final ssidValue = await currentSsid();
      final onHotspot = !Platform.isIOS || ssidValue == ssid;
      final reachable = await probeReachability(cameraIp: cameraIp);

      if (reachable) {
        stablePolls += 1;
        if (stablePolls >= requiredStablePolls) {
          if (settleDelay > Duration.zero) {
            await Future.delayed(settleDelay);
          }
          Log.d(
            'Camera hotspot is ready '
            '(ssid=${ssidValue.isEmpty ? '<empty>' : ssidValue}, '
            'reachable=$reachable, stablePolls=$stablePolls)',
          );
          return true;
        }
      } else {
        stablePolls = 0;
      }

      if (Platform.isIOS &&
          reconnectIfNeeded &&
          !reachable &&
          !onHotspot &&
          (lastReconnectAttempt == null ||
              DateTime.now().difference(lastReconnectAttempt) >=
                  _reconnectThrottle)) {
        lastReconnectAttempt = DateTime.now();
        try {
          final reconnectResult = await connect(password);
          Log.d(
            'Camera hotspot reconnect attempt '
            '(result=${reconnectResult ?? '<null>'}, '
            'ssid=${ssidValue.isEmpty ? '<empty>' : ssidValue})',
          );
        } on PlatformException catch (e) {
          Log.w("Camera hotspot reconnect failed: $e");
        }
      }

      Log.d(
        'Waiting for camera hotspot readiness '
        '(ssid=${ssidValue.isEmpty ? '<empty>' : ssidValue}, '
        'onHotspot=$onHotspot, reachable=$reachable, stablePolls=$stablePolls)',
      );
      await Future.delayed(pollInterval);
    }

    final ssidValue = await currentSsid();
    final reachable = await probeReachability(cameraIp: cameraIp);
    Log.w(
      'Timed out waiting for camera hotspot readiness '
      '(ssid=${ssidValue.isEmpty ? '<empty>' : ssidValue}, '
      'onHotspot=${!Platform.isIOS || ssidValue == ssid}, '
      'reachable=$reachable)',
    );
    return false;
  }
}
