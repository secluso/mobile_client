//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Which official relay the app talks to: production, or the staging server

import 'package:secluso_flutter/keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RelayEnvironment {
  RelayEnvironment._();

  static const _prod = 'https://relay.secluso.net';

  static const _staging = String.fromEnvironment(
    'SECLUSO_STAGING_RELAY',
    defaultValue: 'unset',
  );

  static const _unlockSecret = String.fromEnvironment(
    'SECLUSO_STAGING_UNLOCK',
    defaultValue: 'secluso-stg-4Kq9Rm2v',
  );

  static bool _stagingEnabled = false;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _stagingEnabled = prefs.getBool(PrefKeys.stagingRelay) ?? false;
  }

  static bool get isStaging => _stagingEnabled;

  static String get officialAddress => _stagingEnabled ? _staging : _prod;

  static String get stagingAddress => _staging;

  static String get stagingKey => _stagingEnabled ? _unlockSecret : '';

  static bool unlocks(String input) =>
      _unlockSecret.isNotEmpty && input == _unlockSecret;

  static Future<void> setStaging(bool on) async {
    _stagingEnabled = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefKeys.stagingRelay, on);
  }

  static Map<String, String> stagingHeaders() =>
      (_stagingEnabled && _unlockSecret.isNotEmpty)
          ? {'X-Staging-Key': _unlockSecret}
          : const {};
}
