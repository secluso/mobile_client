//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/routes/activity_page.dart';
import 'package:secluso_flutter/routes/camera/list_cameras.dart';
import 'package:secluso_flutter/routes/camera/camera_ui_bridge.dart';
import 'package:secluso_flutter/routes/server_page.dart';
import 'package:secluso_flutter/routes/settings_page.dart';
import 'package:secluso_flutter/ui/secluso_preview_assets.dart';
import 'package:secluso_flutter/ui/secluso_shell_ui.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/review_environment.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialIndex = 0,
    this.preview = false,
    this.openRelayScanOnLoad = false,
    this.previewHomeHasSynced = true,
    this.previewHomeCameras,
    this.previewHomeShowNotificationWarning = false,
    this.previewHomeShowRecentError = false,
    this.previewHomeUnreadCount,
    this.previewHomeRecentEvents,
    this.previewSystemHasSynced = true,
    this.previewSystemCameraNames,
    this.previewActivityItems,
  });

  final int initialIndex;
  final bool preview;
  final bool openRelayScanOnLoad;
  final bool previewHomeHasSynced;
  final List<CameraPreviewData>? previewHomeCameras;
  final bool previewHomeShowNotificationWarning;
  final bool previewHomeShowRecentError;
  final int? previewHomeUnreadCount;
  final List<HomeRecentEventPreviewData>? previewHomeRecentEvents;
  final bool previewSystemHasSynced;
  final List<String>? previewSystemCameraNames;
  final List<ActivityPreviewItem>? previewActivityItems;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index;
  int _activityRefreshToken = 0;
  int _serverRelayScanRequestId = 0;
  bool _showSettingsAlertBadge = false;
  late final VoidCallback _errorBadgeListener;
  late final VoidCallback _reviewEnvironmentListener;
  ReviewEnvironmentSession? _reviewSession;

  bool get _isReviewMode => !widget.preview && _reviewSession != null;
  bool get _usesPreviewContent => widget.preview || _isReviewMode;

  /// First-run gating... No tabs until the relay is connected and a first camera is paired.
  late final VoidCallback _setupListener;

  bool get _setupLocked {
    if (_usesPreviewContent) return false;
    final relay = CameraUiBridge.relayConnected.value;
    final count = CameraUiBridge.cameraCount.value;
    return relay != true || count == null || count == 0;
  }

  int get _lockedIndex {
    final relay = CameraUiBridge.relayConnected.value;
    if (relay == false) return 2;
    if (relay == true && CameraUiBridge.cameraCount.value == 0) return 0;
    return _index;
  }

  Future<void> _seedSetupState() async {
    final prefs = await SharedPreferences.getInstance();
    CameraUiBridge.relayConnected.value ??=
        (prefs.getString(PrefKeys.serverAddr) ?? '').isNotEmpty;
    if (CameraUiBridge.cameraCount.value == null) {
      if (!AppStores.isInitialized) {
        await AppStores.init();
      }
      final cameras = await AppStores.instance.cameraStore.getAllAsync();
      CameraUiBridge.cameraCount.value ??= cameras.length;
    }
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _setupListener = () {
      if (!mounted) return;
      setState(() {});
    };
    CameraUiBridge.relayConnected.addListener(_setupListener);
    CameraUiBridge.cameraCount.addListener(_setupListener);
    if (!widget.preview) {
      unawaited(_seedSetupState());
    }
    _reviewSession = ReviewEnvironment.instance.session;
    _errorBadgeListener = () => _refreshSettingsAlertBadge();
    _reviewEnvironmentListener = _handleReviewEnvironmentChanged;
    ReviewEnvironment.instance.addListener(_reviewEnvironmentListener);
    Log.errorNotifier.addListener(_errorBadgeListener);
    if (!_usesPreviewContent) {
      _refreshSettingsAlertBadge();
    }
    CameraUiBridge.refreshActivityCallback = () {
      if (!mounted) return;
      setState(() {
        _activityRefreshToken++;
      });
    };
    CameraUiBridge.switchShellTabCallback = (
      index, {
      openRelayScanOnLoad = false,
    }) {
      if (!mounted) return;
      setState(() {
        _index = index;
        if (index == 1) {
          _activityRefreshToken++;
        }
        if (index == 2 && openRelayScanOnLoad) {
          _serverRelayScanRequestId++;
        }
      });
    };
  }

  @override
  void dispose() {
    CameraUiBridge.relayConnected.removeListener(_setupListener);
    CameraUiBridge.cameraCount.removeListener(_setupListener);
    ReviewEnvironment.instance.removeListener(_reviewEnvironmentListener);
    Log.errorNotifier.removeListener(_errorBadgeListener);
    if (CameraUiBridge.refreshActivityCallback != null) {
      CameraUiBridge.refreshActivityCallback = null;
    }
    if (CameraUiBridge.switchShellTabCallback != null) {
      CameraUiBridge.switchShellTabCallback = null;
    }
    super.dispose();
  }

  Future<void> _refreshSettingsAlertBadge() async {
    if (_usesPreviewContent) return;
    final enabled = await Log.errorNotificationsEnabled();
    final showBadge = enabled && await Log.hasUnseenRecentError();
    if (!mounted) return;
    setState(() {
      _showSettingsAlertBadge = showBadge;
    });
  }

  void _handleTabTap(int index) {
    final previousIndex = _index;
    setState(() {
      _index = index;
      if (index == 1) {
        _activityRefreshToken++;
      }
    });
    if (!_usesPreviewContent && previousIndex == 3 && index != 3) {
      Log.markCurrentErrorSeen();
    }
  }

  void _handleReviewEnvironmentChanged() {
    if (!mounted) {
      return;
    }
    final previousReviewMode = _isReviewMode;
    setState(() {
      _reviewSession = ReviewEnvironment.instance.session;
    });
    if (previousReviewMode && !_isReviewMode) {
      _refreshSettingsAlertBadge();
    }
  }

  List<CameraPreviewData> _defaultPreviewHomeCameras() {
    return const [
      CameraPreviewData(
        name: 'Front Door',
        unreadMessages: true,
        previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
        statusLabel: 'Person · 2m',
        recentActivityTitle: 'Person Detected',
        recentActivityTimeLabel: '2m ago',
      ),
      CameraPreviewData(
        name: 'Living Room',
        previewAssetPath: SeclusoPreviewAssets.designLivingRoom,
        statusLabel: 'Quiet',
      ),
      CameraPreviewData(
        name: 'Backyard',
        unreadMessages: true,
        previewAssetPath: SeclusoPreviewAssets.designBackyard,
        statusLabel: 'Motion · 14m',
        recentActivityTitle: 'Motion',
        recentActivityTimeLabel: '14m ago',
      ),
    ];
  }

  List<ActivityPreviewItem> _defaultPreviewActivityItems() {
    return const [
      ActivityPreviewItem(
        cameraName: 'Front Door',
        videoName: '2:34 PM',
        previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
        detections: {'human'},
        durationLabel: '0:12',
        sectionLabel: 'TODAY',
      ),
      ActivityPreviewItem(
        cameraName: 'Backyard',
        videoName: '2:20 PM',
        previewAssetPath: SeclusoPreviewAssets.designBackyard,
        detections: {},
        durationLabel: '0:08',
        sectionLabel: 'TODAY',
      ),
      ActivityPreviewItem(
        cameraName: 'Front Door',
        videoName: '11:15 AM',
        previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
        detections: {'human'},
        durationLabel: '0:22',
        sectionLabel: 'TODAY',
      ),
      ActivityPreviewItem(
        cameraName: '',
        videoName: '6:00 PM',
        detections: {},
        title: 'System',
        subtitle: 'Armed (Away) · 6:00 PM',
        sectionLabel: 'YESTERDAY',
        isSystem: true,
      ),
      ActivityPreviewItem(
        cameraName: 'Living Room',
        videoName: '3:45 PM',
        previewAssetPath: SeclusoPreviewAssets.designLivingRoom,
        detections: {},
        durationLabel: '0:06',
        sectionLabel: 'YESTERDAY',
      ),
      ActivityPreviewItem(
        cameraName: 'Front Door',
        videoName: 'Mon 9:12 AM',
        previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
        detections: {'human'},
        durationLabel: '0:18',
        sectionLabel: 'EARLIER THIS WEEK',
      ),
    ];
  }

  List<CameraPreviewData> _reviewHomeCameras(ReviewEnvironmentSession session) {
    return session.cameras
        .map((camera) {
          final previewVideos = <Video>[];
          final previewDetectionsByVideo = <String, Set<String>>{};
          final previewThumbAssetsByVideo = <String, String>{};
          final previewVideoAssetsByVideo = <String, String>{};
          final previewDurationByVideo = <String, Duration>{};
          for (var i = 0; i < camera.clips.length; i++) {
            final clip = camera.clips[i];
            previewVideos.add(
              Video(camera.name, clip.videoFile, true, clip.motion, id: i + 1),
            );
            previewDetectionsByVideo[clip.videoFile] = clip.detections;
            previewThumbAssetsByVideo[clip.videoFile] = clip.previewAssetPath;
            final videoAssetPath = clip.videoAssetPath;
            if (videoAssetPath != null) {
              previewVideoAssetsByVideo[clip.videoFile] = videoAssetPath;
            }
            previewDurationByVideo[clip.videoFile] = clip.duration;
          }
          return CameraPreviewData(
            name: camera.name,
            unreadMessages: camera.hasUnreadActivity,
            previewAssetPath: camera.livePreviewAssetPath,
            statusLabel: camera.statusLabel,
            recentActivityTitle: camera.recentActivityTitle,
            recentActivityTimeLabel: camera.recentActivityTimeLabel,
            previewVideos: previewVideos,
            previewDetectionsByVideo: previewDetectionsByVideo,
            previewThumbAssetsByVideo: previewThumbAssetsByVideo,
            previewVideoAssetsByVideo: previewVideoAssetsByVideo,
            previewDurationByVideo: previewDurationByVideo,
            previewHeroAssetPath: camera.livePreviewAssetPath,
            previewHeroVideoAssetPath: camera.livePreviewVideoAssetPath,
          );
        })
        .toList(growable: false);
  }

  List<HomeRecentEventPreviewData> _reviewRecentEvents(
    ReviewEnvironmentSession session,
  ) {
    final events = <HomeRecentEventPreviewData>[];
    for (final camera in session.cameras) {
      for (final clip in camera.clips) {
        final hasPerson =
            clip.detections.contains('human') ||
            clip.detections.contains('person');
        events.add(
          HomeRecentEventPreviewData(
            title: hasPerson ? 'Person detected' : 'Motion detected',
            subtitle: camera.name,
            timeLabel: clip.timeLabel,
            previewAssetPath: clip.previewAssetPath,
            previewVideoAssetPath: clip.videoAssetPath,
            accentColor:
                hasPerson ? const Color(0xFF8BB3EE) : const Color(0xFF6B7280),
            videoName: clip.videoFile,
            detections: clip.detections,
            motion: clip.motion,
            canDownload: true,
            hasVideoFile: true,
          ),
        );
      }
    }
    return events.take(3).toList(growable: false);
  }

  List<ActivityPreviewItem> _reviewActivityItems(
    ReviewEnvironmentSession session,
  ) {
    final items = <ActivityPreviewItem>[];
    for (final camera in session.cameras) {
      for (final clip in camera.clips) {
        items.add(
          ActivityPreviewItem(
            cameraName: camera.name,
            videoName: clip.videoFile,
            previewAssetPath: clip.previewAssetPath,
            previewVideoAssetPath: clip.videoAssetPath,
            detections: clip.detections,
            motion: clip.motion,
            durationLabel:
                '0:${clip.duration.inSeconds.toString().padLeft(2, '0')}',
            sectionLabel: clip.sectionLabel,
          ),
        );
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    const designNavWidth = 310.0;
    const designNavHeight = 76.0;
    final navHeight =
        MediaQuery.sizeOf(context).width / designNavWidth * designNavHeight;
    final reviewSession = _reviewSession;
    final previewHomeHasSynced =
        widget.preview ? widget.previewHomeHasSynced : reviewSession != null;
    final previewHomeCameras =
        widget.preview
            ? (widget.previewHomeCameras ?? _defaultPreviewHomeCameras())
            : (reviewSession == null
                ? const <CameraPreviewData>[]
                : _reviewHomeCameras(reviewSession));
    final previewHomeRecentEvents =
        widget.preview
            ? widget.previewHomeRecentEvents
            : (reviewSession == null
                ? const <HomeRecentEventPreviewData>[]
                : _reviewRecentEvents(reviewSession));
    final previewActivityItems =
        widget.preview
            ? (widget.previewActivityItems ?? _defaultPreviewActivityItems())
            : (reviewSession == null
                ? const <ActivityPreviewItem>[]
                : _reviewActivityItems(reviewSession));
    final previewSystemHasSynced =
        widget.preview ? widget.previewSystemHasSynced : reviewSession != null;
    final previewServerAddr =
        widget.preview
            ? 'relay.local:8443'
            : (reviewSession?.relayAddress ?? 'review.secluso.com');
    final previewSystemCameraNames =
        widget.preview
            ? widget.previewSystemCameraNames
            : (reviewSession?.cameraNames ?? const <String>[]);
    final previewSignature =
        widget.preview
            ? 'design:${widget.previewHomeHasSynced}:${widget.previewHomeCameras.hashCode}:${widget.previewHomeRecentEvents.hashCode}:${widget.previewActivityItems.hashCode}:${widget.previewSystemCameraNames.hashCode}'
            : 'review:${reviewSession?.relayId ?? 'none'}:${reviewSession?.cameraNames.join('|') ?? ''}:${reviewSession?.relayAddress ?? ''}';
    final tabs = <Widget>[
      _usesPreviewContent
          ? CamerasPage(
            key: ValueKey('shell-home-$previewSignature'),
            shellMode: true,
            previewServerHasSynced: previewHomeHasSynced,
            previewShowNotificationWarning:
                widget.previewHomeShowNotificationWarning,
            previewShowRecentError: widget.previewHomeShowRecentError,
            previewUnreadCount:
                widget.preview
                    ? widget.previewHomeUnreadCount
                    : previewHomeCameras
                        .where((camera) => camera.unreadMessages)
                        .length,
            previewRecentEvents: previewHomeRecentEvents,
            previewCameras: previewHomeCameras,
          )
          : const CamerasPage(shellMode: true),
      _usesPreviewContent
          ? ActivityPage(
            key: ValueKey('shell-activity-$previewSignature'),
            shellMode: true,
            refreshToken: _activityRefreshToken,
            previewItems: previewActivityItems,
          )
          : ActivityPage(shellMode: true, refreshToken: _activityRefreshToken),
      _usesPreviewContent
          ? ServerPage(
            key: ValueKey('shell-system-$previewSignature'),
            showBackButton: false,
            showShellChrome: true,
            openRelayScanOnLoad: widget.openRelayScanOnLoad,
            relayScanRequestId: _serverRelayScanRequestId,
            previewHasSynced: previewSystemHasSynced,
            previewServerAddr: previewServerAddr,
            previewCameraNames: previewSystemCameraNames,
          )
          : ServerPage(
            showBackButton: false,
            showShellChrome: true,
            openRelayScanOnLoad: widget.openRelayScanOnLoad,
            relayScanRequestId: _serverRelayScanRequestId,
          ),
      widget.preview
          ? SettingsPage(
            key: ValueKey('shell-settings-$previewSignature'),
            showShellChrome: true,
            previewNightTheme: true,
            previewNotificationsOn: true,
          )
          : const SettingsPage(showShellChrome: true),
    ];
    final navBar = ShellBottomNav(
      currentIndex: _index,
      activityBadgeCount:
          _usesPreviewContent
              ? (previewActivityItems.isNotEmpty
                  ? previewActivityItems.length.clamp(1, 9)
                  : null)
              : null,
      settingsAlertBadge: _usesPreviewContent ? false : _showSettingsAlertBadge,
      onTap: _handleTabTap,
    );

    final locked = _setupLocked;
    final index = locked ? _lockedIndex : _index;

    return ShellScaffold(
      safeTop: false,
      body: Stack(
        children: [
          Positioned.fill(
            bottom: (locked || index == 0) ? 0 : navHeight,
            child: IndexedStack(index: index, children: tabs),
          ),
          if (!locked) Positioned(left: 0, right: 0, bottom: 0, child: navBar),
        ],
      ),
    );
  }
}
