//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Tests for the App-Group-side I/O contract that NseBridge maintains with the iOS NotificationService extension.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:secluso_flutter/notifications/nse_bridge.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('secluso_nse_bridge_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  File credFile() => File(p.join(tmp.path, NseBridgePaths.credentialsFile));
  File eventsFile() => File(p.join(tmp.path, NseBridgePaths.eventsLog));
  File eventsDrainSidecar() =>
      File(p.join(tmp.path, '${NseBridgePaths.eventsLog}.drain'));

  group('exportCredentialsTo', () {
    test('writes JSON with all four fields when creds are present', () async {
      await NseBridge.exportCredentialsTo(
        directory: tmp,
        serverAddr: 'https://dummy-relay.secluso.com',
        username: 'alice',
        password: 's3cret',
      );

      expect(await credFile().exists(), isTrue);
      final parsed = jsonDecode(await credFile().readAsString());
      expect(parsed, {
        'server_addr': 'https://dummy-relay.secluso.com',
        'username': 'alice',
        'password': 's3cret',
        'version': 1,
      });
    });

    test('is a no-op when any credential field is missing', () async {
      // Pre-existing file should not be modified.
      await credFile().writeAsString('{"server_addr":"old"}');

      await NseBridge.exportCredentialsTo(
        directory: tmp,
        serverAddr: 'https://dummy-relay.secluso.com',
        username: null,
        password: 's3cret',
      );

      expect(await credFile().readAsString(), '{"server_addr":"old"}');
    });

    test('is a no-op when a credential field is empty string', () async {
      await NseBridge.exportCredentialsTo(
        directory: tmp,
        serverAddr: 'https://dummy-relay.secluso.com',
        username: 'alice',
        password: '',
      );

      expect(await credFile().exists(), isFalse);
    });

    test('overwrites a previously-written credentials file', () async {
      await NseBridge.exportCredentialsTo(
        directory: tmp,
        serverAddr: 'https://old-dummy-relay.secluso.com',
        username: 'alice',
        password: 'old',
      );
      await NseBridge.exportCredentialsTo(
        directory: tmp,
        serverAddr: 'https://new-dummy-relay.secluso.com',
        username: 'bob',
        password: 'new',
      );

      final parsed = jsonDecode(await credFile().readAsString());
      expect(parsed['server_addr'], 'https://new-dummy-relay.secluso.com');
      expect(parsed['username'], 'bob');
      expect(parsed['password'], 'new');
    });
  });

  group('clearCredentialsIn', () {
    test('deletes the credentials file when present', () async {
      await credFile().writeAsString('{"server_addr":"x"}');
      expect(await credFile().exists(), isTrue);

      await NseBridge.clearCredentialsIn(tmp);

      expect(await credFile().exists(), isFalse);
    });

    test('is a no-op when the credentials file does not exist', () async {
      await NseBridge.clearCredentialsIn(tmp);
      expect(await credFile().exists(), isFalse);
    });
  });

  group('drainEventsIn', () {
    test('returns empty list when no events log exists', () async {
      final drained = await NseBridge.drainEventsIn(tmp);
      expect(drained, isEmpty);
    });

    test(
      'parses well-formed JSONL events and removes the drain sidecar',
      () async {
        final line1 = jsonEncode({
          'camera': 'frontdoor',
          'timestamp': '1737000000',
          'thumbnail_filename': 'thumbnail_1737000000.png',
          'detections': ['person', 'package'],
          'decrypted_at_epoch_ms': 1737000123456,
        });
        final line2 = jsonEncode({
          'camera': 'backyard',
          'timestamp': '1737000050',
          'decrypted_at_epoch_ms': 1737000150000,
        });
        await eventsFile().writeAsString('$line1\n$line2\n');

        final events = await NseBridge.drainEventsIn(tmp);

        expect(events.length, 2);
        expect(events[0].camera, 'frontdoor');
        expect(events[0].timestamp, '1737000000');
        expect(events[0].thumbnailFilename, 'thumbnail_1737000000.png');
        expect(events[0].detections, ['person', 'package']);
        expect(events[0].decryptedAtEpochMs, 1737000123456);
        expect(events[1].camera, 'backyard');
        expect(events[1].timestamp, '1737000050');
        expect(events[1].thumbnailFilename, isNull);
        expect(events[1].detections, isEmpty);

        // Drain removes both the original log and the sidecar so the next drain doesn't double-count.
        expect(await eventsFile().exists(), isFalse);
        expect(await eventsDrainSidecar().exists(), isFalse);
      },
    );

    test(
      'skips malformed lines but still returns the well-formed ones',
      () async {
        final good = jsonEncode({
          'camera': 'driveway',
          'timestamp': '1737000100',
          'decrypted_at_epoch_ms': 1737000200000,
        });
        await eventsFile().writeAsString(
          '$good\n'
          'this is not json\n'
          '\n'
          '{"unterminated":\n'
          '$good\n',
        );

        final events = await NseBridge.drainEventsIn(tmp);
        expect(events.length, 2);
        expect(events.every((e) => e.camera == 'driveway'), isTrue);
      },
    );

    test(
      'recovers from a crash mid-drain by re-reading the sidecar on next call',
      () async {
        // Simulate a previous crash
        // The events log was rolled to .drain but the process died before reading/deleting it
        // The next drain has to pick it up
        final line = jsonEncode({
          'camera': 'garage',
          'timestamp': '1737000200',
          'decrypted_at_epoch_ms': 1737000300000,
        });
        await eventsDrainSidecar().writeAsString('$line\n');

        final events = await NseBridge.drainEventsIn(tmp);
        expect(events.length, 1);
        expect(events.first.camera, 'garage');
        expect(await eventsDrainSidecar().exists(), isFalse);
      },
    );
  });
}
