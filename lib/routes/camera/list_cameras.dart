//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:collection/collection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/notifications/android_push_transport.dart';
import 'package:path/path.dart' as p;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'dart:async';

import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/notifications/firebase.dart';
import 'package:secluso_flutter/utilities/firebase_init.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/main.dart';
import 'package:secluso_flutter/routes/app_shell.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/ui/secluso_preview_assets.dart';
import 'package:secluso_flutter/ui/secluso_luxury.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_theme.dart';
import 'package:secluso_flutter/utilities/video_thumbnail_store.dart';
import 'package:secluso_flutter/routes/camera/shell_home_page.dart';
import 'view_camera.dart';
import 'camera_ui_bridge.dart';
import 'new/show_new_camera_options.dart';
import '../server_page.dart';
import '../home_page.dart';

class ThumbnailNotifier {
  ThumbnailNotifier._();
  static final ThumbnailNotifier instance = ThumbnailNotifier._();

  // emits the camera name whose thumbnail just updated
  final _controller = StreamController<String>.broadcast();
  Stream<String> get stream => _controller.stream;

  void notify(String cameraName) {
    _controller.add(cameraName);
    CameraUiBridge.refreshActivityCallback?.call();
  }
}

class CameraListNotifier {
  static final CameraListNotifier instance = CameraListNotifier._();

  VoidCallback? refreshCallback;

  CameraListNotifier._();
}

