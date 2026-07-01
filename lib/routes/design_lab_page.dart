//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/routes/app_drawer.dart';
import 'package:secluso_flutter/routes/activity_page.dart';
import 'package:secluso_flutter/routes/app_shell.dart';
import 'package:secluso_flutter/routes/camera/list_cameras.dart';
import 'package:secluso_flutter/routes/camera/camera_settings.dart'
    as camera_settings;
import 'package:secluso_flutter/routes/camera/new/ip_camera_option.dart';
import 'package:secluso_flutter/routes/camera/new/proprietary_camera_option.dart';
import 'package:secluso_flutter/routes/camera/new/proprietary_camera_waiting.dart';
import 'package:secluso_flutter/routes/camera/new/qr_scan.dart';
import 'package:secluso_flutter/routes/camera/view_camera.dart';
import 'package:secluso_flutter/routes/camera/view_livestream.dart';
import 'package:secluso_flutter/routes/camera/view_video.dart';
import 'package:secluso_flutter/routes/server_page.dart';
import 'package:secluso_flutter/routes/system_shell_page.dart';
import 'package:secluso_flutter/routes/camera-role/camera_role_pages.dart';
import 'package:secluso_flutter/routes/onboarding/walkthrough_page.dart';
import 'package:secluso_flutter/routes/settings_page.dart' as app_settings;
import 'package:secluso_flutter/ui/secluso_preview_assets.dart';
import 'package:secluso_flutter/routes/theme_provider.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_theme.dart';
import 'package:secluso_flutter/utilities/review_environment.dart';
import 'package:secluso_flutter/utilities/storage_manager.dart';

const _designReviewSession = ReviewEnvironmentSession(
  relayId: 'app-review-2026',
  relayLabel: 'Secluso Review Relay',
  relayAddress: 'https://testing-relay.secluso.com',
  cameras: [
    ReviewCameraFixture(
      id: 'review-front-door-01',
      name: 'Front Door',
      profileId: 'front-door',
      livePreviewAssetPath: SeclusoPreviewAssets.designFrontDoor,
      livePreviewVideoAssetPath: SeclusoPreviewAssets.reviewFrontDoorClip,
      statusLabel: 'Person · 2m',
      recentActivityTitle: 'Person detected',
      recentActivityTimeLabel: '2m ago',
      hasUnreadActivity: true,
      clips: [
        ReviewClipFixture(
          videoFile: 'video_1774540440.mp4',
          previewAssetPath: SeclusoPreviewAssets.hallwayEvent,
          videoAssetPath: SeclusoPreviewAssets.reviewFrontDoorClip,
          detections: {'human'},
          motion: true,
          duration: Duration(seconds: 16),
          timeLabel: '2:34 PM',
          sectionLabel: 'TODAY',
        ),
        ReviewClipFixture(
          videoFile: 'video_1774539600.mp4',
          previewAssetPath: SeclusoPreviewAssets.foyerEvent,
          videoAssetPath: SeclusoPreviewAssets.reviewFrontDoorClip,
          detections: {},
          motion: true,
          duration: Duration(seconds: 16),
          timeLabel: '2:20 PM',
          sectionLabel: 'TODAY',
        ),
        ReviewClipFixture(
          videoFile: 'video_1774261920.mp4',
          previewAssetPath: SeclusoPreviewAssets.deliveryNookEvent,
          videoAssetPath: SeclusoPreviewAssets.reviewFrontDoorClip,
          detections: {'human'},
          motion: true,
          duration: Duration(seconds: 16),
          timeLabel: 'Mon 9:12 AM',
          sectionLabel: 'EARLIER THIS WEEK',
        ),
      ],
    ),
  ],
);

List<CameraPreviewData> _reviewHomePreviewCameras(
  ReviewEnvironmentSession session,
) {
  return session.cameras
      .map(
        (camera) => CameraPreviewData(
          name: camera.name,
          unreadMessages: camera.hasUnreadActivity,
          previewAssetPath: camera.livePreviewAssetPath,
          statusLabel: camera.statusLabel,
          recentActivityTitle: camera.recentActivityTitle,
          recentActivityTimeLabel: camera.recentActivityTimeLabel,
        ),
      )
      .toList(growable: false);
}

