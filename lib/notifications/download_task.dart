//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/notifications/epoch.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/routes/app_drawer.dart';
import 'package:secluso_flutter/src/rust/frb_generated.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/lock.dart';
import 'package:secluso_flutter/utilities/app_coordination_state.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/utilities/ui_state.dart';
import 'package:secluso_flutter/utilities/version_gate.dart';
import 'package:secluso_flutter/notifications/download_status.dart';
import 'package:secluso_flutter/notifications/epoch_markers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:ui';
import 'dart:isolate' hide IsolateNameServer;
import 'pending_processor.dart';

// We have another instance of this due to Android requiring another RustLib for our DownloadTasks. This isn't necessary for iOS. We can only have one instance per process, thus needing this.
class RustBridgeHelper {
  static bool _initialized = false;

  static Future<void>? _initFuture;

  /// Call this to avoid double-initialize in Android in the entry-point
  static Future<void> ensureInitialized() {
    if (_initialized) {
      return Future.value();
    }

    _initFuture ??= _doInit();
    return _initFuture!;
  }

  static Future<void> _doInit() async {
    await RustLib.init();
    _initialized = true;
  }
}

const Duration _forceInitCooldown = Duration(seconds: 30);
const Duration _forceInitTimeout = Duration(seconds: 8);
final Map<String, DateTime> _forceInitLast = {};

bool _isEpochMismatch(String message) {
  return message.contains("message epoch") && message.contains("group epoch");
}

bool _isBusyError(String message) {
  return message.contains("Error: Busy");
}

Future<bool> _cameraStillExists(String cameraName) async {
  return AppCoordinationState.containsCamera(cameraName);
}

Future<void> _enqueuePendingVideo(String cameraName, String decFileName) async {
  final baseDir = await AppPaths.dataDirectory();
  final filePath = p.join(
    baseDir.path,
    'waiting',
    'camera_$cameraName',
    decFileName,
  );

  final parentDir = Directory(p.dirname(filePath));
  if (!await parentDir.exists()) {
    await parentDir.create(recursive: true);
  }

  final creationIndicationFile = File(filePath);
  if (!await creationIndicationFile.exists()) {
    await creationIndicationFile.create();
  }

  SendPort? port = IsolateNameServer.lookupPortByName(
    'queue_processor_signal_port',
  );
  port?.send('signal_new_file');

  if (UiState.isBindingReady) {
    camerasPageKey.currentState?.invalidateThumbnail(cameraName);
  } else {
    Log.d("Skipping thumbnail invalidate; UI not initialized");
  }
}

Future<bool> _maybeForceInit(String cameraName, String reason) async {
  final now = DateTime.now();
  final lastAttempt = _forceInitLast[cameraName];
  if (lastAttempt != null && now.difference(lastAttempt) < _forceInitCooldown) {
    Log.w(
      "[download] Skipping force init for $cameraName (cooldown active, reason=$reason)",
    );
    return false;
  }

  _forceInitLast[cameraName] = now;
  Log.w("[download] Forcing init for $cameraName (reason=$reason)");
  final outcome = await initialize(
    cameraName,
    timeout: _forceInitTimeout,
    force: true,
  );
  return outcome.isOk;
}

Future<bool> _runDownloadWithContext(String cameraName, String source) async {
  final traceId = Log.deriveContext('dl');
  return Log.runWithContext(traceId, () async {
    Log.d(
      "Download context started (source=$source, camera=$cameraName, id=$traceId)",
    );
    return await retrieveVideos(cameraName);
  });
}

Future<bool> doWorkNonBackground(String cameraName) async {
  // TODO: Should we wait for downloadingMotionVideos to be false before continuing? Is this meant to be a spinlock?

  if (await lock(Constants.genericDownloadTaskLock)) {
    try {
      Log.d("Starting to work in non-background mode");

      bool result = await _runDownloadWithContext(cameraName, "foreground");

      QueueProcessor.instance.signalNewFile();
      return result;
    } finally {
      await unlock(
        Constants.genericDownloadTaskLock,
      ); // Always ensure this unlocks, even on exceptions
    }
  } else {
    Log.w("Download task already running; will queue work");
    return false;
  }
}