class CameraPreviewData {
  const CameraPreviewData({
    required this.name,
    this.icon = Icons.videocam,
    this.unreadMessages = false,
    this.previewAssetPath,
    this.statusLabel,
    this.recentActivityTitle,
    this.recentActivityTimeLabel,
    this.isLive = true,
    this.isOffline = false,
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
  final IconData icon;
  final bool unreadMessages;
  final String? previewAssetPath;
  final String? statusLabel;
  final String? recentActivityTitle;
  final String? recentActivityTimeLabel;
  final bool isLive;
  final bool isOffline;
  final List<Video>? previewVideos;
  final Map<String, Set<String>>? previewDetectionsByVideo;
  final Map<String, String>? previewThumbAssetsByVideo;
  final Map<String, String>? previewVideoAssetsByVideo;
  final Map<String, Duration>? previewDurationByVideo;
  final String? previewHeroAssetPath;
  final String? previewHeroVideoAssetPath;
  final bool previewDownloadActive;
}

class HomeRecentEventPreviewData {
  const HomeRecentEventPreviewData({
    required this.title,
    required this.subtitle,
    required this.timeLabel,
    this.previewAssetPath,
    this.previewVideoAssetPath,
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
  final Color accentColor;
  final String? videoName;
  final Set<String> detections;
  final bool motion;
  final bool canDownload;
  final bool hasVideoFile;
}

class CamerasPage extends StatefulWidget {
  const CamerasPage({
    super.key,
    this.previewServerHasSynced,
    this.previewCameras,
    this.previewRecentEvents,
    this.previewUnreadCount,
    this.previewShowNotificationWarning = false,
    this.previewShowRecentError = false,
    this.shellMode = false,
  });

  final bool? previewServerHasSynced;
  final List<CameraPreviewData>? previewCameras;
  final List<HomeRecentEventPreviewData>? previewRecentEvents;
  final int? previewUnreadCount;
  final bool previewShowNotificationWarning;
  final bool previewShowRecentError;
  final bool shellMode;

  @override
  CamerasPageState createState() => CamerasPageState();
}

class CameraCard extends StatefulWidget {
  final String cameraName;
  final IconData icon;
  final bool unreadMessages;
  final String? previewAssetPath;
  final bool enableInteractions;

  const CameraCard({
    required this.cameraName,
    required this.icon,
    required this.unreadMessages,
    this.previewAssetPath,
    this.enableInteractions = true,
    super.key,
  });

  @override
  State<CameraCard> createState() => _CameraCardState();
}

class _CameraCardState extends State<CameraCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final surfaceColor =
        dark ? const Color(0xFF0C0D10) : Colors.white.withValues(alpha: 0.96);
    final titleColor = dark ? Colors.white : theme.colorScheme.onSurface;
    final bodyColor =
        dark
            ? Colors.white.withValues(alpha: 0.74)
            : theme.colorScheme.onSurface.withValues(alpha: 0.66);
    return SizedBox(
      width: 176,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(28),
          border:
              dark ? null : Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap:
                  widget.enableInteractions
                      ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) =>
                                  CameraViewPage(cameraName: widget.cameraName),
                        ),
                      )
                      : null,
              onLongPress:
                  widget.enableInteractions
                      ? () => _confirmDeleteCamera(context, widget.cameraName)
                      : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 130,
                    width: double.infinity,
                    child: _thumbnailWithOverlay(
                      widget.cameraName,
                      widget.previewAssetPath,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SeclusoStatusChip(
                          label:
                              widget.unreadMessages
                                  ? 'New activity'
                                  : 'Indoor feed',
                          color:
                              widget.unreadMessages
                                  ? SeclusoColors.blueSoft
                                  : SeclusoColors.blue,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.cameraName,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: titleColor,
                            fontSize: 18,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.unreadMessages
                              ? 'Activity waiting.'
                              : 'Ready to review.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: bodyColor,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              'Open',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: titleColor,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.arrow_forward,
                              size: 18,
                              color:
                                  dark
                                      ? Colors.white.withValues(alpha: 0.72)
                                      : theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
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

  Widget _thumbnailWithOverlay(String camName, String? previewAssetPath) {
    if (previewAssetPath != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(previewAssetPath, fit: BoxFit.cover),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.16),
                  Colors.black.withValues(alpha: 0.54),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      );
    }

    final state = context.findAncestorStateOfType<CamerasPageState>()!;
    final initial = state._thumbCache[camName];

    return FutureBuilder<Uint8List?>(
      future: state._generateThumb(camName),
      initialData: initial,
      builder: (context, snap) {
        // Prefer any bytes we have
        final bytes = snap.data ?? initial;

        final hasBytes = bytes != null;
        final image =
            hasBytes
                ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
                : const Image(
                  image: AssetImage(
                    'assets/android_thumbnail_placeholder.jpeg',
                  ),
                  fit: BoxFit.cover,
                );

        final overlay = Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors:
                  hasBytes
                      ? [
                        Colors.black.withValues(alpha: 0.16),
                        Colors.black.withValues(alpha: 0.54),
                      ]
                      : [
                        Colors.black.withValues(alpha: 0.26),
                        Colors.black.withValues(alpha: 0.66),
                      ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            image,
            overlay,
            if (!hasBytes)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.54),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Awaiting first frame',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _confirmDeleteCamera(BuildContext context, String camName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete this camera?'),
            content: const Text(
              'This will delete the camera, all its videos, and its saved folder. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
    if (confirm == true) {
      final pageState = context.findAncestorStateOfType<CamerasPageState>();
      await pageState?.deleteCamera(camName);
    }
  }
}

class CamerasPageState extends State<CamerasPage>
    with WidgetsBindingObserver, RouteAware {
  final List<Map<String, dynamic>> cameras = [];
  final List<Map<String, dynamic>> _liveRecentEvents = [];
  final List<Map<String, dynamic>> _lastNonEmptyShellCameras = [];
  final List<Map<String, dynamic>> _lastNonEmptyShellRecentEvents = [];
  late Future<SharedPreferences> _prefsFuture;

  late final StreamSubscription<String> _thumbSub;

  bool _showNotificationWarning = false;
  bool _showRecentError = false;
  bool _backgroundDialogShown = false;
  bool _hasCompletedCameraLoad = false;
  bool? _serverHasSyncedState;

  /// cache: cam-name to thumbnail bytes (null = tried but failed)
  final Map<String, Uint8List?> _thumbCache = {};

  /// last known-good thumbnails to fall back on if a new file is corrupted
  final Map<String, Uint8List?> _thumbFallback = {};

  /// avoid running the DB query + channel call more than once at a time
  final Map<String, Future<Uint8List?>> _thumbFutures = {};

  /// cache validated recent-event thumbnails by "camera\nvideo"
  final Map<String, Uint8List> _eventThumbCache = {};

  /// avoid re-reading the same recent-event thumbnail concurrently
  final Map<String, Future<Uint8List?>> _eventThumbFutures = {};

  // Poll the database every so often and update if there's currently read messages or not
  Timer? _pollingTimer;
  late final VoidCallback _errorListener;

  bool get _isPreviewMode =>
      widget.previewServerHasSynced != null || widget.previewCameras != null;

  Future<SharedPreferences> _loadPrefsFresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }

  void _applyPreviewState() {
    _serverHasSyncedState = widget.previewServerHasSynced ?? false;
    _hasCompletedCameraLoad = true;
    cameras
      ..clear()
      ..addAll(
        (widget.previewCameras ?? const <CameraPreviewData>[]).map(
          (camera) => {
            'name': camera.name,
            'icon': camera.icon,
            'unreadMessages': camera.unreadMessages,
            'previewAsset': camera.previewAssetPath,
            'statusLabel': camera.statusLabel,
            'recentActivityTitle': camera.recentActivityTitle,
            'recentActivityTimeLabel': camera.recentActivityTimeLabel,
            'isLive': camera.isLive,
            'isOffline': camera.isOffline,
            'previewVideos': camera.previewVideos,
            'previewDetectionsByVideo': camera.previewDetectionsByVideo,
            'previewThumbAssetsByVideo': camera.previewThumbAssetsByVideo,
            'previewVideoAssetsByVideo': camera.previewVideoAssetsByVideo,
            'previewDurationByVideo': camera.previewDurationByVideo,
            'previewHeroAssetPath': camera.previewHeroAssetPath,
            'previewHeroVideoAssetPath': camera.previewHeroVideoAssetPath,
            'previewDownloadActive': camera.previewDownloadActive,
          },
        ),
      );
    _showNotificationWarning = widget.previewShowNotificationWarning;
    _showRecentError = widget.previewShowRecentError;
  }

  Future<void> _reloadServerSyncState() async {
    if (_isPreviewMode) {
      _serverHasSyncedState = widget.previewServerHasSynced ?? false;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final serverAddr = prefs.getString(PrefKeys.serverAddr);
    final serverUsername = prefs.getString(PrefKeys.serverUsername);
    final synced =
        serverAddr != null && serverAddr.isNotEmpty && serverUsername != null;

    if (!mounted) return;
    setState(() {
      _serverHasSyncedState = synced;
    });
  }

  void _refreshHomeState() {
    if (!mounted) return;
    final freshPrefs = _loadPrefsFresh();
    setState(() {
      _prefsFuture = freshPrefs;
      _serverHasSyncedState = null;
    });
    unawaited(_reloadServerSyncState());
    unawaited(_loadCamerasFromDatabase(true));
  }

  void invalidateThumbnail(String cameraName) {
    _thumbCache.remove(cameraName);
    _thumbFallback.remove(cameraName);
    _thumbFutures.remove(cameraName);
    _eventThumbCache.removeWhere((key, _) => key.startsWith('$cameraName\n'));
    _eventThumbFutures.removeWhere((key, _) => key.startsWith('$cameraName\n'));
    if (_isPreviewMode) {
      setState(() {});
      return;
    }
    unawaited(_loadCamerasFromDatabase(true));
  }

  Future<void> _loadRecentError() async {
    final enabled = await Log.errorNotificationsEnabled();
    final hasError = enabled && await Log.hasRecentError();
    if (!mounted) return;
    setState(() => _showRecentError = hasError);
  }

  Future<void> _copyLogs(BuildContext context) async {
    final logs = await Log.getCopySafeLogDump();
    final message =
        logs.trim().isEmpty
            ? 'No logs available yet.'
            : 'Logs copied to clipboard.';
    if (logs.trim().isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: logs));
      await Log.clearErrorFlag();
    }
    if (!mounted) return;
    setState(() => _showRecentError = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _dismissRecentError() async {
    await Log.clearErrorFlag();
    if (!mounted) return;
    setState(() => _showRecentError = false);
  }

  Future<void> _maybeShowBackgroundLogDialog() async {
    if (_backgroundDialogShown) return;
    if (!await Log.errorNotificationsEnabled()) return;
    final snapshot = await Log.getBackgroundSnapshot();
    if (snapshot == null || !mounted) return;
    _backgroundDialogShown = true;

    final when =
        snapshot.timestamp == null
            ? ''
            : 'Time: ${snapshot.timestamp!.toLocal()}';
    final reason = snapshot.reason.isEmpty ? '' : 'Reason: ${snapshot.reason}';
    final lines = [reason, when]..removeWhere((line) => line.isEmpty);
    final detailText = lines.isEmpty ? '' : '\n${lines.join('\n')}';

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Background error detected'),
              content: Text(
                'An error occurred while the app was in the background. '
                'These are the logs from that event. '
                'Tap Copy Logs to share them with support for troubleshooting.$detailText',
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await Log.clearBackgroundSnapshot();
                    await Log.clearErrorFlag();
                    if (mounted) {
                      setState(() => _showRecentError = false);
                      Navigator.of(ctx).pop();
                    }
                  },
                  child: const Text('Dismiss'),
                ),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: Log.redactSecretsForCopy(snapshot.logs),
                      ),
                    );
                    await Log.clearBackgroundSnapshot();
                    await Log.clearErrorFlag();
                    if (mounted) {
                      setState(() => _showRecentError = false);
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Logs copied to clipboard.'),
                        ),
                      );
                    }
                  },
                  child: const Text('Copy logs'),
                ),
              ],
            ),
      );
    } finally {
      _backgroundDialogShown = false;
    }
  }

  Widget _recentErrorBanner() {
    return _noticeCard(
      icon: Icons.error_outline,
      color: SeclusoColors.danger,
      message:
          'A recent error was captured. Dismiss it or copy the logs so support can help diagnose it quickly.',
      actionLabel: 'Dismiss',
      onPressed: _dismissRecentError,
    );
  }

  @override
  void initState() {
    super.initState();
    _thumbSub = ThumbnailNotifier.instance.stream.listen((cam) {
      // only invalidate the one that updated
      invalidateThumbnail(cam);
    });

    _prefsFuture = _loadPrefsFresh();
    if (_isPreviewMode) {
      _applyPreviewState();
      _errorListener = () {};
      return;
    }

    unawaited(_reloadServerSyncState());
    _prefsFuture.then((_) => _checkNotificationStatus());
    _loadRecentError();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowBackgroundLogDialog();
    });
    CameraUiBridge.showBackgroundLogDialogCallback = () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_maybeShowBackgroundLogDialog());
      });
    };

    _errorListener = () {
      unawaited(() async {
        final enabled = await Log.errorNotificationsEnabled();
        if (!mounted) return;
        if (!enabled) {
          if (_showRecentError) {
            setState(() => _showRecentError = false);
          }
          return;
        }
        if (!_showRecentError && mounted) {
          setState(() => _showRecentError = true);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_maybeShowBackgroundLogDialog());
        });
      }());
    };
    Log.errorNotifier.addListener(_errorListener);

    WidgetsBinding.instance.addObserver(this);
    CameraListNotifier.instance.refreshCallback = _refreshHomeState;
    CameraUiBridge.deleteCameraCallback = deleteCamera;
    CameraUiBridge.refreshCameraListCallback = _refreshHomeState;
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadCamerasFromDatabase(false), // refresh from DB every 5s
    );
    unawaited(_loadCamerasFromDatabase(true));
  }

  @override
  void didPopNext() {
    if (_isPreviewMode) return;
    Log.d("Returned to list cameras [pop]");
    _thumbCache.clear();
    _thumbFutures.clear();
    _eventThumbCache.clear();
    _eventThumbFutures.clear();
    _loadCamerasFromDatabase(true); // Load this every time we enter the page.
    _checkNotificationStatus();
  }

  @override
  void didPush() {
    if (_isPreviewMode) return;
    Log.d('Returned to list cameras [push]');
    _thumbCache.clear();
    _thumbFutures.clear();
    _eventThumbCache.clear();
    _eventThumbFutures.clear();
    _loadCamerasFromDatabase(true); // Load this every time we enter the page.
    _checkNotificationStatus();
  }

  @override
  void didUpdateWidget(covariant CamerasPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasPreviewMode =
        oldWidget.previewServerHasSynced != null ||
        oldWidget.previewCameras != null;
    if (_isPreviewMode) {
      if (!wasPreviewMode ||
          oldWidget.previewServerHasSynced != widget.previewServerHasSynced ||
          oldWidget.previewCameras != widget.previewCameras ||
          oldWidget.previewRecentEvents != widget.previewRecentEvents ||
          oldWidget.previewUnreadCount != widget.previewUnreadCount ||
          oldWidget.previewShowNotificationWarning !=
              widget.previewShowNotificationWarning ||
          oldWidget.previewShowRecentError != widget.previewShowRecentError) {
        setState(_applyPreviewState);
      }
      return;
    }
    if (wasPreviewMode) {
      _refreshHomeState();
    }
  }

  @override
  void dispose() {
    if (!_isPreviewMode) {
      Log.errorNotifier.removeListener(_errorListener);
    }
    _thumbSub.cancel();
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    if (identical(CameraUiBridge.deleteCameraCallback, deleteCamera)) {
      CameraUiBridge.deleteCameraCallback = null;
    }
    if (CameraUiBridge.refreshCameraListCallback != null) {
      CameraUiBridge.refreshCameraListCallback = null;
    }
    if (CameraUiBridge.showBackgroundLogDialogCallback != null) {
      CameraUiBridge.showBackgroundLogDialogCallback = null;
    }
    super.dispose();
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isPreviewMode) return;
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      // regenerate on resume
      _loadCamerasFromDatabase(
        true,
      ); //this may not be up-to-date as our stream doesn't run in the background
      setState(() {});
      _checkNotificationStatus();
    }
  }

  Future<void> _checkNotificationStatus() async {
    if (_isPreviewMode) return;
    final prefs = await _prefsFuture;
    final notificationsRequested =
        prefs.getBool(PrefKeys.notificationsEnabled) ?? true;

    if (cameras.isEmpty) {
      // We don't need to check before a camera is added.
      return;
    }

    if (!notificationsRequested) {
      setState(() => _showNotificationWarning = false);
      return;
    }

    final lastAsked = prefs.getInt(PrefKeys.lastNotificationCheck) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cooldown = const Duration(hours: 24).inMilliseconds;

    final status = await Permission.notification.status;

    if (status.isDenied || status.isRestricted) {
      if (now - lastAsked >= cooldown) {
        Log.d("Requesting for notifications");
        await prefs.setInt(PrefKeys.lastNotificationCheck, now);
        final result = await Permission.notification.request();

        if (mounted) {
          if (!result.isGranted) {
            setState(() => _showNotificationWarning = true);
          } else {
            setState(() => _showNotificationWarning = false);

            //TODO: This might be necessary to work on iOS. Not 100% sure.
            if (Platform.isAndroid) {
              final androidPushPlatform = await AndroidPushTransport.load();
              if (AndroidPushTransport.isUnifiedValue(androidPushPlatform)) {
                await PushNotificationService.instance.init();
              } else if (!FirebaseInit.isInitialized) {
                Log.d(
                  "Skipping FCM permission request; Firebase not initialized",
                );
              } else {
                await FirebaseMessaging.instance.requestPermission(
                  alert: true,
                  badge: true,
                  sound: true,
                );
              }
            } else {
              await PushNotificationService.instance.init();
            }

            // This may be the first time we have access to this after adding a camera.
            PushNotificationService.tryUploadIfNeeded(true);
          }
        }
      } else {
        setState(() => _showNotificationWarning = true);
      }
    } else if (!status.isGranted && mounted) {
      setState(() => _showNotificationWarning = true);
    } else if (status.isGranted && mounted) {
      setState(() => _showNotificationWarning = false);
    }
  }

  Future<void> deleteCamera(String cameraName) async {
    await CameraUiBridge.deleteCamera(cameraName);
    invalidateThumbnail(cameraName);
    await _loadCamerasFromDatabase(false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deleted "$cameraName"',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  final _deepEq = const DeepCollectionEquality.unordered();

  DateTime? _timestampFromVideoName(String videoName) {
    if (videoName.startsWith('video_') && videoName.endsWith('.mp4')) {
      final value = int.tryParse(
        videoName.replaceFirst('video_', '').replaceFirst('.mp4', ''),
      );
      if (value != null) {
        return DateTime.fromMillisecondsSinceEpoch(
          value * 1000,
          isUtc: true,
        ).toLocal();
      }
    }
    return null;
  }

  String _compactAgeLabel(DateTime timestamp) {
    final delta = DateTime.now().difference(timestamp);
    if (delta.inMinutes < 1) {
      return 'Now';
    }
    if (delta.inHours < 1) {
      return '${delta.inMinutes}m';
    }
    if (delta.inDays < 1) {
      return '${delta.inHours}h';
    }
    return '${delta.inDays}d';
  }

  String _agoAgeLabel(DateTime timestamp) {
    final compact = _compactAgeLabel(timestamp);
    return compact == 'Now' ? 'Just now' : '$compact ago';
  }

  Future<Set<String>> _detectionTypesForVideo(String videoName) async {
    final rows = await AppStores.instance.detectionStore.findByVideoFile(
      videoName,
    );
    return rows.map((row) => row.type.toLowerCase()).toSet();
  }

  bool _hasPersonDetection(Set<String> detections) {
    return detections.contains('human') || detections.contains('person');
  }

  String _activityTitleForVideo(bool motion, Set<String> detections) {
    if (!motion) {
      return 'Livestream Clip';
    }
    if (_hasPersonDetection(detections)) {
      return 'Person Detected';
    }
    if (detections.contains('vehicle') || detections.contains('car')) {
      return 'Vehicle Detected';
    }
    if (detections.contains('pet') || detections.contains('pets')) {
      return 'Pet Detected';
    }
    return 'Motion';
  }

  Color _accentColorForVideo(Set<String> detections) {
    return _hasPersonDetection(detections)
        ? const Color(0xFF8BB3EE)
        : const Color(0xFF60A5FA);
  }

  bool _isOfflineStatus(int statusCode) {
    return statusCode == CameraStatus.offline ||
        statusCode == CameraStatus.corrupted ||
        statusCode == CameraStatus.possiblyCorrupted;
  }

  String _statusLabelForCamera({
    required bool isOffline,
    required Video? latestVideo,
    required Set<String> detections,
  }) {
    if (isOffline) {
      return 'Offline';
    }
    if (latestVideo == null) {
      return 'Quiet';
    }

    final timestamp = _timestampFromVideoName(latestVideo.video);
    final timePart = timestamp == null ? null : _compactAgeLabel(timestamp);

    if (_hasPersonDetection(detections)) {
      return timePart == null ? 'Person' : 'Person · $timePart';
    }
    if (latestVideo.motion) {
      return timePart == null ? 'Motion' : 'Motion · $timePart';
    }
    return 'Quiet';
  }

  Future<void> _loadCamerasFromDatabase([bool forceRun = false]) async {
    if (!AppStores.isInitialized) {
      try {
        await AppStores.init();
      } catch (e, st) {
        Log.e("Failed to init AppStores: $e\n$st");
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final cameraStore = AppStores.instance.cameraStore;
    final videoStore = AppStores.instance.videoStore;
    final storedCameras = await cameraStore.getAllAsync();
    final videos = await videoStore.listRecent(limit: 80);

    final latestVideoByCamera = <String, Video>{};
    for (final video in videos) {
      latestVideoByCamera.putIfAbsent(video.camera, () => video);
    }

    final activeCameraNames =
        storedCameras.map((camera) => camera.name).toSet();
    _thumbCache.removeWhere(
      (cameraName, _) => !activeCameraNames.contains(cameraName),
    );
    _thumbFallback.removeWhere(
      (cameraName, _) => !activeCameraNames.contains(cameraName),
    );
    _thumbFutures.removeWhere(
      (cameraName, _) => !activeCameraNames.contains(cameraName),
    );
    _eventThumbCache.removeWhere((key, _) {
      final separator = key.indexOf('\n');
      final cameraName = separator == -1 ? key : key.substring(0, separator);
      return !activeCameraNames.contains(cameraName);
    });
    _eventThumbFutures.removeWhere((key, _) {
      final separator = key.indexOf('\n');
      final cameraName = separator == -1 ? key : key.substring(0, separator);
      return !activeCameraNames.contains(cameraName);
    });

    final detectionCache = <String, Set<String>>{};
    Future<Set<String>> detectionsForVideo(String videoName) async {
      final cached = detectionCache[videoName];
      if (cached != null) {
        return cached;
      }
      final detections = await _detectionTypesForVideo(videoName);
      detectionCache[videoName] = detections;
      return detections;
    }

    final latestDisplayableEventByCamera = <String, Video>{};
    for (final video in videos) {
      if (latestDisplayableEventByCamera.containsKey(video.camera)) {
        continue;
      }
      final hasVideoFile = await _videoFileExists(video.camera, video.video);
      if (!hasVideoFile &&
          await _eventThumbnailBytes(video.camera, video.video) == null) {
        continue;
      }
      final detections = await detectionsForVideo(video.video);
      if (!video.motion && detections.isEmpty) {
        continue;
      }
      latestDisplayableEventByCamera[video.camera] = video;
    }

    final all = <Map<String, dynamic>>[];
    for (final camera in storedCameras) {
      final latestVideo = latestVideoByCamera[camera.name];
      final latestDisplayableEvent =
          latestDisplayableEventByCamera[camera.name];
      final detections =
          latestVideo == null
              ? const <String>{}
              : await detectionsForVideo(latestVideo.video);
      final latestTimestamp =
          latestVideo == null
              ? null
              : _timestampFromVideoName(latestVideo.video);
      final statusCode =
          prefs.getInt(PrefKeys.cameraStatusPrefix + camera.name) ??
          CameraStatus.online;
      final isOffline = _isOfflineStatus(statusCode);
      final thumbnailBytes =
          latestDisplayableEvent == null
              ? null
              : await _eventThumbnailBytes(
                camera.name,
                latestDisplayableEvent.video,
              );
      if (thumbnailBytes != null) {
        _thumbFallback[camera.name] = thumbnailBytes;
      }
      _thumbCache[camera.name] = thumbnailBytes ?? _thumbFallback[camera.name];

      all.add({
        "name": camera.name,
        "icon": Icons.videocam,
        "unreadMessages": camera.unreadMessages,
        "statusLabel": _statusLabelForCamera(
          isOffline: isOffline,
          latestVideo: latestVideo,
          detections: detections,
        ),
        "recentActivityTitle":
            latestVideo == null
                ? null
                : _activityTitleForVideo(latestVideo.motion, detections),
        "recentActivityTimeLabel":
            latestTimestamp == null ? null : _agoAgeLabel(latestTimestamp),
        "isLive": !isOffline,
        "isOffline": isOffline,
        "thumbnailBytes": _thumbCache[camera.name],
        "latestTimestamp": latestTimestamp?.millisecondsSinceEpoch,
      });
    }

    final recentEvents = <Map<String, dynamic>>[];
    final seenRecentKeys = <String>{};
    for (final video in videos) {
      final eventKey = '${video.camera}\n${video.video}';
      if (!seenRecentKeys.add(eventKey)) {
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
      final detections = await detectionsForVideo(video.video);
      if (!video.motion && detections.isEmpty) {
        continue;
      }
      final timestamp = _timestampFromVideoName(video.video);
      recentEvents.add({
        "title": _activityTitleForVideo(video.motion, detections),
        "subtitle": video.camera,
        "timeLabel": timestamp == null ? video.video : _agoAgeLabel(timestamp),
        "videoName": video.video,
        "detections": detections,
        "motion": video.motion,
        "canDownload": video.received,
        "hasVideoFile": hasVideoFile,
        "thumbnailBytes": thumbnailBytes,
        "accentColor": _accentColorForVideo(detections),
      });
      if (recentEvents.length == 2) {
        break;
      }
    }

    if (!forceRun &&
        _deepEq.equals(all, cameras) &&
        _deepEq.equals(recentEvents, _liveRecentEvents)) {
      _hasCompletedCameraLoad = true;
      return;
    }
    Log.d("Refreshing cameras from database");

    setState(() {
      _hasCompletedCameraLoad = true;
      cameras
        ..clear()
        ..addAll(all);
      _liveRecentEvents
        ..clear()
        ..addAll(recentEvents);
      if (all.isNotEmpty) {
        _lastNonEmptyShellCameras
          ..clear()
          ..addAll(all.map((camera) => Map<String, dynamic>.from(camera)));
      }
      if (recentEvents.isNotEmpty) {
        _lastNonEmptyShellRecentEvents
          ..clear()
          ..addAll(
            recentEvents.map((event) => Map<String, dynamic>.from(event)),
          );
      }
    });
  }

  Future<Uint8List?> _generateThumb(String cameraName) {
    if (_thumbCache.containsKey(cameraName)) {
      return Future.value(
        _thumbCache[cameraName] ?? _thumbFallback[cameraName],
      );
    }
    if (_thumbFutures.containsKey(cameraName)) {
      return _thumbFutures[cameraName]!;
    }

    final future = () async {
      final fallback = _thumbFallback[cameraName];
      try {
        final bytes = await _latestDisplayableThumbnailBytes(cameraName);
        if (bytes == null) {
          _thumbCache[cameraName] = fallback;
          return fallback;
        }
        _thumbCache[cameraName] = bytes;
        _thumbFallback[cameraName] = bytes;
        return bytes;
      } catch (e) {
        Log.e('Thumb load error [$cameraName]: $e');
        _thumbCache[cameraName] = fallback;
        return fallback;
      }
    }();

    _thumbFutures[cameraName] = future;
    return future;
  }

  Future<Uint8List?> _latestDisplayableThumbnailBytes(String cameraName) async {
    if (!AppStores.isInitialized) {
      try {
        await AppStores.init();
      } catch (e, st) {
        Log.e(
          "Failed to init AppStores for thumb lookup [$cameraName]: $e\n$st",
        );
        return null;
      }
    }

    final videos = await AppStores.instance.videoStore.listByCamera(
      cameraName,
      limit: 40,
    );

    for (final video in videos) {
      final hasVideoFile = await _videoFileExists(video.camera, video.video);
      if (!hasVideoFile &&
          await _eventThumbnailBytes(video.camera, video.video) == null) {
        continue;
      }
      final detections = await _detectionTypesForVideo(video.video);
      if (!video.motion && detections.isEmpty) {
        continue;
      }
      return _eventThumbnailBytes(video.camera, video.video);
    }

    Log.d(
      'Home thumb miss [$cameraName]: no displayable event found for thumbnail lookup',
    );
    return null;
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
        logPrefix: 'Recent event thumb',
      );
      if (bytes != null) {
        _eventThumbCache[cacheKey] = bytes;
      }
      return bytes;
    } catch (e) {
      Log.e("Event thumbnail read error [$cameraName/$videoFile]: $e");
      return null;
    }
  }

  Future<void> _openPrimaryFlow(
    BuildContext context,
    bool serverHasSynced,
  ) async {
    if (serverHasSynced) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ShowNewCameraOptions()),
      );
      return;
    }

    if (widget.shellMode) {
      CameraUiBridge.switchShellTabCallback?.call(2);
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => ServerPage(
              showBackButton: !widget.shellMode,
              showShellChrome: widget.shellMode,
              previewHasSynced: _isPreviewMode ? false : null,
            ),
      ),
    );
  }

  Widget _noticeCard({
    required IconData icon,
    required Color color,
    required String message,
    required String actionLabel,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SeclusoGlassCard(
        borderRadius: 24,
        tint: color.withValues(alpha: 0.08),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(onPressed: onPressed, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }

  Widget _notificationWarningCard() {
    return _noticeCard(
      icon: Icons.notifications_off_outlined,
      color: SeclusoColors.warning,
      message:
          'Notifications are disabled. Turn them back on if you want motion and camera health alerts.',
      actionLabel: 'Fix',
      onPressed: openAppSettings,
    );
  }

  Widget _primaryHeroBackground(String? cameraName) {
    if (cameraName == null) {
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

    final previewAsset =
        cameras.firstWhereOrNull(
              (camera) => camera['name'] == cameraName,
            )?['previewAsset']
            as String?;
    if (previewAsset != null) {
      return Image.asset(previewAsset, fit: BoxFit.cover);
    }

    final initial = _thumbCache[cameraName];
    return FutureBuilder<Uint8List?>(
      future: _generateThumb(cameraName),
      initialData: initial,
      builder: (context, snapshot) {
        final bytes = snapshot.data ?? initial;
        if (bytes == null) {
          return const Image(
            image: AssetImage('assets/android_thumbnail_placeholder.jpeg'),
            fit: BoxFit.cover,
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }

  Widget _overviewCard(bool serverHasSynced) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final unreadCount =
        cameras.where((camera) => camera['unreadMessages'] == true).length;
    final primaryCameraName =
        cameras.isEmpty ? null : cameras.first['name'] as String;
    final subtitle =
        serverHasSynced
            ? 'Open the main room. Review saved moments.'
            : 'Connect the relay first, then bring the first feed into a system that actually belongs to you.';

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color:
              dark
                  ? const Color(0xFF0C0D10)
                  : Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(34),
          border:
              dark ? null : Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: SizedBox(
            height: 356,
            child: Column(
              children: [
                Expanded(
                  flex: 7,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: _primaryHeroBackground(primaryCameraName),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.02),
                                Colors.black.withValues(alpha: 0.12),
                                Colors.black.withValues(
                                  alpha: dark ? 0.46 : 0.26,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 18,
                        top: 18,
                        child: SeclusoStatusChip(
                          label: unreadCount > 0 ? 'Primary room' : 'Ready now',
                          color:
                              unreadCount > 0
                                  ? SeclusoColors.warning
                                  : SeclusoColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          primaryCameraName ?? 'Your private camera network',
                          style: theme.editorialHero(fontSize: 24),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.72,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${cameras.length} cameras · ${serverHasSynced ? 'relay linked' : 'relay needed'} · ${unreadCount > 0 ? '$unreadCount waiting' : 'quiet'}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.72,
                            ),
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        if (primaryCameraName == null)
                          FilledButton(
                            onPressed:
                                () =>
                                    _openPrimaryFlow(context, serverHasSynced),
                            child: Text(
                              serverHasSynced ? 'Add camera' : 'Connect server',
                            ),
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed:
                                      () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (_) => CameraViewPage(
                                                cameraName: primaryCameraName,
                                              ),
                                        ),
                                      ),
                                  child: const Text('Open feed'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton(
                                onPressed:
                                    () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (_) => const ShowNewCameraOptions(),
                                      ),
                                    ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                ),
                                child: const Text('Add'),
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

  Widget _emptyStateCard(bool serverHasSynced) {
    final headline =
        serverHasSynced ? 'Start with one feed.' : 'Link the relay first.';
    final subtitle =
        serverHasSynced
            ? 'Your relay is ready. Add the first camera and keep every clip on your side.'
            : 'Connect the private relay first, then bring cameras into a system that belongs to you.';
    final action =
        serverHasSynced ? 'Add your first camera' : 'Connect your server';
    final imagePath =
        serverHasSynced
            ? SeclusoPreviewAssets.tabletopCamera
            : SeclusoPreviewAssets.relayDevice;
    final imageAlignment =
        serverHasSynced ? Alignment.centerRight : Alignment.centerRight;
    final imageScale = serverHasSynced ? 1.02 : 1.08;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color:
              dark
                  ? const Color(0xFF0C0D0F)
                  : Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(34),
          border:
              dark ? null : Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: SizedBox(
            height: 428,
            child: Column(
              children: [
                Expanded(
                  flex: 10,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: Transform.scale(
                          scale: imageScale,
                          alignment: imageAlignment,
                          child: Image.asset(
                            imagePath,
                            fit: BoxFit.cover,
                            alignment: imageAlignment,
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
                                Colors.black.withValues(alpha: 0.02),
                                Colors.black.withValues(alpha: 0.08),
                                Colors.black.withValues(alpha: 0.36),
                                Colors.black.withValues(alpha: 0.72),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.black.withValues(alpha: 0.26),
                                Colors.transparent,
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: SeclusoStatusChip(
                            label:
                                serverHasSynced
                                    ? 'Server linked'
                                    : 'Private relay',
                            color:
                                serverHasSynced
                                    ? SeclusoColors.success
                                    : SeclusoColors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 11,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors:
                            dark
                                ? const [Color(0xFF101114), Color(0xFF09090A)]
                                : const [Color(0xFFF7F4EE), Color(0xFFF1ECE2)],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 272),
                            child: Text(
                              headline,
                              style: theme.editorialHero(fontSize: 31),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 284),
                            child: Text(
                              subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.72,
                                ),
                                fontSize: 15,
                                height: 1.42,
                              ),
                            ),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed:
                                () =>
                                    _openPrimaryFlow(context, serverHasSynced),
                            child: Text(action),
                          ),
                        ],
                      ),
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
    if (_isPreviewMode) {
      return _buildPage(widget.previewServerHasSynced ?? false);
    }
    final serverHasSynced = _serverHasSyncedState;
    if (serverHasSynced == null) {
      return _startupHoldingScreen(context);
    }
    return _buildPage(serverHasSynced);
  }

  Widget _buildPage(bool serverHasSynced) {
    if (widget.shellMode) {
      if (!_hasCompletedCameraLoad &&
          cameras.isEmpty &&
          _lastNonEmptyShellCameras.isEmpty) {
        return _startupHoldingScreen(context, shellMode: true);
      }
      final shellCameraSource =
          cameras.isNotEmpty || _hasCompletedCameraLoad
              ? cameras
              : _lastNonEmptyShellCameras;
      final shellRecentEventSource =
          _liveRecentEvents.isNotEmpty || _hasCompletedCameraLoad
              ? _liveRecentEvents
              : _lastNonEmptyShellRecentEvents;
      final homeCameras =
          shellCameraSource
              .map(
                (camera) => ShellHomeCamera(
                  name: camera['name'] as String,
                  previewAssetPath: camera['previewAsset'] as String?,
                  thumbnailBytes: camera['thumbnailBytes'] as Uint8List?,
                  hasUnreadActivity: camera['unreadMessages'] as bool? ?? false,
                  statusLabel: camera['statusLabel'] as String?,
                  recentActivityTitle: camera['recentActivityTitle'] as String?,
                  recentActivityTimeLabel:
                      camera['recentActivityTimeLabel'] as String?,
                  isLive: camera['isLive'] as bool? ?? true,
                  isOffline: camera['isOffline'] as bool? ?? false,
                  previewVideos: camera['previewVideos'] as List<Video>?,
                  previewDetectionsByVideo:
                      camera['previewDetectionsByVideo']
                          as Map<String, Set<String>>?,
                  previewThumbAssetsByVideo:
                      camera['previewThumbAssetsByVideo']
                          as Map<String, String>?,
                  previewVideoAssetsByVideo:
                      camera['previewVideoAssetsByVideo']
                          as Map<String, String>?,
                  previewDurationByVideo:
                      camera['previewDurationByVideo']
                          as Map<String, Duration>?,
                  previewHeroAssetPath:
                      camera['previewHeroAssetPath'] as String?,
                  previewHeroVideoAssetPath:
                      camera['previewHeroVideoAssetPath'] as String?,
                  previewDownloadActive:
                      camera['previewDownloadActive'] as bool? ?? false,
                ),
              )
              .toList();
      final recentEvents =
          widget.previewRecentEvents != null
              ? widget.previewRecentEvents!
                  .map(
                    (event) => ShellHomeEvent(
                      title: event.title,
                      subtitle: event.subtitle,
                      timeLabel: event.timeLabel,
                      previewAssetPath: event.previewAssetPath,
                      previewVideoAssetPath: event.previewVideoAssetPath,
                      accentColor: event.accentColor,
                      videoName: event.videoName,
                      detections: event.detections,
                      motion: event.motion,
                      canDownload: event.canDownload,
                      hasVideoFile: event.hasVideoFile,
                    ),
                  )
                  .toList()
              : shellRecentEventSource
                  .map(
                    (event) => ShellHomeEvent(
                      title: event['title'] as String,
                      subtitle: event['subtitle'] as String,
                      timeLabel: event['timeLabel'] as String,
                      previewAssetPath: null,
                      previewVideoAssetPath: null,
                      thumbnailBytes: event['thumbnailBytes'] as Uint8List?,
                      accentColor: event['accentColor'] as Color,
                      videoName: event['videoName'] as String?,
                      detections:
                          (event['detections'] as Set<String>?) ??
                          const <String>{},
                      motion: event['motion'] as bool? ?? true,
                      canDownload: event['canDownload'] as bool? ?? false,
                      hasVideoFile: event['hasVideoFile'] as bool? ?? true,
                    ),
                  )
                  .toList();
      return ShellHomePage(
        relayConnected: serverHasSynced,
        cameras: homeCameras,
        recentEvents: recentEvents,
        unreadCount:
            widget.previewUnreadCount ??
            cameras.where((camera) => camera["unreadMessages"] == true).length,
        showErrorCard: _isPreviewMode ? _showRecentError : false,
        showOfflineExample: widget.previewShowNotificationWarning,
        onOpenRelaySetup: () => _openPrimaryFlow(context, false),
      );
    }

    final secondaryCameras = cameras.skip(1).toList();
    return SeclusoScaffold(
      appBar:
          widget.shellMode
              ? null
              : seclusoAppBar(
                context,
                title: 'Cameras',
                leading:
                    _isPreviewMode && Navigator.of(context).canPop()
                        ? IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(context).maybePop(),
                        )
                        : IconButton(
                          icon: const Icon(Icons.menu),
                          onPressed: () {
                            scaffoldKey.currentState?.openDrawer();
                          },
                        ),
                actions: [
                  if (_showRecentError)
                    IconButton(
                      icon: const Icon(Icons.copy_all_outlined),
                      tooltip: "Copy logs",
                      onPressed: () => _copyLogs(context),
                    ),
                ],
              ),
      body: SafeArea(
        top: true,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            widget.shellMode ? 22 : 16,
            20,
            widget.shellMode ? 132 : 36,
          ),
          children: [
            if (widget.shellMode)
              _ShellControlHeader(
                hasCameras: cameras.isNotEmpty,
                unreadCount:
                    cameras
                        .where((camera) => camera["unreadMessages"] == true)
                        .length,
              )
            else
              SeclusoSectionIntro(
                eyebrow: 'Control room',
                title:
                    cameras.isEmpty
                        ? 'See everything. Share nothing.'
                        : 'Run the private camera network.',
                subtitle:
                    cameras.isEmpty
                        ? 'A premium overview of feeds, relay state, and the first steps into your encrypted camera system.'
                        : 'Lead with the primary room, surface activity faster, and keep the system status legible above the fold.',
                editorial: true,
              ),
            const SizedBox(height: 14),
            SeclusoSystemStrip(
              items: [
                SeclusoSystemStripItem(
                  label: 'Relay',
                  value: serverHasSynced ? 'Linked' : 'Waiting',
                  color:
                      serverHasSynced
                          ? SeclusoColors.success
                          : SeclusoColors.blue,
                ),
                SeclusoSystemStripItem(
                  label: 'Cameras',
                  value: '${cameras.length}',
                  color: SeclusoColors.blueSoft,
                ),
                SeclusoSystemStripItem(
                  label: 'Unread',
                  value:
                      '${cameras.where((camera) => camera["unreadMessages"] == true).length}',
                  color: SeclusoColors.warning,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (cameras.isEmpty)
              _emptyStateCard(serverHasSynced)
            else
              _overviewCard(serverHasSynced),
            if (_showRecentError) _recentErrorBanner(),
            if (_showNotificationWarning) _notificationWarningCard(),
            if (cameras.isNotEmpty) ...[
              const SizedBox(height: 12),
              SeclusoUtilityCard(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: SeclusoFlatRow(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: SeclusoColors.blue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.motion_photos_on_outlined),
                  ),
                  eyebrow: 'Fast review',
                  title: 'Recent activity',
                  subtitle: 'Review the latest saved moments from here.',
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AppShell(initialIndex: 1),
                        ),
                      ),
                ),
              ),
            ],
            if (secondaryCameras.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Camera rail'.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: SeclusoColors.blue,
                          letterSpacing: 2.2,
                        ),
                      ),
                    ),
                    Text(
                      '${secondaryCameras.length}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 268,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 4),
                  itemCount: secondaryCameras.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final camera = secondaryCameras[index];
                    return CameraCard(
                      key: ValueKey(camera["name"]),
                      cameraName: camera["name"],
                      icon: camera["icon"],
                      unreadMessages: camera["unreadMessages"],
                      previewAssetPath: camera["previewAsset"] as String?,
                      enableInteractions: !_isPreviewMode,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _startupHoldingScreen(BuildContext context, {bool shellMode = false}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7);
    final spinnerColor =
        dark ? Colors.white.withValues(alpha: 0.72) : const Color(0xFF111827);

    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icon_centered.png',
              width: shellMode ? 72 : 68,
              height: shellMode ? 72 : 68,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: spinnerColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellControlHeader extends StatelessWidget {
  const _ShellControlHeader({
    required this.hasCameras,
    required this.unreadCount,
  });

  final bool hasCameras;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PRIVATE CONTROL ROOM',
          style: theme.textTheme.labelSmall?.copyWith(
            color: SeclusoColors.blue,
            letterSpacing: 2.1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          hasCameras ? 'Private overview' : 'Ready for first setup',
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          unreadCount > 0
              ? 'Check camera state, unread activity, and the next action.'
              : 'A quieter overview of the camera network.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
