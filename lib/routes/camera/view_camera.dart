//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:flutter/services.dart';
import 'package:secluso_flutter/notifications/download_task.dart';
import 'package:secluso_flutter/notifications/download_status.dart';
import 'package:secluso_flutter/notifications/thumbnails.dart';
import 'package:secluso_flutter/routes/app_shell.dart';
import 'package:secluso_flutter/routes/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'view_video.dart';
import 'view_livestream.dart';
import 'camera_settings.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/main.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_theme.dart';
import 'package:secluso_flutter/utilities/video_thumbnail_store.dart';

_CameraViewPageState? globalCameraViewPageState;

const Color _designDarkCameraCardFill = Color(0xFF0D0D0D);
const Color _designDarkCameraCardBorder = Color(0x0DFFFFFF);

class CameraViewPage extends StatefulWidget {
  final String cameraName;
  final List<Video>? previewVideos;
  final Map<String, Set<String>>? previewDetectionsByVideo;
  final Map<String, String>? previewThumbAssetsByVideo;
  final Map<String, String>? previewVideoAssetsByVideo;
  final Map<String, Duration>? previewDurationByVideo;
  final String? previewHeroAssetPath;
  final String? previewHeroVideoAssetPath;
  final bool previewDownloadActive;

  const CameraViewPage({
    super.key,
    required this.cameraName,
    this.previewVideos,
    this.previewDetectionsByVideo,
    this.previewThumbAssetsByVideo,
    this.previewVideoAssetsByVideo,
    this.previewDurationByVideo,
    this.previewHeroAssetPath,
    this.previewHeroVideoAssetPath,
    this.previewDownloadActive = false,
  });

  @override
  State<CameraViewPage> createState() => _CameraViewPageState();
}

String repackageVideoTitle(String videoFileName) {
  if (videoFileName.startsWith("video_") && videoFileName.endsWith(".mp4")) {
    var timeOf = int.parse(
      videoFileName.replaceAll("video_", "").replaceAll(".mp4", ""),
    );
    final date =
        DateTime.fromMillisecondsSinceEpoch(
          timeOf * 1000,
          isUtc: true,
        ).toLocal();
    return DateFormat('MMM d · h:mm a').format(date);
  }

  return videoFileName;
}

class _CameraViewPageState extends State<CameraViewPage> with RouteAware {
  late AppVideoStore _videoStore;
  final List<Video> _videos = [];
  final Map<String, Uint8List?> _videoThumbCache = {};
  final Map<String, Future<Uint8List?>> _videoThumbFutures = {};

  late AppDetectionStore _detectionStore;
  final Map<int, Set<String>> _detCache = {};

  static const int _pageSize = 20;
  int _offset = 0;
  bool _hasMore = true;
  bool _isLoading = false;
  int _dataGeneration = 0;

  final ScrollController _scrollController = ScrollController();
  Timer? _downloadStatusTimer;
  late final VoidCallback _downloadStatusListener;
  bool _downloadActive = false;
  bool get _isPreviewMode => widget.previewVideos != null;

  int _cameraStatus = CameraStatus.online;

