//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:secluso_flutter/notifications/epoch.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/routes/camera/list_cameras.dart';
import 'package:secluso_flutter/utilities/app_coordination_state.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/lock.dart';
import 'package:secluso_flutter/utilities/version_gate.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/notifications/epoch_markers.dart';

class ThumbnailManager {
  static const Duration _stableWaitTimeout = Duration(seconds: 2);
  static const Duration _stableWaitPoll = Duration(milliseconds: 120);
  static const int _minPngSizeBytes = 32;
  static const Duration _decryptTimeout = Duration(seconds: 8);
  static const Duration _downloadTimeout = Duration(seconds: 12);
  static const Duration _forceInitCooldown = Duration(seconds: 30);
  static const Duration _forceInitTimeout = Duration(seconds: 8);
  static final Map<String, DateTime> _forceInitLast = {};
  static final Map<String, Future<void>> _activeSessions = {};

  static const List<int> _pngSignature = [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];

  static bool _isEpochMismatch(String message) {
    return message.contains("message epoch") && message.contains("group epoch");
  }

  static bool _isBusyError(String message) {
    return message.contains("Error: Busy");
  }

  static bool _isThumbnailFilename(String name) {
    return name.startsWith("thumbnail_") && name.endsWith(".png");
  }

  static Future<bool> _cameraStillExists(String camera) async {
    return AppCoordinationState.containsCamera(camera);
  }

  static Future<bool> _maybeForceInit(String camera, String reason) async {
    final now = DateTime.now();
    final lastAttempt = _forceInitLast[camera];
    if (lastAttempt != null &&
        now.difference(lastAttempt) < _forceInitCooldown) {
      Log.w(
        "[thumbnail] Skipping force init for $camera (cooldown active, reason=$reason)",
      );
      return false;
    }
    _forceInitLast[camera] = now;
    Log.w("[thumbnail] Forcing init for $camera (reason=$reason)");
    final outcome = await initialize(
      camera,
      timeout: _forceInitTimeout,
      force: true,
    );
    return outcome.isOk;
  }

  static bool _looksLikePngHeader(Uint8List bytes) {
    if (bytes.length < _pngSignature.length) return false;
    for (var i = 0; i < _pngSignature.length; i++) {
      if (bytes[i] != _pngSignature[i]) return false;
    }
    return true;
  }

  static Future<bool> _waitForStablePng(String filePath) async {
    final file = File(filePath);
    final deadline = DateTime.now().add(_stableWaitTimeout);
    int? lastSize;

    while (DateTime.now().isBefore(deadline)) {
      if (!await file.exists()) return false;
      final stat = await file.stat();
      final size = stat.size;
      if (size >= _minPngSizeBytes && lastSize != null && size == lastSize) {
        RandomAccessFile? raf;
        try {
          raf = await file.open(mode: FileMode.read);
          final header = await raf.read(_pngSignature.length);
          return _looksLikePngHeader(header);
        } catch (_) {
          return false;
        } finally {
          await raf?.close();
        }
      }
      lastSize = size;
      await Future.delayed(_stableWaitPoll);
    }
    return false;
  }

  static Future<void> _logThumbnailFileState(
    String camera,
    String filePath, {
    required String stage,
  }) async {
    final file = File(filePath);
    final exists = await file.exists();
    if (!exists) {
      Log.w("[thumbnail] $stage missing for $camera at $filePath");
      return;
    }

    final stat = await file.stat();
    final parent = file.parent;
    int siblingCount = 0;
    try {
      siblingCount =
          await parent
              .list()
              .where(
                (entity) =>
                    entity is File &&
                    _isThumbnailFilename(p.basename(entity.path)),
              )
              .length;
    } catch (_) {}

    Log.d(
      "[thumbnail] $stage ready for $camera at $filePath "
      "(size=${stat.size}, siblings=$siblingCount)",
    );
  }

  static Future<void> _ensureSession({
    required String camera,
    required Duration timeBudget,
    required String targetTimestamp,
  }) async {
    final active = _activeSessions[camera];
    if (active != null) {
      return;
    }
    final future = _session(
      camera: camera,
      timeBudget: timeBudget,
      targetTimestamp: targetTimestamp,
      onTargetReady: (_) {},
    );
    _activeSessions[camera] = future;
    await future.whenComplete(() {
      _activeSessions.remove(camera);
    });
  }

