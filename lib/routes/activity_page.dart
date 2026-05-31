//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/routes/camera/view_camera.dart';
import 'package:secluso_flutter/routes/camera/view_video.dart';
import 'package:secluso_flutter/ui/secluso_preview_assets.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_shell_ui.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/utilities/video_thumbnail_store.dart';
import 'package:path/path.dart' as p;

class ActivityPreviewItem {
  const ActivityPreviewItem({
    required this.cameraName,
    required this.videoName,
    this.previewAssetPath,
    this.previewVideoAssetPath,
    required this.detections,
    this.motion = true,
    this.title,
    this.subtitle,
    this.sectionLabel,
    this.durationLabel,
    this.isSystem = false,
  });

  final String cameraName;
  final String videoName;
  final String? previewAssetPath;
  final String? previewVideoAssetPath;
  final Set<String> detections;
  final bool motion;
  final String? title;
  final String? subtitle;
  final String? sectionLabel;
  final String? durationLabel;
  final bool isSystem;
}

class ActivityPage extends StatefulWidget {
  const ActivityPage({
    super.key,
    this.shellMode = false,
    this.previewItems,
    this.refreshToken = 0,
  });

  final bool shellMode;
  final List<ActivityPreviewItem>? previewItems;
  final int refreshToken;

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityEntry {
  const _ActivityEntry({
    required this.cameraName,
    required this.videoName,
    required this.detections,
    required this.motion,
    this.thumbnailBytes,
    this.previewAssetPath,
    this.previewVideoAssetPath,
    this.title,
    this.subtitle,
    this.sectionLabel,
    this.durationLabel,
    this.isSystem = false,
    this.hasVideoFile = true,
  });

  final String cameraName;
  final String videoName;
  final Set<String> detections;
  final bool motion;
  final Uint8List? thumbnailBytes;
  final String? previewAssetPath;
  final String? previewVideoAssetPath;
  final String? title;
  final String? subtitle;
  final String? sectionLabel;
  final String? durationLabel;
  final bool isSystem;
  final bool hasVideoFile;
}

class _ActivityPageState extends State<ActivityPage>
    with SingleTickerProviderStateMixin {
  static const _categoryFilters = ['ALL', 'PEOPLE', 'MOTION', 'SYSTEM'];
  final List<_ActivityEntry> _entries = [];
  final Map<String, Uint8List> _eventThumbCache = {};
  final Map<String, Future<Uint8List?>> _eventThumbFutures = {};
  bool _isLoading = true;
  String _selectedCategory = 'ALL';
  String? _selectedCameraName;
  late final AnimationController _emptyCardsBreatheController;

  bool get _isPreviewMode => widget.previewItems != null;
  bool get _showSystemExample => _entries.isNotEmpty;

  void _applyPreviewEntries() {
    _entries
      ..clear()
      ..addAll(
        (widget.previewItems ?? const <ActivityPreviewItem>[]).map(
          (item) => _ActivityEntry(
            cameraName: item.cameraName,
            videoName: item.videoName,
            previewAssetPath: item.previewAssetPath,
            previewVideoAssetPath: item.previewVideoAssetPath,
            detections: item.detections,
            motion: item.motion,
            title: item.title,
            subtitle: item.subtitle,
            sectionLabel: item.sectionLabel,
            durationLabel: item.durationLabel,
            isSystem: item.isSystem,
            hasVideoFile: true,
          ),
        ),
      );
    _normalizeCameraSelection();
    _isLoading = false;
  }

  bool _hasPersonDetection(Set<String> detections) {
    return detections.contains('human') || detections.contains('person');
  }

  bool _matchesCategory(_ActivityEntry entry, [String? category]) {
    final activeCategory = category ?? _selectedCategory;
    switch (activeCategory) {
      case 'PEOPLE':
        return !entry.isSystem && _hasPersonDetection(entry.detections);
      case 'MOTION':
        return !entry.isSystem && entry.motion;
      case 'SYSTEM':
        return entry.isSystem;
      case 'ALL':
      default:
        return true;
    }
  }

  List<String> _availableCameraNames([String? category]) {
    final names = <String>[];
    final seen = <String>{};
    for (final entry in _entries) {
      if (entry.isSystem || entry.cameraName.isEmpty) continue;
      if (!_matchesCategory(entry, category)) continue;
      if (!seen.add(entry.cameraName)) continue;
      names.add(entry.cameraName);
    }
    return names;
  }

  void _normalizeCameraSelection([String? category]) {
    final available = _availableCameraNames(category);
    if (_selectedCameraName != null &&
        !available.contains(_selectedCameraName)) {
      _selectedCameraName = null;
    }
  }

  List<_ActivityEntry> get _filteredEntries {
    return _entries.where((entry) {
      if (!_matchesCategory(entry)) {
        return false;
      }
      if (_selectedCameraName == null) {
        return true;
      }
      return !entry.isSystem && entry.cameraName == _selectedCameraName;
    }).toList();
  }

  bool get _shouldShowSyntheticSystemEntry {
    if (_isPreviewMode || widget.shellMode || !_showSystemExample) {
      return false;
    }
    if (_selectedCategory == 'PEOPLE' || _selectedCategory == 'MOTION') {
      return false;
    }
    if (_selectedCameraName == null) {
      return true;
    }
    return _entries.first.cameraName == _selectedCameraName;
  }

  void _selectCategory(String category) {
    if (_selectedCategory == category) return;
    setState(() {
      _selectedCategory = category;
      _normalizeCameraSelection(category);
    });
  }

  void _selectCamera(String? cameraName) {
    if (_selectedCameraName == cameraName) return;
    setState(() {
      _selectedCameraName = cameraName;
    });
  }

  @override
  void initState() {
    super.initState();
    _emptyCardsBreatheController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    if (_isPreviewMode) {
      _applyPreviewEntries();
      return;
    }
    _loadActivity();
  }

  @override
  void dispose() {
    _emptyCardsBreatheController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ActivityPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasPreviewMode = oldWidget.previewItems != null;
    if (_isPreviewMode) {
      if (!wasPreviewMode || oldWidget.previewItems != widget.previewItems) {
        setState(_applyPreviewEntries);
      }
      return;
    }
    if (wasPreviewMode) {
      setState(() {
        _isLoading = true;
        _entries.clear();
      });
      _loadActivity();
      return;
    }
    if (widget.refreshToken != oldWidget.refreshToken) {
      setState(() {
        _isLoading = true;
      });
      _loadActivity();
    }
  }

  Future<bool> _videoFileExists(String cameraName, String videoFile) async {
    final cameraDir = await AppPaths.cameraDirectory(cameraName);
    final file = File(p.join(cameraDir.path, 'videos', videoFile));
    return file.exists();
  }

  Future<Uint8List?> _eventThumbnailBytes(
    String cameraName,
    String videoFile,
  ) async {
    final cacheKey = '$cameraName\n$videoFile';
    final cached = _eventThumbCache[cacheKey];
    if (cached != null) {
      return cached;
    }
    final inFlight = _eventThumbFutures[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _readEventThumbnailBytes(cameraName, videoFile, cacheKey);
    _eventThumbFutures[cacheKey] = future;
    try {
      return await future;
    } finally {
      _eventThumbFutures.remove(cacheKey);
    }
  }

  Future<Uint8List?> _readEventThumbnailBytes(
    String cameraName,
    String videoFile,
    String cacheKey,
  ) async {
    try {
      final bytes = await VideoThumbnailStore.loadOrGenerate(
        cameraName: cameraName,
        videoFile: videoFile,
        logPrefix: 'Activity thumb',
      );
      if (bytes != null) {
        _eventThumbCache[cacheKey] = bytes;
      }
      return bytes;
    } catch (e) {
      Log.w('Activity thumb invalid [$cameraName/$videoFile]: $e');
      return null;
    }
  }

  Future<void> _loadActivity() async {
    try {
      if (!AppStores.isInitialized) {
        await AppStores.init();
      }
      final videoStore = AppStores.instance.videoStore;
      final detectionStore = AppStores.instance.detectionStore;
      final videos = await videoStore.listRecent(limit: 40);

      final loaded = <_ActivityEntry>[];
      final loadedKeys = <String>{};
      final seenKeys = <String>{};
      for (final video in videos) {
        final videoKey = '${video.camera}\n${video.video}';
        if (!seenKeys.add(videoKey)) {
          continue;
        }
        final detections =
            (await detectionStore.findByVideoFile(
              video.video,
            )).map((row) => row.type.toLowerCase()).toSet();

        if (!video.motion && detections.isEmpty) {
          continue;
        }
        final hasVideoFile = await _videoFileExists(video.camera, video.video);
        final thumbnailBytes = await _eventThumbnailBytes(
          video.camera,
          video.video,
        );
        if (!hasVideoFile && thumbnailBytes == null) {
          continue;
        }

        loaded.add(
          _ActivityEntry(
            cameraName: video.camera,
            videoName: video.video,
            detections: detections,
            motion: video.motion,
            thumbnailBytes: thumbnailBytes,
            hasVideoFile: hasVideoFile,
          ),
        );
        loadedKeys.add(videoKey);
      }
      _eventThumbCache.removeWhere((key, _) => !loadedKeys.contains(key));
      _eventThumbFutures.removeWhere((key, _) => !loadedKeys.contains(key));
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(loaded);
        _normalizeCameraSelection();
        _isLoading = false;
      });
    } catch (e, st) {
      Log.e('Failed to load activity: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _timestampLabel(String videoName) {
    if (videoName.startsWith('video_') && videoName.endsWith('.mp4')) {
      final value = int.tryParse(
        videoName.replaceFirst('video_', '').replaceFirst('.mp4', ''),
      );
      if (value != null) {
        final local =
            DateTime.fromMillisecondsSinceEpoch(
              value * 1000,
              isUtc: true,
            ).toLocal();
        final hour =
            local.hour > 12
                ? local.hour - 12
                : (local.hour == 0 ? 12 : local.hour);
        final minute = local.minute.toString().padLeft(2, '0');
        final suffix = local.hour >= 12 ? 'PM' : 'AM';
        return '$hour:$minute $suffix';
      }
    }
    return videoName;
  }

  String _sectionLabel(int index) {
    if (index < 3) return 'TODAY';
    return 'YESTERDAY';
  }

  String _entrySectionLabel(_ActivityEntry entry, int index) {
    return entry.sectionLabel ?? _sectionLabel(index);
  }

  String _detectionTitle(_ActivityEntry entry) {
    if (entry.title != null) return entry.title!;
    if (entry.isSystem) return 'System';
    if (!entry.motion) return 'Livestream Clip';
    if (entry.detections.contains('human')) return 'Person Detected';
    if (entry.detections.contains('vehicle')) return 'Vehicle Detected';
    if (entry.detections.contains('pet') || entry.detections.contains('pets')) {
      return 'Pet Detected';
    }
    return 'Motion';
  }

  String _entrySubtitle(_ActivityEntry entry) {
    return entry.subtitle ??
        '${entry.cameraName} · ${_timestampLabel(entry.videoName)}';
  }

  String _entryDuration(_ActivityEntry entry) {
    return entry.durationLabel ?? (entry.motion ? '0:12' : '0:08');
  }

  double _breatheOpacity(double baseOpacity, double delayFraction) {
    final t = (_emptyCardsBreatheController.value + delayFraction) % 1.0;
    final wave = 0.5 - 0.5 * math.cos(2 * math.pi * t);
    final eased = Curves.easeInOut.transform(wave);
    final minOpacity = (baseOpacity - 0.08).clamp(0.0, 1.0);
    final maxOpacity = (baseOpacity + 0.08).clamp(0.0, 1.0);
    return minOpacity + ((maxOpacity - minOpacity) * eased);
  }

  Widget _thumb(_ActivityEntry entry) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 82,
        height: 58,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (entry.thumbnailBytes != null)
              Image.memory(entry.thumbnailBytes!, fit: BoxFit.cover)
            else ...[
              Container(
                color:
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFF3F4F6),
              ),
              if (entry.previewAssetPath != null)
                Opacity(
                  opacity: 0.45,
                  child: Image.asset(
                    entry.previewAssetPath!,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Center(
                  child: Icon(
                    Icons.videocam_outlined,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.28),
                  ),
                ),
            ],
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  entry.motion ? '0:12' : '0:08',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEntry(_ActivityEntry entry) {
    if (entry.isSystem) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => CameraViewPage(
                cameraName: entry.cameraName,
                previewVideos: const [],
                previewDetectionsByVideo: const {},
              ),
        ),
      );
      return;
    }
    if (!entry.hasVideoFile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clip is still downloading.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => VideoViewPage(
              cameraName: entry.cameraName,
              videoTitle: entry.videoName,
              visibleVideoTitle: _timestampLabel(entry.videoName),
              canDownload: entry.previewVideoAssetPath != null,
              isLivestream: !entry.motion,
              previewAssetPath:
                  _isPreviewMode
                      ? (entry.previewAssetPath ??
                          SeclusoPreviewAssets.hallwayEvent)
                      : entry.previewAssetPath,
              previewVideoAssetPath: entry.previewVideoAssetPath,
              previewDetections: entry.detections,
              previewDuration:
                  entry.previewVideoAssetPath != null
                      ? const Duration(seconds: 16)
                      : const Duration(seconds: 42),
              previewPosition:
                  entry.previewVideoAssetPath != null
                      ? Duration.zero
                      : const Duration(seconds: 12),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredEntries = _filteredEntries;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.shellMode) {
      final backgroundColor =
          Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF050505)
              : const Color(0xFFF2F2F7);
      if (_entries.isEmpty) {
        return ShellScaffold(
          body: _buildShellEmptyBody(context),
          backgroundColor: backgroundColor,
          safeTop: true,
        );
      }
      if (_entries.isNotEmpty) {
        return ShellScaffold(
          body: _buildShellBody(context, filteredEntries),
          backgroundColor: backgroundColor,
          safeTop: true,
        );
      }
    }