Future<bool> doWorkBackground() async {
  final traceId = Log.deriveContext('dlw');
  return Log.runWithContext(traceId, () async {
    Log.d("Download worker context started (id=$traceId)");
    // TODO: We should also create synchronization between any motion download (if we were to have some sort of download from the main)
    if (Platform.isAndroid) {
      await RustBridgeHelper.ensureInitialized();
    }
    Log.d("Starting to work");

    // Perform an initial check (before lock)
    if (!await AppCoordinationState.hasAnyDownloadQueue()) {
      Log.w("There are no pref keys to base off of.");
      return true;
    }

    if (await lock(Constants.genericDownloadTaskLock)) {
      try {
        if (await lock(Constants.cameraWaitingLock)) {
          var downloadCameraQueue;
          try {
            // Secondary check after locking
            if (!await AppCoordinationState.hasAnyDownloadQueue()) {
              Log.e("There are no pref keys to base off of.");
              return true;
            }

            downloadCameraQueue = await AppCoordinationState.getDownloadQueue();

            var backupDownloadCameraQueue =
                await AppCoordinationState.getBackupDownloadQueue();
            if (downloadCameraQueue.isEmpty) {
              downloadCameraQueue =
                  backupDownloadCameraQueue; // Replace the existing queue with the pre-existing backup.
            } else if (backupDownloadCameraQueue.isNotEmpty) {
              // Merge the two queues (without duplicates by using sets)
              downloadCameraQueue =
                  downloadCameraQueue
                      .toSet()
                      .union(backupDownloadCameraQueue.toSet())
                      .toList();
            }

            downloadCameraQueue = await _sanitizeDownloadQueue(
              downloadCameraQueue ?? <String>[],
            );
            if (downloadCameraQueue.isEmpty) {
              Log.w("No valid cameras in download queue after sanitization");
              await AppCoordinationState.clearDownloadQueues();
              return true;
            }

            // Await these, so that they don't run outside the lock.
            await AppCoordinationState.setBackupDownloadQueue(
              downloadCameraQueue,
            ); // Create a backup of the current list.
            await AppCoordinationState.clearDownloadQueue(); // Delete the existing list, so that we know any new entries from this point will require an additional download later
          } finally {
            // Ensure this always unlocks
            await unlock(Constants.cameraWaitingLock);
            Log.d("Released lock");
          }
          if (downloadCameraQueue != null) {
            // What if we have uneven cameras within the batch? Say we have 6 cameras. Three have 10 videos to download. Three have 1. It seems best to associate them when batching, but we randomize currently.
            var batchSize = Constants.downloadBatchSize;
            var batchedQueue = batch(downloadCameraQueue, batchSize);
            Log.d("Batched Queue List: $batchedQueue");

            var retrieveResults = [];
            for (int i = 1; i <= batchedQueue.length; i++) {
              var currentSet = batchedQueue[i - 1];
              Log.d("Batch #$i = $currentSet");

              // Queue all of the current batch
              var currentFutures = [];
              for (int j = 0; j < currentSet.length; j++) {
                currentFutures.add(
                  _runDownloadWithContext(currentSet[j], "background"),
                ); // This is an async function, so it'll run all of these in parallel
              }
              Log.d("Awaiting batch completion");
              // Wait for all of the current batch to complete.
              for (int j = 0; j < currentSet.length; j++) {
                retrieveResults.add(await currentFutures[j]);
              }
              Log.d("Batch completed");
            }

            // Track if at least one was successful, and if we had a single failure or not.
            var oneSuccessful = false;
            var allSuccessful = true;

            await lock(
              Constants.cameraWaitingLock,
            ); // TODO: I'm not sure what to do if this is false. Is it even possible for it to be false? It's blocking.

            try {
              var downloadQueueCopy = List<String>.from(downloadCameraQueue);
              for (int i = 0; i < batchedQueue.length; i++) {
                for (int j = 0; j < batchedQueue[i].length; j++) {
                  var index = i * batchSize + j;
                  if (retrieveResults[index]) {
                    oneSuccessful = true;
                    var cameraName =
                        downloadQueueCopy[index]; // Work from a clone to avoid self-modification
                    downloadCameraQueue.remove(cameraName);
                  } else {
                    allSuccessful =
                        false; // We maintain a queue of ones that still need to be processed.
                  }
                }
              }

              Log.d("After queue cleanup");

              // Merge the failed list and ones that still need updates.
              if (await AppCoordinationState.hasDownloadQueue()) {
                Log.d("Merging lists together");
                List<String> updatedList =
                    await AppCoordinationState.getDownloadQueue();
                downloadCameraQueue =
                    downloadCameraQueue
                        .toSet()
                        .union(updatedList.toSet())
                        .toList();
              } else {
                Log.d("Prefs did not contain new updates");
              }

              downloadCameraQueue = await _sanitizeDownloadQueue(
                downloadCameraQueue,
              );

              // Set the new list to be scheduled next time,
              if (downloadCameraQueue.isEmpty) {
                await AppCoordinationState.clearDownloadQueue();
              } else {
                await AppCoordinationState.setDownloadQueue(
                  downloadCameraQueue,
                );
              }
              await AppCoordinationState.clearBackupDownloadQueue();
            } finally {
              await unlock(
                Constants.cameraWaitingLock,
              ); // Always ensure this unlocks.
            }

            // If at least one succeeded, we know we need to potentially update the camera list.
            if (oneSuccessful) {
              Log.d("Signaling for camera list update");
              QueueProcessor.instance.signalNewFile();
            }

            // If some didn't succeed, we need to schedule another task to run later.
            // Additionally, there's a chance we could have more now from merging with the new list.
            // False means we retry the task again later
            var currentState = allSuccessful && downloadCameraQueue.length == 0;
            Log.d("Returning $currentState, all successful = $allSuccessful");
            return currentState;
          }
        } else {
          Log.w("Failed to acquire motion lock");
        }
      } finally {
        await unlock(
          Constants.genericDownloadTaskLock,
        ); // Always ensure this unlocks, even on exceptions
      }
    } else {
      Log.w("Download task already running; skipping background work");
      return true;
    }

    return false;
  });
}

