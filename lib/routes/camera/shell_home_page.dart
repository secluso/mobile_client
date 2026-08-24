//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/routes/camera/new/qr_scan.dart';
import 'package:secluso_flutter/routes/camera/view_camera.dart';
import 'package:secluso_flutter/routes/camera/view_video.dart';
import 'package:secluso_flutter/routes/server_page.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';
import 'package:secluso_flutter/ui/secluso_shell_ui.dart';

part 'shell_home_empty_state.dart';
part 'shell_home_setup_state.dart';

const String _seclusoLogoArtPath = 'assets/design/secluso_logo.jpg';

class ShellHomeCamera {
  const ShellHomeCamera({
    required this.name,
    required this.previewAssetPath,
    this.thumbnailBytes,
    this.hasUnreadActivity = false,
    this.isLive = true,
    this.isOffline = false,
    this.statusLabel,
    this.recentActivityTitle,
    this.recentActivityTimeLabel,
    this.hasLock = true,
    this.previewVideos,
    this.previewDetectionsByVideo,
    this.previewThumbAssetsByVideo,
    this.previewVideoAssetsByVideo,
    this.previewDurationByVideo,
    this.previewHeroAssetPath,
    this.previewHeroVideoAssetPath,
    this.previewDownloadActive = false,
  });

  final String name;
  final String? previewAssetPath;
  final Uint8List? thumbnailBytes;
  final bool hasUnreadActivity;
  final bool isLive;
  final bool isOffline;
  final String? statusLabel;
  final String? recentActivityTitle;
  final String? recentActivityTimeLabel;
  final bool hasLock;
  final List<Video>? previewVideos;
  final Map<String, Set<String>>? previewDetectionsByVideo;
  final Map<String, String>? previewThumbAssetsByVideo;
  final Map<String, String>? previewVideoAssetsByVideo;
  final Map<String, Duration>? previewDurationByVideo;
  final String? previewHeroAssetPath;
  final String? previewHeroVideoAssetPath;
  final bool previewDownloadActive;
}

Future<void> _openHomeCamera(BuildContext context, ShellHomeCamera camera) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder:
          (_) => CameraViewPage(
            cameraName: camera.name,
            previewVideos: camera.previewVideos,
            previewDetectionsByVideo: camera.previewDetectionsByVideo,
            previewThumbAssetsByVideo: camera.previewThumbAssetsByVideo,
            previewVideoAssetsByVideo: camera.previewVideoAssetsByVideo,
            previewDurationByVideo: camera.previewDurationByVideo,
            previewHeroAssetPath: camera.previewHeroAssetPath,
            previewHeroVideoAssetPath: camera.previewHeroVideoAssetPath,
            previewDownloadActive: camera.previewDownloadActive,
          ),
    ),
  );
}

class ShellHomeEvent {
  const ShellHomeEvent({
    required this.title,
    required this.subtitle,
    required this.timeLabel,
    required this.previewAssetPath,
    this.previewVideoAssetPath,
    this.thumbnailBytes,
    required this.accentColor,
    this.videoName,
    this.detections = const <String>{},
    this.motion = true,
    this.canDownload = false,
    this.hasVideoFile = true,
  });

  final String title;
  final String subtitle;
  final String timeLabel;
  final String? previewAssetPath;
  final String? previewVideoAssetPath;
  final Uint8List? thumbnailBytes;
  final Color accentColor;
  final String? videoName;
  final Set<String> detections;
  final bool motion;
  final bool canDownload;
  final bool hasVideoFile;
}

class ShellHomePage extends StatelessWidget {
  const ShellHomePage({
    super.key,
    required this.relayConnected,
    required this.cameras,
    this.recentEvents,
    this.unreadCount = 0,
    this.showErrorCard = false,
    this.showOfflineExample = false,
    this.onOpenRelaySetup,
  });

