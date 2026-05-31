//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:secluso_flutter/utilities/logger.dart';

class AppPaths {
  AppPaths._();

  static const MethodChannel _storageChannel = MethodChannel(
    'secluso.com/storage',
  );
  static const MethodChannel _appGroupChannel = MethodChannel(
    'secluso.com/app_group',
  );

  /// Identifier shared with the iOS NotificationService extension.
  static const String iosAppGroupIdentifier = 'group.com.secluso.shared';

  static const Duration _backupSweepInterval = Duration(minutes: 1);

  static Future<Directory>? _dataDirectoryFuture;
  static DateTime? _lastBackupSweepAt;
  static Future<void>? _backupSweepFuture;

  /// The active data directory, resolved on first call.
  ///
  /// On iOS this is the App Group container so the NotificationService extension can read the same MLS state the main app writes.
  /// Cameras paired before the App Group switch keep their state under the legacy <ApplicationSupport>/secluso/ location (only new pairing ends up here)
  static Future<Directory> dataDirectory() async {
    final directory = await (_dataDirectoryFuture ??= _resolveDataDirectory());
    await _refreshBackupExclusionIfNeeded(directory);
    return directory;
  }

  /// Return the directory belonging to a certain camera (whether the current or legacy if iOS)
  ///
  /// Newly paired cameras (post-App-Group) go under dataDirectory so the iOS NotificationService extension can see them.
  /// Cameras paired earlier go under <ApplicationSupport>/secluso/camera_dir_<name>
  /// The app reads from there and continues to function normally... the NSE just can't see them (it will fall back to the system text alert for pushes from legacy cameras)
  /// When the user reflashes that camera and re-pairs, the new camera ends up in the App Group container and thumbnails-in-notifications start working for it.
  static Future<Directory> cameraDirectory(String cameraName) async {
    return resolveCameraDirectory(
      cameraName: cameraName,
      primaryRoot: await dataDirectory(),
      legacyRoot: await _iosLegacyRoot(),
    );
  }

  /// All filesystem roots that may contain camera_dir_* subtrees.
  /// (iOS: App Group container && legacy ApplicationSupport/secluso/)
  /// allows size accounting, temp-file cleanup, orphan detection
  static Future<List<Directory>> allDataRoots() async {
    return resolveDataRoots(
      primary: await dataDirectory(),
      legacy: await _iosLegacyRoot(),
    );
  }

  /// Returns the per-camera dir at the App Group primaryRoot if it exists,
  /// otherwise the matching dir under legacyRoot when that exists,
  /// otherwise where a fresh pairing would go (primary)
  @visibleForTesting
  static Future<Directory> resolveCameraDirectory({
    required String cameraName,
    required Directory primaryRoot,
    required Directory? legacyRoot,
  }) async {
    final primary = Directory(
      p.join(primaryRoot.path, 'camera_dir_$cameraName'),
    );
    if (legacyRoot == null) return primary;
    if (await primary.exists()) return primary;
    final legacy = Directory(p.join(legacyRoot.path, 'camera_dir_$cameraName'));
    if (await legacy.exists()) return legacy;
    return primary;
  }

  /// Returns the primary root plus the legacy root iff (if and only if) it actually exists on disk and is a distinct path
  @visibleForTesting
  static Future<List<Directory>> resolveDataRoots({
    required Directory primary,
    required Directory? legacy,
  }) async {
    if (legacy == null) return [primary];
    if (!await legacy.exists()) return [primary];
    if (p.canonicalize(legacy.path) == p.canonicalize(primary.path)) {
      return [primary];
    }
    return [primary, legacy];
  }

  static Future<Directory?> _iosLegacyRoot() async {
    if (!Platform.isIOS) return null;
    final legacyRoot = await getApplicationSupportDirectory();
    return Directory(p.join(legacyRoot.path, 'secluso'));
  }

  static Future<Directory> _resolveDataDirectory() async {
    if (Platform.isIOS) {
      return _resolveIosDataDirectory();
    }
    final rootDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory(p.join(rootDir.path, 'secluso'));
    await dataDir.create(recursive: true);
    Log.i(
      '[storage] Using app data directory ${dataDir.path} (platform=${Platform.operatingSystem})',
    );
    return dataDir;
  }

  static Future<Directory> _resolveIosDataDirectory() async {
    String? containerPath;
    try {
      containerPath = await _appGroupChannel.invokeMethod<String>(
        'getContainerPath',
        {'identifier': iosAppGroupIdentifier},
      );
    } catch (error) {
      Log.w(
        '[storage] Failed to resolve App Group container ($iosAppGroupIdentifier): $error',
      );
    }

    if (containerPath == null || containerPath.isEmpty) {
      // App Group entitlement isn't provisioned on this device yet
      // Fall back to the per-app sandbox so the app still launches (but the NSE won't see state in this mode)
      final legacyRoot = await getApplicationSupportDirectory();
      final legacyDataDir = Directory(p.join(legacyRoot.path, 'secluso'));
      await legacyDataDir.create(recursive: true);
      await _forceRefreshBackupExclusion(legacyDataDir);
      Log.w(
        '[storage] App Group container unavailable; using sandbox path '
        '${legacyDataDir.path} (NSE will be inert).',
      );
      return legacyDataDir;
    }

    final groupDataDir = Directory(p.join(containerPath, 'secluso'));
    await groupDataDir.create(recursive: true);
    await _forceRefreshBackupExclusion(groupDataDir);
    Log.i('[storage] Using iOS App Group data directory ${groupDataDir.path}');
    return groupDataDir;
  }

  static Future<void> _refreshBackupExclusionIfNeeded(
    Directory directory,
  ) async {
    if (!Platform.isIOS) return;
    final now = DateTime.now();
    final lastSweepAt = _lastBackupSweepAt;
    if (lastSweepAt != null &&
        now.difference(lastSweepAt) < _backupSweepInterval) {
      return;
    }
    if (_backupSweepFuture != null) {
      await _backupSweepFuture;
      return;
    }
    final future = _forceRefreshBackupExclusion(directory);
    _backupSweepFuture = future;
    try {
      await future;
    } finally {
      if (identical(_backupSweepFuture, future)) {
        _backupSweepFuture = null;
      }
    }
  }

  static Future<void> _forceRefreshBackupExclusion(Directory directory) async {
    if (!Platform.isIOS) return;
    try {
      await _storageChannel.invokeMethod<void>('excludeTreeFromBackup', {
        'path': directory.path,
      });
      final excluded =
          await _storageChannel.invokeMethod<bool>('isExcludedFromBackup', {
            'path': directory.path,
          }) ??
          false;
      _lastBackupSweepAt = DateTime.now();
      Log.i(
        '[storage] Backup exclusion sweep complete for ${directory.path} (excluded=$excluded)',
      );
    } catch (error) {
      Log.w(
        '[storage] Failed to refresh backup exclusion for ${directory.path}: $error',
      );
    }
  }
}