  // Return quickly; thumbnails are fetched in the background if needed.
  static Future<bool> checkThumbnailsForCamera(
    String camera,
    String timestamp,
  ) async {
    if (VersionGate.isBlocked) {
      await HttpClientService.instance.potentiallySendBackgroundNotification();
      Log.d(
        "$camera: Skipping thumbnail check because version gate is active.",
      );
      return false;
    }
    // Check if the file already exists in the thumbnails folder
    final cameraDir = await AppPaths.cameraDirectory(camera);

    final filePath = p.join(
      cameraDir.path,
      'videos',
      "thumbnail_$timestamp.png",
    );

    if (await File(filePath).exists()) {
      return await _waitForStablePng(filePath);
    }

    // If we can't get the corresponding thumbnail in 15 seconds, we send the notification without it.
    final timeBudget = Duration(seconds: 15);

    unawaited(
      _ensureSession(
        camera: camera,
        timeBudget: timeBudget,
        targetTimestamp: timestamp,
      ),
    );

    return false;
  }

  static Future<void> checkThumbnailsForAll() async {
    if (VersionGate.isBlocked) {
      await HttpClientService.instance.potentiallySendBackgroundNotification();
      Log.d("Skipping thumbnail sweep because version gate is active.");
      return;
    }
    // Call the endpoint asking for the epochs that haven't been used in over 5 mins. This indicates we likely won't get a notification for it.
    // See if we have the epoch beforehand. If we do, we download it.

    var cameraNamesResult = await HttpClientService.instance
        .bulkCheckAvailableCameras(5 * 60);

    if (cameraNamesResult.isFailure ||
        (cameraNamesResult.isSuccess && cameraNamesResult.value!.isEmpty)) {
      return;
    }

    var cameraNames = cameraNamesResult.value!;
    for (String camera in cameraNames) {
      // Should this be awaited?
      _ensureSession(
        camera: camera,
        timeBudget: Duration(seconds: 120),
        targetTimestamp:
            "1", // This is never possible, so it'll go until it runs out
      );
    }
  }