  final bool relayConnected;
  final List<ShellHomeCamera> cameras;
  final List<ShellHomeEvent>? recentEvents;
  final int unreadCount;
  final bool showErrorCard;
  final bool showOfflineExample;
  final Future<void> Function()? onOpenRelaySetup;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        relayConnected
            ? (dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7))
            : (dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7));
    Future<void> openQrPage() {
      final openRelaySetup = onOpenRelaySetup;
      if (openRelaySetup != null) {
        return openRelaySetup();
      }
      return GenericCameraQrScanPage.show(context);
    }

    final body =
        relayConnected
            ? LayoutBuilder(
              builder: (context, constraints) {
                final metrics = _ShellHomeMetrics.forWidth(
                  constraints.maxWidth,
                );
                final dark = Theme.of(context).brightness == Brightness.dark;
                return Container(
                  color:
                      dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7),
                  child: ListView(
                    padding: EdgeInsets.only(bottom: metrics.bottomPadding),
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          metrics.pageInset,
                          metrics.topPadding,
                          metrics.pageInset,
                          0,
                        ),
                        child: _buildConnectedContent(context, metrics),
                      ),
                    ],
                  ),
                );
              },
            )
            : Container(
              color: dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final metrics = _ShellSetupMetrics.forViewport(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return ListView(
                    padding: EdgeInsets.only(bottom: metrics.bottomPadding),
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          metrics.pageInset,
                          metrics.topPadding,
                          metrics.pageInset,
                          0,
                        ),
                        child: _buildSetupContent(context, openQrPage, metrics),
                      ),
                    ],
                  );
                },
              ),
            );

    return ColoredBox(
      color: backgroundColor,
      child: SafeArea(top: true, bottom: false, child: body),
    );
  }

  Widget _buildSetupContent(
    BuildContext context,
    VoidCallback openQrPage,
    _ShellSetupMetrics metrics,
  ) {
    final palette = _ShellSetupPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final securityAccent =
        dark ? const Color(0xFF28D08B) : const Color(0xFF118E5E);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderRow(
          showAdd: false,
          onAdd: openQrPage,
          titleSize: metrics.titleSize,
          titleLetterSpacing: metrics.titleLetterSpacing,
          titleColor: palette.headerTitleColor,
        ),
        SizedBox(height: metrics.headerToEyebrowGap),
        Text(
          "LET'S GET YOU SET UP",
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: palette.eyebrowColor,
            fontSize: metrics.eyebrowSize,
            fontWeight: FontWeight.w400,
            letterSpacing: metrics.eyebrowLetterSpacing,
          ),
        ),
        SizedBox(height: metrics.subtitleToRelayCardGap),
        _RelaySetupCard(onScan: openQrPage, metrics: metrics, palette: palette),
        SizedBox(height: metrics.relayCardToFlowCardGap),
        _RelayFlowCard(metrics: metrics, palette: palette),
        SizedBox(height: metrics.linksToMetaGap),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _HomeLockIcon(
              size: metrics.footerMetaIconSize,
              color: securityAccent,
            ),
            SizedBox(width: metrics.footerMetaGap),
            Text(
              'End-to-end encrypted',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: securityAccent,
                fontSize: metrics.footerMetaSize,
                fontWeight: FontWeight.w600,
                letterSpacing: metrics.footerMetaLetterSpacing,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConnectedContent(
    BuildContext context,
    _ShellHomeMetrics metrics,
  ) {
    final recentEvents =
        this.recentEvents
            ?.map(
              (event) => _ShellRecentEvent(
                title: event.title,
                subtitle: event.subtitle,
                timeLabel: event.timeLabel,
                previewAssetPath: event.previewAssetPath,
                previewVideoAssetPath: event.previewVideoAssetPath,
                thumbnailBytes: event.thumbnailBytes,
                accentColor: event.accentColor,
                videoName: event.videoName,
                detections: event.detections,
                motion: event.motion,
                canDownload: event.canDownload,
                hasVideoFile: event.hasVideoFile,
              ),
            )
            .toList() ??
        _recentEvents();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final relayStatusLabel =
        cameras.isEmpty
            ? 'RELAY CONNECTED'
            : 'RELAY CONNECTED · ${cameras.length} ${cameras.length == 1 ? 'CAMERA' : 'CAMERAS'}';
    final singleAwaitingFirstEvent =
        cameras.length == 1 &&
        recentEvents.isEmpty &&
        cameras.first.thumbnailBytes == null &&
        ((cameras.first.previewAssetPath ?? '').isEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: metrics.headerInsetDelta),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderRow(
                showAdd: true,
                metrics: metrics,
                onAdd: () {
                  GenericCameraQrScanPage.show(context);
                },
              ),
              SizedBox(height: metrics.headerToStatusGap),
              Row(
                children: [
                  SizedBox(
                    width: metrics.statusDotSize,
                    height: metrics.statusDotSize,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  SizedBox(width: metrics.statusDotGap),
                  Expanded(
                    child: Text(
                      relayStatusLabel,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color:
                            dark
                                ? Colors.white.withValues(alpha: 0.4)
                                : const Color(0xFF6B7280),
                        fontSize: metrics.statusLabelSize,
                        fontWeight: FontWeight.w400,
                        letterSpacing: metrics.statusLetterSpacing,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: metrics.statusToChipGap),
              Row(
                children: [
                  _HomeFilterChip(
                    label: 'E2EE',
                    icon: Icons.lock_outline,
                    metrics: metrics,
                    width: metrics.topChipWidth('E2EE'),
                  ),
                  const Spacer(),
                  if (unreadCount > 0)
                    _HomeFilterChip(
                      label: '$unreadCount NEW EVENTS',
                      accentColor: const Color(0xFF8BB3EE),
                      dotColor: const Color(0xFFF59E0B),
                      metrics: metrics,
                      width:
                          unreadCount == 2
                              ? metrics.topChipWidth('2 NEW EVENTS')
                              : null,
                    ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: metrics.headerToCardsGap),
        if (showErrorCard) ...[
          _ErrorCard(metrics: metrics),
          SizedBox(height: metrics.errorCardGap),
        ],
        if (cameras.isEmpty) ...[
          _NoCameraCard(
            metrics: metrics,
            onAdd: () => GenericCameraQrScanPage.show(context),
          ),
        ] else if (singleAwaitingFirstEvent) ...[
          _FirstCameraAwaitingEventState(
            camera: cameras.first,
            metrics: metrics,
          ),
        ] else ...[
          _FeaturedCameraCard(camera: cameras.first, metrics: metrics),
          if (cameras.length > 1) ...[
            SizedBox(height: metrics.gridGap),
            _SecondaryCameraGrid(
              cameras: cameras.skip(1).toList(),
              showOfflineExample: showOfflineExample,
              metrics: metrics,
            ),
          ],
          SizedBox(height: metrics.sectionGap),
          Row(
            children: [
              Text(
                'RECENT ACTIVITY',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color:
                      dark
                          ? Colors.white.withValues(alpha: 0.2)
                          : const Color(0xFF9CA3AF),
                  fontSize: metrics.sectionLabelSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: metrics.sectionLetterSpacing,
                ),
              ),
              const Spacer(),
              if (recentEvents.isNotEmpty)
                Text(
                  '${recentEvents.length} events · View All →',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF8BB3EE),
                    fontSize: metrics.sectionLinkSize,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
            ],
          ),
          SizedBox(height: metrics.sectionToEventsGap),
          if (recentEvents.isNotEmpty) ...[
            for (var i = 0; i < recentEvents.length; i++) ...[
              _RecentEventCard(event: recentEvents[i], metrics: metrics),
              if (i != recentEvents.length - 1)
                SizedBox(height: metrics.eventGap),
            ],
          ] else
            _EmptyRecentActivityCard(metrics: metrics),
        ],
      ],
    );
  }

  List<_ShellRecentEvent> _recentEvents() {
    final items = <_ShellRecentEvent>[];
    for (final camera in cameras) {
      final hasPreviewEvent =
          camera.recentActivityTitle != null &&
          camera.recentActivityTimeLabel != null;
      if (!hasPreviewEvent && !camera.hasUnreadActivity) {
        continue;
      }
      items.add(
        _ShellRecentEvent(
          title: camera.recentActivityTitle ?? _fallbackActivityTitle(camera),
          subtitle: camera.name,
          timeLabel:
              camera.recentActivityTimeLabel ??
              (camera.statusLabel?.contains('14m') == true
                  ? '14m ago'
                  : '2m ago'),
          previewAssetPath: camera.previewAssetPath,
          thumbnailBytes: camera.thumbnailBytes,
          accentColor:
              (camera.recentActivityTitle ?? '').toLowerCase().contains(
                    'motion',
                  )
                  ? const Color(0xFF60A5FA)
                  : const Color(0xFF8BB3EE),
          detections:
              (camera.recentActivityTitle ?? '').toLowerCase().contains(
                    'motion',
                  )
                  ? const <String>{}
                  : const <String>{'human'},
          hasVideoFile: true,
        ),
      );
      if (items.length == 2) {
        break;
      }
    }
    return items;
  }

  String _fallbackActivityTitle(ShellHomeCamera camera) {
    final status = (camera.statusLabel ?? '').toLowerCase();
    if (status.contains('motion')) {
      return 'Motion';
    }
    if (status.contains('person')) {
      return 'Person Detected';
    }
    return 'Camera Activity';
  }
}

class _FirstCameraAwaitingEventState extends StatelessWidget {
  const _FirstCameraAwaitingEventState({
    required this.camera,
    required this.metrics,
  });

  final ShellHomeCamera camera;
  final _ShellHomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final availableWidth =
        MediaQuery.sizeOf(context).width -
        (metrics.pageInset * 2) -
        (metrics.headerInsetDelta * 2);
    final contentWidth = availableWidth;

    return Center(
      child: SizedBox(
        width: contentWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FirstCameraAwaitingEventCard(camera: camera, metrics: metrics),
            SizedBox(height: metrics.scaled(22)),
            Text(
              'RECENT ACTIVITY',
              style: GoogleFonts.inter(
                color:
                    isDark
                        ? Colors.white.withValues(alpha: 0.28)
                        : const Color(0xFF9CA3AF),
                fontSize: metrics.scaled(10),
                fontWeight: FontWeight.w500,
                letterSpacing: metrics.scaled(2.0),
              ),
            ),
            SizedBox(height: metrics.scaled(16)),
            _AwaitingRecentActivitySkeletonCard(
              metrics: metrics,
              delay: 0,
              titleWidth: 112,
              subtitleWidth: 64,
            ),
            SizedBox(height: metrics.scaled(12)),
            _AwaitingRecentActivitySkeletonCard(
              metrics: metrics,
              delay: 1,
              titleWidth: 128,
              subtitleWidth: 80,
            ),
            SizedBox(height: metrics.scaled(16)),
            Text(
              'All quiet — no events yet',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color:
                    isDark
                        ? Colors.white.withValues(alpha: 0.22)
                        : const Color(0xFF6B7280).withValues(alpha: 0.72),
                fontSize: metrics.scaled(11),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FirstCameraAwaitingEventCard extends StatelessWidget {
  const _FirstCameraAwaitingEventCard({
    required this.camera,
    required this.metrics,
  });

  final ShellHomeCamera camera;
  final _ShellHomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final radius = metrics.scaled(16);
    final hasPreviewAsset =
        camera.previewAssetPath != null && camera.previewAssetPath!.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: () => _openHomeCamera(context, camera),
        child: AspectRatio(
          aspectRatio: 258 / 145.13,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF050505),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: metrics.scaled(15),
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF0F172A),
                                Color(0xFF0C1220),
                                Color(0xFF0F172A),
                              ],
                            ),
                          ),
                        ),
                        Opacity(
                          opacity: 0.12,
                          child: Image.asset(
                            _seclusoLogoArtPath,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasPreviewAsset)
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.08,
                        child: Image.asset(
                          camera.previewAssetPath!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _CameraSweepShimmer(
                        borderRadius: BorderRadius.circular(radius),
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
                            Colors.black.withValues(alpha: 0.18),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.58),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: metrics.scaled(12),
                    top: metrics.scaled(12),
                    child: _AwaitingLivePill(metrics: metrics),
                  ),
                  if (camera.hasLock)
                    Positioned(
                      top: metrics.scaled(12),
                      right: metrics.scaled(12),
                      child: _HomeLockIcon(
                        size: metrics.scaled(16),
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  Positioned(
                    left: metrics.scaled(14),
                    right: metrics.scaled(14),
                    bottom: metrics.scaled(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          camera.name,
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.96),
                            fontSize: metrics.scaled(14),
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            letterSpacing: metrics.scaled(0.35),
                          ),
                        ),
                        SizedBox(height: metrics.scaled(12)),
                        _AwaitingStatusPill(
                          metrics: metrics,
                          label: camera.isOffline ? 'Offline' : 'Quiet',
                          activeColor:
                              camera.isOffline
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF22C55E),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AwaitingLivePill extends StatelessWidget {
  const _AwaitingLivePill({required this.metrics});

  final _ShellHomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.scaled(10),
        vertical: metrics.scaled(6),
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(metrics.scaled(999)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: metrics.scaled(8),
            height: metrics.scaled(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.75),
                  blurRadius: metrics.scaled(6),
                ),
              ],
            ),
          ),
          SizedBox(width: metrics.scaled(7)),
          Text(
            'LIVE',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.94),
              fontSize: metrics.scaled(10),
              fontWeight: FontWeight.w700,
              letterSpacing: metrics.scaled(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _AwaitingStatusPill extends StatelessWidget {
  const _AwaitingStatusPill({
    required this.metrics,
    required this.label,
    required this.activeColor,
  });

  final _ShellHomeMetrics metrics;
  final String label;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.scaled(12),
        vertical: metrics.scaled(6),
      ),
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(metrics.scaled(999)),
        border: Border.all(color: activeColor.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: metrics.scaled(7),
            height: metrics.scaled(7),
            decoration: BoxDecoration(
              color: activeColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: metrics.scaled(8)),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              color: activeColor.withValues(alpha: 0.95),
              fontSize: metrics.scaled(8),
              fontWeight: FontWeight.w700,
              letterSpacing: metrics.scaled(1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _AwaitingRecentActivitySkeletonCard extends StatelessWidget {
  const _AwaitingRecentActivitySkeletonCard({
    required this.metrics,
    required this.delay,
    required this.titleWidth,
    required this.subtitleWidth,
  });

  final _ShellHomeMetrics metrics;
  final int delay;
  final double titleWidth;
  final double subtitleWidth;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _GhostBreathing(
      delay: Duration(milliseconds: delay * 800),
      child: Container(
        height: metrics.scaled(62),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF0B0B0C) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(metrics.scaled(12)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(metrics.scaled(12)),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _DashedRoundedRectPainter(
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.1)
                              : const Color(0xFFD1D5DB),
                      radius: metrics.scaled(12),
                      strokeWidth: 1,
                      dashLength: metrics.scaled(5.5),
                      gapLength: metrics.scaled(4.5),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: _GhostSweepShimmer(
                    borderRadius: BorderRadius.circular(metrics.scaled(12)),
                    delay: Duration(milliseconds: delay * 1200),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.scaled(14),
                  vertical: metrics.scaled(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: metrics.scaled(32),
                      height: metrics.scaled(32),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: metrics.scaled(14)),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: metrics.scaled(titleWidth),
                            child: Container(
                              height: metrics.scaled(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(
                                  metrics.scaled(999),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: metrics.scaled(10)),
                          SizedBox(
                            width: metrics.scaled(subtitleWidth),
                            child: Container(
                              height: metrics.scaled(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(
                                  metrics.scaled(999),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostBreathing extends StatefulWidget {
  const _GhostBreathing({required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<_GhostBreathing> createState() => _GhostBreathingState();
}

class _GhostBreathingState extends State<_GhostBreathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _start();
  }

  Future<void> _start() async {
    if (widget.delay > Duration.zero) {
      await Future<void>.delayed(widget.delay);
      if (!mounted) return;
    }
    setState(() {
      _started = true;
    });
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_started && widget.delay > Duration.zero) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity =
            lerpDouble(
              0.4,
              0.7,
              Curves.easeInOut.transform(_controller.value),
            )!;
        return Opacity(opacity: opacity, child: widget.child);
      },
    );
  }
}

class _GhostSweepShimmer extends StatefulWidget {
  const _GhostSweepShimmer({
    required this.borderRadius,
    this.delay = Duration.zero,
  });

  final BorderRadius borderRadius;
  final Duration delay;

  @override
  State<_GhostSweepShimmer> createState() => _GhostSweepShimmerState();
}

class _GhostSweepShimmerState extends State<_GhostSweepShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    _start();
  }

  Future<void> _start() async {
    if (widget.delay > Duration.zero) {
      await Future<void>.delayed(widget.delay);
      if (!mounted) return;
    }
    setState(() {
      _started = true;
    });
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_started && widget.delay > Duration.zero) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final leftFactor = t <= 0.4 ? lerpDouble(-2.0, 2.0, t / 0.4)! : 2.0;
        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionalTranslation(
              translation: Offset(leftFactor, 0),
              child: Transform(
                transform: Matrix4.skewX(-20 * math.pi / 180),
                alignment: Alignment.center,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.015),
                        Colors.white.withValues(alpha: 0.06),
                        Colors.white.withValues(alpha: 0.015),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CameraSweepShimmer extends StatefulWidget {
  const _CameraSweepShimmer({required this.borderRadius});

  final BorderRadius borderRadius;

  @override
  State<_CameraSweepShimmer> createState() => _CameraSweepShimmerState();
}

class _CameraSweepShimmerState extends State<_CameraSweepShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 10000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final leftFactor = t <= 0.3 ? lerpDouble(-1.5, 1.5, t / 0.3)! : 1.5;
        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.8,
              child: FractionalTranslation(
                translation: Offset(leftFactor, 0),
                child: Transform(
                  transform: Matrix4.skewX(-15 * math.pi / 180),
                  alignment: Alignment.center,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          Colors.white.withValues(alpha: 0.01),
                          Colors.white.withValues(alpha: 0.06),
                          Colors.white.withValues(alpha: 0.01),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.showAdd,
    required this.onAdd,
    this.metrics,
    this.titleSize,
    this.titleLetterSpacing,
    this.titleColor,
  });

  final bool showAdd;
  final VoidCallback onAdd;
  final _ShellHomeMetrics? metrics;
  final double? titleSize;
  final double? titleLetterSpacing;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final effectiveMetrics = metrics ?? _ShellHomeMetrics.design;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Secluso',
            style: shellTitleStyle(
              context,
              fontSize: titleSize ?? effectiveMetrics.titleSize,
              designLetterSpacing:
                  titleLetterSpacing ?? effectiveMetrics.titleLetterSpacing,
              color: titleColor,
            ),
          ),
        ),
        if (showAdd)
          Material(
            color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                effectiveMetrics.addButtonRadius,
              ),
              side: BorderSide(
                color:
                    dark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFE5E7EB),
              ),
            ),
            elevation: dark ? 0 : 1,
            shadowColor: Colors.black.withValues(alpha: dark ? 0 : 0.05),
            child: InkWell(
              onTap: onAdd,
              customBorder: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  effectiveMetrics.addButtonRadius,
                ),
              ),
              child: SizedBox(
                width: effectiveMetrics.addButtonSize,
                height: effectiveMetrics.addButtonSize,
                child: Center(
                  child: _HomeAddIcon(
                    size: effectiveMetrics.addIconSize,
                    color:
                        dark
                            ? Theme.of(context).colorScheme.onSurface
                            : const Color(0xFF4B5563),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HomeFilterChip extends StatelessWidget {
  const _HomeFilterChip({
    required this.label,
    this.icon,
    this.accentColor,
    this.dotColor,
    required this.metrics,
    this.width,
  });

  final String label;
  final IconData? icon;
  final Color? accentColor;
  final Color? dotColor;
  final _ShellHomeMetrics metrics;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        accentColor ??
        (dark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF4B5563));
    final chip = Container(
      height: metrics.chipHeight,
      padding: EdgeInsets.symmetric(horizontal: metrics.chipHorizontalPadding),
      decoration: BoxDecoration(
        color:
            accentColor == null
                ? (dark ? Colors.white.withValues(alpha: 0.05) : Colors.white)
                : accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color:
              accentColor == null
                  ? (dark
                      ? Colors.white.withValues(alpha: 0.1)
                      : const Color(0xFFE5E7EB))
                  : accent.withValues(alpha: dark ? 0.2 : 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            _HomeLockIcon(
              size: metrics.chipIconSize,
              color:
                  dark
                      ? Colors.white.withValues(alpha: 0.78)
                      : const Color(0xFF4B5563),
            ),
            SizedBox(width: metrics.chipInnerGap),
          ] else if (dotColor != null) ...[
            Container(
              width: metrics.chipDotSize,
              height: metrics.chipDotSize,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: metrics.chipInnerGap),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: accent,
              fontSize: metrics.chipTextSize,
              fontWeight: FontWeight.w600,
              letterSpacing: metrics.chipLetterSpacing,
            ),
          ),
        ],
      ),
    );
    if (width == null) {
      return chip;
    }
    return SizedBox(width: width, child: chip);
  }
}

class _FeaturedCameraCard extends StatelessWidget {
  const _FeaturedCameraCard({required this.camera, required this.metrics});

  final ShellHomeCamera camera;
  final _ShellHomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final hasVisual =
        camera.thumbnailBytes != null ||
        (camera.previewAssetPath != null &&
            camera.previewAssetPath!.isNotEmpty);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(metrics.cameraCardRadius),
        onTap: () => _openHomeCamera(context, camera),
        child: AspectRatio(
          aspectRatio: 2,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A),
              borderRadius: BorderRadius.circular(metrics.cameraCardRadius),
              border: Border.all(
                color:
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0x00000000),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(metrics.cameraCardRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasVisual) ...[
                    if (camera.thumbnailBytes != null)
                      Image.memory(camera.thumbnailBytes!, fit: BoxFit.cover),
                    if (camera.previewAssetPath != null &&
                        camera.previewAssetPath!.isNotEmpty)
                      Image.asset(camera.previewAssetPath!, fit: BoxFit.cover),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.1),
                            Colors.black.withValues(alpha: 0.02),
                            Colors.black.withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        metrics.cameraCardInsetStart,
                        metrics.cameraCardInsetTop,
                        metrics.cameraCardInsetEnd,
                        metrics.cameraCardInsetBottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (camera.hasLock)
                                _HomeLockIcon(
                                  size: metrics.cameraLockSize,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              const Spacer(),
                              _LivePill(
                                isOffline: camera.isOffline,
                                metrics: metrics,
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            camera.name,
                            style: Theme.of(
                              context,
                            ).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontSize: metrics.featuredTitleSize,
                              fontWeight: FontWeight.w600,
                              letterSpacing:
                                  -metrics.featuredTitleLetterSpacing,
                            ),
                          ),
                          SizedBox(height: metrics.cameraTitleToStatusGap),
                          _StatusPill(
                            label:
                                camera.statusLabel ??
                                (camera.hasUnreadActivity
                                    ? 'Person · 2m'
                                    : 'Quiet'),
                            metrics: metrics,
                          ),
                        ],
                      ),
                    ),
                  ] else
                    _CameraNoImagePlaceholder(
                      camera: camera,
                      metrics: metrics,
                      featured: true,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryCameraGrid extends StatelessWidget {
  const _SecondaryCameraGrid({
    required this.cameras,
    required this.showOfflineExample,
    required this.metrics,
  });

  final List<ShellHomeCamera> cameras;
  final bool showOfflineExample;
  final _ShellHomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final tiles = [...cameras];
    if (tiles.length.isOdd) {
      tiles.add(const ShellHomeCamera(name: '__add__', previewAssetPath: ''));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - metrics.gridGap) / 2;
        return Wrap(
          spacing: metrics.gridGap,
          runSpacing: metrics.gridGap,
          children: [
            for (var i = 0; i < tiles.length; i++)
              SizedBox(
                width: tileWidth,
                child:
                    tiles[i].name == '__add__'
                        ? _AddCameraTile(metrics: metrics)
                        : _SmallCameraTile(
                          metrics: metrics,
                          camera:
                              i == 0 && showOfflineExample
                                  ? ShellHomeCamera(
                                    name: tiles[i].name,
                                    previewAssetPath: tiles[i].previewAssetPath,
                                    thumbnailBytes: tiles[i].thumbnailBytes,
                                    isLive: false,
                                    isOffline: true,
                                    statusLabel: 'Offline',
                                  )
                                  : tiles[i],
                        ),
              ),
          ],
        );
      },
    );
  }
}

class _SmallCameraTile extends StatelessWidget {
  const _SmallCameraTile({required this.camera, required this.metrics});

  final ShellHomeCamera camera;
  final _ShellHomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final hasVisual =
        camera.thumbnailBytes != null ||
        (camera.previewAssetPath != null &&
            camera.previewAssetPath!.isNotEmpty);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(metrics.cameraCardRadius),
        border: Border.all(
          color:
              camera.isOffline
                  ? const Color(0x66E15C5C)
                  : (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0x00000000)),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(metrics.cameraCardRadius),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasVisual) ...[
                if (camera.thumbnailBytes != null)
                  Image.memory(camera.thumbnailBytes!, fit: BoxFit.cover),
                if (camera.previewAssetPath != null &&
                    camera.previewAssetPath!.isNotEmpty)
                  Image.asset(camera.previewAssetPath!, fit: BoxFit.cover),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.1),
                        Colors.black.withValues(alpha: 0.04),
                        Colors.black.withValues(alpha: 0.82),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    metrics.cameraCardInsetStart,
                    metrics.cameraCardInsetTop,
                    metrics.cameraCardInsetStart,
                    metrics.cameraCardInsetBottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (camera.hasLock)
                            _HomeLockIcon(
                              size: metrics.cameraLockSize,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          const Spacer(),
                          _LivePill(
                            isOffline: camera.isOffline,
                            metrics: metrics,
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        camera.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontSize: metrics.smallTitleSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: metrics.cameraTitleToStatusGap),
                      _StatusPill(
                        label:
                            camera.statusLabel ??
                            (camera.isOffline
                                ? 'Offline'
                                : (camera.hasUnreadActivity
                                    ? 'Motion · 2m'
                                    : 'Quiet')),
                        metrics: metrics,
                      ),
                    ],
                  ),
                ),
              ] else
                _CameraNoImagePlaceholder(
                  camera: camera,
                  metrics: metrics,
                  featured: false,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddCameraTile extends StatelessWidget {
  const _AddCameraTile({required this.metrics});

  final _ShellHomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = metrics.addTileRadius;
    return CustomPaint(
      painter: _DashedRoundedRectPainter(
        color:
            dark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFD1D5DB),
        strokeWidth: metrics.scaled(dark ? 1.5 : 2),
        radius: radius,
        dashLength: metrics.scaled(6),
        gapLength: metrics.scaled(4),
      ),
      child: Material(
        color:
            dark
                ? Colors.white.withValues(alpha: 0.02)
                : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: () => GenericCameraQrScanPage.show(context),
          child: AspectRatio(
            aspectRatio: metrics.addTileAspectRatio,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: metrics.addTileIconWrapSize,
                    height: metrics.addTileIconWrapSize,
                    decoration: BoxDecoration(
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.04)
                              : const Color(0xFFF3F4F6),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: _HomeAddIcon(
                        size: metrics.addTileIconSize,
                        color:
                            dark
                                ? Colors.white.withValues(alpha: 0.7)
                                : const Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                  SizedBox(height: metrics.addTileGap),
                  Text(
                    'Add Camera',
                    style: GoogleFonts.inter(
                      fontSize: metrics.addTileTextSize,
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.3)
                              : const Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w500,
                      fontStyle: FontStyle.normal,
                      height: 15 / 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraNoImagePlaceholder extends StatelessWidget {
  const _CameraNoImagePlaceholder({
    required this.camera,
    required this.metrics,
    required this.featured,
  });

  final ShellHomeCamera camera;
  final _ShellHomeMetrics metrics;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final nameStyle =
        featured
            ? Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontSize: metrics.featuredTitleSize,
              fontWeight: FontWeight.w600,
              letterSpacing: -metrics.featuredTitleLetterSpacing,
            )
            : Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontSize: metrics.smallTitleSize,
              fontWeight: FontWeight.w500,
            );

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF0C0C0C)),
        _AnimatedCameraPlaceholderArt(
          featured: featured,
          scale: metrics.scaled(1),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.02),
                Colors.black.withValues(alpha: 0.02),
                Colors.black.withValues(alpha: 0.7),
              ],
              stops: const [0, 0.52, 1],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            metrics.cameraCardInsetStart,
            metrics.cameraCardInsetTop,
            metrics.cameraCardInsetEnd,
            metrics.cameraCardInsetBottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (camera.hasLock)
                    _HomeLockIcon(
                      size: metrics.cameraLockSize,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  const Spacer(),
                  if (camera.hasUnreadActivity) _HomeNewPill(metrics: metrics),
                ],
              ),
              const Spacer(),
              Text(camera.name, style: nameStyle),
              SizedBox(height: metrics.scaled(featured ? 3 : 3.5)),
              Row(
                children: [
                  _AnimatedQuietDot(size: metrics.scaled(4)),
                  SizedBox(width: metrics.scaled(6)),
                  Text(
                    'No activity yet',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: metrics.scaled(9),
                      fontWeight: FontWeight.w500,
                      height: 13.5 / 9,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnimatedCameraPlaceholderArt extends StatefulWidget {
  const _AnimatedCameraPlaceholderArt({
    required this.featured,
    required this.scale,
  });

  final bool featured;
  final double scale;

  @override
  State<_AnimatedCameraPlaceholderArt> createState() =>
      _AnimatedCameraPlaceholderArtState();
}

class _AnimatedCameraPlaceholderArtState
    extends State<_AnimatedCameraPlaceholderArt>
    with SingleTickerProviderStateMixin {
  static const _featuredDelays = <double>[
    1.8,
    1.5,
    1.2,
    0.9,
    0.6,
    0.9,
    1.2,
    1.5,
    1.5,
    1.2,
    0.9,
    0.6,
    0.3,
    0.6,
    0.9,
    1.2,
    1.2,
    0.9,
    0.6,
    0.3,
    -1,
    0.3,
    0.6,
    0.9,
    0.9,
    0.6,
    0.3,
    0.6,
    0.9,
    1.2,
    1.2,
    0.9,
  ];
  static const _smallDelays = <double>[
    1.2,
    0.9,
    0.6,
    0.9,
    1.2,
    0.9,
    0.6,
    0.3,
    0.6,
    0.9,
    0.6,
    0.3,
    -1,
    0.3,
    0.6,
    0.3,
    0.6,
    0.9,
    0.6,
    0.3,
  ];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _flashStrength(double delaySeconds) {
    if (delaySeconds < 0) {
      return 0;
    }
    final shifted = ((_controller.value * 4) + delaySeconds) / 4;
    final wave = 0.5 + 0.5 * math.sin(shifted * math.pi * 2);
    return Curves.easeInOut.transform(wave.clamp(0, 1));
  }

  @override
  Widget build(BuildContext context) {
    final columns = widget.featured ? 8 : 5;
    final spacing = widget.scale;
    final cellSize = widget.scale * (widget.featured ? 22.0 : 20.0);
    final iconSize = widget.scale * (widget.featured ? 10.0 : 9.0);
    final highlightSize = widget.scale * (widget.featured ? 16.0 : 14.0);
    final delays = widget.featured ? _featuredDelays : _smallDelays;
    final bottomPadding = widget.scale * 20;
    final rows = (delays.length / columns).ceil();
    final gridWidth = columns * cellSize + (columns - 1) * spacing;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomPadding),
                child: SizedBox(
                  width: gridWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var row = 0; row < rows; row++) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (
                              var column = 0;
                              column < columns;
                              column++
                            ) ...[
                              Builder(
                                builder: (_) {
                                  final index = row * columns + column;
                                  if (index >= delays.length) {
                                    return SizedBox(
                                      width: cellSize,
                                      height: cellSize,
                                    );
                                  }
                                  final delay = delays[index];
                                  return SizedBox(
                                    width: cellSize,
                                    height: cellSize,
                                    child: Center(
                                      child:
                                          delay < 0
                                              ? _HomeAlertShieldIcon(
                                                size: highlightSize,
                                                color: const Color(0xFFB45309),
                                              )
                                              : _HomeShieldIcon(
                                                size: iconSize,
                                                color: Colors.white.withValues(
                                                  alpha:
                                                      0.03 +
                                                      _flashStrength(delay) *
                                                          0.12,
                                                ),
                                              ),
                                    ),
                                  );
                                },
                              ),
                              if (column != columns - 1)
                                SizedBox(width: spacing),
                            ],
                          ],
                        ),
                        if (row != rows - 1) SizedBox(height: spacing),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AnimatedFirstEventShieldGridArt extends StatefulWidget {
  const _AnimatedFirstEventShieldGridArt({required this.scale});

  final double scale;

  @override
  State<_AnimatedFirstEventShieldGridArt> createState() =>
      _AnimatedFirstEventShieldGridArtState();
}

class _AnimatedFirstEventShieldGridArtState
    extends State<_AnimatedFirstEventShieldGridArt>
    with SingleTickerProviderStateMixin {
  static const _columns = 6;
  static const _rows = 8;
  static const _centerColumn = 3;
  static const _centerRow = 4;
  static const _delayGrid = <double>[
    2.8,
    2.4,
    2.0,
    1.6,
    2.0,
    2.4,
    2.4,
    2.0,
    1.6,
    1.2,
    1.6,
    2.0,
    2.0,
    1.6,
    1.2,
    0.8,
    1.2,
    1.6,
    1.6,
    1.2,
    0.8,
    0.4,
    0.8,
    1.2,
    1.2,
    0.8,
    0.4,
    -1.0,
    0.4,
    0.8,
    1.6,
    1.2,
    0.8,
    0.4,
    0.8,
    1.2,
    2.0,
    1.6,
    1.2,
    0.8,
    1.2,
    1.6,
    2.4,
    2.0,
    1.6,
    1.2,
    1.6,
    2.0,
  ];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _flashOpacity(double delaySeconds) {
    if (delaySeconds < 0) {
      return 1;
    }
    final shifted = (_controller.value + (delaySeconds / 8.0)) % 1.0;
    final wave = 0.5 + 0.5 * math.sin(shifted * math.pi * 2);
    return 0.025 + (Curves.easeInOut.transform(wave.clamp(0, 1)) * 0.035);
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final iconSize = scale * 14;
    final highlightSize = scale * 24;
    final step = scale * 32;
    final glowSize = scale * 148;

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = step * (_columns - 1) + iconSize;
        final gridHeight = step * (_rows - 1) + iconSize;
        final gridLeft = (constraints.maxWidth - gridWidth) / 2;
        final gridTop = ((constraints.maxHeight - gridHeight) / 2) - scale * 8;
        final glowLeft =
            gridLeft + (_centerColumn * step) + (iconSize / 2) - (glowSize / 2);
        final glowTop =
            gridTop + (_centerRow * step) + (iconSize / 2) - (glowSize / 2);

        return AnimatedBuilder(
          animation: _controller,
          builder:
              (context, _) => Stack(
                children: [
                  Positioned(
                    left: glowLeft,
                    top: glowTop,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
                      child: Container(
                        width: glowSize,
                        height: glowSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(
                            0xFFB45309,
                          ).withValues(alpha: 0.038),
                        ),
                      ),
                    ),
                  ),
                  for (var row = 0; row < _rows; row++)
                    for (var column = 0; column < _columns; column++)
                      Positioned(
                        left: gridLeft + (column * step),
                        top: gridTop + (row * step),
                        child:
                            row == _centerRow && column == _centerColumn
                                ? SizedBox(
                                  width: highlightSize,
                                  height: highlightSize,
                                  child: Center(
                                    child: _FirstEventAlertShieldIcon(
                                      size: highlightSize,
                                      color: const Color(0xFFB45309),
                                    ),
                                  ),
                                )
                                : Builder(
                                  builder: (_) {
                                    final index = (row * _columns) + column;
                                    final delay = _delayGrid[index];
                                    return SizedBox(
                                      width: iconSize,
                                      height: iconSize,
                                      child: Center(
                                        child: _FirstEventShieldIcon(
                                          size: iconSize,
                                          color: Colors.white.withValues(
                                            alpha: _flashOpacity(delay),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                      ),
                ],
              ),
        );
      },
    );
  }
}

class _HomeNewPill extends StatelessWidget {
  const _HomeNewPill({required this.metrics});

  final _ShellHomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final width = metrics.scaled(46.28);
    return Container(
      width: width,
      height: metrics.livePillHeight,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: metrics.scaled(2),
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: metrics.livePillDotSize,
            height: metrics.livePillDotSize,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                  blurRadius: metrics.scaled(6),
                ),
              ],
            ),
          ),
          SizedBox(width: metrics.scaled(4)),
          Text(
            'NEW',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: metrics.scaled(8),
              fontWeight: FontWeight.w600,
              letterSpacing: metrics.scaled(0.4),
              height: 12 / 8,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedQuietDot extends StatefulWidget {
  const _AnimatedQuietDot({required this.size});

  final double size;

  @override
  State<_AnimatedQuietDot> createState() => _AnimatedQuietDotState();
}

class _AnimatedQuietDotState extends State<_AnimatedQuietDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.4,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ShellRecentEvent {
  const _ShellRecentEvent({
    required this.title,
    required this.subtitle,
    required this.timeLabel,
    required this.previewAssetPath,
    this.previewVideoAssetPath,
    required this.thumbnailBytes,
    required this.accentColor,
    this.videoName,
    this.detections = const <String>{},
    this.motion = true,
    this.canDownload = false,
    this.hasVideoFile = true,
  });

  final String title;
  final String subtitle;
  final String timeLabel;
  final String? previewAssetPath;
  final String? previewVideoAssetPath;
  final Uint8List? thumbnailBytes;
  final Color accentColor;
  final String? videoName;
  final Set<String> detections;
  final bool motion;
  final bool canDownload;
  final bool hasVideoFile;
}

class _EventAccentPainter extends CustomPainter {
  const _EventAccentPainter({
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
        ..strokeWidth = strokeWidth,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EventAccentPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius;
  }
}

class _RecentEventCard extends StatelessWidget {
  const _RecentEventCard({required this.event, required this.metrics});

  final _ShellRecentEvent event;
  final _ShellHomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final canOpenClip =
        (event.previewAssetPath != null &&
            event.previewAssetPath!.isNotEmpty) ||
        (event.hasVideoFile &&
            event.videoName != null &&
            event.videoName!.isNotEmpty);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(metrics.eventCardRadius),
        onTap:
            !canOpenClip
                ? null
                : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => VideoViewPage(
                          cameraName: event.subtitle,
                          videoTitle: event.videoName ?? event.timeLabel,
                          visibleVideoTitle: event.timeLabel,
                          isLivestream: !event.motion,
                          canDownload: event.canDownload,
                          previewAssetPath: event.previewAssetPath,
                          previewVideoAssetPath: event.previewVideoAssetPath,
                          previewDetections: event.detections,
                          previewDuration:
                              event.previewVideoAssetPath != null
                                  ? const Duration(seconds: 16)
                                  : const Duration(seconds: 42),
                          previewPosition:
                              event.previewVideoAssetPath != null
                                  ? Duration.zero
                                  : const Duration(seconds: 12),
                        ),
                  ),
                ),
        child: Container(
          height: metrics.eventCardHeight,
          decoration: BoxDecoration(
            color: dark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(metrics.eventCardRadius),
            border: Border.all(
              color:
                  dark
                      ? Colors.white.withValues(alpha: 0.04)
                      : event.accentColor.withValues(alpha: 0.34),
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(metrics.eventCardRadius),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _EventAccentPainter(
                        color: event.accentColor,
                        strokeWidth: metrics.eventAccentWidth,
                        radius: metrics.eventCardRadius,
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    SizedBox(width: metrics.eventLeadingGap),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        metrics.eventThumbRadius,
                      ),
                      child: SizedBox(
                        width: metrics.eventThumbSize,
                        height: metrics.eventThumbSize,
                        child:
                            event.thumbnailBytes != null
                                ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.memory(
                                      event.thumbnailBytes!,
                                      fit: BoxFit.cover,
                                    ),
                                    Positioned(
                                      right: -1,
                                      bottom: -1,
                                      child: Container(
                                        width: metrics.eventThumbBadgeSize,
                                        height: metrics.eventThumbBadgeSize,
                                        decoration: BoxDecoration(
                                          color: event.accentColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color:
                                                dark
                                                    ? const Color(0xFF0A0A0A)
                                                    : Colors.white,
                                            width:
                                                metrics
                                                    .eventThumbBadgeBorderWidth,
                                          ),
                                        ),
                                        child: Center(
                                          child:
                                              event.title
                                                      .toLowerCase()
                                                      .contains('motion')
                                                  ? _HomeMotionBadgeIcon(
                                                    size:
                                                        metrics
                                                            .eventThumbBadgeIconSize,
                                                    color: Colors.white,
                                                  )
                                                  : _HomePersonBadgeIcon(
                                                    size:
                                                        metrics
                                                            .eventThumbBadgeIconSize,
                                                    color: Colors.white,
                                                  ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                                : event.previewAssetPath != null &&
                                    event.previewAssetPath!.isNotEmpty
                                ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.asset(
                                      event.previewAssetPath!,
                                      fit: BoxFit.cover,
                                    ),
                                    Positioned(
                                      right: -1,
                                      bottom: -1,
                                      child: Container(
                                        width: metrics.eventThumbBadgeSize,
                                        height: metrics.eventThumbBadgeSize,
                                        decoration: BoxDecoration(
                                          color: event.accentColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color:
                                                dark
                                                    ? const Color(0xFF0A0A0A)
                                                    : Colors.white,
                                            width:
                                                metrics
                                                    .eventThumbBadgeBorderWidth,
                                          ),
                                        ),
                                        child: Center(
                                          child:
                                              event.title
                                                      .toLowerCase()
                                                      .contains('motion')
                                                  ? _HomeMotionBadgeIcon(
                                                    size:
                                                        metrics
                                                            .eventThumbBadgeIconSize,
                                                    color: Colors.white,
                                                  )
                                                  : _HomePersonBadgeIcon(
                                                    size:
                                                        metrics
                                                            .eventThumbBadgeIconSize,
                                                    color: Colors.white,
                                                  ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                                : Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    const ColoredBox(color: Color(0xFF1F2937)),
                                    Positioned.fill(
                                      child: Padding(
                                        padding: const EdgeInsets.all(0.5),
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: const Color(0xFFC0C0C0),
                                              width: 1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              metrics.eventThumbRadius - 0.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: -1,
                                      bottom: -1,
                                      child: Container(
                                        width: metrics.eventThumbBadgeSize,
                                        height: metrics.eventThumbBadgeSize,
                                        decoration: BoxDecoration(
                                          color: event.accentColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color:
                                                dark
                                                    ? const Color(0xFF0A0A0A)
                                                    : Colors.white,
                                            width:
                                                metrics
                                                    .eventThumbBadgeBorderWidth,
                                          ),
                                        ),
                                        child: Center(
                                          child:
                                              event.title
                                                      .toLowerCase()
                                                      .contains('motion')
                                                  ? _HomeMotionBadgeIcon(
                                                    size:
                                                        metrics
                                                            .eventThumbBadgeIconSize,
                                                    color: Colors.white,
                                                  )
                                                  : _HomePersonBadgeIcon(
                                                    size:
                                                        metrics
                                                            .eventThumbBadgeIconSize,
                                                    color: Colors.white,
                                                  ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                      ),
                    ),
                    SizedBox(width: metrics.eventTextGap),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(
                              color:
                                  dark ? Colors.white : const Color(0xFF111827),
                              fontSize: metrics.eventTitleSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: metrics.eventTitleSubtitleGap),
                          Text(
                            event.subtitle,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color:
                                  dark
                                      ? Colors.white.withValues(alpha: 0.4)
                                      : const Color(0xFF6B7280),
                              fontSize: metrics.eventSubtitleSize,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: metrics.eventTimeGap),
                    SizedBox(
                      width: metrics.eventTrailingWidth,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            event.timeLabel,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color:
                                  dark
                                      ? Colors.white.withValues(alpha: 0.18)
                                      : const Color(0xFF9CA3AF),
                              fontSize: metrics.eventTimeSize,
                            ),
                          ),
                          SizedBox(height: metrics.eventTimeChevronGap),
                          _HomeChevronIcon(
                            size: metrics.eventChevronSize,
                            color:
                                dark
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : const Color(0xFF9CA3AF),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: metrics.eventTrailingInset),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyRecentActivityCard extends StatefulWidget {
  const _EmptyRecentActivityCard({required this.metrics});

  final _ShellHomeMetrics metrics;

  @override
  State<_EmptyRecentActivityCard> createState() =>
      _EmptyRecentActivityCardState();
}

class _EmptyRecentActivityCardState extends State<_EmptyRecentActivityCard>
    with TickerProviderStateMixin {
  late final AnimationController _orbitController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();
  late final AnimationController _accentController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _orbitController.dispose();
    _accentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final metrics = widget.metrics;
    final cardHeight = metrics.scaled(204);
    final artSize = metrics.scaled(80);
    final titleTop = metrics.scaled(120);
    final bodyTop = metrics.scaled(146);
    final iconTop = metrics.scaled(24);

    return Container(
      height: cardHeight,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF08080C) : Colors.white,
        borderRadius: BorderRadius.circular(metrics.cameraCardRadius),
        border: Border.all(
          color:
              dark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFE5E7EB),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(metrics.cameraCardRadius),
        child: Stack(
          children: [
            Positioned(
              top: iconTop,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _orbitController,
                    _accentController,
                  ]),
                  builder:
                      (context, _) => _VaultSealedPlaceholderArt(
                        size: artSize,
                        dark: dark,
                        orbitValue: _orbitController.value,
                        accentValue: _accentController.value,
                      ),
                ),
              ),
            ),
            Positioned(
              top: titleTop,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Vault sealed',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color:
                        dark
                            ? Colors.white.withValues(alpha: 0.5)
                            : const Color(0xFF6B7280),
                    fontSize: metrics.scaled(13),
                    fontWeight: FontWeight.w600,
                    height: 19.5 / 13,
                  ),
                ),
              ),
            ),
            Positioned(
              top: bodyTop,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: metrics.scaled(190.01),
                  child: Text(
                    'Your footage is encrypted end-to-end.\nActivity will appear here when detected.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.4)
                              : const Color(0xFF6B7280).withValues(alpha: 0.78),
                      fontSize: metrics.scaled(10),
                      fontWeight: FontWeight.w400,
                      height: 16.25 / 10,
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
}

class _VaultSealedPlaceholderArt extends StatelessWidget {
  const _VaultSealedPlaceholderArt({
    required this.size,
    required this.dark,
    required this.orbitValue,
    required this.accentValue,
  });

  final double size;
  final bool dark;
  final double orbitValue;
  final double accentValue;

  double _shimmerOffset(double travel) {
    return math.sin(accentValue * math.pi * 2) * travel;
  }

  @override
  Widget build(BuildContext context) {
    final amber = const Color(0xFFB45309);
    final shieldSize = size * (52 / 80);
    final shimmerWidth = size * 2;
    final orbitRadius = size * (28 / 80);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: _VaultOrbitParticle(
              progress: orbitValue * 1.5,
              radius: orbitRadius,
              size: size * (1 / 80),
              color: amber.withValues(alpha: dark ? 0.4 : 0.3),
            ),
          ),
          Positioned.fill(
            child: _VaultOrbitParticle(
              progress: -orbitValue,
              radius: orbitRadius,
              size: size * (0.5 / 80),
              color: amber.withValues(alpha: dark ? 0.25 : 0.2),
            ),
          ),
          Positioned.fill(
            child: _VaultOrbitParticle(
              progress: orbitValue * 1.2 + 0.3,
              radius: orbitRadius,
              size: size * (0.5 / 80),
              color: Colors.white.withValues(alpha: dark ? 0.2 : 0.16),
            ),
          ),
          Positioned.fill(
            child: ClipOval(
              child: Transform.translate(
                offset: Offset(_shimmerOffset(size), 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: shimmerWidth,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          (dark ? Colors.white : amber).withValues(alpha: 0),
                          (dark ? Colors.white : amber).withValues(
                            alpha: dark ? 0.06 : 0.15,
                          ),
                          (dark ? Colors.white : amber).withValues(alpha: 0),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: size * (40 / 80) - shieldSize / 2,
            top: size * (13 / 80),
            child: SizedBox(
              width: shieldSize,
              height: shieldSize,
              child: CustomPaint(
                painter: _VaultSealedShieldPainter(dark: dark),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitParticle extends StatelessWidget {
  const _OrbitParticle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _VaultOrbitParticle extends StatelessWidget {
  const _VaultOrbitParticle({
    required this.progress,
    required this.radius,
    required this.size,
    required this.color,
  });

  final double progress;
  final double radius;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final angle = progress * math.pi * 2;
    return SizedBox.expand(
      child: Transform.rotate(
        angle: angle,
        alignment: Alignment.center,
        child: Transform.translate(
          offset: Offset(radius, 0),
          child: Transform.rotate(
            angle: -angle,
            alignment: Alignment.center,
            child: Align(
              alignment: Alignment.topLeft,
              child: _OrbitParticle(size: size, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.isOffline, required this.metrics});

  final bool isOffline;
  final _ShellHomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final dotColor =
        isOffline ? const Color(0xFFE15C5C) : const Color(0xFF10B981);
    return Container(
      height: metrics.livePillHeight,
      padding: EdgeInsets.symmetric(
        horizontal: metrics.livePillHorizontalPadding,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: metrics.livePillDotSize,
            height: metrics.livePillDotSize,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          SizedBox(width: metrics.livePillInnerGap),
          Text(
            isOffline ? 'OFFLINE' : 'LIVE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontSize: metrics.livePillTextSize,
              fontWeight: FontWeight.w600,
              letterSpacing: metrics.livePillLetterSpacing,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.metrics});

  final String label;
  final _ShellHomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final lower = label.toLowerCase();
    final isPerson = lower.contains('person');
    final isMotion = lower.contains('motion');
    final backgroundColor =
        isPerson
            ? const Color(0x9978350F)
            : isMotion
            ? Colors.black.withValues(alpha: 0.5)
            : Colors.black.withValues(alpha: 0.4);
    final foregroundColor =
        isPerson
            ? const Color(0xFFFEF3C7)
            : Colors.white.withValues(alpha: 0.9);
    final icon =
        isPerson
            ? null
            : isMotion
            ? null
            : null;
    return Container(
      height: metrics.statusPillHeight,
      padding: EdgeInsets.symmetric(
        horizontal: metrics.statusPillHorizontalPadding,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: isPerson ? Border.all(color: const Color(0x4D8BB3EE)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            const SizedBox.shrink(),
            SizedBox(width: metrics.statusPillInnerGap),
          ],
          if (isPerson) ...[
            _HomePersonIcon(
              size: metrics.statusPillIconSize,
              color: foregroundColor,
            ),
            SizedBox(width: metrics.statusPillInnerGap),
          ] else if (isMotion) ...[
            _HomeMotionIcon(
              size: metrics.statusPillIconSize,
              color: foregroundColor,
            ),
            SizedBox(width: metrics.statusPillInnerGap),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foregroundColor,
              fontSize: metrics.statusPillTextSize,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeAddIcon extends StatelessWidget {
  const _HomeAddIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HomeAddIconPainter(color)),
    );
  }
}

class _HomeLockIcon extends StatelessWidget {
  const _HomeLockIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HomeLockIconPainter(color)),
    );
  }
}

class _HomeShieldIcon extends StatelessWidget {
  const _HomeShieldIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HomeShieldIconPainter(color)),
    );
  }
}

class _HomeAlertShieldIcon extends StatelessWidget {
  const _HomeAlertShieldIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HomeAlertShieldIconPainter(color)),
    );
  }
}

class _FirstEventShieldIcon extends StatelessWidget {
  const _FirstEventShieldIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _FirstEventShieldIconPainter(color)),
    );
  }
}

class _FirstEventAlertShieldIcon extends StatelessWidget {
  const _FirstEventAlertShieldIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _FirstEventAlertShieldIconPainter(color)),
    );
  }
}

class _HomeErrorWarningIcon extends StatelessWidget {
  const _HomeErrorWarningIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HomeErrorWarningIconPainter(color)),
    );
  }
}

class _HomeErrorCloseIcon extends StatelessWidget {
  const _HomeErrorCloseIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HomeErrorCloseIconPainter(color)),
    );
  }
}

class _HomePersonIcon extends StatelessWidget {
  const _HomePersonIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HomePersonIconPainter(color)),
    );
  }
}

class _HomeMotionIcon extends StatelessWidget {
  const _HomeMotionIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HomeMotionIconPainter(color)),
    );
  }
}