/// Separate a long list into batches of size batchSize
List<List<T>> batch<T>(List<T> items, int batchSize) {
  List<List<T>> result = [];
  for (var i = 0; i < items.length; i += batchSize) {
    result.add(
      items.sublist(
        i,
        i + batchSize > items.length ? items.length : i + batchSize,
      ),
    );
  }
  return result;
}

List<String> _dedupePreserveOrder(List<String> items) {
  final seen = <String>{};
  final result = <String>[];
  for (final item in items) {
    if (seen.add(item)) {
      result.add(item);
    }
  }
  return result;
}

Future<List<String>> _sanitizeDownloadQueue(List<String> queue) async {
  final nonEmpty =
      queue.where((cameraName) => cameraName.trim().isNotEmpty).toList();
  final cameraSet = await AppCoordinationState.getCameraSet();
  if (cameraSet.isEmpty) {
    if (nonEmpty.isNotEmpty) {
      Log.w(
        "Dropping all cameras from download queue because camera set is empty: $nonEmpty",
      );
    } else if (nonEmpty.length != queue.length) {
      Log.w("Dropping empty camera names from download queue");
    }
    return const <String>[];
  }

  final cameraSetLookup = cameraSet.toSet();
  final filtered =
      nonEmpty
          .where((cameraName) => cameraSetLookup.contains(cameraName))
          .toList();
  final dropped = nonEmpty.where((c) => !cameraSetLookup.contains(c)).toList();
  if (dropped.isNotEmpty) {
    Log.w("Dropping unknown cameras from download queue: $dropped");
  }
  return _dedupePreserveOrder(filtered);
}

//TODO: What if we miss a notification and don't get one for a long time? Should we occasionally query? What about if the user is in the app without any notifications?