List<HomeRecentEventPreviewData> _reviewRecentEventPreviews(
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

List<ActivityPreviewItem> _reviewActivityPreviewItems(
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

CameraViewPage _reviewCameraDetailPreview(ReviewCameraFixture camera) {
  final previewVideos = <Video>[];
  final previewDetectionsByVideo = <String, Set<String>>{};
  final previewThumbAssetsByVideo = <String, String>{};
  final previewVideoAssetsByVideo = <String, String>{};
  final previewDurationByVideo = <String, Duration>{};

  for (final clip in camera.clips) {
    previewVideos.add(Video(camera.name, clip.videoFile, true, clip.motion));
    previewDetectionsByVideo[clip.videoFile] = clip.detections;
    previewThumbAssetsByVideo[clip.videoFile] = clip.previewAssetPath;
    final videoAssetPath = clip.videoAssetPath;
    if (videoAssetPath != null) {
      previewVideoAssetsByVideo[clip.videoFile] = videoAssetPath;
    }
    previewDurationByVideo[clip.videoFile] = clip.duration;
  }

  return CameraViewPage(
    cameraName: camera.name,
    previewVideos: previewVideos,
    previewDetectionsByVideo: previewDetectionsByVideo,
    previewThumbAssetsByVideo: previewThumbAssetsByVideo,
    previewVideoAssetsByVideo: previewVideoAssetsByVideo,
    previewDurationByVideo: previewDurationByVideo,
    previewHeroAssetPath: camera.livePreviewAssetPath,
    previewHeroVideoAssetPath: camera.livePreviewVideoAssetPath,
  );
}

Widget? designLabTargetPage(String target, {String themeName = 'dark'}) {
  final isLight = themeName == 'light';
  final reviewSession = _designReviewSession;
  final reviewCamera = reviewSession.cameras.first;
  final reviewActivityItems = _reviewActivityPreviewItems(reviewSession);
  final reviewHomeCameras = _reviewHomePreviewCameras(reviewSession);
  final reviewRecentEvents = _reviewRecentEventPreviews(reviewSession);
  final reviewClip = reviewCamera.clips.first;
  final previewVideos = <Video>[
    Video('Front Door', '2:34 PM', true, true, id: 1),
    Video('Front Door', '11:02 AM', true, true, id: 2),
    Video('Front Door', 'Yesterday', true, true, id: 3),
  ];
  const previewThumbAssets = <String, String>{
    '2:34 PM': SeclusoPreviewAssets.designFrontDoor,
    '11:02 AM': SeclusoPreviewAssets.designBackyard,
    'Yesterday': SeclusoPreviewAssets.designLivingRoom,
  };
  const previewDurations = <String, Duration>{
    '2:34 PM': Duration(seconds: 12),
    '11:02 AM': Duration(seconds: 8),
    'Yesterday': Duration(seconds: 22),
  };
  const previewDetections = <String, Set<String>>{
    '2:34 PM': {'human'},
    '11:02 AM': {},
    'Yesterday': {'human'},
  };

  switch (target) {
    case 'cameras_relay_missing':
      return const CamerasPage(previewServerHasSynced: false);
    case 'home_shell_no_relay_dark':
    case 'home_shell_no_relay_light':
      return const AppShell(
        preview: true,
        previewHomeHasSynced: false,
        previewHomeCameras: [],
        previewHomeUnreadCount: 0,
        previewActivityItems: [],
      );
    case 'home_shell_no_cameras':
      return const AppShell(
        preview: true,
        previewHomeHasSynced: true,
        previewHomeCameras: [],
        previewHomeUnreadCount: 0,
        previewActivityItems: [],
      );
    case 'home_shell_error':
      return const AppShell(
        preview: true,
        previewHomeShowRecentError: true,
        previewHomeUnreadCount: 2,
        previewHomeRecentEvents: [
          HomeRecentEventPreviewData(
            title: 'Person Detected',
            subtitle: 'Front Door',
            timeLabel: '2m ago',
            previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
            accentColor: Color(0xFF8BB3EE),
          ),
          HomeRecentEventPreviewData(
            title: 'Motion',
            subtitle: 'Backyard',
            timeLabel: '14m ago',
            previewAssetPath: SeclusoPreviewAssets.designBackyard,
            accentColor: Color(0xFF60A5FA),
          ),
        ],
        previewHomeCameras: [
          CameraPreviewData(
            name: 'Front Door',
            unreadMessages: true,
            previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
            statusLabel: 'Person · 2m',
          ),
          CameraPreviewData(
            name: 'Living Room',
            previewAssetPath: SeclusoPreviewAssets.designLivingRoom,
            statusLabel: 'Quiet',
          ),
          CameraPreviewData(
            name: 'Backyard',
            previewAssetPath: SeclusoPreviewAssets.designBackyard,
            statusLabel: 'Motion · 14m',
          ),
        ],
      );
    case 'home_shell_offline':
      return const AppShell(
        preview: true,
        previewHomeShowNotificationWarning: true,
        previewHomeUnreadCount: 2,
        previewHomeCameras: [
          CameraPreviewData(
            name: 'Front Door',
            unreadMessages: true,
            previewAssetPath: SeclusoPreviewAssets.previewFrontDoor,
          ),
          CameraPreviewData(
            name: 'Living Room',
            previewAssetPath: SeclusoPreviewAssets.tabletopCamera,
          ),
          CameraPreviewData(
            name: 'Backyard',
            previewAssetPath: SeclusoPreviewAssets.homeOfficeFeed,
          ),
        ],
      );
    case 'control_room':
      return const AppShell(preview: true);
    case 'review_control_room':
      return AppShell(
        preview: true,
        previewHomeHasSynced: true,
        previewHomeUnreadCount:
            reviewHomeCameras.where((camera) => camera.unreadMessages).length,
        previewHomeCameras: reviewHomeCameras,
        previewHomeRecentEvents: reviewRecentEvents,
        previewActivityItems: reviewActivityItems,
        previewSystemHasSynced: true,
        previewSystemCameraNames: reviewSession.cameraNames,
      );
    case 'home_shell_two_cameras':
      return const AppShell(
        preview: true,
        previewHomeUnreadCount: 2,
        previewHomeCameras: [
          CameraPreviewData(
            name: 'Front Door',
            unreadMessages: true,
            previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
          ),
          CameraPreviewData(
            name: 'Living Room',
            previewAssetPath: SeclusoPreviewAssets.designLivingRoom,
          ),
        ],
        previewHomeRecentEvents: [
          HomeRecentEventPreviewData(
            title: 'Person Detected',
            subtitle: 'Front Door',
            timeLabel: '2m ago',
            previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
            accentColor: Color(0xFF8BB3EE),
          ),
          HomeRecentEventPreviewData(
            title: 'Motion',
            subtitle: 'Backyard',
            timeLabel: '14m ago',
            previewAssetPath: SeclusoPreviewAssets.designBackyard,
            accentColor: Color(0xFF60A5FA),
          ),
        ],
      );
    case 'home_shell_placeholder':
      return const AppShell(
        preview: true,
        previewHomeUnreadCount: 2,
        previewHomeCameras: [
          CameraPreviewData(
            name: 'Front Door',
            unreadMessages: true,
            previewAssetPath: null,
          ),
          CameraPreviewData(
            name: 'Nursery',
            unreadMessages: true,
            previewAssetPath: null,
          ),
        ],
        previewHomeRecentEvents: [
          HomeRecentEventPreviewData(
            title: 'Person Detected',
            subtitle: 'Front Door',
            timeLabel: '2m ago',
            previewAssetPath: '',
            accentColor: Color(0xFF8BB3EE),
          ),
          HomeRecentEventPreviewData(
            title: 'Motion',
            subtitle: 'Backyard',
            timeLabel: '14m ago',
            previewAssetPath: '',
            accentColor: Color(0xFF60A5FA),
          ),
        ],
      );
    case 'home_shell_one_camera':
      return const AppShell(
        preview: true,
        previewHomeUnreadCount: 2,
        previewHomeCameras: [
          CameraPreviewData(
            name: 'Front Door',
            unreadMessages: true,
            previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
            statusLabel: 'Person · 2m',
          ),
        ],
        previewHomeRecentEvents: [
          HomeRecentEventPreviewData(
            title: 'Person Detected',
            subtitle: 'Front Door',
            timeLabel: '2m ago',
            previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
            accentColor: Color(0xFF8BB3EE),
          ),
          HomeRecentEventPreviewData(
            title: 'Motion',
            subtitle: 'Backyard',
            timeLabel: '14m ago',
            previewAssetPath: '',
            accentColor: Color(0xFF60A5FA),
          ),
        ],
      );
    case 'home_shell_one_camera_empty_dark':
      return const AppShell(
        preview: true,
        previewHomeUnreadCount: 0,
        previewHomeCameras: [
          CameraPreviewData(
            name: 'Front Door',
            previewAssetPath: null,
            statusLabel: null,
          ),
        ],
        previewHomeRecentEvents: [],
      );
    case 'home_shell_three_cameras':
      return const AppShell(
        preview: true,
        previewHomeUnreadCount: 2,
        previewHomeCameras: [
          CameraPreviewData(
            name: 'Front Door',
            unreadMessages: true,
            previewAssetPath: SeclusoPreviewAssets.previewFrontDoor,
          ),
          CameraPreviewData(
            name: 'Living Room',
            previewAssetPath: SeclusoPreviewAssets.tabletopCamera,
          ),
          CameraPreviewData(
            name: 'Backyard',
            previewAssetPath: SeclusoPreviewAssets.homeOfficeFeed,
          ),
        ],
      );
    case 'home_shell_four_cameras':
      return const AppShell(
        preview: true,
        previewHomeUnreadCount: 2,
        previewHomeCameras: [
          CameraPreviewData(
            name: 'Front Door',
            unreadMessages: true,
            previewAssetPath: SeclusoPreviewAssets.previewFrontDoor,
          ),
          CameraPreviewData(
            name: 'Living Room',
            previewAssetPath: SeclusoPreviewAssets.tabletopCamera,
          ),
          CameraPreviewData(
            name: 'Backyard',
            previewAssetPath: SeclusoPreviewAssets.homeOfficeFeed,
          ),
          CameraPreviewData(name: 'Garage', previewAssetPath: null),
        ],
      );
    case 'activity_overview':
      return const AppShell(initialIndex: 1, preview: true);
    case 'review_activity_overview':
      return AppShell(
        initialIndex: 1,
        preview: true,
        previewHomeHasSynced: true,
        previewHomeUnreadCount:
            reviewHomeCameras.where((camera) => camera.unreadMessages).length,
        previewHomeCameras: reviewHomeCameras,
        previewHomeRecentEvents: reviewRecentEvents,
        previewActivityItems: reviewActivityItems,
        previewSystemHasSynced: true,
        previewSystemCameraNames: reviewSession.cameraNames,
      );
    case 'activity_empty':
      return const AppShell(
        initialIndex: 1,
        preview: true,
        previewActivityItems: [],
      );
    case 'system_overview':
      return const AppShell(initialIndex: 2, preview: true);
    case 'review_system_linked':
      return ServerPage(
        showBackButton: false,
        showShellChrome: true,
        previewHasSynced: true,
        previewServerAddr: reviewSession.relayAddress,
        previewCameraNames: reviewSession.cameraNames,
      );
    case 'walkthrough_1':
    case 'walkthrough_2':
    case 'walkthrough_3':
    case 'walkthrough_4':
    case 'walkthrough_5':
      return WalkthroughPage(
        onDone: () {},
        initialIndex: int.parse(target.split('_').last) - 1,
      );
    case 'role_select':
      return Builder(
        builder:
            (context) => RoleSelectPage(
              onWatchCameras: () {},
              onBeCamera:
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CameraRolePairingPage(),
                    ),
                  ),
            ),
      );
    case 'camera_role_pairing':
      return const CameraRolePairingPage();
    case 'camera_role_recording':
      return const CameraRoleRecordingPage();
    case 'system_unpaired':
      return const AppShell(
        initialIndex: 2,
        preview: true,
        previewSystemHasSynced: false,
      );
    case 'settings_overview':
      return const AppShell(initialIndex: 3, preview: true);
    case 'review_settings_overview':
      return AppShell(
        initialIndex: 3,
        preview: true,
        previewHomeHasSynced: true,
        previewHomeUnreadCount:
            reviewHomeCameras.where((camera) => camera.unreadMessages).length,
        previewHomeCameras: reviewHomeCameras,
        previewHomeRecentEvents: reviewRecentEvents,
        previewActivityItems: reviewActivityItems,
        previewSystemHasSynced: true,
        previewSystemCameraNames: reviewSession.cameraNames,
      );
    case 'cameras_ready':
      return const CamerasPage(previewServerHasSynced: true);
    case 'cameras_populated':
      return const CamerasPage(
        previewServerHasSynced: true,
        previewCameras: [
          CameraPreviewData(
            name: 'Living room',
            unreadMessages: true,
            previewAssetPath: SeclusoPreviewAssets.livingRoomHero,
          ),
          CameraPreviewData(
            name: 'Home office',
            previewAssetPath: SeclusoPreviewAssets.homeOfficeFeed,
          ),
          CameraPreviewData(
            name: 'Archive room',
            previewAssetPath: SeclusoPreviewAssets.storageFeed,
          ),
          CameraPreviewData(
            name: 'Entry corridor',
            previewAssetPath: SeclusoPreviewAssets.corridorFeed,
          ),
        ],
      );
    case 'add_camera':
    case 'scan_qr_page':
      return const QrScanPage();
    case 'server_linked':
      return const ServerPage(
        showBackButton: true,
        previewHasSynced: true,
        previewServerAddr: 'http://secluso.relay:8000',
      );
    case 'server_pairing':
      return const ServerPage(showBackButton: true, previewHasSynced: false);
    case 'camera_detail':
      return CameraViewPage(
        cameraName: 'Front Door',
        previewVideos: isLight ? const <Video>[] : previewVideos,
        previewDetectionsByVideo:
            isLight ? const <String, Set<String>>{} : previewDetections,
        previewThumbAssetsByVideo:
            isLight ? const <String, String>{} : previewThumbAssets,
        previewDurationByVideo:
            isLight ? const <String, Duration>{} : previewDurations,
        previewHeroAssetPath: SeclusoPreviewAssets.designFrontDoor,
      );
    case 'review_camera_detail':
      return _reviewCameraDetailPreview(reviewCamera);
    case 'camera_detail_empty_dark':
      return const CameraViewPage(
        cameraName: 'Front Door',
        previewVideos: <Video>[],
        previewDetectionsByVideo: <String, Set<String>>{},
        previewThumbAssetsByVideo: <String, String>{},
        previewDurationByVideo: <String, Duration>{},
        previewHeroAssetPath: SeclusoPreviewAssets.designFrontDoor,
      );
    case 'video_viewer':
      return const VideoViewPage(
        cameraName: 'Front Door',
        videoTitle: '2:34 PM',
        visibleVideoTitle: 'Today · 2:34 PM',
        canDownload: true,
        isLivestream: false,
        previewAssetPath: SeclusoPreviewAssets.previewFrontDoor,
        previewDetections: {'human'},
        previewDuration: Duration(seconds: 12),
        previewPosition: Duration(seconds: 4),
      );
    case 'review_clip_viewer':
      return VideoViewPage(
        cameraName: reviewCamera.name,
        videoTitle: reviewClip.videoFile,
        visibleVideoTitle: 'Today · ${reviewClip.timeLabel}',
        canDownload: true,
        isLivestream: false,
        previewAssetPath: reviewClip.previewAssetPath,
        previewVideoAssetPath: reviewClip.videoAssetPath,
        previewDetections: reviewClip.detections,
        previewDuration: reviewClip.duration,
        previewPosition: const Duration(seconds: 4),
      );
    case 'livestream_viewer':
      return const LivestreamPage(
        cameraName: 'Front Door',
        previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
      );
    case 'review_livestream_viewer':
      return LivestreamPage(
        cameraName: reviewCamera.name,
        previewAssetPath: reviewCamera.livePreviewAssetPath,
        previewVideoAssetPath: reviewCamera.livePreviewVideoAssetPath,
      );
    case 'livestream_error':
      return const LivestreamPage(
        cameraName: 'Living Room',
        previewStreaming: false,
        previewErrorMessage:
            "The peer-to-peer connection to Living Room couldn't be established.",
      );
    case 'app_settings':
      return const app_settings.SettingsPage(
        showShellChrome: true,
        previewNightTheme: true,
        previewNotificationsOn: true,
      );
    case 'settings_top':
      return const app_settings.SettingsPage(
        showShellChrome: true,
        previewNightTheme: true,
        previewNotificationsOn: true,
        previewScrollPosition: app_settings.SettingsPreviewScrollPosition.top,
      );
    case 'settings_bottom':
      return const app_settings.SettingsPage(
        showShellChrome: true,
        previewNightTheme: true,
        previewNotificationsOn: true,
        previewScrollPosition:
            app_settings.SettingsPreviewScrollPosition.bottom,
      );
    case 'settings_very_bottom':
      return const app_settings.SettingsPage(
        showShellChrome: true,
        previewNightTheme: true,
        previewNotificationsOn: true,
        previewScrollPosition:
            app_settings.SettingsPreviewScrollPosition.veryBottom,
      );
    case 'storage_manage':
      return const app_settings.StorageSettingsPage(
        initialSummary: StorageSummary(
          totalBytes: 1058013184,
          videoBytes: 888143872,
          thumbnailBytes: 130023424,
          encryptedBytes: 39845888,
          otherBytes: 0,
          videoCount: 148,
          thumbnailCount: 148,
        ),
        initialAutoCleanupEnabled: true,
        initialRetentionDays: 30,
      );
    case 'camera_settings':
      return const camera_settings.SettingsPage(
        cameraName: 'Front Door',
        previewFirmwareVersion: '1.4.2',
        previewOsVersion: '1.0.2',
        previewSelectedResolution: '4K',
        previewSelectedFps: 30,
        previewNotificationsEnabled: true,
        previewSelectedNotificationEvents: {'Humans', 'Vehicles'},
      );
    case 'drawer_preview':
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: 340, child: AppDrawer(onNavigate: (_) {})),
        ),
      );
    case 'dialog_secluso_connect':
      return const ProprietaryCameraConnectDialog(
        hotspotPassword: 'password123',
      );
    case 'dialog_secluso_setup':
      return const ProprietaryCameraInfoDialog(previewMode: true);
    case 'dialog_secluso_pairing':
      return const ProprietaryCameraWaitingDialog(
        cameraName: 'Front Door',
        wifiSsid: 'Home WiFi',
        wifiPassword: 'password123',
        previewMode: true,
        hotspotPassword: "password123",
      );
    case 'dialog_secluso_pairing_failed':
      return const ProprietaryCameraWaitingDialog(
        cameraName: 'Front Door',
        wifiSsid: 'Home WiFi',
        wifiPassword: 'password123',
        previewMode: true,
        hotspotPassword: "password123",
        previewState: ProprietaryPairingPreviewState.failure,
      );
    case 'dialog_secluso_paired':
      return const ProprietaryCameraPairedPage(cameraName: 'Front Door');
    case 'review_camera_paired':
      return ProprietaryCameraPairedPage(cameraName: reviewCamera.name);
    case 'dialog_ip_import':
      return const IpCameraDialog();
    case 'dialog_qr_scan':
      return const _DesignLabDialogHost(
        title: 'QR scan dialog',
        builder: _qrScanDialogBuilder,
      );
    default:
      return null;
  }
}

