//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/video_thumbnail_fallback.dart';

class VideoThumbnailStore {
  VideoThumbnailStore._();

  static final Map<String, Future<Uint8List?>> _pending = {};

  static String? timestampTokenFromVideo(String videoFile) {
    if (!videoFile.startsWith('video_') || !videoFile.endsWith('.mp4')) {
      return null;
    }
    return videoFile.substring(6, videoFile.length - 4);
  }

  static Future<Uint8List?> loadOrGenerate({
    required String cameraName,
    required String videoFile,
    String? logPrefix,
  }) async {
    final timestamp = timestampTokenFromVideo(videoFile);
    if (timestamp == null) {
      if (logPrefix != null) {
        Log.d(
          '$logPrefix [$cameraName/$videoFile]: could not derive timestamp token',
        );
      }
      return null;
    }

    final cacheKey = '$cameraName\n$videoFile';
    final inFlight = _pending[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final future = () async {
      try {
        final cameraDir = await AppPaths.cameraDirectory(cameraName);
        final videosDir = p.join(cameraDir.path, 'videos');
        final thumbPath = p.join(videosDir, 'thumbnail_$timestamp.png');

        final existingBytes = await _readValidatedImageBytes(thumbPath);
        if (existingBytes != null) {
          if (logPrefix != null) {
            Log.d(
              '$logPrefix [$cameraName/$videoFile]: loaded existing $thumbPath (${existingBytes.length} bytes)',
            );
          }
          return existingBytes;
        }

        final videoPath = p.join(videosDir, videoFile);
        final video = File(videoPath);
        if (!await video.exists()) {
          if (logPrefix != null) {
            Log.d(
              '$logPrefix [$cameraName/$videoFile]: video missing at $videoPath',
            );
          }
          return null;
        }

        final generated = await VideoThumbnailFallback.generate(videoPath);
        if (generated == null || !await _isValidImageBytes(generated)) {
          if (logPrefix != null) {
            Log.w(
              '$logPrefix [$cameraName/$videoFile]: native thumbnail extraction failed',
            );
          }
          return null;
        }

        await Directory(videosDir).create(recursive: true);
        await File(thumbPath).writeAsBytes(generated, flush: true);

        if (logPrefix != null) {
          Log.d(
            '$logPrefix [$cameraName/$videoFile]: generated $thumbPath (${generated.length} bytes)',
          );
        }
        return generated;
      } catch (e) {
        Log.e(
          'Video thumbnail load/generate error [$cameraName/$videoFile]: $e',
        );
        return null;
      } finally {
        _pending.remove(cacheKey);
      }
    }();

    _pending[cacheKey] = future;
    return future;
  }

  static Future<Uint8List?> _readValidatedImageBytes(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    try {
      final bytes = await file.readAsBytes();
      if (await _isValidImageBytes(bytes)) {
        return bytes;
      }
    } catch (e) {
      Log.w('Existing video thumbnail invalid [$path]: $e');
    }
    return null;
  }

  static Future<bool> _isValidImageBytes(Uint8List bytes) async {
    try {
      final image = await decodeImageFromList(bytes);
      image.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }
}
