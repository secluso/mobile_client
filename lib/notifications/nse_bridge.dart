//! SPDX-License-Identifier: GPL-3.0-or-later
//
// "Glue" between the Flutter app and the iOS Notification Service Extension.
//
// The NSE runs in a separate process with no Dart engine.
// The two sides share the App Group container's filesystem.
// This file is rsponsible for the main app's side of that contract.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../keys.dart';
import '../utilities/app_paths.dart';
import '../utilities/logger.dart';

/// File names + relative paths that the NSE expects.
class NseBridgePaths {
  NseBridgePaths._();

  /// JSON: server_addr, username, password, version
  static const String credentialsFile = 'nse_credentials.json';

  /// Append-only JSONL written by the NSE. Each line is one motion event.
  static const String eventsLog = 'nse_events.jsonl';
}

class NseEvent {
  final String camera;
  final String timestamp;
  final String? thumbnailFilename;
  final List<String> detections;
  final int decryptedAtEpochMs;

  const NseEvent({
    required this.camera,
    required this.timestamp,
    this.thumbnailFilename,
    this.detections = const [],
    required this.decryptedAtEpochMs,
  });

  factory NseEvent.fromJson(Map<String, dynamic> json) {
    return NseEvent(
      camera: (json['camera'] ?? '').toString(),
      timestamp: (json['timestamp'] ?? '').toString(),
      thumbnailFilename: json['thumbnail_filename']?.toString(),
      detections:
          (json['detections'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      decryptedAtEpochMs:
          (json['decrypted_at_epoch_ms'] is int)
              ? json['decrypted_at_epoch_ms'] as int
              : int.tryParse(json['decrypted_at_epoch_ms']?.toString() ?? '') ??
                  0,
    );
  }
}

class NseBridge {
  NseBridge._();

  /// Write the current credentials to the App Group so the NSE can call the hub.
  static Future<void> exportCredentials() async {
    if (!Platform.isIOS) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverAddr = prefs.getString(PrefKeys.serverAddr);
      final username = prefs.getString(PrefKeys.serverUsername);
      final password = prefs.getString(PrefKeys.serverPassword);
      final dir = await AppPaths.dataDirectory();
      await exportCredentialsTo(
        directory: dir,
        serverAddr: serverAddr,
        username: username,
        password: password,
      );
    } catch (error, stack) {
      Log.w('[nse_bridge] Failed to export credentials: $error\n$stack');
    }
  }

  /// Remove the credentials file when the user signs out. iOS-only.
  static Future<void> clearCredentials() async {
    if (!Platform.isIOS) return;
    try {
      final dir = await AppPaths.dataDirectory();
      await clearCredentialsIn(dir);
    } catch (error) {
      Log.w('[nse_bridge] Failed to clear credentials: $error');
    }
  }

  /// Read and remove any events the NSE has logged since the last drain.
  static Future<List<NseEvent>> drainEvents() async {
    if (!Platform.isIOS) return const [];
    final dir = await AppPaths.dataDirectory();
    return drainEventsIn(dir);
  }

  /// I/O helper for export creds method
  @visibleForTesting
  static Future<void> exportCredentialsTo({
    required Directory directory,
    required String? serverAddr,
    required String? username,
    required String? password,
  }) async {
    if (serverAddr == null ||
        serverAddr.isEmpty ||
        username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      // NSE checks for all-or-nothing, will fail if everything isn't included
      return;
    }
    final file = File(p.join(directory.path, NseBridgePaths.credentialsFile));
    final tmp = File('${file.path}.tmp');
    final payload = jsonEncode({
      'server_addr': serverAddr,
      'username': username,
      'password': password,
      'version': 1,
    });
    await tmp.writeAsString(payload, flush: true);
    await tmp.rename(file.path);
  }

  /// I/O helper for clearCredentials method
  @visibleForTesting
  static Future<void> clearCredentialsIn(Directory directory) async {
    final file = File(p.join(directory.path, NseBridgePaths.credentialsFile));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// I/O helper for drainEvents
  @visibleForTesting
  static Future<List<NseEvent>> drainEventsIn(Directory directory) async {
    final file = File(p.join(directory.path, NseBridgePaths.eventsLog));
    final drain = File('${file.path}.drain');

    // Atomic-ish drain: rename to a .drain sidecar then read+delete.
    // If the sidecar already exists we got here because a previous drain crashed between rename and delete
    // We still want to consume it
    if (!await drain.exists()) {
      if (!await file.exists()) return const [];
      try {
        await file.rename(drain.path);
      } catch (error) {
        Log.w('[nse_bridge] Failed to roll events log to drain: $error');
        return const [];
      }
    }

    final events = <NseEvent>[];
    try {
      final lines = await drain.readAsLines();
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        try {
          final json = jsonDecode(line);
          if (json is Map<String, dynamic>) {
            events.add(NseEvent.fromJson(json));
          }
        } catch (error) {
          Log.w('[nse_bridge] Ignoring malformed event line: $error');
        }
      }
    } catch (error) {
      Log.w('[nse_bridge] Failed to read events log: $error');
      return const [];
    }

    try {
      await drain.delete();
    } catch (_) {
      // if delete fails the next drain will overwrite (this is best effort)
    }
    return events;
  }
}
