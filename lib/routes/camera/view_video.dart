//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_theme.dart';

import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/utilities/mp4_fix.dart';

class VideoViewPage extends StatefulWidget {
  final String videoTitle;
  final String visibleVideoTitle;
  final bool canDownload;
  final String cameraName;
  final bool isLivestream;
  final String? previewAssetPath;
  final String? previewVideoAssetPath;
  final Set<String>? previewDetections;
  final Duration previewDuration;
  final Duration previewPosition;

  const VideoViewPage({
    super.key,
    required this.videoTitle,
    required this.visibleVideoTitle,
    required this.canDownload,
    required this.cameraName,
    required this.isLivestream,
    this.previewAssetPath,
    this.previewVideoAssetPath,
    this.previewDetections,
    this.previewDuration = const Duration(seconds: 42),
    this.previewPosition = const Duration(seconds: 12),
  });

  @override
  State<VideoViewPage> createState() => _VideoViewPageState();
}

class _VideoViewPageState extends State<VideoViewPage> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  String? _loadError;
  String? _videoPath;
  late AppDetectionStore _detectionStore;
  Set<String> _dets = {};
  bool _shareInProgress = false;
  double _playbackSpeed = 1.0;

  bool get _hasPreviewImage => widget.previewAssetPath != null;
  bool get _hasPreviewVideo => widget.previewVideoAssetPath != null;
  bool get _isStaticPreviewMode => _hasPreviewImage && !_hasPreviewVideo;
  VideoPlayerController get _videoController => _controller!;

  @override
  void initState() {
    super.initState();
    if (_isStaticPreviewMode) {
      _dets = widget.previewDetections ?? const <String>{};
      _initialized = true;
      return;
    }
    if (_hasPreviewVideo) {
      _dets = widget.previewDetections ?? const <String>{};
      _initPreviewVideo();
      return;
    }
    _openBoxesAndLoadDetections();
    _initVideo();
  }

  Future<void> _openBoxesAndLoadDetections() async {
    if (!AppStores.isInitialized) {
      try {
        await AppStores.init();
      } catch (e, st) {
        Log.e("Failed to init AppStores in video view: $e\n$st");
        return;
      }
    }
    _detectionStore = AppStores.instance.detectionStore;
    await _loadDetections();
  }

  Future<void> _loadDetections() async {
    final rows = await _detectionStore.findByCameraAndVideoFile(
      widget.cameraName,
      widget.videoTitle,
    );

    final types = <String>{};
    for (final d in rows) {
      if (d.type.isNotEmpty) types.add(d.type.toLowerCase());
    }

    if (mounted) {
      setState(() {
        _dets = types;
      });
    }
  }

  Future<void> _initVideo() async {
    try {
      final cameraDir = await AppPaths.cameraDirectory(widget.cameraName);
      _videoPath = p.join(cameraDir.path, 'videos', widget.videoTitle);
      Log.d("Found path: $_videoPath");

      final sourcePath = _videoPath!;
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        if (mounted) {
          setState(() {
            _loadError = 'Clip file is not available on this device yet.';
          });
        }
        return;
      }

      // apply patch only for livestreams, and only once
      if (widget.isLivestream) {
        final markerPath = '$sourcePath.patched_livestream';
        final marker = File(markerPath);
        final alreadyFixed = await marker.exists();

        if (alreadyFixed) {
          Log.d("[fix] skip: marker exists ($markerPath)");
        } else {
          Log.d("Attempting to fix (livestream only)");
          final res = await Mp4DurationFixer(sourceFile, log: Log.d).fix();

          // Only mark if it actually patched something
          if (res.patched) {
            try {
              await marker.writeAsString(
                "ok ${res.duration.inMilliseconds}ms fps=${res.fps.toStringAsFixed(3)}",
                flush: true,
              );
              Log.d("[fix] marker written ($markerPath)");
            } catch (e) {
              Log.d("[fix] could not write marker: $e");
            }
          } else {
            Log.d(
              "[fix] no patch applied (res.patched=false) — not writing marker",
            );
          }
        }
      } else {
        Log.d("[fix] not a livestream — skipping patch");
      }

      await _attachController(
        VideoPlayerController.file(sourceFile),
        initialPosition: Duration.zero,
      );
    } catch (e, st) {
      Log.e("Failed to initialize video view: $e\n$st");
      if (mounted) {
        setState(() {
          _loadError = 'Unable to open this saved clip.';
        });
      }
    }
  }

  Future<File> _ensurePreviewVideoFile() async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory(p.join(tempDir.path, 'review_preview_assets'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final assetPath = widget.previewVideoAssetPath!;
    final targetFile = File(p.join(cacheDir.path, p.basename(assetPath)));
    if (await targetFile.exists() && await targetFile.length() > 0) {
      return targetFile;
    }

    final assetBytes = await rootBundle.load(assetPath);
    await targetFile.writeAsBytes(assetBytes.buffer.asUint8List(), flush: true);
    return targetFile;
  }

  Future<void> _initPreviewVideo() async {
    try {
      final previewFile = await _ensurePreviewVideoFile();
      _videoPath = previewFile.path;
      await _attachController(
        VideoPlayerController.file(previewFile),
        initialPosition: widget.previewPosition,
      );
    } catch (e, st) {
      Log.e('Failed to initialize preview video: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = 'Unable to open this review clip.';
      });
    }
  }

  Future<void> _attachController(
    VideoPlayerController controller, {
    required Duration initialPosition,
  }) async {
    _controller = controller;
    await controller.initialize();
    await controller.setLooping(true);
    await controller.setPlaybackSpeed(_playbackSpeed);
    if (initialPosition > Duration.zero) {
      await controller.seekTo(
        _safeSeekTarget(initialPosition, controller.value.duration),
      );
    }
    controller.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    await controller.play();
    if (!mounted) return;
    setState(() {
      _initialized = true;
      _loadError = null;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _downloadVideo() async {
    Log.d("Requested video download");
    final videoPath = _videoPath;
    if (videoPath == null || videoPath.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Video file not found")));
      return;
    }
    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Video file not found")));
      return;
    }

    try {
      var permission =
          Platform.isIOS ? Permission.photosAddOnly : Permission.mediaLibrary;
      await permission
          .onDeniedCallback(() {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Unable to save due to denied access to photos'),
                backgroundColor: Colors.red[700],
                behavior: SnackBarBehavior.floating,
              ),
            );
          })
          .onGrantedCallback(() async {
            Log.d("Granted permission to photos");

            try {
              await Gal.putVideo(videoFile.path);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("Saved to Photos")));
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Unable to save for unknown reason'),
                  backgroundColor: Colors.red[700],
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          })
          .onPermanentlyDeniedCallback(() {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Unable to save due to permanently denied access to photos',
                ),
                backgroundColor: Colors.red[700],
                behavior: SnackBarBehavior.floating,
              ),
            );
          })
          .onRestrictedCallback(() {})
          .onLimitedCallback(() {})
          .onProvisionalCallback(() {})
          .request();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !_initialized) {
      return;
    }
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    final controller = _controller;
    if (_isStaticPreviewMode ||
        controller == null ||
        !_initialized ||
        _playbackSpeed == speed) {
      return;
    }

    try {
      await controller.setPlaybackSpeed(speed);
      if (!mounted) return;
      setState(() {
        _playbackSpeed = speed;
      });
    } catch (e, st) {
      Log.e('Failed to change playback speed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to change playback speed')),
      );
    }
  }

  Duration _safeSeekTarget(Duration requested, Duration duration) {
    if (requested <= Duration.zero) {
      return Duration.zero;
    }

    if (duration <= Duration.zero) {
      return Duration.zero;
    }

    final endPadding = Duration(
      milliseconds: duration.inMilliseconds > 250 ? 250 : 1,
    );
    final lastSafePosition = duration - endPadding;
    if (requested >= duration) {
      return lastSafePosition > Duration.zero
          ? lastSafePosition
          : Duration.zero;
    }

    return requested;
  }

  Future<void> _seekToSafe(Duration requested) async {
    final controller = _controller;
    if (_isStaticPreviewMode || controller == null || !_initialized) {
      return;
    }

    final duration = controller.value.duration;
    final target = _safeSeekTarget(requested, duration);
    await controller.seekTo(target);
  }

  Future<void> _shareVideo() async {
    if (_isStaticPreviewMode || _shareInProgress) {
      return;
    }

    final videoPath = _videoPath;
    if (videoPath == null || videoPath.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Video file not found')));
      return;
    }
    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Video file not found')));
      return;
    }

    setState(() {
      _shareInProgress = true;
    });

    try {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(videoFile.path, mimeType: 'video/mp4')],
          subject: 'Secluso clip',
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e, st) {
      Log.e('Failed to share video: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to share clip')));
    } finally {
      if (mounted) {
        setState(() {
          _shareInProgress = false;
        });
      }
    }
  }

  String _detectionLabel(Set<String> types) {
    if (types.isEmpty) return 'None';
    final norm = {for (final t in types) (t == 'pets' ? 'pet' : t)};
    final ordered = <String>[];
    if (norm.contains('human')) ordered.add('Person');
    if (norm.contains('vehicle')) ordered.add('Vehicle');
    if (norm.contains('pet')) ordered.add('Pet');
    return ordered.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (_loadError != null) {
      return Scaffold(
        backgroundColor:
            dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    if (_isStaticPreviewMode) {
      return Scaffold(
        backgroundColor:
            dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7),
        body: _buildPreviewContent(),
      );
    }

    final controller = _controller;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7),
      body:
          _initialized && controller != null
              ? isLandscape
                  ? _buildLandscapePlayer()
                  : _buildPortraitContent()
              : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildLandscapePlayer() {
    final controller = _videoController;
    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        // Progress bar & time
        Positioned(
          left: 16,
          right: 16,
          bottom: 80,
          child: SeclusoGlassCard(
            borderRadius: 24,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            tint: Colors.black.withValues(alpha: 0.48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VideoProgressIndicator(
                  controller,
                  allowScrubbing: false,
                  colors: const VideoProgressColors(
                    playedColor: SeclusoColors.blue,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(controller.value.position),
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                    Text(
                      _formatDuration(controller.value.duration),
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Playback controls
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_5),
                  iconSize: 36,
                  color: Colors.white,
                  onPressed: () {
                    final current = controller.value.position;
                    final newPosition = current - const Duration(seconds: 5);
                    _seekToSafe(
                      newPosition >= Duration.zero
                          ? newPosition
                          : Duration.zero,
                    );
                  },
                ),
                const SizedBox(width: 24),
                IconButton(
                  icon: Icon(
                    controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                  iconSize: 44,
                  color: Colors.white,
                  onPressed: _togglePlayPause,
                ),
                const SizedBox(width: 24),
                IconButton(
                  icon: const Icon(Icons.forward_5),
                  iconSize: 36,
                  color: Colors.white,
                  onPressed: () {
                    final current = controller.value.position;
                    final max = controller.value.duration;
                    final newPosition = current + const Duration(seconds: 5);
                    _seekToSafe(newPosition <= max ? newPosition : max);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitContent() {
    final controller = _videoController;
    return _buildPortraitShell(
      aspectRatio: controller.value.aspectRatio,
      media: VideoPlayer(controller),
      position: controller.value.position,
      duration: controller.value.duration,
      detections: _dets,
      canDownload: widget.canDownload,
      onDownload: _downloadVideo,
      isPlaying: controller.value.isPlaying,
      onTogglePlay: _togglePlayPause,
      onRewind: () {
        final current = controller.value.position;
        final newPosition = current - const Duration(seconds: 5);
        _seekToSafe(newPosition >= Duration.zero ? newPosition : Duration.zero);
      },
      onFastForward: () {
        final current = controller.value.position;
        final max = controller.value.duration;
        final newPosition = current + const Duration(seconds: 5);
        _seekToSafe(newPosition <= max ? newPosition : max);
      },
    );
  }

  Widget _buildPreviewContent() {
    return _buildPortraitShell(
      aspectRatio: 16 / 9,
      media: Stack(
        fit: StackFit.expand,
        children: [Image.asset(widget.previewAssetPath!, fit: BoxFit.cover)],
      ),
      position: widget.previewPosition,
      duration: widget.previewDuration,
      detections: widget.previewDetections ?? const <String>{},
      canDownload: widget.canDownload,
      onDownload: () {},
      isPlaying: true,
      onTogglePlay: () {},
      onRewind: () {},
      onFastForward: () {},
    );
  }

  Widget _buildPortraitShell({
    required double aspectRatio,
    required Widget media,
    required Duration position,
    required Duration duration,
    required Set<String> detections,
    required bool canDownload,
    required VoidCallback onDownload,
    required bool isPlaying,
    required VoidCallback onTogglePlay,
    required VoidCallback onRewind,
    required VoidCallback onFastForward,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final metrics = _ClipViewMetrics.forWidth(MediaQuery.sizeOf(context).width);
    final effectiveDuration =
        duration > Duration.zero ? duration : const Duration(seconds: 1);
    final maxMs = effectiveDuration.inMilliseconds.toDouble();
    final currentMs =
        position.inMilliseconds
            .clamp(0, effectiveDuration.inMilliseconds)
            .toDouble();
    final activeDetection = _detectionLabel(detections).split(',').first;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          metrics.pageInset,
          metrics.topPadding,
          metrics.pageInset,
          metrics.bottomPadding + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Row(
            children: [
              _ClipCircleButton(
                size: metrics.backButtonSize,
                fill:
                    dark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFE5E7EB),
                onTap: () => Navigator.of(context).maybePop(),
                child: _ClipBackIcon(
                  size: metrics.backIconSize,
                  color:
                      dark
                          ? Colors.white.withValues(alpha: 0.7)
                          : const Color(0xFF6B7280),
                ),
              ),
              SizedBox(width: metrics.headerGap),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.cameraName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: metrics.titleSize,
                      fontWeight: FontWeight.w600,
                      color: dark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                  SizedBox(height: metrics.subtitleGap),
                  Text(
                    'Recorded Clip',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: metrics.subtitleSize,
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.4)
                              : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: metrics.headerToMediaGap),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(metrics.mediaRadius),
              border: Border.all(
                color:
                    dark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0x00000000),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(metrics.mediaRadius),
              child: AspectRatio(
                aspectRatio: 258 / 145.13,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    media,
                    if (isPlaying)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onTogglePlay,
                        ),
                      ),
                    if (!isPlaying)
                      Center(
                        child: _ClipPlayOverlayButton(
                          size: metrics.playButtonSize,
                          dark: dark,
                          onTap: onTogglePlay,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: metrics.mediaToProgressGap),
          _ClipProgressBar(
            valueMs: currentMs,
            maxMs: maxMs,
            dark: dark,
            height: metrics.progressHeight,
            thumbRadius: metrics.progressThumbRadius,
            onChanged:
                _isStaticPreviewMode
                    ? null
                    : (value) async {
                      await _seekToSafe(Duration(milliseconds: value.round()));
                    },
          ),
          SizedBox(height: metrics.progressToTimeGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: metrics.timeSize,
                  color:
                      dark
                          ? Colors.white.withValues(alpha: 0.4)
                          : const Color(0xFF6B7280),
                ),
              ),
              Text(
                _formatDuration(effectiveDuration),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: metrics.timeSize,
                  color:
                      dark
                          ? Colors.white.withValues(alpha: 0.4)
                          : const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.timeToControlsGap),
          Row(
            children: [
              _ClipBareIconButton(
                size: metrics.controlIconSize,
                onTap: onRewind,
                child: _ClipRewindIcon(
                  size: metrics.controlIconSize,
                  color:
                      dark
                          ? Colors.white.withValues(alpha: 0.7)
                          : const Color(0xFF6B7280),
                ),
              ),
              SizedBox(width: metrics.controlIconGap),
              _ClipBareIconButton(
                size: metrics.controlIconSize,
                onTap: onFastForward,
                child: _ClipForwardIcon(
                  size: metrics.controlIconSize,
                  color:
                      dark
                          ? Colors.white.withValues(alpha: 0.7)
                          : const Color(0xFF6B7280),
                ),
              ),
              const Spacer(),
              _speedChip(
                '0.5×',
                _playbackSpeed == 0.5,
                metrics: metrics,
                onTap: () => _setPlaybackSpeed(0.5),
              ),
              SizedBox(width: metrics.speedChipGap),
              _speedChip(
                '1×',
                _playbackSpeed == 1.0,
                metrics: metrics,
                onTap: () => _setPlaybackSpeed(1.0),
              ),
              SizedBox(width: metrics.speedChipGap),
              _speedChip(
                '2×',
                _playbackSpeed == 2.0,
                metrics: metrics,
                onTap: () => _setPlaybackSpeed(2.0),
              ),
            ],
          ),
          SizedBox(height: metrics.controlsToDetailsGap),
          Container(
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF111113) : Colors.white,
              borderRadius: BorderRadius.circular(metrics.detailCardRadius),
              border: Border.all(
                color:
                    dark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0x14000000),
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
            child: Padding(
              padding: EdgeInsets.all(metrics.detailCardInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.visibleVideoTitle.replaceAll('·', ','),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: metrics.detailTitleSize,
                            fontWeight: FontWeight.w600,
                            color:
                                dark ? Colors.white : const Color(0xFF111827),
                          ),
                        ),
                      ),
                      if (detections.isNotEmpty)
                        Container(
                          height: metrics.badgeHeight,
                          padding: EdgeInsets.symmetric(
                            horizontal: metrics.badgeHorizontalPadding,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF8BB3EE,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(
                              metrics.badgeRadius,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ClipPersonBadgeIcon(
                                size: metrics.badgeIconSize,
                                color: const Color(0xFF8BB3EE),
                              ),
                              SizedBox(width: metrics.badgeIconGap),
                              Text(
                                activeDetection.toUpperCase(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: metrics.badgeTextSize,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: metrics.badgeLetterSpacing,
                                  color: const Color(0xFF8BB3EE),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: metrics.detailTitleGap),
                  Row(
                    children: [
                      _ClipLockIcon(
                        size: metrics.metaLockSize,
                        color:
                            dark
                                ? Colors.white.withValues(alpha: 0.2)
                                : const Color(0xFF9CA3AF),
                      ),
                      SizedBox(width: metrics.metaLockGap),
                      Text(
                        'End-to-end encrypted',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: metrics.metaTextSize,
                          color:
                              dark
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : const Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: metrics.detailDividerTopGap),
                  Container(
                    height: 1,
                    color:
                        dark
                            ? Colors.white.withValues(alpha: 0.04)
                            : const Color(0xFFE5E7EB),
                  ),
                  SizedBox(height: metrics.detailDividerBottomGap),
                  Row(
                    children: [
                      Expanded(
                        child: _ClipActionButton(
                          metrics: metrics,
                          dark: dark,
                          label: 'Save',
                          onTap: canDownload ? onDownload : () {},
                          child: _ClipDownloadIcon(
                            size: metrics.actionIconSize,
                            color:
                                dark ? Colors.white : const Color(0xFF111827),
                          ),
                        ),
                      ),
                      SizedBox(width: metrics.actionGap),
                      Expanded(
                        child: _ClipActionButton(
                          metrics: metrics,
                          dark: dark,
                          label: 'Share',
                          onTap:
                              (_isStaticPreviewMode || _shareInProgress)
                                  ? () {}
                                  : _shareVideo,
                          child: _ClipShareIcon(
                            size: metrics.actionIconSize,
                            color:
                                dark ? Colors.white : const Color(0xFF111827),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: metrics.detailFooterTopGap),
                  Container(
                    height: 1,
                    color:
                        dark
                            ? Colors.white.withValues(alpha: 0.04)
                            : const Color(0xFFE5E7EB),
                  ),
                  SizedBox(height: metrics.detailFooterBottomGap),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: metrics.scaled(1)),
                        child: _ClipLockIcon(
                          size: metrics.footerLockSize,
                          color:
                              dark
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : const Color(0xFF9CA3AF),
                        ),
                      ),
                      SizedBox(width: metrics.footerLockGap),
                      Expanded(
                        child: Text(
                          'Shared clips are decrypted for the recipient.\nOnly share with people you trust.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: metrics.footerTextSize,
                            height: 14.63 / 9,
                            color:
                                dark
                                    ? Colors.white.withValues(alpha: 0.4)
                                    : const Color(0xFF6B7280),
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
    );
  }

  Widget _speedChip(
    String label,
    bool selected, {
    required _ClipViewMetrics metrics,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width:
            label == '0.5×'
                ? metrics.speedChipWideWidth
                : metrics.speedChipNarrowWidth,
        height: metrics.speedChipHeight,
        decoration: BoxDecoration(
          color:
              selected
                  ? const Color(0xFF8BB1F4).withValues(alpha: 0.14)
                  : (dark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFF3F4F6)),
          borderRadius: BorderRadius.circular(metrics.speedChipRadius),
          border: Border.all(
            color:
                selected
                    ? const Color(0xFF8BB1F4)
                    : (dark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFE5E7EB)),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: metrics.speedChipTextSize,
              color:
                  selected
                      ? const Color(0xFF8BB1F4)
                      : (dark
                          ? Colors.white.withValues(alpha: 0.4)
                          : const Color(0xFF6B7280)),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration position) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(position.inMinutes.remainder(60));
    final seconds = twoDigits(position.inSeconds.remainder(60));
    return "${position.inHours > 0 ? '${twoDigits(position.inHours)}:' : ''}$minutes:$seconds";
  }
}

class _ClipViewMetrics {
  const _ClipViewMetrics(this.scale);

  final double scale;

  double scaled(double value) => value * scale;

  static _ClipViewMetrics forWidth(double width) {
    final scale = width / 290;
    return _ClipViewMetrics(scale);
  }

  double get pageInset => scaled(20);
  double get topPadding => scaled(12);
  double get bottomPadding => scaled(28);
  double get backButtonSize => scaled(32);
  double get backIconSize => scaled(16);
  double get headerGap => scaled(12);
  double get titleSize => scaled(15);
  double get subtitleSize => scaled(10);
  double get subtitleGap => scaled(4);
  double get headerToMediaGap => scaled(22.5);
  double get mediaRadius => scaled(16);
  double get playButtonSize => scaled(48);
  double get mediaToProgressGap => scaled(12);
  double get progressHeight => scaled(8);
  double get progressThumbRadius => scaled(6);
  double get progressToTimeGap => scaled(6);
  double get timeSize => scaled(9);
  double get timeToControlsGap => scaled(14);
  double get controlIconSize => scaled(16);
  double get controlIconGap => scaled(16);
  double get speedChipWideWidth => scaled(48.27);
  double get speedChipNarrowWidth => scaled(38.96);
  double get speedChipHeight => scaled(29);
  double get speedChipRadius => scaled(8);
  double get speedChipGap => scaled(8);
  double get speedChipTextSize => scaled(10);
  double get controlsToDetailsGap => scaled(22.5);
  double get detailCardRadius => scaled(12);
  double get detailCardInset => scaled(16);
  double get detailTitleSize => scaled(16);
  double get detailTitleGap => scaled(8);
  double get badgeHeight => scaled(23);
  double get badgeRadius => scaled(6);
  double get badgeHorizontalPadding => scaled(10);
  double get badgeIconSize => scaled(10);
  double get badgeIconGap => scaled(6);
  double get badgeTextSize => scaled(10);
  double get badgeLetterSpacing => scaled(0.5);
  double get metaLockSize => scaled(10);
  double get metaLockGap => scaled(6);
  double get metaTextSize => scaled(9);
  double get detailDividerTopGap => scaled(16);
  double get detailDividerBottomGap => scaled(16);
  double get actionGap => scaled(12);
  double get actionHeight => scaled(36.5);
  double get actionRadius => scaled(8);
  double get actionIconSize => scaled(14);
  double get actionIconGap => scaled(8);
  double get actionTextSize => scaled(11);
  double get detailFooterTopGap => scaled(16);
  double get detailFooterBottomGap => scaled(14);
  double get footerLockSize => scaled(10);
  double get footerLockGap => scaled(8);
  double get footerTextSize => scaled(9);
}

class _ClipProgressBar extends StatelessWidget {
  const _ClipProgressBar({
    required this.valueMs,
    required this.maxMs,
    required this.dark,
    required this.height,
    required this.thumbRadius,
    required this.onChanged,
  });

  final double valueMs;
  final double maxMs;
  final bool dark;
  final double height;
  final double thumbRadius;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: height,
        activeTrackColor: const Color(0xFF8BB3EE),
        inactiveTrackColor:
            dark
                ? Colors.white.withValues(alpha: 0.1)
                : const Color(0xFFE5E7EB),
        thumbColor: Colors.white,
        overlayShape: SliderComponentShape.noOverlay,
        trackShape: const RoundedRectSliderTrackShape(),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumbRadius),
      ),
      child: Slider(
        value: valueMs.clamp(0, maxMs),
        max: maxMs <= 0 ? 1 : maxMs,
        onChanged: onChanged,
      ),
    );
  }
}

class _ClipCircleButton extends StatelessWidget {
  const _ClipCircleButton({
    required this.size,
    required this.fill,
    required this.onTap,
    required this.child,
  });

  final double size;
  final Color fill;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(size / 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size / 2),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _ClipBareIconButton extends StatelessWidget {
  const _ClipBareIconButton({
    required this.size,
    required this.onTap,
    required this.child,
  });

  final double size;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: SizedBox(
        width: size + 8,
        height: size + 8,
        child: Center(child: child),
      ),
    );
  }
}

class _ClipPlayOverlayButton extends StatelessWidget {
  const _ClipPlayOverlayButton({
    required this.size,
    required this.dark,
    required this.onTap,
  });

  final double size;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(size / 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size / 2),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 15,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: _ClipPlayIcon(
              size: size * 0.42,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClipActionButton extends StatelessWidget {
  const _ClipActionButton({
    required this.metrics,
    required this.dark,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final _ClipViewMetrics metrics;
  final bool dark;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          dark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(metrics.actionRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(metrics.actionRadius),
        onTap: onTap,
        child: SizedBox(
          height: metrics.actionHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              child,
              SizedBox(width: metrics.actionIconGap),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: metrics.actionTextSize,
                  fontWeight: FontWeight.w500,
                  color: dark ? Colors.white : const Color(0xFF111827),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClipBackIcon extends StatelessWidget {
  const _ClipBackIcon({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _ClipBackPainter(color)),
  );
}

class _ClipPlayIcon extends StatelessWidget {
  const _ClipPlayIcon({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _ClipPlayPainter(color)),
  );
}

class _ClipRewindIcon extends StatelessWidget {
  const _ClipRewindIcon({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _ClipRewindPainter(color)),
  );
}

class _ClipForwardIcon extends StatelessWidget {
  const _ClipForwardIcon({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _ClipForwardPainter(color)),
  );
}

class _ClipDownloadIcon extends StatelessWidget {
  const _ClipDownloadIcon({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _ClipDownloadPainter(color)),
  );
}

class _ClipShareIcon extends StatelessWidget {
  const _ClipShareIcon({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _ClipSharePainter(color)),
  );
}

class _ClipLockIcon extends StatelessWidget {
  const _ClipLockIcon({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _ClipLockPainter(color)),
  );
}

class _ClipPersonBadgeIcon extends StatelessWidget {
  const _ClipPersonBadgeIcon({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _ClipPersonPainter(color)),
  );
}

class _ClipBackPainter extends CustomPainter {
  const _ClipBackPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.125
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color;
    final path =
        Path()
          ..moveTo(size.width * 0.62, size.height * 0.2)
          ..lineTo(size.width * 0.32, size.height * 0.5)
          ..lineTo(size.width * 0.62, size.height * 0.8);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ClipBackPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ClipPlayPainter extends CustomPainter {
  const _ClipPlayPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()
          ..moveTo(size.width * 0.28, size.height * 0.18)
          ..lineTo(size.width * 0.78, size.height * 0.5)
          ..lineTo(size.width * 0.28, size.height * 0.82)
          ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _ClipPlayPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ClipRewindPainter extends CustomPainter {
  const _ClipRewindPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.11
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color;
    final first =
        Path()
          ..moveTo(size.width * 0.62, size.height * 0.18)
          ..lineTo(size.width * 0.34, size.height * 0.5)
          ..lineTo(size.width * 0.62, size.height * 0.82);
    final second =
        Path()
          ..moveTo(size.width * 0.88, size.height * 0.18)
          ..lineTo(size.width * 0.6, size.height * 0.5)
          ..lineTo(size.width * 0.88, size.height * 0.82);
    canvas.drawPath(first, paint);
    canvas.drawPath(second, paint);
  }

  @override
  bool shouldRepaint(covariant _ClipRewindPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ClipForwardPainter extends CustomPainter {
  const _ClipForwardPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.11
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color;
    final first =
        Path()
          ..moveTo(size.width * 0.12, size.height * 0.18)
          ..lineTo(size.width * 0.4, size.height * 0.5)
          ..lineTo(size.width * 0.12, size.height * 0.82);
    final second =
        Path()
          ..moveTo(size.width * 0.38, size.height * 0.18)
          ..lineTo(size.width * 0.66, size.height * 0.5)
          ..lineTo(size.width * 0.38, size.height * 0.82);
    canvas.drawPath(first, paint);
    canvas.drawPath(second, paint);
  }

  @override
  bool shouldRepaint(covariant _ClipForwardPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ClipDownloadPainter extends CustomPainter {
  const _ClipDownloadPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.12
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color;
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.18),
      Offset(size.width * 0.5, size.height * 0.62),
      paint,
    );
    final arrow =
        Path()
          ..moveTo(size.width * 0.3, size.height * 0.46)
          ..lineTo(size.width * 0.5, size.height * 0.66)
          ..lineTo(size.width * 0.7, size.height * 0.46);
    canvas.drawPath(arrow, paint);
    final tray =
        Path()
          ..moveTo(size.width * 0.22, size.height * 0.78)
          ..lineTo(size.width * 0.78, size.height * 0.78)
          ..lineTo(size.width * 0.7, size.height * 0.92)
          ..lineTo(size.width * 0.3, size.height * 0.92)
          ..close();
    canvas.drawPath(tray, paint);
  }

  @override
  bool shouldRepaint(covariant _ClipDownloadPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ClipSharePainter extends CustomPainter {
  const _ClipSharePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.12
          ..strokeCap = StrokeCap.round
          ..color = color;
    final fill =
        Paint()
          ..style = PaintingStyle.fill
          ..color = color;
    final a = Offset(size.width * 0.28, size.height * 0.52);
    final b = Offset(size.width * 0.68, size.height * 0.28);
    final c = Offset(size.width * 0.72, size.height * 0.76);
    canvas.drawLine(a, b, stroke);
    canvas.drawLine(a, c, stroke);
    canvas.drawCircle(a, size.width * 0.1, fill);
    canvas.drawCircle(b, size.width * 0.1, fill);
    canvas.drawCircle(c, size.width * 0.1, fill);
  }

  @override
  bool shouldRepaint(covariant _ClipSharePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ClipLockPainter extends CustomPainter {
  const _ClipLockPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.14
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.42,
        size.width * 0.64,
        size.height * 0.42,
      ),
      Radius.circular(size.width * 0.12),
    );
    canvas.drawRRect(body, paint);
    final shackle =
        Path()
          ..moveTo(size.width * 0.32, size.height * 0.42)
          ..lineTo(size.width * 0.32, size.height * 0.26)
          ..arcToPoint(
            Offset(size.width * 0.68, size.height * 0.26),
            radius: Radius.circular(size.width * 0.18),
          )
          ..lineTo(size.width * 0.68, size.height * 0.42);
    canvas.drawPath(shackle, paint);
  }

  @override
  bool shouldRepaint(covariant _ClipLockPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ClipPersonPainter extends CustomPainter {
  const _ClipPersonPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.15
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color;
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.34),
      size.width * 0.18,
      paint,
    );
    final body =
        Path()
          ..moveTo(size.width * 0.18, size.height * 0.88)
          ..lineTo(size.width * 0.18, size.height * 0.74)
          ..quadraticBezierTo(
            size.width * 0.5,
            size.height * 0.48,
            size.width * 0.82,
            size.height * 0.74,
          )
          ..lineTo(size.width * 0.82, size.height * 0.88);
    canvas.drawPath(body, paint);
  }

  @override
  bool shouldRepaint(covariant _ClipPersonPainter oldDelegate) =>
      oldDelegate.color != color;
}
