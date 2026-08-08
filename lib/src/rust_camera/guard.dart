//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:secluso_flutter/src/rust_camera/frb_generated.dart'
    as rust_camera;

class RustCameraLibGuard {
  static Future<void>? _opening;
  static bool _initialized = false;

  static Future<void> initOnce() {
    if (_initialized) return Future.value();
    if (_opening != null) return _opening!;
    _opening = _init().whenComplete(() => _opening = null);
    return _opening!;
  }

  static Future<void> _init() async {
    await rust_camera.RustLib.init();
    _initialized = true;
  }

  static bool get isInitialized => _initialized;
}
