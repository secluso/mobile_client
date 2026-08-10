//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';

const int maxConnectedAppDisplayNameLength = 80;
const int maxProtocolAppNameBytes = 4096;

class ConnectedApp {
  const ConnectedApp({required this.appName, required this.displayName});

  final String appName;
  final String displayName;
}

class AddAppResp {
  const AddAppResp({required this.appName, required this.payload});

  final String appName;
  final Uint8List payload;
}

String validateConnectedAppDisplayName(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw const FormatException('Phone name is required.');
  }
  if (normalized.length > maxConnectedAppDisplayNameLength) {
    throw const FormatException('Phone name is too long.');
  }
  if (normalized.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw const FormatException('Phone name contains invalid characters.');
  }
  return normalized;
}

AddAppResp decodeAddAppResp(List<int> bytes) {
  if (bytes.length < 3) {
    throw const FormatException('Invalid add-phone response.');
  }
  final nameLength = (bytes[0] << 8) | bytes[1];
  if (nameLength == 0 ||
      nameLength > maxProtocolAppNameBytes ||
      bytes.length <= 2 + nameLength) {
    throw const FormatException('Invalid add-phone response.');
  }
  final appName = utf8.decode(
    bytes.sublist(2, 2 + nameLength),
    allowMalformed: false,
  );
  if (appName.isEmpty || appName.runes.any((rune) => rune < 0x20)) {
    throw const FormatException('Invalid camera app name.');
  }
  return AddAppResp(
    appName: appName,
    payload: Uint8List.fromList(bytes.sublist(2 + nameLength)),
  );
}

Future<List<ConnectedApp>> loadConnectedApps(String cameraName) async {
  final prefs = await SharedPreferences.getInstance();
  final encoded = prefs.getString(PrefKeys.connectedAppsPrefix + cameraName);
  if (encoded == null) return <ConnectedApp>[];
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! List || decoded.length > 128) return <ConnectedApp>[];
    final apps = <ConnectedApp>[];
    final seen = <String>{};
    for (final item in decoded) {
      if (item is! Map) continue;
      final appName = item['appName'];
      final displayName = item['displayName'];
      if (appName is! String || displayName is! String || !seen.add(appName)) {
        continue;
      }
      if (utf8.encode(appName).length > maxProtocolAppNameBytes) continue;
      try {
        apps.add(
          ConnectedApp(
            appName: appName,
            displayName: validateConnectedAppDisplayName(displayName),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return apps;
  } on FormatException {
    return <ConnectedApp>[];
  }
}

Future<void> saveConnectedApp(
  String cameraName,
  ConnectedApp connectedApp,
) async {
  final apps = await loadConnectedApps(cameraName);
  apps.removeWhere((app) => app.appName == connectedApp.appName);
  apps.add(connectedApp);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    PrefKeys.connectedAppsPrefix + cameraName,
    jsonEncode(
      apps.map((app) => {
        'appName': app.appName,
        'displayName': app.displayName,
      }).toList(),
    ),
  );
}

Future<void> removeConnectedApp(String cameraName, String appName) async {
  final apps = await loadConnectedApps(cameraName);
  apps.removeWhere((app) => app.appName == appName);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    PrefKeys.connectedAppsPrefix + cameraName,
    jsonEncode(
      apps.map((app) => {
        'appName': app.appName,
        'displayName': app.displayName,
      }).toList(),
    ),
  );
}