  //FIXME: _session() and retrieveThumbnails have a lot of shared code
  static Future<void> _session({
    required String camera,
    required Duration timeBudget,
    required String targetTimestamp,
    required void Function(bool)
    onTargetReady, //true = found, false = not found
  }) async {
    return Log.runWithDerivedContext('thumb', () async {
      Log.d("Entered thumbnail session");
      if (VersionGate.isBlocked) {
        await HttpClientService.instance
            .potentiallySendBackgroundNotification();
        Log.d(
          "$camera: Skipping thumbnail session because version gate is active.",
        );
        return;
      }
      if (!await _cameraStillExists(camera)) {
        Log.d(
          "$camera: Camera deleted before thumbnail session started; skipping.",
        );
        return;
      }
      // There's a chance a thumbnail could be requested multiple times at once for a given camera. So we need to lock this function per-camera to ensure that doesn't occur.
      if (await lock("thumbnail$camera.lock")) {
        try {
          if (!await _cameraStillExists(camera)) {
            Log.d(
              "$camera: Camera deleted after thumbnail session lock acquired; skipping.",
            );
            return;
          }
          final initOutcome = await initialize(camera);
          if (!initOutcome.isOk) {
            if (initOutcome == InitOutcome.timeout) {
              Log.w(
                "Thumbnail init timeout for camera $camera (${Log.ownerTag()})",
              );
            } else {
              Log.e("Thumbnail init failed for camera $camera");
            }
            return;
          }

          final sw = Stopwatch()..start();

          while (sw.elapsed <= timeBudget) {
            if (!await _cameraStillExists(camera)) {
              Log.d(
                "$camera: Camera deleted during thumbnail session loop; aborting.",
              );
              return;
            }
            // Epoch for this starts at 2 when not set from before.
            final epoch = await readEpoch(camera, "thumbnail");
            final assumedEpoch = epoch > 0 ? epoch - 1 : 0;
            Log.d("Thumbnail Epoch = $epoch");
            final fileName = "encThumbnail$epoch";
            final downloadSw = Stopwatch()..start();
            var result = await HttpClientService.instance.download(
              destinationFile: fileName,
              cameraName: camera,
              serverFile: epoch.toString(),
              type: Group.thumbnail,
              timeout: _downloadTimeout,
            );
            downloadSw.stop();
            if (!kReleaseMode) {
              Log.d(
                "[perf] Download thumbnail $camera epoch $epoch in ${downloadSw.elapsedMilliseconds}ms (ok=${result.isSuccess})",
              );
            }

            if (result.isFailure) break;

            final downloadValue = result.value!;
            if (downloadValue.not_found) {
              return;
            }

            if (downloadValue.file == null) {
              Log.e("Successful download without file/data");
              return;
            }

            Log.d("Proceeding after thumbnail download");
            final baseDir = await AppPaths.dataDirectory();
            final metaDir = Directory(p.join(baseDir.path, 'waiting', 'meta'));
            await metaDir.create(recursive: true);

            // Decode the thumbnail
            var file = downloadValue.file!;
            if (!await _cameraStillExists(camera)) {
              Log.d(
                "$camera: Camera deleted after encrypted thumbnail session download; discarding work.",
              );
              if (await file.exists()) {
                await file.delete();
              }
              return;
            }
            String decFileName;
            final decryptSw = Stopwatch()..start();
            try {
              decFileName = await decryptThumbnail(
                cameraName: camera,
                encFilename: fileName,
                pendingMetaDirectory: metaDir.path,
                assumedEpoch: BigInt.from(assumedEpoch),
              ).timeout(_decryptTimeout);
            } on TimeoutException {
              Log.e(
                "Thumbnail decrypt timeout for $camera after ${_decryptTimeout.inSeconds}s (${Log.ownerTag()})",
              );
              return;
            }
            decryptSw.stop();
            if (!kReleaseMode) {
              Log.d(
                "[perf] Decrypt thumbnail $camera $fileName in ${decryptSw.elapsedMilliseconds}ms (result=$decFileName)",
              );
            }

            if (decFileName.startsWith("Error")) {
              Log.w(
                "Thumbnail decrypt failed for $camera epoch $epoch: $decFileName",
              );
              if (_isBusyError(decFileName)) {
                Log.w(
                  "Thumbnail decrypt busy for $camera epoch $epoch; skipping for now",
                );
                return;
              }
              if (_isEpochMismatch(decFileName)) {
                final markerPayload = await readEpochMarker(
                  camera,
                  "thumbnail",
                  epoch,
                );
                if (markerPayload != null &&
                    _isThumbnailFilename(markerPayload)) {
                  final cameraDir = await AppPaths.cameraDirectory(camera);
                  final decPath = p.join(
                    cameraDir.path,
                    'videos',
                    markerPayload,
                  );
                  if (await File(decPath).exists()) {
                    await _logThumbnailFileState(
                      camera,
                      decPath,
                      stage: "session epoch marker",
                    );
                    ThumbnailNotifier.instance.notify(camera);
                  } else {
                    Log.w(
                      "Epoch marker exists but thumbnail file missing: $decPath",
                    );
                  }
                  Log.w(
                    "Epoch mismatch for $camera thumbnail $epoch but marker exists; treating as duplicate",
                  );
                  await file.delete();
                  await writeEpoch(camera, "thumbnail", epoch + 1);
                  await HttpClientService.instance.delete(
                    destinationFile: fileName,
                    cameraName: camera,
                    serverFile: epoch.toString(),
                    type: Group.thumbnail,
                  );
                  continue;
                } else if (markerPayload != null) {
                  Log.w(
                    "Epoch marker exists for $camera thumbnail $epoch but payload is invalid; not skipping",
                  );
                }
              }
              final forceOk = await _maybeForceInit(
                camera,
                "decrypt_thumbnail",
              );
              if (forceOk) {
                final retrySw = Stopwatch()..start();
                try {
                  decFileName = await decryptThumbnail(
                    cameraName: camera,
                    encFilename: fileName,
                    pendingMetaDirectory: metaDir.path,
                    assumedEpoch: BigInt.from(assumedEpoch),
                  ).timeout(_decryptTimeout);
                } on TimeoutException {
                  Log.e(
                    "Thumbnail decrypt timeout after forced init for $camera (${Log.ownerTag()})",
                  );
                  return;
                }
                retrySw.stop();
                if (!kReleaseMode) {
                  Log.d(
                    "[perf] Decrypt thumbnail retry $camera $fileName in ${retrySw.elapsedMilliseconds}ms (result=$decFileName)",
                  );
                }
              }
            }

            Log.d("Thumbnail dec file name = $decFileName");

            if (!await _cameraStillExists(camera)) {
              Log.d(
                "$camera: Camera deleted after thumbnail session decrypt; skipping remaining work.",
              );
              if (await file.exists()) {
                await file.delete();
              }
              return;
            }

            if (decFileName == "Duplicate") {
              final markerPayload = await readEpochMarker(
                camera,
                "thumbnail",
                epoch,
              );
              if (markerPayload != null &&
                  _isThumbnailFilename(markerPayload)) {
                final cameraDir = await AppPaths.cameraDirectory(camera);
                final decPath = p.join(cameraDir.path, 'videos', markerPayload);
                if (await File(decPath).exists()) {
                  await _logThumbnailFileState(
                    camera,
                    decPath,
                    stage: "session duplicate marker",
                  );
                  ThumbnailNotifier.instance.notify(camera);
                  if (markerPayload == "thumbnail_$targetTimestamp.png") {
                    Log.d("Received target thumbnail");
                    onTargetReady(true);
                    return;
                  }
                } else {
                  Log.w("Duplicate thumbnail marker missing file: $decPath");
                }
              }

              await file.delete();
              await writeEpoch(camera, "thumbnail", epoch + 1);
              await HttpClientService.instance.delete(
                destinationFile: fileName,
                cameraName: camera,
                serverFile: epoch.toString(),
                type: Group.thumbnail,
              );
              continue;
            }

            if (!decFileName.startsWith("Error")) {
              final cameraDir = await AppPaths.cameraDirectory(camera);
              final decPath = p.join(cameraDir.path, 'videos', decFileName);
              final ready = await _waitForStablePng(decPath);
              if (!ready) {
                Log.e("Thumbnail file not ready or invalid: $decPath");
                return;
              }

              await _logThumbnailFileState(
                camera,
                decPath,
                stage: "session decrypt",
              );

              await file.delete();
              var result = decFileName == "thumbnail_$targetTimestamp.png";
              Log.d(
                "Received thumbnail 100%, comparing to thumbnail_$targetTimestamp.png ($result)",
              );
              ThumbnailNotifier.instance.notify(camera);

              if (decFileName == "thumbnail_$targetTimestamp.png") {
                Log.d("Received target thumbnail");
                onTargetReady(true);
              }
            } else {
              Log.e(
                "Thumbnail decrypt failed for $camera epoch $epoch; leaving epoch unchanged",
              );
              return;
            }

            await writeEpoch(camera, "thumbnail", epoch + 1);

            await HttpClientService.instance.delete(
              destinationFile: fileName,
              cameraName: camera,
              serverFile: epoch.toString(),
              type: Group.thumbnail,
            );
          }
        } finally {
          await unlock(
            "thumbnail$camera.lock",
          ); // Always ensure this unlocks, even on exceptions
        }
      } else {
        Log.w("Thumbnail session lock busy; skipping this cycle");
      }
    });
  }