    final body = ListView(
      padding: EdgeInsets.fromLTRB(
        28,
        widget.shellMode ? 24 : 18,
        28,
        widget.shellMode ? 20 : 32,
      ),
      children: [
        Text(
          'Activity',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Saved clips and recent events across all cameras.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.56),
            height: 1.4,
          ),
        ),
        if (_entries.isEmpty) ...[
          const SizedBox(height: 18),
          for (var i = 0; i < 3; i++) ...[
            _ActivitySkeletonCard(
              icon:
                  i == 0
                      ? Icons.person_outline
                      : (i == 1
                          ? Icons.graphic_eq_rounded
                          : Icons.shield_outlined),
            ),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 22),
          Icon(
            Icons.graphic_eq_rounded,
            size: 32,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.34),
          ),
          const SizedBox(height: 18),
          Text(
            'Events will appear here when your\ncameras detect people or motion.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.58),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.24),
              ),
              const SizedBox(width: 8),
              Text(
                'Clips encrypted on-device · Never uploaded',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.24),
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final filter in _categoryFilters)
                _ActivityPill(
                  label: filter,
                  selected: filter == _selectedCategory,
                  onTap: () => _selectCategory(filter),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ActivityPill(
                label: 'ALL CAMERAS',
                selected: _selectedCameraName == null,
                onTap: () => _selectCamera(null),
              ),
              for (final cameraName in _availableCameraNames())
                _ActivityPill(
                  label: cameraName.toUpperCase(),
                  selected: _selectedCameraName == cameraName,
                  onTap: () => _selectCamera(cameraName),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (filteredEntries.isEmpty) ...[
            const SizedBox(height: 18),
            Icon(
              Icons.filter_alt_off_outlined,
              size: 32,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.34),
            ),
            const SizedBox(height: 18),
            Text(
              'No activity matches these filters.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.58),
                height: 1.45,
              ),
            ),
          ] else
            for (var i = 0; i < filteredEntries.length; i++) ...[
              if (i == 0 ||
                  _entrySectionLabel(filteredEntries[i], i) !=
                      _entrySectionLabel(filteredEntries[i - 1], i - 1)) ...[
                ShellSectionLabel(_entrySectionLabel(filteredEntries[i], i)),
                const SizedBox(height: 12),
              ],
              _ActivityCard(
                title: _detectionTitle(filteredEntries[i]),
                subtitle: _entrySubtitle(filteredEntries[i]),
                thumbnail: _thumb(filteredEntries[i]),
                onTap: () => _openEntry(filteredEntries[i]),
              ),
              const SizedBox(height: 12),
            ],
          if (_shouldShowSyntheticSystemEntry) ...[
            const SizedBox(height: 6),
            const ShellSectionLabel('Yesterday'),
            const SizedBox(height: 12),
            _ActivityCard(
              title: 'System',
              subtitle: 'Armed (Away) · 6:00 PM',
              thumbnail: Container(
                width: 82,
                height: 58,
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.04)
                          : const Color(0xFFF1F2F6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.shield_outlined,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
              onTap:
                  () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => CameraViewPage(
                            cameraName: _entries.first.cameraName,
                            previewVideos: const [],
                            previewDetectionsByVideo: const {},
                          ),
                    ),
                  ),
            ),
          ],
        ],
      ],
    );

    if (widget.shellMode) {
      return ShellScaffold(body: body, safeTop: true);
    }

    return SeclusoScaffold(
      appBar: seclusoAppBar(
        context,
        title: '',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(top: true, child: body),
    );
  }

  Widget _buildShellBody(
    BuildContext context,
    List<_ActivityEntry> filteredEntries,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _ShellActivityMetrics.forWidth(constraints.maxWidth);
        final dark = Theme.of(context).brightness == Brightness.dark;
        final filterViewportWidth =
            metrics.filterViewportWidth
                .clamp(0, constraints.maxWidth - (metrics.railInset * 2))
                .toDouble();
        return Container(
          color: dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              0,
              metrics.topPadding,
              0,
              metrics.bottomPadding,
            ),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.headerInset),
                child: Text(
                  'Activity',
                  style: shellTitleStyle(
                    context,
                    fontSize: metrics.titleSize,
                    designLetterSpacing: metrics.titleLetterSpacing,
                    color: dark ? Colors.white : const Color(0xFF111827),
                  ),
                ),
              ),
              SizedBox(height: metrics.subtitleTopGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.headerInset),
                child: Text(
                  'Saved clips and recent events across all\ncameras.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:
                        dark
                            ? Colors.white.withValues(alpha: 0.4)
                            : const Color(0xFF6B7280),
                    fontSize: metrics.subtitleSize,
                    fontWeight: FontWeight.w400,
                    height: 1.5,
                  ),
                ),
              ),
              SizedBox(height: metrics.headerBlockGap),
              SizedBox(
                height: metrics.largeChipTrackHeight,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: filterViewportWidth,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _ShellActivityPill(
                              label: 'ALL',
                              selected: _selectedCategory == 'ALL',
                              compact: false,
                              metrics: metrics,
                              dark: dark,
                              width: metrics.largeChipWidth('ALL'),
                              onTap: () => _selectCategory('ALL'),
                            ),
                            SizedBox(width: metrics.chipGap),
                            _ShellActivityPill(
                              label: 'PEOPLE',
                              selected: _selectedCategory == 'PEOPLE',
                              compact: false,
                              metrics: metrics,
                              dark: dark,
                              width: metrics.largeChipWidth('PEOPLE'),
                              onTap: () => _selectCategory('PEOPLE'),
                            ),
                            SizedBox(width: metrics.chipGap),
                            _ShellActivityPill(
                              label: 'MOTION',
                              selected: _selectedCategory == 'MOTION',
                              compact: false,
                              metrics: metrics,
                              dark: dark,
                              width: metrics.largeChipWidth('MOTION'),
                              onTap: () => _selectCategory('MOTION'),
                            ),
                            SizedBox(width: metrics.chipGap),
                            _ShellActivityPill(
                              label: 'SYSTEM',
                              selected: _selectedCategory == 'SYSTEM',
                              compact: false,
                              metrics: metrics,
                              dark: dark,
                              width: metrics.largeChipWidth('SYSTEM'),
                              onTap: () => _selectCategory('SYSTEM'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: metrics.filterRowsGap),
              SizedBox(
                height: metrics.compactChipTrackHeight,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: metrics.railInset),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: filterViewportWidth,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _ShellActivityPill(
                              label: 'ALL CAMERAS',
                              selected: _selectedCameraName == null,
                              compact: true,
                              metrics: metrics,
                              dark: dark,
                              width: metrics.compactChipWidth('ALL CAMERAS'),
                              onTap: () => _selectCamera(null),
                            ),
                            ..._buildCameraPills(
                              metrics,
                              dark,
                              _selectedCategory,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: metrics.filterToListGap),
              if (filteredEntries.isEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    metrics.headerInset,
                    metrics.sectionTopInset,
                    metrics.headerInset,
                    metrics.cardGap,
                  ),
                  child: Text(
                    'No activity matches these filters.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.4)
                              : const Color(0xFF6B7280),
                      fontSize: metrics.subtitleSize,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
                ),
              for (var i = 0; i < filteredEntries.length; i++) ...[
                if (i == 0 ||
                    _entrySectionLabel(filteredEntries[i], i) !=
                        _entrySectionLabel(filteredEntries[i - 1], i - 1))
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      metrics.headerInset,
                      metrics.sectionTopInset,
                      metrics.headerInset,
                      metrics.sectionBottomInset,
                    ),
                    child: _ShellActivitySectionLabel(
                      _entrySectionLabel(filteredEntries[i], i),
                      metrics: metrics,
                      dark: dark,
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    metrics.railInset,
                    0,
                    metrics.railInset,
                    metrics.cardGap,
                  ),
                  child: _ShellActivityCard(
                    title: _detectionTitle(filteredEntries[i]),
                    subtitle: _entrySubtitle(filteredEntries[i]),
                    previewAssetPath: filteredEntries[i].previewAssetPath,
                    thumbnailBytes: filteredEntries[i].thumbnailBytes,
                    durationLabel: _entryDuration(filteredEntries[i]),
                    isSystem: filteredEntries[i].isSystem,
                    metrics: metrics,
                    dark: dark,
                    onTap: () => _openEntry(filteredEntries[i]),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildShellEmptyBody(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _ShellEmptyActivityMetrics.forWidth(
          constraints.maxWidth,
        );
        final dark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          color: dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              0,
              metrics.topPadding,
              0,
              metrics.bottomPadding,
            ),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.headerInset),
                child: Text(
                  'Activity',
                  style: shellTitleStyle(
                    context,
                    fontSize: metrics.titleSize,
                    designLetterSpacing: metrics.titleLetterSpacing,
                    color: dark ? Colors.white : const Color(0xFF111827),
                  ),
                ),
              ),
              SizedBox(height: metrics.subtitleTopGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.headerInset),
                child: Text(
                  'Saved clips and recent events across all\ncameras.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:
                        dark
                            ? Colors.white.withValues(alpha: 0.4)
                            : const Color(0xFF6B7280),
                    fontSize: metrics.subtitleSize,
                    fontWeight: FontWeight.w400,
                    height: 1.5,
                  ),
                ),
              ),
              SizedBox(height: metrics.headerBlockGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.cardInset),
                child: AnimatedBuilder(
                  animation: _emptyCardsBreatheController,
                  builder:
                      (context, _) => Column(
                        children: [
                          _ShellEmptyActivityPlaceholderCard(
                            metrics: metrics,
                            dark: dark,
                            opacity: _breatheOpacity(0.5, 0.0),
                            leftAccentColor:
                                dark
                                    ? const Color(0x4D8BB3EE)
                                    : const Color(0x4D8BB3EE),
                            iconBuilder:
                                (size, color) =>
                                    _DesignPersonIcon(size: size, color: color),
                            titleWidth: metrics.scaleValue(96),
                            subtitleWidth: metrics.scaleValue(64),
                            metaWidth: metrics.scaleValue(32),
                          ),
                          SizedBox(height: metrics.cardGap),
                          _ShellEmptyActivityPlaceholderCard(
                            metrics: metrics,
                            dark: dark,
                            opacity: _breatheOpacity(0.35, 0.24),
                            leftAccentColor:
                                dark
                                    ? const Color(0x4D60A5FA)
                                    : const Color(0x4D60A5FA),
                            iconBuilder:
                                (size, color) =>
                                    _DesignPulseIcon(size: size, color: color),
                            titleWidth: metrics.scaleValue(64),
                            subtitleWidth: metrics.scaleValue(80),
                            metaWidth: metrics.scaleValue(40),
                          ),
                          SizedBox(height: metrics.cardGap),
                          _ShellEmptyActivityPlaceholderCard(
                            metrics: metrics,
                            dark: dark,
                            opacity: _breatheOpacity(0.2, 0.48),
                            iconBuilder:
                                (size, color) =>
                                    _DesignShieldIcon(size: size, color: color),
                            titleWidth: metrics.scaleValue(80),
                            subtitleWidth: metrics.scaleValue(48),
                            metaWidth: metrics.scaleValue(24),
                          ),
                        ],
                      ),
                ),
              ),
              SizedBox(height: metrics.placeholderToIconGap),
              Center(
                child: SizedBox(
                  width: metrics.emptyIconCircleSize,
                  height: metrics.emptyIconCircleSize,
                  child: Center(
                    child: _DesignCenterPulseIcon(
                      size: metrics.emptyIconSize,
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.3)
                              : const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ),
              SizedBox(height: metrics.emptyIconToCopyGap),
              Text(
                'Events will appear here when your\ncameras detect people or motion.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color:
                      dark
                          ? Colors.white.withValues(alpha: 0.4)
                          : const Color(0xFF6B7280),
                  fontSize: metrics.emptyCopySize,
                  fontWeight: FontWeight.w400,
                  height: 1.625,
                ),
              ),
              SizedBox(height: metrics.copyToButtonGap),
              SizedBox(height: metrics.buttonToFooterGap),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _DesignFooterLockIcon(
                    size: metrics.footerIconSize,
                    color:
                        dark
                            ? Colors.white.withValues(alpha: 0.2)
                            : const Color(0xFFD1D5DB),
                  ),
                  SizedBox(width: metrics.footerIconGap),
                  Text(
                    'Clips encrypted on-device · Never uploaded',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.2)
                              : const Color(0xFFD1D5DB),
                      fontSize: metrics.footerTextSize,
                      fontWeight: FontWeight.w400,
                      letterSpacing: metrics.footerLetterSpacing,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildCameraPills(
    _ShellActivityMetrics metrics,
    bool dark,
    String category,
  ) {
    final labels = <String>{};
    final chips = <Widget>[];
    for (final entry in _entries) {
      if (entry.isSystem || entry.cameraName.isEmpty) continue;
      if (!_matchesCategory(entry, category)) continue;
      final label = entry.cameraName.toUpperCase();
      if (!labels.add(label)) continue;
      chips.add(SizedBox(width: metrics.chipGap));
      chips.add(
        _ShellActivityPill(
          label: label,
          selected: _selectedCameraName == entry.cameraName,
          compact: true,
          metrics: metrics,
          dark: dark,
          width: metrics.compactChipWidth(label),
          onTap: () => _selectCamera(entry.cameraName),
        ),
      );
    }
    return chips;
  }
}