Widget _qrScanDialogBuilder(BuildContext context) =>
    const QrScanDialog(previewAssetPath: SeclusoPreviewAssets.pairingCard);

class DesignCommandPage extends StatefulWidget {
  const DesignCommandPage({
    super.key,
    required this.commandFilePath,
    this.initialTarget = 'cameras_ready',
  });

  final String commandFilePath;
  final String initialTarget;

  @override
  State<DesignCommandPage> createState() => _DesignCommandPageState();
}

class _DesignCommandPageState extends State<DesignCommandPage> {
  Timer? _pollTimer;
  String _activeTarget = '';
  String? _lastCommand;
  int _commandRevision = 0;
  String? _activeTheme;

  @override
  void initState() {
    super.initState();
    _activeTarget = widget.initialTarget;
    unawaited(_primeCommandFile());
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 350),
      (_) => unawaited(_pollCommandFile()),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _primeCommandFile() async {
    final file = File(widget.commandFilePath);
    try {
      await file.parent.create(recursive: true);
      if (!await file.exists()) {
        await file.writeAsString('${widget.initialTarget}\n');
      }
      await _pollCommandFile();
    } catch (_) {}
  }

  Future<void> _pollCommandFile() async {
    final file = File(widget.commandFilePath);
    if (!await file.exists()) return;

    try {
      final raw = await file.readAsString();
      if (raw == _lastCommand) return;
      _lastCommand = raw;

      final lines = raw.split('\n').map((line) => line.trim()).toList();
      final target = lines.firstWhere(
        (line) => line.isNotEmpty && !line.startsWith('theme='),
        orElse: () => '',
      );
      final themeLine = lines.firstWhere(
        (line) => line.startsWith('theme='),
        orElse: () => '',
      );
      if (target.isEmpty || !mounted) return;

      final themeName = themeLine.replaceFirst('theme=', '');
      if (themeName == 'light' || themeName == 'dark') {
        if (_activeTheme != themeName) {
          _activeTheme = themeName;
          Provider.of<ThemeProvider>(
            context,
            listen: false,
          ).setTheme(themeName == 'dark');
        }
      }

      setState(() {
        _activeTarget = target;
        _commandRevision++;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final themeName =
        _activeTheme ??
        (Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light');
    final page =
        designLabTargetPage(_activeTarget, themeName: themeName) ??
        const DesignLabPage();
    return Navigator(
      key: ValueKey('design-command-nav-$_activeTarget-$_commandRevision'),
      onGenerateRoute:
          (_) => MaterialPageRoute<void>(
            builder:
                (_) => KeyedSubtree(
                  key: ValueKey(
                    'design-command-target-$_activeTarget-$_commandRevision',
                  ),
                  child: page,
                ),
          ),
    );
  }
}

class DesignLabPage extends StatelessWidget {
  const DesignLabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SeclusoScaffold(
      appBar: seclusoAppBar(
        context,
        title: 'Design Lab',
        leading:
            Navigator.of(context).canPop()
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
                : null,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              'Debug tools'.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: SeclusoColors.blue,
                letterSpacing: 2.3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Stable screens for fast UI iteration.',
              style: theme.textTheme.headlineSmall?.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              'Open production screens with fixed mock state so layout review does not depend on live camera, relay, Wi-Fi, or QR flows.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            _LabSection(
              title: 'Core screens',
              children: [
                _LabEntry(
                  title: 'Shell / control room',
                  subtitle:
                      'Primary luxury navigation shell with hero overview.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('control_room')!,
                      ),
                ),
                _LabEntry(
                  title: 'Shell / activity',
                  subtitle:
                      'Archive-first review destination inside the shell.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('activity_overview')!,
                      ),
                ),
                _LabEntry(
                  title: 'Shell / system',
                  subtitle: 'Relay and trust destination inside the shell.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('system_overview')!,
                      ),
                ),
                _LabEntry(
                  title: 'Shell / settings',
                  subtitle:
                      'Global preferences destination with bottom navigation.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('settings_overview')!,
                      ),
                ),
                _LabEntry(
                  title: 'Cameras / relay missing',
                  subtitle: 'Empty state before the relay is connected.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('cameras_relay_missing')!,
                      ),
                ),
                _LabEntry(
                  title: 'Cameras / ready for first feed',
                  subtitle: 'Empty state after the relay is linked.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('cameras_ready')!,
                      ),
                ),
                _LabEntry(
                  title: 'Cameras / populated',
                  subtitle:
                      'Two sample feeds with deterministic imagery and no live data.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('cameras_populated')!,
                      ),
                ),
                _LabEntry(
                  title: 'Scan Camera QR',
                  subtitle: 'Direct add-camera flow with QR scanning.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('scan_qr_page')!,
                      ),
                ),
                _LabEntry(
                  title: 'Server / linked',
                  subtitle: 'Relay connected and ready to add a feed.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('server_linked')!,
                      ),
                ),
                _LabEntry(
                  title: 'Server / pairing',
                  subtitle: 'Relay pairing state without opening the scanner.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('server_pairing')!,
                      ),
                ),
                _LabEntry(
                  title: 'Camera / detail',
                  subtitle: 'Single feed with deterministic archive clips.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('camera_detail')!,
                      ),
                ),
                _LabEntry(
                  title: 'Video / playback',
                  subtitle: 'Clip player with fixed detections and controls.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('video_viewer')!,
                      ),
                ),
                _LabEntry(
                  title: 'Livestream / viewer',
                  subtitle: 'Live camera chrome without network state.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('livestream_viewer')!,
                      ),
                ),
                _LabEntry(
                  title: 'Livestream / error',
                  subtitle: 'Unable-to-connect failure state.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('livestream_error')!,
                      ),
                ),
                _LabEntry(
                  title: 'App / settings',
                  subtitle: 'Global preferences page in a stable mock state.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('app_settings')!,
                      ),
                ),
                _LabEntry(
                  title: 'Settings / top',
                  subtitle: 'Top of the long settings page.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('settings_top')!,
                      ),
                ),
                _LabEntry(
                  title: 'Settings / bottom',
                  subtitle: 'Lower storage and diagnostics section.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('settings_bottom')!,
                      ),
                ),
                _LabEntry(
                  title: 'Settings / very bottom',
                  subtitle: 'Bottom-most about and legal section.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('settings_very_bottom')!,
                      ),
                ),
                _LabEntry(
                  title: 'Camera / settings',
                  subtitle: 'Per-camera controls and firmware information.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('camera_settings')!,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // This section intentionally mirrors the wider screenshot manifest
            // more closely than the original "core screens" list did.
            //
            // The practical reason is simple: if the design lab is our starting
            // point for visual review, it should expose the major shell states
            // and failure/empty variants too, not just the happy-path screens.
            _LabSection(
              title: 'State coverage',
              children: [
                _LabEntry(
                  title: 'Home / no relay (dark)',
                  subtitle: 'Primary relay setup state in dark mode.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('home_shell_no_relay_dark')!,
                      ),
                ),
                _LabEntry(
                  title: 'Home / no relay (light)',
                  subtitle: 'Primary relay setup state in light mode.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage(
                          'home_shell_no_relay_light',
                          themeName: 'light',
                        )!,
                      ),
                ),
                _LabEntry(
                  title: 'Home / no cameras',
                  subtitle: 'Linked relay with no paired camera feeds yet.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('home_shell_no_cameras')!,
                      ),
                ),
                _LabEntry(
                  title: 'Home / error state',
                  subtitle:
                      'Recent event rail plus the inline error treatment.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('home_shell_error')!,
                      ),
                ),
                _LabEntry(
                  title: 'Home / notifications offline',
                  subtitle:
                      'Offline warning treatment for background delivery.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('home_shell_offline')!,
                      ),
                ),
                _LabEntry(
                  title: 'Home / one camera',
                  subtitle: 'Single paired camera with a populated hero card.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('home_shell_one_camera')!,
                      ),
                ),
                _LabEntry(
                  title: 'Home / one camera awaiting event',
                  subtitle:
                      'Single paired camera before the first visible clip.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage(
                          'home_shell_one_camera_empty_dark',
                        )!,
                      ),
                ),
                _LabEntry(
                  title: 'Home / two cameras',
                  subtitle: 'Balanced two-camera shell layout.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('home_shell_two_cameras')!,
                      ),
                ),
                _LabEntry(
                  title: 'Home / three cameras',
                  subtitle: 'Three-card camera rail stress state.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('home_shell_three_cameras')!,
                      ),
                ),
                _LabEntry(
                  title: 'Home / four cameras',
                  subtitle: 'Dense four-camera shell stress state.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('home_shell_four_cameras')!,
                      ),
                ),
                _LabEntry(
                  title: 'Home / placeholder imagery',
                  subtitle: 'Shell with intentionally missing preview media.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('home_shell_placeholder')!,
                      ),
                ),
                _LabEntry(
                  title: 'Activity / empty',
                  subtitle: 'Zero-event archive state inside the shell.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('activity_empty')!,
                      ),
                ),
                _LabEntry(
                  title: 'System / unpaired',
                  subtitle: 'Relay server setup state before linking.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('system_unpaired')!,
                      ),
                ),
                _LabEntry(
                  title: 'Camera / detail empty',
                  subtitle: 'Camera page before any clip thumbnails exist.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('camera_detail_empty_dark')!,
                      ),
                ),
                _LabEntry(
                  title: 'Shell / drawer',
                  subtitle: 'Navigation drawer treatment from the new shell.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('drawer_preview')!,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _LabSection(
              title: 'Dialogs',
              children: [
                _LabEntry(
                  title: 'Secluso camera / connect dialog',
                  subtitle: 'Initial proprietary pairing modal.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('dialog_secluso_connect')!,
                      ),
                ),
                _LabEntry(
                  title: 'Secluso camera / setup dialog',
                  subtitle: 'Relay account guidance step before pairing.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('dialog_secluso_setup')!,
                      ),
                ),
                _LabEntry(
                  title: 'Secluso camera / pairing dialog',
                  subtitle: 'In-progress camera pairing modal.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('dialog_secluso_pairing')!,
                      ),
                ),
                _LabEntry(
                  title: 'Secluso camera / pairing failed dialog',
                  subtitle: 'Failure treatment for pairing problems.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('dialog_secluso_pairing_failed')!,
                      ),
                ),
                _LabEntry(
                  title: 'Secluso camera / paired dialog',
                  subtitle: 'Successful camera pairing confirmation state.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('dialog_secluso_paired')!,
                      ),
                ),
                _LabEntry(
                  title: 'IP camera / import dialog',
                  subtitle: 'Initial IP camera import modal.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('dialog_ip_import')!,
                      ),
                ),
                _LabEntry(
                  title: 'Camera QR / scan dialog',
                  subtitle:
                      'Scanner framing and guidance without live camera input.',
                  onTap:
                      () => _openScreen(
                        context,
                        designLabTargetPage('dialog_qr_scan')!,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openScreen(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _DesignLabDialogHost extends StatefulWidget {
  const _DesignLabDialogHost({required this.title, required this.builder});

  final String title;
  final WidgetBuilder builder;

  @override
  State<_DesignLabDialogHost> createState() => _DesignLabDialogHostState();
}

class _DesignLabDialogHostState extends State<_DesignLabDialogHost> {
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: widget.builder,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SeclusoScaffold(
      appBar: seclusoAppBar(
        context,
        title: widget.title,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: const SizedBox.expand(),
    );
  }
}

class _LabSection extends StatelessWidget {
  const _LabSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SeclusoGlassCard(
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: SeclusoColors.blueSoft,
              letterSpacing: 2.1,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _LabEntry extends StatelessWidget {
  const _LabEntry({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