  Future<void> _openSettings() async {
    final action = await Navigator.push<CameraSettingsAction>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(cameraName: widget.cameraName),
      ),
    );
    if (action != CameraSettingsAction.removeCamera || !mounted) {
      return;
    }
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  /// We store an unreadMessages flag instead of iterating through all videos to be more efficient
  Future<void> _markCameraRead() async {
    if (!AppStores.isInitialized) {
      try {
        await AppStores.init();
      } catch (e, st) {
        Log.e("Failed to init AppStores: $e\n$st");
        return;
      }
    }
    final foundCamera = await AppStores.instance.cameraStore.findFirstByName(
      widget.cameraName,
    );

    if (foundCamera != null && foundCamera.unreadMessages) {
      foundCamera.unreadMessages = false;
      await AppStores.instance.cameraStore.put(foundCamera);
    }
  }

  @override
  void initState() {
    super.initState();
    globalCameraViewPageState = this;
    if (_isPreviewMode) {
      _videos.addAll(widget.previewVideos!);
      for (final video in widget.previewVideos!) {
        _detCache[video.id] =
            widget.previewDetectionsByVideo?[video.video] ?? const <String>{};
      }
      _downloadActive = widget.previewDownloadActive;
      _hasMore = false;
      return;
    }
    _scrollController.addListener(_maybeLoadNextPage);
    _downloadActive = DownloadStatus.isActiveInMemory(widget.cameraName);
    _downloadStatusListener = () {
      final active = DownloadStatus.isActiveInMemory(widget.cameraName);
      if (active != _downloadActive && mounted) {
        setState(() => _downloadActive = active);
      }
    };
    DownloadStatus.active.addListener(_downloadStatusListener);
    _downloadStatusTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => DownloadStatus.syncFromPrefs(),
    );
    unawaited(DownloadStatus.syncFromPrefs());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isPreviewMode) return;
    final ModalRoute? route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    if (_isPreviewMode) return;
    Log.d("Returned to view camera [pop]");
    _videoThumbCache.clear();
    _videoThumbFutures.clear();
    _markCameraRead(); // Load this every time we enter the page.
    _initDbAndFirstPage();
  }

  @override
  void didPush() {
    if (_isPreviewMode) return;
    Log.d('Returned to view camera [push]');
    _videoThumbCache.clear();
    _videoThumbFutures.clear();
    _markCameraRead(); // Load this every time we enter the page.
    _initDbAndFirstPage();
  }

  Future<void> _prefetchDetectionsFor(List<Video> vids) async {
    for (final v in vids) {
      final vidPath = v.video;
      final detsForVid = await _detectionStore.findByVideoFile(vidPath);
      final matchingTypes = <String>{};

      for (final d in detsForVid) {
        if (d.type.isNotEmpty) matchingTypes.add(d.type.toLowerCase());
      }
      _detCache[v.id] = matchingTypes;
    }
  }

  Future<void> _initDbAndFirstPage() async {
    if (!AppStores.isInitialized) {
      try {
        await AppStores.init();
      } catch (e, st) {
        Log.e("Failed to init AppStores: $e\n$st");
        return;
      }
    }
    _videoStore = AppStores.instance.videoStore;
    _detectionStore = AppStores.instance.detectionStore;
    await _loadNextPage(); // first 20

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final cameraName = widget.cameraName;
    final cameraStatus =
      prefs.getInt(PrefKeys.cameraStatusPrefix + cameraName) ??
      CameraStatus.online;

    if (mounted) {
      setState(() => _cameraStatus = cameraStatus);
    }
    Log.d("Viewing camera: camera status = $cameraStatus");

    if (cameraStatus == CameraStatus.offline ||
        cameraStatus == CameraStatus.corrupted ||
        cameraStatus == CameraStatus.possiblyCorrupted) {
      late final String msg;

      if (cameraStatus == CameraStatus.offline) {
        msg = "Camera ($cameraName) seems to be offline.";
      } else if (cameraStatus == CameraStatus.corrupted) {
        msg = "Camera ($cameraName) is corrupted. Pair again.";
      } else {
        //possiblyCorrupted
        msg = "Camera ($cameraName) is likely corrupted. Pair again.";
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    if (!_isPreviewMode) {
      routeObserver.unsubscribe(this);
      _downloadStatusTimer?.cancel();
      DownloadStatus.active.removeListener(_downloadStatusListener);
    }
    globalCameraViewPageState = null;

    super.dispose();
  }

  Future<void> reloadVideos() async {
    final int generation = _dataGeneration;
    _videoThumbCache.clear();
    _videoThumbFutures.clear();
    final newVideos = await _videoStore.listByCamera(
      widget.cameraName,
      limit: _pageSize,
    );

    await _prefetchDetectionsFor(newVideos);

    if (generation != _dataGeneration || !mounted) return;
    setState(() {
      _videos.clear();
      _videos.addAll(newVideos);
      _hasMore = newVideos.length == _pageSize;
    });
  }

  Future<void> _loadNextPage() async {
    if (!_hasMore || _isLoading) return;
    setState(() => _isLoading = true);
    final int generation = _dataGeneration;
    final batch = await _videoStore.listByCamera(
      widget.cameraName,
      limit: _pageSize,
      offset: _offset,
    );

    await _prefetchDetectionsFor(batch);

    if (generation != _dataGeneration || !mounted) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _videos.addAll(batch);
      _offset += batch.length;
      _hasMore = batch.length == _pageSize;
      _isLoading = false;
    });
  }

  void _maybeLoadNextPage() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_isLoading) {
      _loadNextPage();
    }
  }

  // Useful for debugging
  /*
  Future<void> _printAllFiles(String cameraName) async {
    Log.d("_printAllFiles called for $cameraName");
    final docsDir = await AppPaths.dataDirectory();
    final dir = Directory(p.join(docsDir.path, 'camera_dir_$cameraName'));

    if (!await dir.exists()) return;

    Log.d("printing all files in the camera directory");
    final entries = await dir.list(followLinks: false).toList();
    for (final ent in entries) {
      Log.d("_printAllFiles: $cameraName: ${ent.path}");
    }

    final videosDir = Directory(p.join(dir.path, 'videos'));

    if (!await videosDir.exists()) return;

    Log.d("printing all files in the camera's video directory");
    final ventries = await videosDir.list(followLinks: false).toList();
    for (final ent in ventries) {
      Log.d("_printAllFiles: $cameraName: ${ent.path}");
    }
  }
  */

  void _deleteAllVideos() async {
    HapticFeedback.heavyImpact();
    _dataGeneration++;
    _isLoading = false;

    final dir = await AppPaths.dataDirectory();
    final videoDir = Directory(
      '${dir.path}/camera_dir_${widget.cameraName}/videos',
    );
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const recentThresholdMs = 15000;

    int? newestVideoTs;
    final deletedPaths = <String>[];
    final deletedVideoNames = <String>{};
    if (await videoDir.exists()) {
      try {
        final entries = await videoDir.list(followLinks: false).toList();
        for (final entry in entries) {
          if (entry is! File) continue;
          final name = p.basename(entry.path);
          final ts = _timestampFromVideo(name);
          if (ts != null) {
            final parsed = int.tryParse(ts);
            if (parsed != null) {
              if (newestVideoTs == null || parsed > newestVideoTs) {
                newestVideoTs = parsed;
              }
            }
          }
        }

        for (final entry in entries) {
          if (entry is! File) continue;
          final name = p.basename(entry.path);
          if (name.startsWith("thumbnail_") && name.endsWith(".png")) {
            final tsStr = name.substring("thumbnail_".length, name.length - 4);
            final ts = int.tryParse(tsStr);
            if (newestVideoTs != null && ts != null && ts > newestVideoTs) {
              continue; // retain newer thumbnails
            }
          }
          bool shouldDelete = true;
          try {
            final stat = await entry.stat();
            if (nowMs - stat.modified.millisecondsSinceEpoch <
                recentThresholdMs) {
              shouldDelete = false; // skip very recent files
            }
          } catch (_) {}
          if (!shouldDelete) continue;
          deletedPaths.add(entry.path);
          try {
            await entry.delete();
            if (name.startsWith("video_") && name.endsWith(".mp4")) {
              deletedVideoNames.add(name);
            }
          } catch (e) {
            Log.e('Error deleting file ${entry.path}: $e');
          }
        }
        Log.d('Cleared camera folder: ${videoDir.path}');
      } catch (e) {
        Log.e('Error clearing folder: $e');
      }
    }

    // Ensure videos directory exists
    try {
      await videoDir.create(recursive: true);
    } catch (e) {
      Log.e("Error: Failed to create directory for videos");
    }

    final videosToDelete = await _videoStore.listByCamera(widget.cameraName);

    final ids =
        videosToDelete
            .where((v) => deletedVideoNames.contains(v.video))
            .map((v) => v.id)
            .toList();
    try {
      if (ids.isNotEmpty) {
        await _videoStore.removeMany(ids);
      }
    } catch (e) {
      Log.e("Error deleting videos from DB; retrying once: $e");
      try {
        if (ids.isNotEmpty) {
          await _videoStore.removeMany(ids);
        }
      } catch (e2) {
        Log.e("DB delete retry failed: $e2");
      }
    }

    try {
      final dbCount = await _videoStore.countForCamera(widget.cameraName);

      final remainingDeletedPaths = <String>[];
      for (final path in deletedPaths) {
        if (await File(path).exists()) {
          remainingDeletedPaths.add(path);
        }
      }

      if (dbCount != 0 || remainingDeletedPaths.isNotEmpty) {
        Log.e(
          "Delete all mismatch for ${widget.cameraName}: dbCount=$dbCount remainingFiles=$remainingDeletedPaths dir=${videoDir.path}",
        );
      }
    } catch (e) {
      Log.e("Error verifying delete all for ${widget.cameraName}: $e");
    }

    setState(() {
      _videos.clear();
      _offset = 0;
      _hasMore = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('All videos deleted.'),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );

    // nuke any residual caches
    _videoThumbCache.clear();
    _videoThumbFutures.clear();

    reloadVideos();
    await _logDeleteAllState(videoDir);
  }

  Future<void> _logDeleteAllState(Directory videoDir) async {
    try {
      final dbCount = await _videoStore.countForCamera(widget.cameraName);
      final remainingVideos = await _videoStore.listByCamera(widget.cameraName);

      final files = <String>[];
      final retainedThumbs = <String>[];
      int? newestVideoTs;
      if (await videoDir.exists()) {
        final entries = await videoDir.list(followLinks: false).toList();
        for (final entry in entries) {
          if (entry is! File) continue;
          final name = p.basename(entry.path);
          final ts = _timestampFromVideo(name);
          if (ts != null) {
            final parsed = int.tryParse(ts);
            if (parsed != null) {
              if (newestVideoTs == null || parsed > newestVideoTs) {
                newestVideoTs = parsed;
              }
            }
          }
          if (entry.path.endsWith(".mp4")) {
            files.add(entry.path);
          }
        }
        if (newestVideoTs != null) {
          for (final entry in entries) {
            if (entry is! File) continue;
            final name = p.basename(entry.path);
            if (name.startsWith("thumbnail_") && name.endsWith(".png")) {
              final tsStr = name.substring(
                "thumbnail_".length,
                name.length - 4,
              );
              final ts = int.tryParse(tsStr);
              if (ts != null && ts > newestVideoTs) {
                retainedThumbs.add(entry.path);
              }
            }
          }
        }
      }

      Log.d(
        "Delete all debug for ${widget.cameraName}: dbCount=$dbCount dbVideos=${remainingVideos.map((v) => v.video).toList()} files=$files retainedThumbs=$retainedThumbs",
      );
    } catch (e) {
      Log.e("Delete all debug failed for ${widget.cameraName}: $e");
    }
  }

  void _deleteOne(Video v, int index) async {
    final dir = await AppPaths.dataDirectory();

    if (v.received) {
      final videoPath = '${dir.path}/camera_dir_${v.camera}/videos/${v.video}';
      final file = File(videoPath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          Log.e('Error deleting file: $e');
        }
      }

      final ts = _timestampFromVideo(v.video);
      if (ts != null) {
        final thumbPath =
            '${dir.path}/camera_dir_${v.camera}/videos/thumbnail_$ts.png';
        final thumb = File(thumbPath);
        if (await thumb.exists()) {
          try {
            await thumb.delete();
          } catch (_) {}
        }
      }
    }

    _invalidateVideoThumb(v.camera, v.video);
    await _videoStore.removeMany([v.id]);
    setState(() => _videos.removeAt(index));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Video deleted'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  String? _timestampFromVideo(String videoFile) {
    // expects "video_<unix>.mp4"
    if (!videoFile.startsWith("video_") || !videoFile.endsWith(".mp4")) {
      return null;
    }
    return videoFile.substring(
      6,
      videoFile.length - 4,
    ); // strip "video_" and ".mp4"
  }

  Future<Uint8List?> _loadVideoThumbBytes(String cameraName, String videoFile) {
    final ts = _timestampFromVideo(videoFile);
    if (ts == null) {
      Log.d(
        'Camera thumb miss [$cameraName/$videoFile]: could not derive timestamp',
      );
      return Future.value(null);
    }
    final key = "$cameraName/$ts";

    if (_videoThumbCache.containsKey(key)) {
      Log.d('Camera thumb cache hit [$key]: ${_videoThumbCache[key] != null}');
      return Future.value(_videoThumbCache[key]);
    }
    if (_videoThumbFutures.containsKey(key)) {
      Log.d('Camera thumb future hit [$key]');
      return _videoThumbFutures[key]!;
    }

    final fut = () async {
      try {
        final bytes = await VideoThumbnailStore.loadOrGenerate(
          cameraName: cameraName,
          videoFile: videoFile,
          logPrefix: 'Camera thumb',
        );
        if (bytes == null) {
          _videoThumbCache[key] = null;
          return null;
        }
        _videoThumbCache[key] = bytes;
        return bytes;
      } catch (e) {
        Log.e("Video thumb load error [$key]: $e");
        _videoThumbCache[key] = null;
        return null;
      } finally {
        _videoThumbFutures.remove(key);
      }
    }();

    _videoThumbFutures[key] = fut;
    return fut;
  }

  void _invalidateVideoThumb(String cameraName, String videoFile) {
    final ts = _timestampFromVideo(videoFile);
    if (ts == null) return;
    final key = "$cameraName/$ts";
    _videoThumbCache.remove(key);
    _videoThumbFutures.remove(key);
  }

  String _detectionLabel(Set<String> types) {
    if (types.isEmpty) return 'None';
    final norm = {for (final t in types) (t == 'pets' ? 'pet' : t)};
    final ordered = <String>[];
    if (norm.contains('human')) ordered.add('Human');
    if (norm.contains('vehicle')) ordered.add('Vehicle');
    if (norm.contains('pet')) ordered.add('Pet');
    return ordered.join(', ');
  }

  Future<void> _onPullToRefresh() async {
    if (_isPreviewMode) return;
    await ThumbnailManager.retrieveThumbnails(camera: widget.cameraName);
    await retrieveVideos(widget.cameraName);
  }

  Future<void> _openLivestream() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => LivestreamPage(
              cameraName: widget.cameraName,
              previewAssetPath: _isPreviewMode ? _previewHeroAssetPath() : null,
              previewVideoAssetPath:
                  _isPreviewMode ? _previewHeroVideoAssetPath() : null,
            ),
      ),
    );
  }

  Widget _heroBackground() {
    if (_isPreviewMode) {
      final assetPath = _previewHeroAssetPath();
      if (assetPath != null) {
        return Image.asset(
          assetPath,
          fit: BoxFit.cover,
          alignment: Alignment.centerRight,
        );
      }
    }
    if (_videos.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              SeclusoColors.nightRaised,
              SeclusoColors.nightSoft,
              SeclusoColors.ink,
            ],
          ),
        ),
      );
    }

    final latestVideo = _videos.first;
    return FutureBuilder<Uint8List?>(
      future: _loadVideoThumbBytes(widget.cameraName, latestVideo.video),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          Log.d(
            'Hero thumb placeholder [${widget.cameraName}/${latestVideo.video}]: snapshot has no bytes',
          );
          return const Image(
            image: AssetImage('assets/android_thumbnail_placeholder.jpeg'),
            fit: BoxFit.cover,
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }

  Widget _heroCard() {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final latestKind =
        _videos.isEmpty
            ? 'Waiting'
            : (_videos.first.motion ? 'Detected' : 'Live');
    final latestLabel =
        latestKind == 'Detected'
            ? 'latest motion'
            : latestKind == 'Live'
            ? 'latest live capture'
            : 'waiting for archive';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color:
              dark
                  ? const Color(0xFF0C0D10)
                  : Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(32),
          border:
              dark ? null : Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: SizedBox(
            height: 380,
            child: Column(
              children: [
                Expanded(
                  flex: 7,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(child: _heroBackground()),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.04),
                                Colors.black.withValues(alpha: 0.12),
                                Colors.black.withValues(
                                  alpha: dark ? 0.44 : 0.24,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_downloadActive)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: SeclusoStatusChip(
                              label: 'Syncing archive',
                              color: SeclusoColors.warning,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.cameraName,
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _downloadActive
                              ? 'The archive is still syncing. Review stored clips while the rest catches up.'
                              : 'Open the live room or review saved moments.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.72,
                            ),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_videos.length} saved clips · $latestLabel',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.72,
                            ),
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _primaryBtn(
                                label: 'Go live',
                                icon: Icons.live_tv,
                                color: SeclusoColors.paper,
                                onTap: _openLivestream,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _secondaryActionButton(
                              icon: Icons.tune_rounded,
                              onTap:
                                  () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => SettingsPage(
                                            cameraName: widget.cameraName,
                                          ),
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SeclusoScaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        color:
            Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF050505)
                : const Color(0xFFF2F2F7),
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useLightEmptyLayout =
                  Theme.of(context).brightness == Brightness.light &&
                  _videos.isEmpty;
              final useDarkEmptyState =
                  Theme.of(context).brightness == Brightness.dark &&
                  _videos.isEmpty;
              final metrics = _CameraViewMetrics.forWidth(
                constraints.maxWidth,
                lightEmptyState: useLightEmptyLayout,
                darkEmptyState: useDarkEmptyState,
              );
              if (useLightEmptyLayout) {
                return _buildLightEmptyCameraDetail(metrics);
              }
              return RefreshIndicator.adaptive(
                onRefresh: _onPullToRefresh,
                child: ListView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    metrics.pageInset,
                    metrics.topPadding,
                    metrics.pageInset,
                    metrics.bottomPadding,
                  ),
                  children: [
                    _overviewHeader(metrics),
                    SizedBox(height: metrics.headerToHeroGap),
                    _overviewHeroCard(metrics),
                    SizedBox(height: metrics.heroToActionsGap),
                    Row(
                      children: [
                        Expanded(
                          child: _cameraActionCard(
                            icon: _DesignCameraActivityIcon(
                              size: metrics.actionIconSize,
                              color:
                                  Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white.withValues(alpha: 0.4)
                                      : const Color(0xFF6B7280),
                            ),
                            title: 'Activity',
                            subtitle: 'View events',
                            metrics: metrics,
                            onTap:
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => const AppShell(initialIndex: 1),
                                  ),
                                ),
                          ),
                        ),
                        SizedBox(width: metrics.actionCardGap),
                        Expanded(
                          child: _cameraActionCard(
                            icon: _DesignCameraSettingsIcon(
                              size: metrics.actionIconSize,
                              color:
                                  Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white.withValues(alpha: 0.4)
                                      : const Color(0xFF6B7280),
                            ),
                            title: 'Settings',
                            subtitle: 'Configure',
                            metrics: metrics,
                            onTap: _openSettings,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: metrics.sectionTopGap),
                    Row(
                      children: [
                        Text(
                          'SAVED CLIPS',
                          style: Theme.of(
                            context,
                          ).textTheme.labelMedium?.copyWith(
                            color: _sectionLabelColor(context),
                            fontSize: metrics.sectionLabelSize,
                            fontWeight: FontWeight.w600,
                            letterSpacing: metrics.sectionLabelLetterSpacing,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_videos.length} clips',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color: _sectionMetaColor(context),
                            fontSize: metrics.sectionMetaSize,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: metrics.sectionToListGap),
                    if (_videos.isEmpty)
                      _cameraEmptyState(metrics)
                    else
                      for (var i = 0; i < _videos.length; i++) ...[
                        _clipCard(_videos[i], i, metrics),
                        if (i != _videos.length - 1)
                          SizedBox(height: metrics.clipGap),
                      ],
                    if (_hasMore)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLightEmptyCameraDetail(_CameraViewMetrics metrics) {
    return RefreshIndicator.adaptive(
      onRefresh: _onPullToRefresh,
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          0,
          metrics.topPadding,
          0,
          metrics.bottomPadding,
        ),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: metrics.headerInset),
            child: _overviewHeader(metrics),
          ),
          SizedBox(height: metrics.headerToHeroGap),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: metrics.contentInset),
            child: _overviewHeroCard(metrics),
          ),
          SizedBox(height: metrics.heroToActionsGap),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: metrics.contentInset),
            child: Row(
              children: [
                Expanded(
                  child: _cameraActionCard(
                    icon: _DesignCameraActivityIcon(
                      size: metrics.actionIconSize,
                      color: const Color(0xFF6B7280),
                    ),
                    title: 'Activity',
                    subtitle: 'View events',
                    metrics: metrics,
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AppShell(initialIndex: 1),
                          ),
                        ),
                  ),
                ),
                SizedBox(width: metrics.actionCardGap),
                Expanded(
                  child: _cameraActionCard(
                    icon: _DesignCameraSettingsIcon(
                      size: metrics.actionIconSize,
                      color: const Color(0xFF6B7280),
                    ),
                    title: 'Settings',
                    subtitle: 'Configure',
                    metrics: metrics,
                    onTap: _openSettings,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.sectionTopGap),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: metrics.headerInset),
            child: Row(
              children: [
                Text(
                  'SAVED CLIPS',
                  style: TextStyle(
                    color: const Color(0xFF9CA3AF),
                    fontSize: metrics.sectionLabelSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: metrics.sectionLabelLetterSpacing,
                    height: 1.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '0 clips',
                  style: TextStyle(
                    color: const Color(0xFF9CA3AF),
                    fontSize: metrics.sectionMetaSize,
                    fontWeight: FontWeight.w400,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.sectionToListGap),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: metrics.contentInset),
            child: _cameraEmptyState(metrics),
          ),
          if (_hasMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _overviewHeader(_CameraViewMetrics metrics) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final isOnline = _cameraStatus == CameraStatus.online;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _circleIconButton(
          metrics: metrics,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        SizedBox(width: metrics.headerGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.cameraName,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: dark ? Colors.white : const Color(0xFF111827),
                  fontSize: metrics.titleSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -metrics.titleLetterSpacing,
                  height: 28 / 18,
                ),
              ),
              SizedBox(height: metrics.titleToStatusGap),
              Row(
                children: [
                  Container(
                    width: metrics.statusDotSize,
                    height: metrics.statusDotSize,
                    decoration: BoxDecoration(
                      color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: metrics.statusDotGap),
                  Text(
                    isOnline ? 'ONLINE · E2E ENCRYPTED' : 'OFFLINE',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.4)
                              : const Color(0xFF6B7280),
                      fontSize: metrics.statusTextSize,
                      fontWeight: FontWeight.w400,
                      letterSpacing: metrics.statusLetterSpacing,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            top: (metrics.backButtonSize - metrics.headerLockSize) / 2,
          ),
          child: SizedBox(
            width: metrics.headerLockSize,
            height: metrics.headerLockSize,
            child: CustomPaint(
              painter: _DesignCameraLockPainter(
                color:
                    dark
                        ? Colors.white.withValues(alpha: 0.7)
                        : const Color(0xFF4B5563),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _overviewHeroCard(_CameraViewMetrics metrics) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final asset = _previewHeroAssetPath();
    final playIconSize =
        dark ? metrics.heroPlayIconSize * (24 / 28) : metrics.heroPlayIconSize;
    final playIconOffsetX =
        dark ? metrics.heroPlayIconOffsetX + 1 : metrics.heroPlayIconOffsetX;
    return Container(
      height: metrics.heroHeight,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0A0A0A) : Colors.transparent,
        borderRadius: BorderRadius.circular(metrics.heroRadius),
        border: Border.all(
          color:
              dark ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(metrics.heroRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (asset != null)
              Image.asset(asset, fit: BoxFit.cover, alignment: Alignment.center)
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors:
                        dark
                            ? const [Color(0xFF1E293B), Color(0xFF0F172A)]
                            : const [Color(0xFFD7DEE8), Color(0xFFB9C7D8)],
                  ),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: metrics.heroInset,
              left: metrics.heroInset,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(
                    height: metrics.heroLiveChipHeight,
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.heroLiveChipPadding,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: metrics.heroLiveChipDotSize,
                          height: metrics.heroLiveChipDotSize,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: metrics.heroLiveChipGap),
                        Text(
                          'TAP TO VIEW LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: metrics.heroLiveChipTextSize,
                            fontWeight: FontWeight.w600,
                            letterSpacing: metrics.heroLiveChipLetterSpacing,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: GestureDetector(
                onTap: _openLivestream,
                child: Container(
                  width: metrics.heroPlayButtonSize,
                  height: metrics.heroPlayButtonSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 15,
                        offset: Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 6,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: metrics.heroPlayBlurSigma,
                        sigmaY: metrics.heroPlayBlurSigma,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.2),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          gradient: RadialGradient(
                            center: const Alignment(-0.25, -0.3),
                            radius: 1.1,
                            colors: [
                              Colors.white.withValues(alpha: 0.16),
                              Colors.white.withValues(alpha: 0.08),
                              Colors.white.withValues(alpha: 0.02),
                            ],
                            stops: const [0, 0.48, 1],
                          ),
                        ),
                        child: Center(
                          child: Transform.translate(
                            offset: Offset(playIconOffsetX, 0),
                            child: SizedBox(
                              width: playIconSize,
                              height: playIconSize,
                              child: CustomPaint(
                                painter: const _DesignCameraPlayPainter(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cameraActionCard({
    required Widget icon,
    required String title,
    required String subtitle,
    required _CameraViewMetrics metrics,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(metrics.actionCardRadius),
      onTap: onTap,
      child: Container(
        height: metrics.actionCardHeight,
        decoration: BoxDecoration(
          color: dark ? _designDarkCameraCardFill : Colors.white,
          borderRadius: BorderRadius.circular(metrics.actionCardRadius),
          border: Border.all(
            color:
                dark
                    ? _designDarkCameraCardBorder
                    : Colors.black.withValues(alpha: 0.04),
          ),
          boxShadow:
              dark
                  ? null
                  : const [
                    BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
        ),
        padding: EdgeInsets.symmetric(
          horizontal: metrics.actionCardHorizontalInset,
          vertical: metrics.actionCardVerticalInset,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            icon,
            const Spacer(),
            Text(
              title,
              style: TextStyle(
                color: dark ? Colors.white : const Color(0xFF111827),
                fontSize: metrics.actionTitleSize,
                fontWeight: FontWeight.w500,
                height: 16.5 / 11,
              ),
            ),
            SizedBox(height: metrics.actionTitleGap),
            Text(
              subtitle,
              style: TextStyle(
                color:
                    dark
                        ? Colors.white.withValues(alpha: 0.5)
                        : const Color(0xFF6B7280),
                fontSize: metrics.actionSubtitleSize,
                fontWeight: FontWeight.w400,
                height: 13.5 / 9,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cameraEmptyState(_CameraViewMetrics metrics) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    if (!dark && _videos.isEmpty) {
      return Container(
        height: metrics.emptyStateCardHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(metrics.clipRadius),
          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            SizedBox(height: metrics.emptyStateIconTopInset),
            SizedBox(
              width: metrics.emptyStateIconSize,
              height: metrics.emptyStateIconSize,
              child: CustomPaint(
                painter: const _DesignSavedClipsPainter(
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ),
            SizedBox(height: metrics.emptyStateIconGap),
            Text(
              'No saved clips yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF4B5563),
                fontSize: metrics.emptyStateTitleSize,
                fontWeight: FontWeight.w500,
                height: 16.5 / 11,
              ),
            ),
            SizedBox(height: metrics.emptyStateTitleGap),
            Text(
              'Clips are saved automatically when activity\nis detected by this camera.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF6B7280),
                fontSize: metrics.emptyStateBodySize,
                fontWeight: FontWeight.w400,
                height: 16.25 / 10,
              ),
            ),
          ],
        ),
      );
    }
    if (dark && _videos.isEmpty) {
      return Container(
        height: metrics.emptyStateCardHeight,
        decoration: BoxDecoration(
          color: _designDarkCameraCardFill,
          borderRadius: BorderRadius.circular(metrics.clipRadius),
          border: Border.all(color: _designDarkCameraCardBorder),
        ),
        child: Column(
          children: [
            SizedBox(height: metrics.emptyStateIconTopInset),
            SizedBox(
              width: metrics.emptyStateIconSize,
              height: metrics.emptyStateIconSize,
              child: CustomPaint(
                painter: _DesignSavedClipsPainter(
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
            SizedBox(height: metrics.emptyStateIconGap),
            Text(
              'No saved clips yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: metrics.emptyStateTitleSize,
                fontWeight: FontWeight.w500,
                height: 16.5 / 11,
              ),
            ),
            SizedBox(height: metrics.emptyStateTitleGap),
            Text(
              'Clips are saved automatically when activity\nis detected by this camera.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: metrics.emptyStateBodySize,
                fontWeight: FontWeight.w400,
                height: 16.25 / 10,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: dark ? _designDarkCameraCardFill : Colors.white,
        borderRadius: BorderRadius.circular(metrics.clipRadius),
        border: Border.all(
          color:
              dark
                  ? _designDarkCameraCardBorder
                  : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      padding: EdgeInsets.all(metrics.emptyStateInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No saved clips yet',
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: metrics.emptyStateTitleSize,
            ),
          ),
          SizedBox(height: metrics.emptyStateTitleGap),
          Text(
            'Open the live feed to start generating footage for this camera.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.54),
              fontSize: metrics.emptyStateBodySize,
            ),
          ),
          SizedBox(height: metrics.emptyStateButtonGap),
          FilledButton(
            onPressed: _openLivestream,
            child: const Text('View live'),
          ),
        ],
      ),
    );
  }

  Widget _clipCard(Video video, int index, _CameraViewMetrics metrics) {
    final detections = _detCache[video.id] ?? <String>{};
    final title =
        detections.contains('human')
            ? 'Person Detected'
            : (video.motion ? 'Motion Detected' : 'Livestream Clip');
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(metrics.clipRadius),
      onTap: () => _openVideoClip(video, detections),
      onLongPress: _isPreviewMode ? null : () => _deleteOne(video, index),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? _designDarkCameraCardFill : Colors.white,
          borderRadius: BorderRadius.circular(metrics.clipRadius),
          border: Border.all(
            color:
                dark
                    ? _designDarkCameraCardBorder
                    : Colors.black.withValues(alpha: 0.04),
          ),
          boxShadow:
              dark
                  ? null
                  : const [
                    BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
        ),
        padding: EdgeInsets.symmetric(
          horizontal: metrics.clipHorizontalInset,
          vertical: metrics.clipVerticalInset,
        ),
        child: Row(
          children: [
            FutureBuilder<Widget>(
              future: _thumbPlaceholder(video.camera, video.video, metrics),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData) {
                  return snapshot.data!;
                }
                return SizedBox(
                  width: metrics.clipThumbWidth,
                  height: metrics.clipThumbHeight,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            ),
            SizedBox(width: metrics.clipThumbGap),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: dark ? Colors.white : const Color(0xFF111827),
                      fontSize: metrics.clipTitleSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: metrics.clipTitleGap),
                  Text(
                    repackageVideoTitle(video.video),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.5)
                              : const Color(0xFF6B7280),
                      fontSize: metrics.clipSubtitleSize,
                    ),
                  ),
                ],
              ),
            ),
            _DesignClipChevronIcon(
              size: metrics.clipChevronSize,
              color:
                  dark
                      ? Colors.white.withValues(alpha: 0.2)
                      : const Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openVideoClip(Video video, Set<String> detections) async {
    Log.d("Opening saved clip: ${video.video} for ${video.camera}");
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => VideoViewPage(
              cameraName: video.camera,
              videoTitle: video.video,
              visibleVideoTitle: repackageVideoTitle(video.video),
              isLivestream: !video.motion,
              canDownload:
                  _isPreviewMode
                      ? _previewVideoAsset(video) != null
                      : video.received,
              previewAssetPath:
                  _isPreviewMode ? _previewThumbAsset(video) : null,
              previewVideoAssetPath:
                  _isPreviewMode ? _previewVideoAsset(video) : null,
              previewDetections: _isPreviewMode ? detections : null,
              previewDuration:
                  _isPreviewMode && _previewVideoAsset(video) != null
                      ? const Duration(seconds: 16)
                      : const Duration(seconds: 42),
              previewPosition:
                  _isPreviewMode && _previewVideoAsset(video) != null
                      ? Duration.zero
                      : const Duration(seconds: 12),
            ),
      ),
    );
  }

  Widget _circleIconButton({
    required _CameraViewMetrics metrics,
    required VoidCallback onTap,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color:
          dark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E7EB),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: metrics.backButtonSize,
          height: metrics.backButtonSize,
          child: Center(
            child: _DesignCameraBackIcon(
              size: metrics.backButtonIconSize,
              color: dark ? Colors.white : const Color(0xFF111827),
            ),
          ),
        ),
      ),
    );
  }

  Future<Widget> _thumbPlaceholder(
    String cameraName,
    String videoFile,
    _CameraViewMetrics metrics,
  ) async {
    final previewAsset = widget.previewThumbAssetsByVideo?[videoFile];
    final durationLabel = _clipDurationLabel(videoFile);
    if (previewAsset != null) {
      return _clipThumb(
        image: Image.asset(previewAsset, fit: BoxFit.cover),
        durationLabel: durationLabel,
        metrics: metrics,
      );
    }

    final bytes = await _loadVideoThumbBytes(cameraName, videoFile);

    if (bytes == null) {
      return _clipThumb(
        image: Container(
          color:
              Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFE5E7EB),
          child: const Icon(Icons.videocam, color: SeclusoColors.paperMuted),
        ),
        durationLabel: durationLabel,
        metrics: metrics,
      );
    }

    return _clipThumb(
      image: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      durationLabel: durationLabel,
      metrics: metrics,
    );
  }

  Widget _clipThumb({
    required Widget image,
    required String? durationLabel,
    required _CameraViewMetrics metrics,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(metrics.clipThumbRadius),
      child: SizedBox(
        width: metrics.clipThumbWidth,
        height: metrics.clipThumbHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: dark ? 0.5 : 1, child: image),
            if (durationLabel != null)
              Positioned(
                right: metrics.clipDurationInset,
                bottom: metrics.clipDurationInset,
                child: Container(
                  height: metrics.clipDurationHeight,
                  padding: EdgeInsets.symmetric(
                    horizontal: metrics.clipDurationHorizontalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(
                      metrics.clipDurationRadius,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      durationLabel,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: metrics.clipDurationTextSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _primaryBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bool outlined = color == Colors.transparent;
    final Color fillColor =
        outlined
            ? Colors.transparent
            : (dark && color == SeclusoColors.paper
                ? color
                : SeclusoColors.ink);
    final Color foregroundColor =
        outlined
            ? (dark ? Colors.white : Theme.of(context).colorScheme.onSurface)
            : (dark ? SeclusoColors.ink : SeclusoColors.paper);
    return ElevatedButton(
      onPressed: enabled ? onTap : null,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            enabled ? fillColor : Theme.of(context).colorScheme.outlineVariant,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
        side:
            outlined
                ? BorderSide(
                  color:
                      dark
                          ? Colors.white.withValues(alpha: 0.16)
                          : Theme.of(context).colorScheme.outline,
                )
                : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foregroundColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: foregroundColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _secondaryActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(46, 46),
        padding: const EdgeInsets.all(0),
        foregroundColor: dark ? Colors.white : theme.colorScheme.onSurface,
        side: BorderSide(
          color:
              dark
                  ? Colors.white.withValues(alpha: 0.16)
                  : theme.colorScheme.outline,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Icon(icon, size: 18),
    );
  }

  String? _previewHeroAssetPath() {
    if (widget.previewHeroAssetPath != null) {
      return widget.previewHeroAssetPath;
    }
    if (_videos.isEmpty) return null;
    return _previewThumbAsset(_videos.first);
  }

  String? _previewHeroVideoAssetPath() {
    if (widget.previewHeroVideoAssetPath != null) {
      return widget.previewHeroVideoAssetPath;
    }
    if (_videos.isEmpty) return null;
    return _previewVideoAsset(_videos.first);
  }

  String? _previewThumbAsset(Video video) {
    return widget.previewThumbAssetsByVideo?[video.video];
  }

  String? _previewVideoAsset(Video video) {
    return widget.previewVideoAssetsByVideo?[video.video];
  }

  Color _sectionLabelColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.2)
        : const Color(0xFF9CA3AF);
  }

  Color _sectionMetaColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.2)
        : const Color(0xFF9CA3AF);
  }

  String? _clipDurationLabel(String videoFile) {
    final duration = widget.previewDurationByVideo?[videoFile];
    if (duration == null) return null;
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _DesignCameraBackIcon extends StatelessWidget {
  const _DesignCameraBackIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DesignCameraBackPainter(color)),
    );
  }
}

class _DesignCameraActivityIcon extends StatelessWidget {
  const _DesignCameraActivityIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DesignCameraActivityPainter(color)),
    );
  }
}

class _DesignCameraSettingsIcon extends StatelessWidget {
  const _DesignCameraSettingsIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DesignCameraSettingsPainter(color)),
    );
  }
}

class _DesignClipChevronIcon extends StatelessWidget {
  const _DesignClipChevronIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DesignClipChevronPainter(color)),
    );
  }
}

class _DesignCameraBackPainter extends CustomPainter {
  const _DesignCameraBackPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.33333 / 16)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (10 / 16), size.height * (12 / 16))
          ..lineTo(size.width * (6 / 16), size.height * (8 / 16))
          ..lineTo(size.width * (10 / 16), size.height * (4 / 16));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignCameraBackPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignCameraActivityPainter extends CustomPainter {
  const _DesignCameraActivityPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.66667 / 20)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (18.3333 / 20), size.height * (10 / 20))
          ..lineTo(size.width * (15 / 20), size.height * (10 / 20))
          ..lineTo(size.width * (12.5 / 20), size.height * (17.5 / 20))
          ..lineTo(size.width * (7.5 / 20), size.height * (2.5 / 20))
          ..lineTo(size.width * (5 / 20), size.height * (10 / 20))
          ..lineTo(size.width * (1.66667 / 20), size.height * (10 / 20));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignCameraActivityPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignCameraSettingsPainter extends CustomPainter {
  const _DesignCameraSettingsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.66667 / 20)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width * (8.45 / 20);
    final rootRadius = size.width * (7.25 / 20);
    final gear = Path();
    for (var i = 0; i < 16; i++) {
      final angle = (-math.pi / 2) + (math.pi / 8 * i);
      final radius = i.isEven ? outerRadius : rootRadius;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      if (i == 0) {
        gear.moveTo(point.dx, point.dy);
      } else {
        gear.lineTo(point.dx, point.dy);
      }
    }
    gear.close();
    canvas.drawPath(gear, stroke);
    canvas.drawCircle(center, size.width * (2.5 / 20), stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignCameraSettingsPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignClipChevronPainter extends CustomPainter {
  const _DesignClipChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.16667 / 14)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (2.91667 / 14), size.height * (1.75 / 14))
          ..lineTo(size.width * (11.0833 / 14), size.height * (7 / 14))
          ..lineTo(size.width * (2.91667 / 14), size.height * (12.25 / 14))
          ..close();
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignClipChevronPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignCameraPlayPainter extends CustomPainter {
  const _DesignCameraPlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()
          ..moveTo(size.width * (5 / 24), size.height * (3 / 24))
          ..lineTo(size.width * (19 / 24), size.height * (12 / 24))
          ..lineTo(size.width * (5 / 24), size.height * (21 / 24))
          ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DesignCameraLockPainter extends CustomPainter {
  const _DesignCameraLockPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * (1.04167 / 10);
    final stroke =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..isAntiAlias = true;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (1.25 / 10),
        size.height * (4.58333 / 10),
        size.width * (7.5 / 10),
        size.height * (4.58334 / 10),
      ),
      Radius.circular(size.width * (0.83333 / 10)),
    );
    canvas.drawRRect(body, stroke);

    final shackle =
        Path()
          ..moveTo(size.width * (2.91667 / 10), size.height * (4.58333 / 10))
          ..lineTo(size.width * (2.91667 / 10), size.height * (2.91667 / 10))
          ..arcToPoint(
            Offset(size.width * (7.08333 / 10), size.height * (2.91667 / 10)),
            radius: Radius.circular(size.width * (2.08333 / 10)),
            clockwise: true,
          )
          ..lineTo(size.width * (7.08333 / 10), size.height * (4.58333 / 10));
    canvas.drawPath(shackle, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignCameraLockPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignSavedClipsPainter extends CustomPainter {
  const _DesignSavedClipsPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * (1.5 / 24);
    final stroke =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..isAntiAlias = true;

    final outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (2 / 24),
        size.height * (2 / 24),
        size.width * (20 / 24),
        size.height * (20 / 24),
      ),
      Radius.circular(size.width * (2.18 / 24)),
    );
    canvas.drawRRect(outer, stroke);

    void drawLine(double x1, double y1, double x2, double y2) {
      canvas.drawLine(
        Offset(size.width * (x1 / 24), size.height * (y1 / 24)),
        Offset(size.width * (x2 / 24), size.height * (y2 / 24)),
        stroke,
      );
    }

    drawLine(7, 2, 7, 22);
    drawLine(17, 2, 17, 22);
    drawLine(2, 12, 22, 12);
    drawLine(2, 7, 7, 7);
    drawLine(2, 17, 7, 17);
    drawLine(17, 7, 22, 7);
    drawLine(17, 17, 22, 17);
  }

  @override
  bool shouldRepaint(covariant _DesignSavedClipsPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _CameraViewMetrics {
  const _CameraViewMetrics({
    required this.pageInset,
    required this.topPadding,
    required this.bottomPadding,
    required this.backButtonSize,
    required this.backButtonIconSize,
    required this.headerGap,
    required this.titleSize,
    required this.titleLetterSpacing,
    required this.titleToStatusGap,
    required this.statusDotSize,
    required this.statusDotGap,
    required this.statusTextSize,
    required this.statusLetterSpacing,
    required this.headerLockSize,
    required this.headerToHeroGap,
    required this.heroHeight,
    required this.heroRadius,
    required this.heroInset,
    required this.heroLiveChipHeight,
    required this.heroLiveChipPadding,
    required this.heroLiveChipDotSize,
    required this.heroLiveChipGap,
    required this.heroLiveChipTextSize,
    required this.heroLiveChipLetterSpacing,
    required this.heroPlayButtonSize,
    required this.heroPlayIconSize,
    required this.heroPlayIconOffsetX,
    required this.heroPlayBlurSigma,
    required this.heroToActionsGap,
    required this.actionCardHeight,
    required this.actionCardRadius,
    required this.actionCardHorizontalInset,
    required this.actionCardVerticalInset,
    required this.actionCardGap,
    required this.actionIconSize,
    required this.actionTitleSize,
    required this.actionTitleGap,
    required this.actionSubtitleSize,
    required this.sectionTopGap,
    required this.sectionLabelSize,
    required this.sectionLabelLetterSpacing,
    required this.sectionMetaSize,
    required this.sectionToListGap,
    required this.clipGap,
    required this.clipRadius,
    required this.clipHorizontalInset,
    required this.clipVerticalInset,
    required this.clipThumbWidth,
    required this.clipThumbHeight,
    required this.clipThumbRadius,
    required this.clipThumbGap,
    required this.clipTitleSize,
    required this.clipTitleGap,
    required this.clipSubtitleSize,
    required this.clipChevronSize,
    required this.clipDurationInset,
    required this.clipDurationHeight,
    required this.clipDurationHorizontalPadding,
    required this.clipDurationRadius,
    required this.clipDurationTextSize,
    required this.emptyStateInset,
    required this.emptyStateCardHeight,
    required this.emptyStateIconTopInset,
    required this.emptyStateIconSize,
    required this.emptyStateIconGap,
    required this.emptyStateTitleSize,
    required this.emptyStateTitleGap,
    required this.emptyStateBodySize,
    required this.emptyStateButtonGap,
    required this.headerInset,
    required this.contentInset,
  });

  final double pageInset;
  final double topPadding;
  final double bottomPadding;
  final double backButtonSize;
  final double backButtonIconSize;
  final double headerGap;
  final double titleSize;
  final double titleLetterSpacing;
  final double titleToStatusGap;
  final double statusDotSize;
  final double statusDotGap;
  final double statusTextSize;
  final double statusLetterSpacing;
  final double headerLockSize;
  final double headerToHeroGap;
  final double heroHeight;
  final double heroRadius;
  final double heroInset;
  final double heroLiveChipHeight;
  final double heroLiveChipPadding;
  final double heroLiveChipDotSize;
  final double heroLiveChipGap;
  final double heroLiveChipTextSize;
  final double heroLiveChipLetterSpacing;
  final double heroPlayButtonSize;
  final double heroPlayIconSize;
  final double heroPlayIconOffsetX;
  final double heroPlayBlurSigma;
  final double heroToActionsGap;
  final double actionCardHeight;
  final double actionCardRadius;
  final double actionCardHorizontalInset;
  final double actionCardVerticalInset;
  final double actionCardGap;
  final double actionIconSize;
  final double actionTitleSize;
  final double actionTitleGap;
  final double actionSubtitleSize;
  final double sectionTopGap;
  final double sectionLabelSize;
  final double sectionLabelLetterSpacing;
  final double sectionMetaSize;
  final double sectionToListGap;
  final double clipGap;
  final double clipRadius;
  final double clipHorizontalInset;
  final double clipVerticalInset;
  final double clipThumbWidth;
  final double clipThumbHeight;
  final double clipThumbRadius;
  final double clipThumbGap;
  final double clipTitleSize;
  final double clipTitleGap;
  final double clipSubtitleSize;
  final double clipChevronSize;
  final double clipDurationInset;
  final double clipDurationHeight;
  final double clipDurationHorizontalPadding;
  final double clipDurationRadius;
  final double clipDurationTextSize;
  final double emptyStateInset;
  final double emptyStateCardHeight;
  final double emptyStateIconTopInset;
  final double emptyStateIconSize;
  final double emptyStateIconGap;
  final double emptyStateTitleSize;
  final double emptyStateTitleGap;
  final double emptyStateBodySize;
  final double emptyStateButtonGap;
  final double headerInset;
  final double contentInset;

  factory _CameraViewMetrics.forWidth(
    double width, {
    bool lightEmptyState = false,
    bool darkEmptyState = false,
  }) {
    final scale = width / 290;
    double scaled(double designValue) => designValue * scale;
    final designEmptyState = lightEmptyState || darkEmptyState;

    return _CameraViewMetrics(
      pageInset: scaled(20),
      topPadding: scaled(8),
      bottomPadding: scaled(20),
      backButtonSize: scaled(32),
      backButtonIconSize: scaled(16),
      headerGap: scaled(12),
      titleSize: scaled(18),
      titleLetterSpacing: scaled(0.3),
      titleToStatusGap: scaled(5),
      statusDotSize: scaled(6),
      statusDotGap: scaled(6),
      statusTextSize: scaled(9),
      statusLetterSpacing: scaled(0.45),
      headerLockSize: scaled(10),
      headerToHeroGap: scaled(14),
      heroHeight: scaled(145.13),
      heroRadius: scaled(16),
      heroInset: scaled(12),
      heroLiveChipHeight: scaled(20),
      heroLiveChipPadding: scaled(8),
      heroLiveChipDotSize: scaled(6),
      heroLiveChipGap: scaled(6),
      heroLiveChipTextSize: scaled(8),
      heroLiveChipLetterSpacing: scaled(0.4),
      heroPlayButtonSize: scaled(56),
      heroPlayIconSize: scaled(lightEmptyState ? 24 : 28),
      heroPlayIconOffsetX: scaled(lightEmptyState ? 2 : 1),
      heroPlayBlurSigma: scaled(6),
      heroToActionsGap: scaled(lightEmptyState ? 21.5 : 24),
      actionCardHeight: scaled(88),
      actionCardRadius: scaled(12),
      actionCardHorizontalInset: scaled(16),
      actionCardVerticalInset: scaled(designEmptyState ? 14 : 16),
      actionCardGap: scaled(12),
      actionIconSize: scaled(20),
      actionTitleSize: scaled(11),
      actionTitleGap: scaled(2),
      actionSubtitleSize: scaled(9),
      sectionTopGap: scaled(designEmptyState ? 16 : 18),
      sectionLabelSize: scaled(10),
      sectionLabelLetterSpacing: scaled(1),
      sectionMetaSize: scaled(10),
      sectionToListGap: scaled(12),
      clipGap: scaled(8),
      clipRadius: scaled(12),
      clipHorizontalInset: scaled(12),
      clipVerticalInset: scaled(13),
      clipThumbWidth: scaled(56),
      clipThumbHeight: scaled(40),
      clipThumbRadius: scaled(8),
      clipThumbGap: scaled(12),
      clipTitleSize: scaled(12),
      clipTitleGap: scaled(1),
      clipSubtitleSize: scaled(10),
      clipChevronSize: scaled(20),
      clipDurationInset: scaled(2),
      clipDurationHeight: scaled(12),
      clipDurationHorizontalPadding: scaled(4),
      clipDurationRadius: scaled(4),
      clipDurationTextSize: scaled(8),
      emptyStateInset: scaled(18),
      emptyStateCardHeight: scaled(designEmptyState ? 139 : 0),
      emptyStateIconTopInset: scaled(designEmptyState ? 24 : 0),
      emptyStateIconSize: scaled(designEmptyState ? 24 : 0),
      emptyStateIconGap: scaled(designEmptyState ? 12.25 : 0),
      emptyStateTitleSize: scaled(designEmptyState ? 11 : 18),
      emptyStateTitleGap: scaled(designEmptyState ? 12 : 8),
      emptyStateBodySize: scaled(designEmptyState ? 10 : 14),
      emptyStateButtonGap: scaled(14),
      headerInset: scaled(lightEmptyState ? 20 : 20),
      contentInset: scaled(lightEmptyState ? 16 : 20),
    );
  }
}
