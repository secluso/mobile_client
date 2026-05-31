//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Tests for the App Group / per-camera path resolution logic in AppPaths.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:secluso_flutter/utilities/app_paths.dart';

void main() {
  late Directory tmp;
  late Directory primary;
  late Directory legacy;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('secluso_app_paths_test_');
    primary = Directory(p.join(tmp.path, 'app_group'))..createSync();
    legacy = Directory(p.join(tmp.path, 'legacy'))..createSync();
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  Directory pairCamera(Directory root, String camera) {
    final dir = Directory(p.join(root.path, 'camera_dir_$camera'))
      ..createSync(recursive: true);
    return dir;
  }

  group('resolveCameraDirectory', () {
    test('returns primary path when no legacy fallback is provided '
        '(non-iOS case)', () async {
      final dir = await AppPaths.resolveCameraDirectory(
        cameraName: 'frontdoor',
        primaryRoot: primary,
        legacyRoot: null,
      );
      expect(p.basename(dir.path), 'camera_dir_frontdoor');
      expect(p.dirname(dir.path), primary.path);
    });

    test('returns primary path when only the primary dir exists', () async {
      pairCamera(primary, 'frontdoor');
      final dir = await AppPaths.resolveCameraDirectory(
        cameraName: 'frontdoor',
        primaryRoot: primary,
        legacyRoot: legacy,
      );
      expect(dir.path, p.join(primary.path, 'camera_dir_frontdoor'));
    });

    test('returns legacy path when only the legacy dir exists '
        '(existing pre-upgrade camera)', () async {
      pairCamera(legacy, 'backyard');
      final dir = await AppPaths.resolveCameraDirectory(
        cameraName: 'backyard',
        primaryRoot: primary,
        legacyRoot: legacy,
      );
      expect(dir.path, p.join(legacy.path, 'camera_dir_backyard'));
    });

    test('returns primary path when both exist '
        '(post-upgrade camera supersedes legacy)', () async {
      pairCamera(primary, 'garage');
      pairCamera(legacy, 'garage');
      final dir = await AppPaths.resolveCameraDirectory(
        cameraName: 'garage',
        primaryRoot: primary,
        legacyRoot: legacy,
      );
      expect(dir.path, p.join(primary.path, 'camera_dir_garage'));
    });

    test('returns primary path when neither exists '
        '(fresh pairing lands in App Group)', () async {
      final dir = await AppPaths.resolveCameraDirectory(
        cameraName: 'newcam',
        primaryRoot: primary,
        legacyRoot: legacy,
      );
      expect(dir.path, p.join(primary.path, 'camera_dir_newcam'));
    });

    test(
      'returns directory referencing the actual path even before it exists',
      () async {
        final dir = await AppPaths.resolveCameraDirectory(
          cameraName: 'newcam',
          primaryRoot: primary,
          legacyRoot: legacy,
        );
        // The pair-time flow expects to receive a Directory it can `.create()`
        // on. Don't assert .exists() here because the resolver intentionally
        // does not create directories.
        expect(dir, isA<Directory>());
        expect(dir.path, isNotEmpty);
      },
    );
  });

  group('resolveDataRoots', () {
    test('returns [primary] only when no legacy is provided', () async {
      final roots = await AppPaths.resolveDataRoots(
        primary: primary,
        legacy: null,
      );
      expect(roots, [primary]);
    });

    test('returns [primary] when legacy does not exist on disk', () async {
      legacy.deleteSync();
      final roots = await AppPaths.resolveDataRoots(
        primary: primary,
        legacy: legacy,
      );
      expect(roots.map((d) => d.path), [primary.path]);
    });

    test(
      'returns [primary, legacy] when both exist and are distinct paths',
      () async {
        final roots = await AppPaths.resolveDataRoots(
          primary: primary,
          legacy: legacy,
        );
        expect(roots.map((d) => d.path), [primary.path, legacy.path]);
      },
    );

    test('returns [primary] when legacy and primary canonicalize to the '
        'same path (avoids double-scanning the same tree)', () async {
      final sameAsPrimary = Directory(primary.path);
      final roots = await AppPaths.resolveDataRoots(
        primary: primary,
        legacy: sameAsPrimary,
      );
      expect(roots.length, 1);
      expect(roots.first.path, primary.path);
    });
  });
}