  // RetriveAllThumbnails of a camera
  static Future<bool> retrieveThumbnails({required String camera}) async {
    return Log.runWithDerivedContext('thumb', () async {
      Log.d("Entered retrieveThumbnails");
      if (VersionGate.isBlocked) {
        await HttpClientService.instance
            .potentiallySendBackgroundNotification();
        Log.d(
          "$camera: Skipping thumbnail retrieval because version gate is active.",
        );
        return true;
      }
      if (!await _cameraStillExists(camera)) {
        Log.d(
          "$camera: Camera deleted before thumbnail retrieval started; skipping.",
        );
        return true;
      }
      if (await lock("thumbnail$camera.lock")) {
        if (!await _cameraStillExists(camera)) {
          Log.d(
            "$camera: Camera deleted after thumbnail lock acquired; skipping.",
          );
          await unlock("thumbnail$camera.lock");
          return true;
        }
        final initOutcome = await initialize(camera);
        if (!initOutcome.isOk) {
          if (initOutcome == InitOutcome.timeout) {
            Log.w(
              "Thumbnail init timeout for camera $camera (${Log.ownerTag()})",
            );
          } else {
            Log.e("Thumbnail init failed for camera $camera");
          }
          return false;
        }

        // Epoch for this starts at 2 when not set from before.
        var epoch = await readEpoch(camera, "thumbnail");
        try {
          while (true) {
            if (!await _cameraStillExists(camera)) {
              Log.d("$camera: Camera deleted during thumbnail loop; aborting.");
              return true;
            }
            final assumedEpoch = epoch > 0 ? epoch - 1 : 0;
            Log.d("Thumbnail Epoch = $epoch");
            final fileName = "encThumbnail$epoch";
            final downloadSw = Stopwatch()..start();
            var result = await HttpClientService.instance.download(
              destinationFile: fileName,
              cameraName: camera,
              serverFile: epoch.toString(),
              type: Group.thumbnail,
              timeout: _downloadTimeout,
            );
            downloadSw.stop();
            if (!kReleaseMode) {
              Log.d(
                "[perf] Download thumbnail $camera epoch $epoch in ${downloadSw.elapsedMilliseconds}ms (ok=${result.isSuccess})",
              );
            }

            if (result.isFailure) {
              Log.d("HTTP download of encrypted thumbnail failed");
              return false;
            } else {
              if (result.value!.not_found) {
                Log.d("Finished downloading encrypted thumbnails for $camera");
                return true;
              }
            }

            Log.d("Proceeding after thumbnail download");
            final baseDir = await AppPaths.dataDirectory();
            final metaDir = Directory(p.join(baseDir.path, 'waiting', 'meta'));
            await metaDir.create(recursive: true);

            // Decode the thumbnail
            var file = result.value!.file!;
            if (!await _cameraStillExists(camera)) {
              Log.d(
                "$camera: Camera deleted after encrypted thumbnail download; discarding work.",
              );
              if (await file.exists()) {
                await file.delete();
              }
              return true;
            }
            String decFileName;
            final decryptSw = Stopwatch()..start();
            try {
              decFileName = await decryptThumbnail(
                cameraName: camera,
                encFilename: fileName,
                pendingMetaDirectory: metaDir.path,
                assumedEpoch: BigInt.from(assumedEpoch),
              ).timeout(_decryptTimeout);
            } on TimeoutException {
              Log.e(
                "Thumbnail decrypt timeout for $camera after ${_decryptTimeout.inSeconds}s (${Log.ownerTag()})",
              );
              return false;
            }
            decryptSw.stop();
            if (!kReleaseMode) {
              Log.d(
                "[perf] Decrypt thumbnail $camera $fileName in ${decryptSw.elapsedMilliseconds}ms (result=$decFileName)",
              );
            }

            if (decFileName.startsWith("Error")) {
              Log.w(
                "Thumbnail decrypt failed for $camera epoch $epoch: $decFileName",
              );
              if (_isBusyError(decFileName)) {
                Log.w(
                  "Thumbnail decrypt busy for $camera epoch $epoch; skipping for now",
                );
              }
              if (_isEpochMismatch(decFileName)) {
                final markerPayload = await readEpochMarker(
                  camera,
                  "thumbnail",
                  epoch,
                );
                if (markerPayload != null &&
                    _isThumbnailFilename(markerPayload)) {
                  final cameraDir = await AppPaths.cameraDirectory(camera);
                  final decPath = p.join(
                    cameraDir.path,
                    'videos',
                    markerPayload,
                  );
                  if (await File(decPath).exists()) {
                    await _logThumbnailFileState(
                      camera,
                      decPath,
                      stage: "retrieve epoch marker",
                    );
                    ThumbnailNotifier.instance.notify(camera);
                  } else {
                    Log.w(
                      "Epoch marker exists but thumbnail file missing: $decPath",
                    );
                  }
                  Log.w(
                    "Epoch mismatch for $camera thumbnail $epoch but marker exists; treating as duplicate",
                  );
                  await file.delete();
                  await writeEpoch(camera, "thumbnail", epoch + 1);
                  await HttpClientService.instance.delete(
                    destinationFile: fileName,
                    cameraName: camera,
                    serverFile: epoch.toString(),
                    type: Group.thumbnail,
                  );
                } else if (markerPayload != null) {
                  Log.w(
                    "Epoch marker exists for $camera thumbnail $epoch but payload is invalid; not skipping",
                  );
                }
              }
              final forceOk = await _maybeForceInit(
                camera,
                "decrypt_thumbnail",
              );
              if (forceOk) {
                final retrySw = Stopwatch()..start();
                try {
                  decFileName = await decryptThumbnail(
                    cameraName: camera,
                    encFilename: fileName,
                    pendingMetaDirectory: metaDir.path,
                    assumedEpoch: BigInt.from(assumedEpoch),
                  ).timeout(_decryptTimeout);
                } on TimeoutException {
                  Log.e(
                    "Thumbnail decrypt timeout after forced init for $camera (${Log.ownerTag()})",
                  );
                  return false;
                }
                retrySw.stop();
                if (!kReleaseMode) {
                  Log.d(
                    "[perf] Decrypt thumbnail retry $camera $fileName in ${retrySw.elapsedMilliseconds}ms (result=$decFileName)",
                  );
                }
              }
            }

            Log.d("Thumbnail dec file name = $decFileName");

            if (!await _cameraStillExists(camera)) {
              Log.d(
                "$camera: Camera deleted after thumbnail decrypt; skipping remaining work.",
              );
              if (await file.exists()) {
                await file.delete();
              }
              return true;
            }

            if (decFileName == "Duplicate") {
              final markerPayload = await readEpochMarker(
                camera,
                "thumbnail",
                epoch,
              );
              if (markerPayload != null &&
                  _isThumbnailFilename(markerPayload)) {
                final cameraDir = await AppPaths.cameraDirectory(camera);
                final decPath = p.join(cameraDir.path, 'videos', markerPayload);
                if (await File(decPath).exists()) {
                  await _logThumbnailFileState(
                    camera,
                    decPath,
                    stage: "retrieve duplicate marker",
                  );
                  ThumbnailNotifier.instance.notify(camera);
                } else {
                  Log.w("Duplicate thumbnail marker missing file: $decPath");
                }
              }

              await file.delete();
              await writeEpoch(camera, "thumbnail", epoch + 1);
              await HttpClientService.instance.delete(
                destinationFile: fileName,
                cameraName: camera,
                serverFile: epoch.toString(),
                type: Group.thumbnail,
              );

              epoch += 1;
              continue;
            }

            if (!decFileName.startsWith("Error")) {
              final cameraDir = await AppPaths.cameraDirectory(camera);
              final decPath = p.join(cameraDir.path, 'videos', decFileName);
              final ready = await _waitForStablePng(decPath);
              if (!ready) {
                Log.e("Thumbnail file not ready or invalid: $decPath");
              } else {
                await _logThumbnailFileState(
                  camera,
                  decPath,
                  stage: "retrieve decrypt",
                );
              }

              await file.delete();
              ThumbnailNotifier.instance.notify(camera);
            } else {
              Log.e(
                "Thumbnail decrypt failed for $camera epoch $epoch; leaving epoch unchanged",
              );
            }

            await writeEpoch(camera, "thumbnail", epoch + 1);

            await HttpClientService.instance.delete(
              destinationFile: fileName,
              cameraName: camera,
              serverFile: epoch.toString(),
              type: Group.thumbnail,
            );

            epoch += 1;
          }
        } finally {
          await unlock(
            "thumbnail$camera.lock",
          ); // Always ensure this unlocks, even on exceptions
        }
      } else {
        Log.w("Thumbnail session lock busy; skipping this cycle");
        return false;
      }
    });
  }
}