class _HomeChevronIcon extends StatelessWidget {
  const _HomeChevronIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HomeChevronIconPainter(color)),
    );
  }
}

class _HomePersonBadgeIcon extends StatelessWidget {
  const _HomePersonBadgeIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HomePersonBadgeIconPainter(color)),
    );
  }
}

class _HomeMotionBadgeIcon extends StatelessWidget {
  const _HomeMotionBadgeIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HomeMotionBadgeIconPainter(color)),
    );
  }
}

class _HomeAddIconPainter extends CustomPainter {
  const _HomeAddIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.33333 / 16)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;
    canvas.drawLine(
      Offset(size.width * (8 / 16), size.height * (3.33333 / 16)),
      Offset(size.width * (8 / 16), size.height * (12.6667 / 16)),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * (3.33333 / 16), size.height * (8 / 16)),
      Offset(size.width * (12.6667 / 16), size.height * (8 / 16)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeAddIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _HomeLockIconPainter extends CustomPainter {
  const _HomeLockIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.04167 / 10)
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
  bool shouldRepaint(covariant _HomeLockIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _HomeShieldIconPainter extends CustomPainter {
  const _HomeShieldIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.5 / 10)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * 0.5, size.height * 0.1)
          ..lineTo(size.width * 0.84, size.height * 0.25)
          ..lineTo(size.width * 0.84, size.height * 0.53)
          ..cubicTo(
            size.width * 0.84,
            size.height * 0.77,
            size.width * 0.69,
            size.height * 0.96,
            size.width * 0.5,
            size.height * 1.05,
          )
          ..cubicTo(
            size.width * 0.31,
            size.height * 0.96,
            size.width * 0.16,
            size.height * 0.77,
            size.width * 0.16,
            size.height * 0.53,
          )
          ..lineTo(size.width * 0.16, size.height * 0.25)
          ..close();
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _HomeShieldIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _HomeAlertShieldIconPainter extends CustomPainter {
  const _HomeAlertShieldIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final shieldPath =
        Path()
          ..moveTo(size.width * 0.5, size.height * 0.1)
          ..lineTo(size.width * 0.84, size.height * 0.25)
          ..lineTo(size.width * 0.84, size.height * 0.53)
          ..cubicTo(
            size.width * 0.84,
            size.height * 0.77,
            size.width * 0.69,
            size.height * 0.96,
            size.width * 0.5,
            size.height * 1.05,
          )
          ..cubicTo(
            size.width * 0.31,
            size.height * 0.96,
            size.width * 0.16,
            size.height * 0.77,
            size.width * 0.16,
            size.height * 0.53,
          )
          ..lineTo(size.width * 0.16, size.height * 0.25)
          ..close();
    final fill =
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: 0.15)
          ..isAntiAlias = true;
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.5 / 16)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    canvas.drawPath(shieldPath, fill);
    canvas.drawPath(shieldPath, stroke);
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.47),
      size.width * (2 / 16),
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.6)
        ..isAntiAlias = true,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.6),
      Offset(size.width * 0.5, size.height * 0.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * (1.5 / 16)
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.6)
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeAlertShieldIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _FirstEventShieldIconPainter extends CustomPainter {
  const _FirstEventShieldIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.5 / 14)
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
          )
          ..close();
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _FirstEventShieldIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _FirstEventAlertShieldIconPainter extends CustomPainter {
  const _FirstEventAlertShieldIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final shieldPath =
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
          )
          ..close();
    final fill =
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: 0.15)
          ..isAntiAlias = true;
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.5 / 24)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    canvas.drawPath(shieldPath, fill);
    canvas.drawPath(shieldPath, stroke);
    canvas.drawCircle(
      Offset(size.width * (12 / 24), size.height * (11 / 24)),
      size.width * (2 / 24),
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.6)
        ..isAntiAlias = true,
    );
    canvas.drawLine(
      Offset(size.width * (12 / 24), size.height * (13 / 24)),
      Offset(size.width * (12 / 24), size.height * (16 / 24)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * (1.5 / 24)
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.6)
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _FirstEventAlertShieldIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _VaultSealedShieldPainter extends CustomPainter {
  const _VaultSealedShieldPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final amber = const Color(0xFFB45309);
    final outerPath =
        Path()
          ..moveTo(size.width * 0.5, size.height * 0.08)
          ..cubicTo(
            size.width * 0.72,
            size.height * 0.16,
            size.width * 0.84,
            size.height * 0.19,
            size.width * 0.84,
            size.height * 0.23,
          )
          ..lineTo(size.width * 0.84, size.height * 0.53)
          ..cubicTo(
            size.width * 0.84,
            size.height * 0.78,
            size.width * 0.66,
            size.height * 0.92,
            size.width * 0.5,
            size.height * 1.03,
          )
          ..cubicTo(
            size.width * 0.34,
            size.height * 0.92,
            size.width * 0.16,
            size.height * 0.78,
            size.width * 0.16,
            size.height * 0.53,
          )
          ..lineTo(size.width * 0.16, size.height * 0.23)
          ..cubicTo(
            size.width * 0.16,
            size.height * 0.19,
            size.width * 0.28,
            size.height * 0.16,
            size.width * 0.5,
            size.height * 0.08,
          )
          ..close();
    final innerPath =
        Path()
          ..moveTo(size.width * 0.5, size.height * 0.15)
          ..cubicTo(
            size.width * 0.68,
            size.height * 0.22,
            size.width * 0.77,
            size.height * 0.24,
            size.width * 0.77,
            size.height * 0.28,
          )
          ..lineTo(size.width * 0.77, size.height * 0.53)
          ..cubicTo(
            size.width * 0.77,
            size.height * 0.73,
            size.width * 0.62,
            size.height * 0.84,
            size.width * 0.5,
            size.height * 0.92,
          )
          ..cubicTo(
            size.width * 0.38,
            size.height * 0.84,
            size.width * 0.23,
            size.height * 0.73,
            size.width * 0.23,
            size.height * 0.53,
          )
          ..lineTo(size.width * 0.23, size.height * 0.28)
          ..cubicTo(
            size.width * 0.23,
            size.height * 0.24,
            size.width * 0.32,
            size.height * 0.22,
            size.width * 0.5,
            size.height * 0.15,
          )
          ..close();
    canvas.drawPath(
      outerPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = amber.withValues(alpha: dark ? 0.06 : 0.05)
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      outerPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * (0.8 / 52)
        ..color = amber.withValues(alpha: dark ? 0.3 : 0.26)
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      innerPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * (0.4 / 52)
        ..color = amber.withValues(alpha: dark ? 0.15 : 0.13)
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.48),
      size.width * (1.5 / 52),
      Paint()
        ..style = PaintingStyle.fill
        ..color = amber.withValues(alpha: dark ? 0.2 : 0.18)
        ..isAntiAlias = true,
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.48),
      size.width * (1.5 / 52),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * (0.5 / 52)
        ..color = amber.withValues(alpha: dark ? 0.4 : 0.32)
        ..isAntiAlias = true,
    );
    final stemRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.62),
        width: size.width * (1.2 / 52),
        height: size.height * (6.5 / 52),
      ),
      Radius.circular(size.width * (0.6 / 52)),
    );
    canvas.drawRRect(
      stemRect,
      Paint()
        ..style = PaintingStyle.fill
        ..color = amber.withValues(alpha: dark ? 0.2 : 0.18)
        ..isAntiAlias = true,
    );
    canvas.drawRRect(
      stemRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * (0.5 / 52)
        ..color = amber.withValues(alpha: dark ? 0.4 : 0.32)
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _VaultSealedShieldPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class _HomeErrorWarningIconPainter extends CustomPainter {
  const _HomeErrorWarningIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.75 / 16)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

    final triangle =
        Path()
          ..moveTo(size.width * (8 / 16), size.height * (2 / 16))
          ..lineTo(size.width * (14.25 / 16), size.height * (13 / 16))
          ..cubicTo(
            size.width * (14.55 / 16),
            size.height * (13.55 / 16),
            size.width * (14.1 / 16),
            size.height * (14.25 / 16),
            size.width * (13.45 / 16),
            size.height * (14.25 / 16),
          )
          ..lineTo(size.width * (2.55 / 16), size.height * (14.25 / 16))
          ..cubicTo(
            size.width * (1.9 / 16),
            size.height * (14.25 / 16),
            size.width * (1.45 / 16),
            size.height * (13.55 / 16),
            size.width * (1.75 / 16),
            size.height * (13 / 16),
          )
          ..close();
    canvas.drawPath(triangle, stroke);

    final exclamation =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.5 / 16)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * (5.25 / 16)),
      Offset(size.width * 0.5, size.height * (9.5 / 16)),
      exclamation,
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * (12 / 16)),
      size.width * (0.75 / 16),
      Paint()
        ..style = PaintingStyle.fill
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeErrorWarningIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _HomeErrorCloseIconPainter extends CustomPainter {
  const _HomeErrorCloseIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.5 / 14)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;
    canvas.drawLine(
      Offset(size.width * (3.5 / 14), size.height * (3.5 / 14)),
      Offset(size.width * (10.5 / 14), size.height * (10.5 / 14)),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * (10.5 / 14), size.height * (3.5 / 14)),
      Offset(size.width * (3.5 / 14), size.height * (10.5 / 14)),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeErrorCloseIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _HomePersonIconPainter extends CustomPainter {
  const _HomePersonIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.04167 / 10)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final headCenter = Offset(size.width * 0.5, size.height * (2.91667 / 10));
    canvas.drawCircle(headCenter, size.width * (1.66667 / 10), stroke);
    final body =
        Path()
          ..moveTo(size.width * (1.66667 / 10), size.height * (8.75 / 10))
          ..lineTo(size.width * (1.66667 / 10), size.height * (7.91667 / 10))
          ..cubicTo(
            size.width * (1.66667 / 10),
            size.height * (7.47464 / 10),
            size.width * (1.84226 / 10),
            size.height * (7.05072 / 10),
            size.width * (2.15482 / 10),
            size.height * (6.73816 / 10),
          )
          ..cubicTo(
            size.width * (2.46738 / 10),
            size.height * (6.4256 / 10),
            size.width * (2.89131 / 10),
            size.height * (6.25 / 10),
            size.width * (3.33333 / 10),
            size.height * (6.25 / 10),
          )
          ..lineTo(size.width * (6.66667 / 10), size.height * (6.25 / 10))
          ..cubicTo(
            size.width * (7.10869 / 10),
            size.height * (6.25 / 10),
            size.width * (7.53262 / 10),
            size.height * (6.4256 / 10),
            size.width * (7.84518 / 10),
            size.height * (6.73816 / 10),
          )
          ..cubicTo(
            size.width * (8.15774 / 10),
            size.height * (7.05072 / 10),
            size.width * (8.33333 / 10),
            size.height * (7.47464 / 10),
            size.width * (8.33333 / 10),
            size.height * (7.91667 / 10),
          )
          ..lineTo(size.width * (8.33333 / 10), size.height * (8.75 / 10));
    canvas.drawPath(body, stroke);
  }

  @override
  bool shouldRepaint(covariant _HomePersonIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _HomeMotionIconPainter extends CustomPainter {
  const _HomeMotionIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.04167 / 10)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (9.16667 / 10), size.height * (5 / 10))
          ..lineTo(size.width * (7.5 / 10), size.height * (5 / 10))
          ..lineTo(size.width * (6.25 / 10), size.height * (8.75 / 10))
          ..lineTo(size.width * (3.75 / 10), size.height * (1.25 / 10))
          ..lineTo(size.width * (2.5 / 10), size.height * (5 / 10))
          ..lineTo(size.width * (0.833333 / 10), size.height * (5 / 10));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _HomeMotionIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _HomeChevronIconPainter extends CustomPainter {
  const _HomeChevronIconPainter(this.color);

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
          ..moveTo(size.width * (5.25 / 14), size.height * (10.5 / 14))
          ..lineTo(size.width * (8.75 / 14), size.height * (7 / 14))
          ..lineTo(size.width * (5.25 / 14), size.height * (3.5 / 14));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _HomeChevronIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _HomePersonBadgeIconPainter extends CustomPainter {
  const _HomePersonBadgeIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width / 8
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * (2.33333 / 8)),
      size.width * (1.33333 / 8),
      stroke,
    );
    final body =
        Path()
          ..moveTo(size.width * (1.33333 / 8), size.height * (7 / 8))
          ..lineTo(size.width * (1.33333 / 8), size.height * (6.33333 / 8))
          ..cubicTo(
            size.width * (1.33333 / 8),
            size.height * (5.97971 / 8),
            size.width * (1.47381 / 8),
            size.height * (5.64057 / 8),
            size.width * (1.72386 / 8),
            size.height * (5.39052 / 8),
          )
          ..cubicTo(
            size.width * (1.97391 / 8),
            size.height * (5.14048 / 8),
            size.width * (2.31304 / 8),
            size.height * (5 / 8),
            size.width * (2.66667 / 8),
            size.height * (5 / 8),
          )
          ..lineTo(size.width * (5.33333 / 8), size.height * (5 / 8))
          ..cubicTo(
            size.width * (5.68696 / 8),
            size.height * (5 / 8),
            size.width * (6.02609 / 8),
            size.height * (5.14048 / 8),
            size.width * (6.27614 / 8),
            size.height * (5.39052 / 8),
          )
          ..cubicTo(
            size.width * (6.52619 / 8),
            size.height * (5.64057 / 8),
            size.width * (6.66667 / 8),
            size.height * (5.97971 / 8),
            size.width * (6.66667 / 8),
            size.height * (6.33333 / 8),
          )
          ..lineTo(size.width * (6.66667 / 8), size.height * (7 / 8));
    canvas.drawPath(body, stroke);
  }

  @override
  bool shouldRepaint(covariant _HomePersonBadgeIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _HomeMotionBadgeIconPainter extends CustomPainter {
  const _HomeMotionBadgeIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width / 8
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (7.33333 / 8), size.height * (4 / 8))
          ..lineTo(size.width * (6 / 8), size.height * (4 / 8))
          ..lineTo(size.width * (5 / 8), size.height * (7 / 8))
          ..lineTo(size.width * (3 / 8), size.height * (1 / 8))
          ..lineTo(size.width * (2 / 8), size.height * (4 / 8))
          ..lineTo(size.width * (0.666667 / 8), size.height * (4 / 8));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _HomeMotionBadgeIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.metrics});

  final _ShellHomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final radius = metrics.scaled(16);
    final cardPadding = EdgeInsets.fromLTRB(
      metrics.scaled(16),
      metrics.scaled(16),
      metrics.scaled(16),
      metrics.scaled(16),
    );
    final copyButtonSize = Size(metrics.scaled(77.07), metrics.scaled(29));
    return Container(
      height: metrics.scaled(169.13),
      decoration: BoxDecoration(
        color: const Color(0x0FEF4444),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark ? const Color(0x33EF4444) : const Color(0x4DEF4444),
        ),
      ),
      child: Padding(
        padding: cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: metrics.scaled(1)),
                  child: _HomeErrorWarningIcon(
                    size: metrics.scaled(16),
                    color: const Color(0xFFEF4444),
                  ),
                ),
                SizedBox(width: metrics.scaled(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Relay sync failed',
                        style: GoogleFonts.inter(
                          color: const Color(0xFFEF4444),
                          fontSize: metrics.scaled(13),
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.normal,
                          height: 19.5 / 13,
                        ),
                      ),
                      SizedBox(height: metrics.scaled(2)),
                      Text(
                        '2 minutes ago',
                        style: GoogleFonts.inter(
                          color:
                              dark
                                  ? Colors.white.withValues(alpha: 0.4)
                                  : const Color(0xFF6B7280),
                          fontSize: metrics.scaled(10),
                          fontWeight: FontWeight.w400,
                          fontStyle: FontStyle.normal,
                          height: 15 / 10,
                        ),
                      ),
                    ],
                  ),
                ),
                _HomeErrorCloseIcon(
                  size: metrics.scaled(14),
                  color:
                      dark
                          ? Colors.white.withValues(alpha: 0.4)
                          : const Color(0xFF9CA3AF),
                ),
              ],
            ),
            SizedBox(height: metrics.scaled(12)),
            Padding(
              padding: EdgeInsets.only(left: metrics.scaled(28)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: metrics.scaled(193.33)),
                child: Text(
                  "Couldn't reach your relay. Check that it's powered on and connected to your network.",
                  style: GoogleFonts.inter(
                    color:
                        dark
                            ? Colors.white.withValues(alpha: 0.6)
                            : const Color(0xFF4B5563),
                    fontSize: metrics.scaled(11),
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.normal,
                    height: 17.88 / 11,
                  ),
                ),
              ),
            ),
            const Spacer(),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: copyButtonSize.width,
                height: copyButtonSize.height,
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: BorderSide(
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.1)
                              : const Color(0xFFD1D5DB),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(metrics.scaled(8)),
                    ),
                    foregroundColor:
                        dark
                            ? Colors.white.withValues(alpha: 0.7)
                            : const Color(0xFF374151),
                    backgroundColor:
                        dark
                            ? Colors.transparent
                            : Colors.white.withValues(alpha: 0.4),
                    textStyle: GoogleFonts.inter(
                      fontSize: metrics.scaled(10),
                      fontWeight: FontWeight.w500,
                      fontStyle: FontStyle.normal,
                      height: 15 / 10,
                    ),
                  ),
                  child: const Text('Copy Logs'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellHomeMetrics {
  const _ShellHomeMetrics({
    required this.pageInset,
    required this.topPadding,
    required this.bottomPadding,
    required this.headerInsetDelta,
    required this.titleSize,
    required this.titleLetterSpacing,
    required this.addButtonSize,
    required this.addButtonRadius,
    required this.addIconSize,
    required this.headerToStatusGap,
    required this.statusDotSize,
    required this.statusDotGap,
    required this.statusLabelSize,
    required this.statusLetterSpacing,
    required this.statusToChipGap,
    required this.chipHeight,
    required this.chipHorizontalPadding,
    required this.chipIconSize,
    required this.chipDotSize,
    required this.chipInnerGap,
    required this.chipTextSize,
    required this.chipLetterSpacing,
    required this.headerToCardsGap,
    required this.gridGap,
    required this.cameraCardRadius,
    required this.cameraCardInsetStart,
    required this.cameraCardInsetTop,
    required this.cameraCardInsetEnd,
    required this.cameraCardInsetBottom,
    required this.cameraLockSize,
    required this.livePillHeight,
    required this.livePillHorizontalPadding,
    required this.livePillDotSize,
    required this.livePillInnerGap,
    required this.livePillTextSize,
    required this.livePillLetterSpacing,
    required this.featuredTitleSize,
    required this.featuredTitleLetterSpacing,
    required this.smallTitleSize,
    required this.cameraTitleToStatusGap,
    required this.statusPillHeight,
    required this.statusPillHorizontalPadding,
    required this.statusPillIconSize,
    required this.statusPillInnerGap,
    required this.statusPillTextSize,
    required this.sectionGap,
    required this.sectionLabelSize,
    required this.sectionLetterSpacing,
    required this.sectionLinkSize,
    required this.sectionToEventsGap,
    required this.eventGap,
    required this.eventCardHeight,
    required this.eventCardRadius,
    required this.eventAccentWidth,
    required this.eventLeadingGap,
    required this.eventThumbSize,
    required this.eventThumbRadius,
    required this.eventThumbBadgeSize,
    required this.eventThumbBadgeBorderWidth,
    required this.eventThumbBadgeIconSize,
    required this.eventTextGap,
    required this.eventTitleSize,
    required this.eventTitleSubtitleGap,
    required this.eventSubtitleSize,
    required this.eventTimeGap,
    required this.eventTimeSize,
    required this.eventTimeChevronGap,
    required this.eventChevronSize,
    required this.eventTrailingWidth,
    required this.eventTrailingInset,
    required this.errorCardGap,
    required this.errorIconSize,
    required this.errorIconGap,
    required this.errorTitleSize,
    required this.errorCloseSize,
    required this.errorTitleGap,
    required this.errorMetaSize,
    required this.errorMetaGap,
    required this.errorBodySize,
    required this.errorButtonGap,
    required this.emptyCardHeight,
    required this.emptyCardIconSize,
    required this.emptyCardGap,
    required this.emptyCardTitleSize,
    required this.emptyCardTextGap,
    required this.emptyCardBodySize,
    required this.emptyCardButtonGap,
    required this.addTileAspectRatio,
    required this.addTileRadius,
    required this.addTileIconWrapSize,
    required this.addTileIconSize,
    required this.addTileGap,
    required this.addTileTextSize,
    required double scale,
  }) : _scale = scale;

  static const design = _ShellHomeMetrics(
    pageInset: 16,
    topPadding: 10,
    bottomPadding: 28,
    headerInsetDelta: 4,
    titleSize: 22,
    titleLetterSpacing: 0.55,
    addButtonSize: 36,
    addButtonRadius: 18,
    addIconSize: 18,
    headerToStatusGap: 6,
    statusDotSize: 6,
    statusDotGap: 8,
    statusLabelSize: 10,
    statusLetterSpacing: 0.5,
    statusToChipGap: 14,
    chipHeight: 22,
    chipHorizontalPadding: 10,
    chipIconSize: 11,
    chipDotSize: 6,
    chipInnerGap: 6,
    chipTextSize: 8,
    chipLetterSpacing: 0.4,
    headerToCardsGap: 18,
    gridGap: 10,
    cameraCardRadius: 16,
    cameraCardInsetStart: 10,
    cameraCardInsetTop: 10,
    cameraCardInsetEnd: 12,
    cameraCardInsetBottom: 12,
    cameraLockSize: 12,
    livePillHeight: 20,
    livePillHorizontalPadding: 8,
    livePillDotSize: 6,
    livePillInnerGap: 6,
    livePillTextSize: 8,
    livePillLetterSpacing: 0.4,
    featuredTitleSize: 14,
    featuredTitleLetterSpacing: 0.35,
    smallTitleSize: 13,
    cameraTitleToStatusGap: 6,
    statusPillHeight: 21,
    statusPillHorizontalPadding: 8,
    statusPillIconSize: 11,
    statusPillInnerGap: 4,
    statusPillTextSize: 10,
    sectionGap: 16,
    sectionLabelSize: 10,
    sectionLetterSpacing: 1,
    sectionLinkSize: 10,
    sectionToEventsGap: 12,
    eventGap: 8,
    eventCardHeight: 66,
    eventCardRadius: 12,
    eventAccentWidth: 2,
    eventLeadingGap: 10,
    eventThumbSize: 40,
    eventThumbRadius: 8,
    eventThumbBadgeSize: 16,
    eventThumbBadgeBorderWidth: 2,
    eventThumbBadgeIconSize: 11,
    eventTextGap: 12,
    eventTitleSize: 13,
    eventTitleSubtitleGap: 2,
    eventSubtitleSize: 10,
    eventTimeGap: 8,
    eventTimeSize: 9,
    eventTimeChevronGap: 2,
    eventChevronSize: 14,
    eventTrailingWidth: 46,
    eventTrailingInset: 10,
    errorCardGap: 16,
    errorIconSize: 24,
    errorIconGap: 10,
    errorTitleSize: 20,
    errorCloseSize: 24,
    errorTitleGap: 10,
    errorMetaSize: 12,
    errorMetaGap: 8,
    errorBodySize: 14,
    errorButtonGap: 16,
    emptyCardHeight: 340,
    emptyCardIconSize: 78,
    emptyCardGap: 18,
    emptyCardTitleSize: 20,
    emptyCardTextGap: 8,
    emptyCardBodySize: 14,
    emptyCardButtonGap: 22,
    addTileAspectRatio: 1,
    addTileRadius: 16,
    addTileIconWrapSize: 40,
    addTileIconSize: 20,
    addTileGap: 12,
    addTileTextSize: 10,
    scale: 1,
  );

  final double pageInset;
  final double topPadding;
  final double bottomPadding;
  final double headerInsetDelta;
  final double titleSize;
  final double titleLetterSpacing;
  final double addButtonSize;
  final double addButtonRadius;
  final double addIconSize;
  final double headerToStatusGap;
  final double statusDotSize;
  final double statusDotGap;
  final double statusLabelSize;
  final double statusLetterSpacing;
  final double statusToChipGap;
  final double chipHeight;
  final double chipHorizontalPadding;
  final double chipIconSize;
  final double chipDotSize;
  final double chipInnerGap;
  final double chipTextSize;
  final double chipLetterSpacing;
  final double headerToCardsGap;
  final double gridGap;
  final double cameraCardRadius;
  final double cameraCardInsetStart;
  final double cameraCardInsetTop;
  final double cameraCardInsetEnd;
  final double cameraCardInsetBottom;
  final double cameraLockSize;
  final double livePillHeight;
  final double livePillHorizontalPadding;
  final double livePillDotSize;
  final double livePillInnerGap;
  final double livePillTextSize;
  final double livePillLetterSpacing;
  final double featuredTitleSize;
  final double featuredTitleLetterSpacing;
  final double smallTitleSize;
  final double cameraTitleToStatusGap;
  final double statusPillHeight;
  final double statusPillHorizontalPadding;
  final double statusPillIconSize;
  final double statusPillInnerGap;
  final double statusPillTextSize;
  final double sectionGap;
  final double sectionLabelSize;
  final double sectionLetterSpacing;
  final double sectionLinkSize;
  final double sectionToEventsGap;
  final double eventGap;
  final double eventCardHeight;
  final double eventCardRadius;
  final double eventAccentWidth;
  final double eventLeadingGap;
  final double eventThumbSize;
  final double eventThumbRadius;
  final double eventThumbBadgeSize;
  final double eventThumbBadgeBorderWidth;
  final double eventThumbBadgeIconSize;
  final double eventTextGap;
  final double eventTitleSize;
  final double eventTitleSubtitleGap;
  final double eventSubtitleSize;
  final double eventTimeGap;
  final double eventTimeSize;
  final double eventTimeChevronGap;
  final double eventChevronSize;
  final double eventTrailingWidth;
  final double eventTrailingInset;
  final double errorCardGap;
  final double errorIconSize;
  final double errorIconGap;
  final double errorTitleSize;
  final double errorCloseSize;
  final double errorTitleGap;
  final double errorMetaSize;
  final double errorMetaGap;
  final double errorBodySize;
  final double errorButtonGap;
  final double emptyCardHeight;
  final double emptyCardIconSize;
  final double emptyCardGap;
  final double emptyCardTitleSize;
  final double emptyCardTextGap;
  final double emptyCardBodySize;
  final double emptyCardButtonGap;
  final double addTileAspectRatio;
  final double addTileRadius;
  final double addTileIconWrapSize;
  final double addTileIconSize;
  final double addTileGap;
  final double addTileTextSize;
  final double _scale;

  double scaled(double designValue) => designValue * _scale;

  double? topChipWidth(String label) {
    const widths = <String, double>{'E2EE': 63.0, '2 NEW EVENTS': 98.93};
    final designWidth = widths[label];
    return designWidth == null ? null : designWidth * _scale;
  }

  factory _ShellHomeMetrics.forWidth(double width) {
    final scale = width / 290;
    double scaled(double designValue) => designValue * scale;

    return _ShellHomeMetrics(
      pageInset: scaled(16),
      topPadding: scaled(10),
      bottomPadding: scaled(28),
      headerInsetDelta: scaled(4),
      titleSize: scaled(22),
      titleLetterSpacing: scaled(0.55),
      addButtonSize: scaled(36),
      addButtonRadius: scaled(18),
      addIconSize: scaled(18),
      headerToStatusGap: scaled(6),
      statusDotSize: scaled(6),
      statusDotGap: scaled(8),
      statusLabelSize: scaled(10),
      statusLetterSpacing: scaled(0.5),
      statusToChipGap: scaled(14),
      chipHeight: scaled(22),
      chipHorizontalPadding: scaled(10),
      chipIconSize: scaled(11),
      chipDotSize: scaled(6),
      chipInnerGap: scaled(6),
      chipTextSize: scaled(8),
      chipLetterSpacing: scaled(0.4),
      headerToCardsGap: scaled(18),
      gridGap: scaled(10),
      cameraCardRadius: scaled(16),
      cameraCardInsetStart: scaled(10),
      cameraCardInsetTop: scaled(10),
      cameraCardInsetEnd: scaled(12),
      cameraCardInsetBottom: scaled(12),
      cameraLockSize: scaled(12),
      livePillHeight: scaled(20),
      livePillHorizontalPadding: scaled(8),
      livePillDotSize: scaled(6),
      livePillInnerGap: scaled(6),
      livePillTextSize: scaled(8),
      livePillLetterSpacing: scaled(0.4),
      featuredTitleSize: scaled(14),
      featuredTitleLetterSpacing: scaled(0.35),
      smallTitleSize: scaled(13),
      cameraTitleToStatusGap: scaled(6),
      statusPillHeight: scaled(21),
      statusPillHorizontalPadding: scaled(8),
      statusPillIconSize: scaled(11),
      statusPillInnerGap: scaled(4),
      statusPillTextSize: scaled(10),
      sectionGap: scaled(16),
      sectionLabelSize: scaled(10),
      sectionLetterSpacing: scaled(1),
      sectionLinkSize: scaled(10),
      sectionToEventsGap: scaled(12),
      eventGap: scaled(8),
      eventCardHeight: scaled(66),
      eventCardRadius: scaled(12),
      eventAccentWidth: scaled(2),
      eventLeadingGap: scaled(10),
      eventThumbSize: scaled(40),
      eventThumbRadius: scaled(8),
      eventThumbBadgeSize: scaled(16),
      eventThumbBadgeBorderWidth: scaled(2),
      eventThumbBadgeIconSize: scaled(11),
      eventTextGap: scaled(12),
      eventTitleSize: scaled(13),
      eventTitleSubtitleGap: scaled(2),
      eventSubtitleSize: scaled(10),
      eventTimeGap: scaled(8),
      eventTimeSize: scaled(9),
      eventTimeChevronGap: scaled(2),
      eventChevronSize: scaled(14),
      eventTrailingWidth: scaled(46),
      eventTrailingInset: scaled(10),
      errorCardGap: scaled(16),
      errorIconSize: scaled(24),
      errorIconGap: scaled(10),
      errorTitleSize: scaled(20),
      errorCloseSize: scaled(24),
      errorTitleGap: scaled(10),
      errorMetaSize: scaled(12),
      errorMetaGap: scaled(8),
      errorBodySize: scaled(14),
      errorButtonGap: scaled(16),
      emptyCardHeight: scaled(340),
      emptyCardIconSize: scaled(78),
      emptyCardGap: scaled(18),
      emptyCardTitleSize: scaled(20),
      emptyCardTextGap: scaled(8),
      emptyCardBodySize: scaled(14),
      emptyCardButtonGap: scaled(22),
      addTileAspectRatio: 1,
      addTileRadius: scaled(16),
      addTileIconWrapSize: scaled(40),
      addTileIconSize: scaled(20),
      addTileGap: scaled(12),
      addTileTextSize: scaled(10),
      scale: scale,
    );
  }
}