Future<bool> retrieveVideos(String cameraName) async {
  Log.d("Entered for $cameraName");
  if (VersionGate.isBlocked) {
    await HttpClientService.instance.potentiallySendBackgroundNotification();
    Log.d(
      "$cameraName: Skipping video retrieval because version gate is active.",
    );
    return true;
  }
  if (!await _cameraStillExists(cameraName)) {
    Log.d(
      "$cameraName: Camera deleted before background download started; skipping.",
    );
    return true;
  }
  final cameraLock = "motion$cameraName.lock";
  if (await lock(cameraLock)) {
    await DownloadStatus.markActive(cameraName, true);
    var epoch = await readEpoch(cameraName, "video");
    const downloadTimeout = Duration(seconds: 60);

    // We could crash/be terminated at any point during execution.
    // We need to perform the following steps carefully so that we
    // don't end up with a "fatal crash point", i.e., a crash that
    // will corrupt the MLS channel for good. For example, imagine
    // that we download the video and delete it from the server and
    // then we crash before decrypting it. At that point, the video
    // file, which includes the MLS commit msg, is gone and we won't
    // be able to decrypt any other videos on that channel anymore.
    // So here's the order of steps that should work:
    // 1. Download the video
    // 2. Decrypt the video (which merges the MLS commit)
    //    We should not terminate the loop if this step fails
    //    since that could happen if we previously crashed between
    //    steps 2 and 3.
    // 3. Increase epoch number in shared preferences
    // 4. Delete file from server

    try {
      while (true) {
        if (!await _cameraStillExists(cameraName)) {
          Log.d(
            "$cameraName: Camera deleted during background download loop; aborting.",
          );
          return true;
        }
        Log.d(
          "Trying to download video for epoch $epoch with $cameraName and encVideo$epoch",
        );

        final assumedEpoch = epoch > 0 ? epoch - 1 : 0;
        final fileName = "encVideo$epoch";
        final downloadSw = Stopwatch()..start();
        var result = await HttpClientService.instance.download(
          destinationFile: fileName,
          cameraName: cameraName,
          serverFile: epoch.toString(),
          type: Group.motion,
          timeout: downloadTimeout,
        );
        downloadSw.stop();
        if (!kReleaseMode) {
          Log.d(
            "[perf] Download motion $cameraName epoch $epoch in ${downloadSw.elapsedMilliseconds}ms (ok=${result.isSuccess})",
          );
        }

        if (result.isFailure) {
          Log.d("HTTP download of encrypted video failed");
          return false;
        } else {
          //result.isSuccess
          if (result.value!.not_found) {
            // There's no video to download
            Log.d("Finished downloading encrypted videos for $cameraName");
            return true;
          }

          Log.d("Success!");
          var file = result.value!.file!;
          if (!await _cameraStillExists(cameraName)) {
            Log.d(
              "$cameraName: Camera deleted after encrypted video download; discarding work.",
            );
            if (await file.exists()) {
              await file.delete();
            }
            return true;
          }
          final decryptSw = Stopwatch()..start();
          var decFileName = await decryptVideo(
            cameraName: cameraName,
            encFilename: fileName,
            assumedEpoch: BigInt.from(assumedEpoch),
          );
          decryptSw.stop();
          if (!kReleaseMode) {
            Log.d(
              "[perf] Decrypt motion $cameraName $fileName in ${decryptSw.elapsedMilliseconds}ms (result=$decFileName)",
            );
          }
          if (decFileName.startsWith("Error")) {
            Log.w("Decrypt failed for $cameraName epoch $epoch: $decFileName");
            if (_isBusyError(decFileName)) {
              Log.w(
                "Motion decrypt busy for $cameraName epoch $epoch; skipping for now",
              );
            }
            if (_isEpochMismatch(decFileName)) {
              final markerPayload = await readEpochMarker(
                cameraName,
                "motion",
                epoch,
              );
              if (markerPayload != null) {
                final cameraDir = await AppPaths.cameraDirectory(cameraName);
                final decPath = p.join(cameraDir.path, 'videos', markerPayload);
                final decFile = File(decPath);
                if (await decFile.exists()) {
                  await _enqueuePendingVideo(cameraName, markerPayload);
                } else {
                  Log.w(
                    "Epoch marker exists but decrypted file missing: $decPath",
                  );
                }
                Log.w(
                  "Epoch mismatch for $cameraName epoch $epoch but marker exists; treating as duplicate",
                );
                await file.delete();
                await writeEpoch(cameraName, "video", epoch + 1);
                await HttpClientService.instance.delete(
                  destinationFile: fileName,
                  cameraName: cameraName,
                  serverFile: epoch.toString(),
                  type: Group.motion,
                );
                epoch += 1;
                continue;
              } else {
                Log.w(
                  "Epoch marker exists for $cameraName epoch $epoch but no payload; not skipping",
                );
              }
            }
            final forceOk = await _maybeForceInit(cameraName, "decrypt_video");
            if (forceOk) {
              final retrySw = Stopwatch()..start();
              decFileName = await decryptVideo(
                cameraName: cameraName,
                encFilename: fileName,
                assumedEpoch: BigInt.from(assumedEpoch),
              );
              retrySw.stop();
              if (!kReleaseMode) {
                Log.d(
                  "[perf] Decrypt motion retry $cameraName $fileName in ${retrySw.elapsedMilliseconds}ms (result=$decFileName)",
                );
              }
            }
          }

          if (decFileName.startsWith("Error")) {
            Log.e(
              "Decrypt failed for $cameraName epoch $epoch; leaving epoch unchanged",
            );
          }

          Log.d("Dec file name = $decFileName");

          // Delete only after successful decrypt to avoid losing MLS commits.
          if (await file.exists()) {
            try {
              await file.delete();
            } catch (e) {
              Log.e("Failed to delete encrypted file $fileName: $e");
            }
          } else {
            Log.w("Encrypted file already missing: $fileName");
          }

          Log.d("Received 100%");

          if (!await _cameraStillExists(cameraName)) {
            Log.d(
              "$cameraName: Camera deleted after decrypt; skipping pending queue updates.",
            );
            return true;
          }

          if (decFileName != "Duplicate") {
            await _enqueuePendingVideo(cameraName, decFileName);
          }

          await writeEpoch(cameraName, "video", epoch + 1);

          await HttpClientService.instance.delete(
            destinationFile: fileName,
            cameraName: cameraName,
            serverFile: epoch.toString(),
            type: Group.motion,
          );

          epoch += 1;
        }
      }
    } finally {
      await DownloadStatus.markActive(cameraName, false);
      await unlock(cameraLock);
    }
  } else {
    Log.w("Motion download lock busy for $cameraName; skipping");
    return false;
  }
}
