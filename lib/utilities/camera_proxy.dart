//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'logger.dart';

/// Bridges camera-pairing traffic through iOS Network.framework.
class CameraProxyBridge {
  CameraProxyBridge._();

  static const _channel = MethodChannel('secluso.com/camera_proxy');
  static bool _handlerInstalled = false;

  /// native proxy forwards 127.0.0.1:12348 -> 10.42.0.1:12348 over Wi-Fi.
  static const loopbackIp = '127.0.0.1';

  /// Install a handler so it can mirror debug lines into the in-app log stream.
  static void _ensureHandler() {
    if (_handlerInstalled) {
      return;
    }
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'nativeLog') {
        Log.d(call.arguments?.toString() ?? '');
      }
      return null;
    });
  }

  /// Reachability check via Network.framework instead of a raw socket
  static Future<bool> probe() async {
    if (!Platform.isIOS) {
      return false;
    }
    _ensureHandler();
    try {
      final res = await _channel.invokeMethod<Map>('probe');
      final reachable = res?['reachable'] == true;
      final detail = res?['detail']?.toString() ?? 'no detail';
      Log.d('Camera proxy probe: reachable=$reachable ($detail)');
      return reachable;
    } catch (e) {
      Log.w('Camera proxy probe failed: $e');
      return false;
    }
  }

  /// Starts the loopback proxy. Idempotent. Returns true if the proxy is up.
  static Future<bool> startProxy() async {
    if (!Platform.isIOS) {
      return false;
    }
    _ensureHandler();
    try {
      final port = await _channel.invokeMethod<int>('startProxy');
      return port != null;
    } catch (e) {
      Log.w('Camera proxy start failed: $e');
      return false;
    }
  }

  static Future<void> stopProxy() async {
    if (!Platform.isIOS) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stopProxy');
    } catch (e) {
      Log.w('Camera proxy stop failed: $e');
    }
  }
}