class _ActivityPill extends StatelessWidget {
  const _ActivityPill({required this.label, this.selected = false, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color:
                selected
                    ? const Color(0xFF8BB1F4)
                    : (dark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.white),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color:
                  selected
                      ? const Color(0xFF8BB1F4)
                      : (dark
                          ? Colors.white.withValues(alpha: 0.08)
                          : theme.colorScheme.outlineVariant),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color:
                  selected
                      ? Colors.white
                      : theme.colorScheme.onSurface.withValues(alpha: 0.56),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellActivitySectionLabel extends StatelessWidget {
  const _ShellActivitySectionLabel(
    this.label, {
    required this.metrics,
    required this.dark,
  });

  final String label;
  final _ShellActivityMetrics metrics;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color:
            dark
                ? Colors.white.withValues(alpha: 0.2)
                : const Color(0xFF9CA3AF),
        fontSize: metrics.sectionLabelSize,
        fontWeight: FontWeight.w600,
        letterSpacing: metrics.sectionLabelLetterSpacing,
      ),
    );
  }
}

class _ShellActivityPill extends StatelessWidget {
  const _ShellActivityPill({
    required this.label,
    required this.compact,
    required this.metrics,
    required this.dark,
    this.width,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool compact;
  final bool selected;
  final _ShellActivityMetrics metrics;
  final bool dark;
  final double? width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final height =
        compact ? metrics.compactChipHeight : metrics.largeChipHeight;
    final fontSize =
        compact ? metrics.compactChipFontSize : metrics.largeChipFontSize;
    final letterSpacing =
        compact
            ? metrics.compactChipLetterSpacing
            : metrics.largeChipLetterSpacing;
    final horizontalPadding =
        compact
            ? metrics.compactChipHorizontalPadding
            : metrics.largeChipHorizontalPadding;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: width,
          height: height,
          padding:
              width == null
                  ? EdgeInsets.symmetric(horizontal: horizontalPadding)
                  : EdgeInsets.zero,
          decoration: BoxDecoration(
            color:
                selected
                    ? const Color(0xFF8BB3EE)
                    : (dark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.white),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color:
                  selected
                      ? const Color(0xFF8BB3EE)
                      : (dark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFE5E7EB)),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color:
                    selected
                        ? Colors.white
                        : (dark
                            ? Colors.white.withValues(alpha: 0.4)
                            : const Color(0xFF6B7280)),
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                letterSpacing: letterSpacing,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellActivityCard extends StatelessWidget {
  const _ShellActivityCard({
    required this.title,
    required this.subtitle,
    required this.durationLabel,
    required this.isSystem,
    required this.metrics,
    required this.dark,
    required this.onTap,
    this.previewAssetPath,
    this.thumbnailBytes,
  });

  final String title;
  final String subtitle;
  final String durationLabel;
  final bool isSystem;
  final _ShellActivityMetrics metrics;
  final bool dark;
  final VoidCallback onTap;
  final String? previewAssetPath;
  final Uint8List? thumbnailBytes;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(metrics.cardRadius),
        onTap: onTap,
        child: Container(
          height: metrics.cardHeight,
          decoration: BoxDecoration(
            color: dark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(metrics.cardRadius),
            border: Border.all(
              color:
                  dark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0x0A000000),
            ),
            boxShadow:
                dark
                    ? null
                    : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.cardHorizontalInset,
            ),
            child: Row(
              children: [
                _ShellActivityThumbnail(
                  previewAssetPath: previewAssetPath,
                  thumbnailBytes: thumbnailBytes,
                  durationLabel: durationLabel,
                  isSystem: isSystem,
                  metrics: metrics,
                  dark: dark,
                ),
                SizedBox(width: metrics.thumbGap),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          color: dark ? Colors.white : const Color(0xFF111827),
                          fontSize: metrics.cardTitleSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: metrics.cardTextGap),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              dark
                                  ? Colors.white.withValues(alpha: 0.4)
                                  : const Color(0xFF6B7280),
                          fontSize: metrics.cardSubtitleSize,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isSystem)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: metrics.chevronSize,
                    color:
                        dark
                            ? Colors.white.withValues(alpha: 0.2)
                            : const Color(0xFF9CA3AF),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellActivityThumbnail extends StatelessWidget {
  const _ShellActivityThumbnail({
    required this.durationLabel,
    required this.isSystem,
    required this.metrics,
    required this.dark,
    this.previewAssetPath,
    this.thumbnailBytes,
  });

  final String durationLabel;
  final bool isSystem;
  final _ShellActivityMetrics metrics;
  final bool dark;
  final String? previewAssetPath;
  final Uint8List? thumbnailBytes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: metrics.thumbnailWidth,
      height: metrics.thumbnailHeight,
      decoration: BoxDecoration(
        color:
            dark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(metrics.thumbnailRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(metrics.thumbnailRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isSystem)
              Center(
                child: Icon(
                  Icons.shield_outlined,
                  size: metrics.systemIconSize,
                  color:
                      dark
                          ? Colors.white.withValues(alpha: 0.5)
                          : const Color(0xFF9CA3AF),
                ),
              )
            else if (thumbnailBytes != null)
              Image.memory(thumbnailBytes!, fit: BoxFit.cover)
            else if (previewAssetPath != null && previewAssetPath!.isNotEmpty)
              Opacity(
                opacity: 0.5,
                child: Image.asset(previewAssetPath!, fit: BoxFit.cover),
              ),
            if (!isSystem)
              Positioned(
                right: metrics.durationInset,
                bottom: metrics.durationInset,
                child: Container(
                  height: metrics.durationHeight,
                  padding: EdgeInsets.symmetric(
                    horizontal: metrics.durationHorizontalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(metrics.durationRadius),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    durationLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontSize: metrics.durationFontSize,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.title,
    required this.subtitle,
    required this.thumbnail,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget thumbnail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ShellCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: SizedBox(
          height: 92,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                thumbnail,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.56),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.34),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellActivityMetrics {
  const _ShellActivityMetrics({
    required this.topPadding,
    required this.bottomPadding,
    required this.headerInset,
    required this.railInset,
    required this.titleSize,
    required this.titleLetterSpacing,
    required this.subtitleSize,
    required this.subtitleTopGap,
    required this.headerBlockGap,
    required this.largeChipTrackHeight,
    required this.compactChipTrackHeight,
    required this.largeChipHeight,
    required this.compactChipHeight,
    required this.largeChipHorizontalPadding,
    required this.compactChipHorizontalPadding,
    required this.largeChipFontSize,
    required this.compactChipFontSize,
    required this.largeChipLetterSpacing,
    required this.compactChipLetterSpacing,
    required this.chipGap,
    required this.filterRowsGap,
    required this.filterToListGap,
    required this.sectionTopInset,
    required this.sectionBottomInset,
    required this.sectionLabelSize,
    required this.sectionLabelLetterSpacing,
    required this.cardGap,
    required this.cardHeight,
    required this.cardRadius,
    required this.cardHorizontalInset,
    required this.cardTitleSize,
    required this.cardSubtitleSize,
    required this.cardTextGap,
    required this.thumbGap,
    required this.thumbnailWidth,
    required this.thumbnailHeight,
    required this.thumbnailRadius,
    required this.systemIconSize,
    required this.chevronSize,
    required this.durationInset,
    required this.durationHeight,
    required this.durationHorizontalPadding,
    required this.durationRadius,
    required this.durationFontSize,
    required this.filterViewportWidth,
    required double scale,
  }) : _scale = scale;

  final double topPadding;
  final double bottomPadding;
  final double headerInset;
  final double railInset;
  final double titleSize;
  final double titleLetterSpacing;
  final double subtitleSize;
  final double subtitleTopGap;
  final double headerBlockGap;
  final double largeChipTrackHeight;
  final double compactChipTrackHeight;
  final double largeChipHeight;
  final double compactChipHeight;
  final double largeChipHorizontalPadding;
  final double compactChipHorizontalPadding;
  final double largeChipFontSize;
  final double compactChipFontSize;
  final double largeChipLetterSpacing;
  final double compactChipLetterSpacing;
  final double chipGap;
  final double filterRowsGap;
  final double filterToListGap;
  final double sectionTopInset;
  final double sectionBottomInset;
  final double sectionLabelSize;
  final double sectionLabelLetterSpacing;
  final double cardGap;
  final double cardHeight;
  final double cardRadius;
  final double cardHorizontalInset;
  final double cardTitleSize;
  final double cardSubtitleSize;
  final double cardTextGap;
  final double thumbGap;
  final double thumbnailWidth;
  final double thumbnailHeight;
  final double thumbnailRadius;
  final double systemIconSize;
  final double chevronSize;
  final double durationInset;
  final double durationHeight;
  final double durationHorizontalPadding;
  final double durationRadius;
  final double durationFontSize;
  final double filterViewportWidth;

  double? largeChipWidth(String label) {
    const widths = <String, double>{
      'ALL': 45.9,
      'PEOPLE': 67.23,
      'MOTION': 69.97,
      'SYSTEM': 70.52,
    };
    final designWidth = widths[label];
    return designWidth == null ? null : designWidth * _scale;
  }

  double? compactChipWidth(String label) {
    const widths = <String, double>{
      'ALL CAMERAS': 90.31,
      'FRONT DOOR': 85.74,
      'BACKYARD': 74.65,
      'LIVING ROOM': 87.11,
    };
    final designWidth = widths[label];
    return designWidth == null ? null : designWidth * _scale;
  }

  final double _scale;

  factory _ShellActivityMetrics.forWidth(double width) {
    final scale = width / 290;
    double scaled(double designValue) => designValue * scale;

    return _ShellActivityMetrics(
      topPadding: scaled(12),
      bottomPadding: scaled(20),
      headerInset: scaled(20),
      railInset: scaled(16),
      titleSize: scaled(22),
      titleLetterSpacing: scaled(0.55),
      subtitleSize: scaled(11),
      subtitleTopGap: scaled(7),
      headerBlockGap: scaled(14),
      largeChipTrackHeight: scaled(33),
      compactChipTrackHeight: scaled(27.5),
      largeChipHeight: scaled(29),
      compactChipHeight: scaled(23.5),
      largeChipHorizontalPadding: scaled(13),
      compactChipHorizontalPadding: scaled(11),
      largeChipFontSize: scaled(10),
      compactChipFontSize: scaled(9),
      largeChipLetterSpacing: scaled(0.5),
      compactChipLetterSpacing: scaled(0.45),
      chipGap: scaled(8),
      filterRowsGap: scaled(8),
      filterToListGap: scaled(11),
      sectionTopInset: scaled(8),
      sectionBottomInset: scaled(13.5),
      sectionLabelSize: scaled(9),
      sectionLabelLetterSpacing: scaled(0.9),
      cardGap: scaled(8),
      cardHeight: scaled(70),
      cardRadius: scaled(12),
      cardHorizontalInset: scaled(12),
      cardTitleSize: scaled(12),
      cardSubtitleSize: scaled(10),
      cardTextGap: scaled(2),
      thumbGap: scaled(12),
      thumbnailWidth: scaled(64),
      thumbnailHeight: scaled(44),
      thumbnailRadius: scaled(8),
      systemIconSize: scaled(20),
      chevronSize: scaled(14),
      durationInset: scaled(2),
      durationHeight: scaled(10.5),
      durationHorizontalPadding: scaled(4),
      durationRadius: scaled(4),
      durationFontSize: scaled(7),
      filterViewportWidth: scaled(258),
      scale: scale,
    );
  }
}

class _ActivitySkeletonCard extends StatelessWidget {
  const _ActivitySkeletonCard({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final blockColor =
        dark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF6F6FA);
    return ShellCard(
      padding: const EdgeInsets.all(14),
      child: SizedBox(
        height: 74,
        child: Row(
          children: [
            Container(
              width: 64,
              height: 50,
              decoration: BoxDecoration(
                color: blockColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.14),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 10,
                    width: 110,
                    decoration: BoxDecoration(
                      color: blockColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 9,
                    width: 86,
                    decoration: BoxDecoration(
                      color: blockColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.14),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellEmptyActivityPlaceholderCard extends StatelessWidget {
  const _ShellEmptyActivityPlaceholderCard({
    required this.metrics,
    required this.dark,
    required this.opacity,
    required this.iconBuilder,
    required this.titleWidth,
    required this.subtitleWidth,
    required this.metaWidth,
    this.leftAccentColor,
  });

  final _ShellEmptyActivityMetrics metrics;
  final bool dark;
  final double opacity;
  final Widget Function(double size, Color color) iconBuilder;
  final double titleWidth;
  final double subtitleWidth;
  final double metaWidth;
  final Color? leftAccentColor;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: CustomPaint(
        foregroundPainter:
            leftAccentColor == null
                ? null
                : _ShellEmptyActivityAccentPainter(
                  color: leftAccentColor!,
                  strokeWidth: metrics.scaleValue(2),
                  radius: metrics.cardRadius,
                ),
        child: Container(
          height: metrics.cardHeight,
          decoration: BoxDecoration(
            color: dark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(metrics.cardRadius),
            border: Border.all(
              color:
                  dark
                      ? Colors.white.withValues(alpha: 0.05)
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
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.cardHorizontalInset,
            ),
            child: Row(
              children: [
                Container(
                  width: metrics.thumbWidth,
                  height: metrics.thumbHeight,
                  decoration: BoxDecoration(
                    color:
                        dark
                            ? Colors.white.withValues(alpha: 0.04)
                            : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(metrics.thumbRadius),
                  ),
                  alignment: Alignment.center,
                  child: iconBuilder(
                    metrics.thumbIconSize,
                    dark
                        ? Colors.white.withValues(alpha: 0.2)
                        : const Color(0xFFD1D5DB),
                  ),
                ),
                SizedBox(width: metrics.thumbGap),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _placeholderBar(
                        width: titleWidth,
                        height: metrics.titleBarHeight,
                        color:
                            dark
                                ? Colors.white.withValues(alpha: 0.08)
                                : const Color(0xFFE5E7EB),
                      ),
                      SizedBox(height: metrics.barGap),
                      _placeholderBar(
                        width: subtitleWidth,
                        height: metrics.subtitleBarHeight,
                        color:
                            dark
                                ? Colors.white.withValues(alpha: 0.04)
                                : const Color(0xFFF3F4F6),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: metrics.metaGap),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _placeholderBar(
                      width: metaWidth,
                      height: metrics.metaBarHeight,
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.06)
                              : const Color(0xFFE5E7EB),
                    ),
                    SizedBox(height: metrics.chevronTopGap),
                    _DesignChevronIcon(
                      size: metrics.chevronSize,
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.2)
                              : const Color(0xFFD1D5DB),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholderBar({
    required double width,
    required double height,
    required Color color,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _ShellEmptyActivityMetrics {
  const _ShellEmptyActivityMetrics({
    required this.topPadding,
    required this.bottomPadding,
    required this.headerInset,
    required this.titleSize,
    required this.titleLetterSpacing,
    required this.subtitleSize,
    required this.subtitleTopGap,
    required this.headerBlockGap,
    required this.cardInset,
    required this.cardGap,
    required this.cardHeight,
    required this.cardRadius,
    required this.leftAccentWidth,
    required this.cardHorizontalInset,
    required this.thumbWidth,
    required this.thumbHeight,
    required this.thumbRadius,
    required this.thumbIconSize,
    required this.thumbGap,
    required this.titleBarHeight,
    required this.subtitleBarHeight,
    required this.metaBarHeight,
    required this.barGap,
    required this.metaGap,
    required this.chevronTopGap,
    required this.chevronSize,
    required this.placeholderToIconGap,
    required this.emptyIconCircleSize,
    required this.emptyIconSize,
    required this.emptyIconToCopyGap,
    required this.emptyCopySize,
    required this.copyToButtonGap,
    required this.buttonWidth,
    required this.buttonHeight,
    required this.buttonRadius,
    required this.buttonHorizontalInset,
    required this.buttonIconSize,
    required this.buttonIconGap,
    required this.buttonTextSize,
    required this.buttonToFooterGap,
    required this.footerIconSize,
    required this.footerIconGap,
    required this.footerTextSize,
    required this.footerLetterSpacing,
    required this.scale,
  });

  final double topPadding;
  final double bottomPadding;
  final double headerInset;
  final double titleSize;
  final double titleLetterSpacing;
  final double subtitleSize;
  final double subtitleTopGap;
  final double headerBlockGap;
  final double cardInset;
  final double cardGap;
  final double cardHeight;
  final double cardRadius;
  final double leftAccentWidth;
  final double cardHorizontalInset;
  final double thumbWidth;
  final double thumbHeight;
  final double thumbRadius;
  final double thumbIconSize;
  final double thumbGap;
  final double titleBarHeight;
  final double subtitleBarHeight;
  final double metaBarHeight;
  final double barGap;
  final double metaGap;
  final double chevronTopGap;
  final double chevronSize;
  final double placeholderToIconGap;
  final double emptyIconCircleSize;
  final double emptyIconSize;
  final double emptyIconToCopyGap;
  final double emptyCopySize;
  final double copyToButtonGap;
  final double buttonWidth;
  final double buttonHeight;
  final double buttonRadius;
  final double buttonHorizontalInset;
  final double buttonIconSize;
  final double buttonIconGap;
  final double buttonTextSize;
  final double buttonToFooterGap;
  final double footerIconSize;
  final double footerIconGap;
  final double footerTextSize;
  final double footerLetterSpacing;
  final double scale;

  double scaleValue(double designValue) => designValue * scale;

  factory _ShellEmptyActivityMetrics.forWidth(double width) {
    final scale = width / 290;
    double scaled(double designValue) => designValue * scale;

    return _ShellEmptyActivityMetrics(
      topPadding: scaled(20),
      bottomPadding: scaled(18),
      headerInset: scaled(20),
      titleSize: scaled(22),
      titleLetterSpacing: scaled(0.55),
      subtitleSize: scaled(11),
      subtitleTopGap: scaled(7),
      headerBlockGap: scaled(10),
      cardInset: scaled(16),
      cardGap: scaled(10),
      cardHeight: scaled(66),
      cardRadius: scaled(12),
      leftAccentWidth: scaled(2),
      cardHorizontalInset: scaled(10),
      thumbWidth: scaled(56),
      thumbHeight: scaled(40),
      thumbRadius: scaled(8),
      thumbIconSize: scaled(14),
      thumbGap: scaled(12),
      titleBarHeight: scaled(10),
      subtitleBarHeight: scaled(8),
      metaBarHeight: scaled(8),
      barGap: scaled(8),
      metaGap: scaled(12),
      chevronTopGap: scaled(6),
      chevronSize: scaled(12),
      placeholderToIconGap: scaled(10),
      emptyIconCircleSize: scaled(40),
      emptyIconSize: scaled(18),
      emptyIconToCopyGap: scaled(14),
      emptyCopySize: scaled(12),
      copyToButtonGap: scaled(14),
      buttonWidth: scaled(168.79),
      buttonHeight: scaled(38.5),
      buttonRadius: scaled(12),
      buttonHorizontalInset: scaled(20),
      buttonIconSize: scaled(13),
      buttonIconGap: scaled(8),
      buttonTextSize: scaled(11),
      buttonToFooterGap: scaled(10),
      footerIconSize: scaled(10),
      footerIconGap: scaled(8),
      footerTextSize: scaled(9),
      footerLetterSpacing: scaled(0.225),
      scale: scale,
    );
  }
}

class _ShellEmptyActivityAccentPainter extends CustomPainter {
  const _ShellEmptyActivityAccentPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(strokeWidth / 2);

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(0, 0, radius * 0.68 + strokeWidth, size.height),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShellEmptyActivityAccentPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius;
  }
}

class _DesignPersonIcon extends StatelessWidget {
  const _DesignPersonIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DesignPersonIconPainter(color)),
    );
  }
}

class _DesignPulseIcon extends StatelessWidget {
  const _DesignPulseIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DesignPulseIconPainter(color)),
    );
  }
}

class _DesignCenterPulseIcon extends StatelessWidget {
  const _DesignCenterPulseIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DesignCenterPulseIconPainter(color)),
    );
  }
}

class _DesignShieldIcon extends StatelessWidget {
  const _DesignShieldIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DesignShieldIconPainter(color)),
    );
  }
}

class _DesignChevronIcon extends StatelessWidget {
  const _DesignChevronIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DesignChevronIconPainter(color)),
    );
  }
}

class _DesignFooterLockIcon extends StatelessWidget {
  const _DesignFooterLockIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DesignFooterLockIconPainter(color)),
    );
  }
}

class _DesignPersonIconPainter extends CustomPainter {
  const _DesignPersonIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.5 / 24)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * (7 / 24)),
      size.width * (4 / 24),
      stroke,
    );

    final shoulders =
        Path()
          ..moveTo(size.width * (4 / 24), size.height * (21 / 24))
          ..lineTo(size.width * (4 / 24), size.height * (19 / 24))
          ..cubicTo(
            size.width * (4 / 24),
            size.height * (16.7909 / 24),
            size.width * (5.7909 / 24),
            size.height * (15 / 24),
            size.width * (8 / 24),
            size.height * (15 / 24),
          )
          ..lineTo(size.width * (16 / 24), size.height * (15 / 24))
          ..cubicTo(
            size.width * (18.2091 / 24),
            size.height * (15 / 24),
            size.width * (20 / 24),
            size.height * (16.7909 / 24),
            size.width * (20 / 24),
            size.height * (19 / 24),
          )
          ..lineTo(size.width * (20 / 24), size.height * (21 / 24));
    canvas.drawPath(shoulders, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignPersonIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignPulseIconPainter extends CustomPainter {
  const _DesignPulseIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.5 / 24)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (22 / 24), size.height * (12 / 24))
          ..lineTo(size.width * (18 / 24), size.height * (12 / 24))
          ..lineTo(size.width * (15 / 24), size.height * (21 / 24))
          ..lineTo(size.width * (9 / 24), size.height * (3 / 24))
          ..lineTo(size.width * (6 / 24), size.height * (12 / 24))
          ..lineTo(size.width * (2 / 24), size.height * (12 / 24));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignPulseIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignCenterPulseIconPainter extends CustomPainter {
  const _DesignCenterPulseIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.125 / 18)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (16.5 / 18), size.height * (9 / 18))
          ..lineTo(size.width * (13.5 / 18), size.height * (9 / 18))
          ..lineTo(size.width * (11.25 / 18), size.height * (15.75 / 18))
          ..lineTo(size.width * (6.75 / 18), size.height * (2.25 / 18))
          ..lineTo(size.width * (4.5 / 18), size.height * (9 / 18))
          ..lineTo(size.width * (1.5 / 18), size.height * (9 / 18));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignCenterPulseIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignShieldIconPainter extends CustomPainter {
  const _DesignShieldIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.5 / 24)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (12 / 24), size.height * (22 / 24))
          ..cubicTo(
            size.width * (12 / 24),
            size.height * (22 / 24),
            size.width * (20 / 24),
            size.height * (18 / 24),
            size.width * (20 / 24),
            size.height * (12 / 24),
          )
          ..lineTo(size.width * (20 / 24), size.height * (5 / 24))
          ..lineTo(size.width * (12 / 24), size.height * (2 / 24))
          ..lineTo(size.width * (4 / 24), size.height * (5 / 24))
          ..lineTo(size.width * (4 / 24), size.height * (12 / 24))
          ..cubicTo(
            size.width * (4 / 24),
            size.height * (18 / 24),
            size.width * (12 / 24),
            size.height * (22 / 24),
            size.width * (12 / 24),
            size.height * (22 / 24),
          );
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignShieldIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignChevronIconPainter extends CustomPainter {
  const _DesignChevronIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (2 / 24)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (9 / 24), size.height * (18 / 24))
          ..lineTo(size.width * (15 / 24), size.height * (12 / 24))
          ..lineTo(size.width * (9 / 24), size.height * (6 / 24));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignChevronIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignFooterLockIconPainter extends CustomPainter {
  const _DesignFooterLockIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * (0.833333 / 10);
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
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
  bool shouldRepaint(covariant _DesignFooterLockIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
