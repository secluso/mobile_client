//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/utilities/firebase_init.dart';
import 'package:flutter/services.dart';
import 'package:secluso_flutter/notifications/heartbeat_task.dart';
import 'package:secluso_flutter/notifications/scheduler.dart';
import 'package:secluso_flutter/notifications/android_push_transport.dart';
import 'package:secluso_flutter/src/rust/guard.dart';
import 'package:secluso_flutter/src/rust/api/logger.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/notifications/thumbnails.dart';
import 'package:secluso_flutter/notifications/notifications.dart';
import 'routes/app_shell.dart';
import 'routes/design_lab_page.dart';
import 'routes/camera/camera_ui_bridge.dart';
import "routes/theme_provider.dart";
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/notifications/firebase.dart';
import 'package:secluso_flutter/notifications/unified_push_service.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/notifications/pending_processor.dart';
import 'package:secluso_flutter/database/migration_runner.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/trace_id.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/app_coordination_state.dart';
import 'package:secluso_flutter/utilities/lock.dart';
import 'package:secluso_flutter/utilities/storage_manager.dart';
import 'package:secluso_flutter/utilities/version_gate.dart';
import 'package:secluso_flutter/utilities/ui_state.dart';
import 'package:secluso_flutter/utilities/review_environment.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/font_licenses.dart';
import 'package:secluso_flutter/ui/secluso_theme.dart';
import 'package:secluso_flutter/routes/camera-role/camera_role_pages.dart';
import 'package:secluso_flutter/routes/system_shell_page.dart';
import 'package:secluso_flutter/routes/camera-role/android_camera_hub_launcher.dart';
import 'package:secluso_flutter/utilities/device_role_controller.dart';
import 'dart:isolate';

final ReceivePort _mainReceivePort = ReceivePort();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const queueProcessorPortName = 'queue_processor_signal_port';
const _startupPhaseCameraInit = 'camera_init';
const _startupPhasePostFirebase = 'post_firebase';
const _versionCheckRetryDelay = Duration(seconds: 30);
Timer? _versionCheckRetryTimer;
bool _versionCheckInFlight = false;
const bool _launchDesignLab = bool.fromEnvironment(
  'SECLUSO_DESIGN_LAB',
  defaultValue: false,
);
const bool _launchDesignController = bool.fromEnvironment(
  'SECLUSO_DESIGN_CONTROLLER',
  defaultValue: false,
);
const bool _captureMode = bool.fromEnvironment(
  'SECLUSO_CAPTURE_MODE',
  defaultValue: false,
);
const String _launchDesignTarget = String.fromEnvironment(
  'SECLUSO_DESIGN_TARGET',
  defaultValue: '',
);
const String _designCommandFile = String.fromEnvironment(
  'SECLUSO_DESIGN_COMMAND_FILE',
  defaultValue: '/tmp/secluso_design_command.txt',
);
const bool _designPreviewBoot =
    (kDebugMode || _captureMode) &&
    (_launchDesignLab || _launchDesignTarget != '' || _launchDesignController);

void main([List<String> args = const []]) {
  // Wrap main() with a zone so if something throws during init, we still attempt to close the DB.
  runZonedGuarded(
    () async {
      Log.init();
      final traceId = newTraceId('ui');
      Log.setDefaultContext(traceId);
      await Log.runWithContext(traceId, () async {
        Log.i('UI context started (id=$traceId)');
        Log.i('main() started');
        final binding = WidgetsFlutterBinding.ensureInitialized();
        registerBundledFontLicenses();
        final isUnifiedPushBackground = args.contains('--unifiedpush-bg');
        if (Platform.isAndroid) {
          await UnifiedPushService.instance.init(
            background: isUnifiedPushBackground,
          );
          if (!isUnifiedPushBackground &&
              !AndroidPushTransport.fdroidUnifiedOnly) {
            FirebaseMessaging.onBackgroundMessage(
              firebaseMessagingBackgroundHandler,
            );
          }
        }
        if (isUnifiedPushBackground) {
          Log.i('UnifiedPush background isolate started');
          return;
        }
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        UiState.markBindingReady();
        final initialDarkMode = await ThemeProvider.loadThemePreference();
        final shouldDeferFirstFrame = !_designPreviewBoot;
        if (shouldDeferFirstFrame) {
          // Keep the native Android splash visible until startup actually
          // resolves. That gives us one continuous launch surface instead of a
          // native splash handing off to extra black/white placeholder frames.
          binding.deferFirstFrame();
        }
        FlutterError.onError = (details) {
          Log.e('FlutterError: ${details.exceptionAsString()}');
          final stack = details.stack;
          if (stack != null) {
            Log.e(stack.toString());
          }
          if (_isAppInBackground()) {
            unawaited(
              _handleBackgroundError(
                'FlutterError: ${details.exceptionAsString()}',
              ),
            );
          }
          FlutterError.presentError(details);
        };
        ErrorWidget.builder = (details) {
          Log.e('ErrorWidget: ${details.exceptionAsString()}');
          final stack = details.stack;
          if (stack != null) {
            Log.e(stack.toString());
          }
          if (_isAppInBackground()) {
            unawaited(
              _handleBackgroundError(
                'ErrorWidget: ${details.exceptionAsString()}',
              ),
            );
          }
          return ErrorWidget(details.exception);
        };
        PlatformDispatcher.instance.onError = (error, stack) {
          Log.e('PlatformDispatcher: $error');
          Log.e(stack.toString());
          if (_isAppInBackground()) {
            unawaited(_handleBackgroundError('PlatformDispatcher: $error'));
          }
          return true;
        };
        unawaited(Log.ensureStorageReady());
        runApp(
          AppBootstrap(
            initialDarkMode: initialDarkMode,
            releaseFirstFrameOnReady: shouldDeferFirstFrame,
          ),
        );
      });
    },
    (error, stack) async {
      Log.e('Zone error: $error');
      Log.e(stack.toString());
      if (_isAppInBackground()) {
        unawaited(_handleBackgroundError('Zone error: $error'));
      }
      try {
        await AppStores.instance.close();
      } catch (_) {}
    },
  );
}

bool _isAppInBackground() {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == AppLifecycleState.inactive ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached;
}

Future<void> _handleBackgroundError(String reason) async {
  await Log.saveBackgroundSnapshot(reason: reason);
  if (!await Log.errorNotificationsEnabled()) {
    return;
  }
  await initLocalNotifications();
  await showSupportLogNotification();
}

Future<void> _runStartupPhase(String phase, List<String> cameraNames) async {
  if (phase == _startupPhaseCameraInit) {
    _checkServerVersion();
  }

  if (phase == _startupPhaseCameraInit && cameraNames.isEmpty) {
    return;
  }

  final rootToken = RootIsolateToken.instance;
  if (rootToken == null) {
    Log.w('RootIsolateToken unavailable; running startup on main isolate');
    await _runStartupPhaseOnMain(phase, cameraNames);
    return;
  }

  final receivePort = ReceivePort();
  try {
    await Isolate.spawn(_startupPhaseEntry, {
      'sendPort': receivePort.sendPort,
      'rootToken': rootToken,
      'phase': phase,
      'cameraNames': cameraNames,
    });
  } catch (e, st) {
    Log.e('Failed to spawn startup isolate: $e\n$st');
    await _runStartupPhaseOnMain(phase, cameraNames);
    receivePort.close();
    return;
  }

  final result = await receivePort.first;
  receivePort.close();
  if (result is Map && result['error'] != null) {
    final stack = result['stack'];
    throw Exception(
      'Startup isolate failed: ${result['error']}${stack == null ? '' : '\n$stack'}',
    );
  }
}

Future<void> _runStartupPhaseOnMain(
  String phase,
  List<String> cameraNames,
) async {
  switch (phase) {
    case _startupPhaseCameraInit:
      await RustLibGuard.initOnce();
      await _initAllCameras(cameraNames: cameraNames);
      return;
    case _startupPhasePostFirebase:
      await RustLibGuard.initOnce();
      try {
        await _checkForUpdates(); // Must come before download scheduler
        await ThumbnailManager.checkThumbnailsForAll();
      } catch (e) {
        Log.d("Caught error - $e");
      }

      await DownloadScheduler.init();
      await HeartbeatScheduler.registerPeriodicTask();
      unawaited(
        Future<void>.delayed(Duration.zero, () {
          doAllHeartbeatTasks(false);
        }),
      );
      return;
    default:
      Log.w('Unknown startup phase: $phase');
  }
}

@pragma('vm:entry-point')
void _startupPhaseEntry(Map<String, dynamic> message) async {
  final SendPort sendPort = message['sendPort'] as SendPort;
  try {
    final RootIsolateToken rootToken = message['rootToken'] as RootIsolateToken;
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
    DartPluginRegistrant.ensureInitialized();
    Log.init();
    final traceId = newTraceId('startup');
    Log.setDefaultContext(traceId);

    final phase = message['phase'] as String;
    final cameraNames = (message['cameraNames'] as List).cast<String>();
    await _runStartupPhaseOnMain(phase, cameraNames);
    sendPort.send({'ok': true});
  } catch (e, st) {
    Log.e('Startup isolate error: $e\n$st');
    sendPort.send({'error': e.toString(), 'stack': st.toString()});
  }
}

Future<void> _initializeApp(ThemeProvider themeProvider) async {
  Log.d("Initialization started");
  await RustLibGuard.initOnce();

  Log.d("After RustLibGuard.initOnce");

  // The native logger causes some reentrancy deadlocks.
  // Only enable if needed.

  if (kDebugMode) {
    createLogStream().listen((event) {
      var level = event.level;
      var tag = event.tag; // Represents the calling file
      final context = event.traceId ?? '';

      // For now, we filter out all Rust code that isn't from us in release mode.
      if (kReleaseMode &&
          (!tag.contains("secluso") && !tag.startsWith("src"))) {
        return;
      }

      // We filter out OpenMLS as we don't need OpenMLS logging leaking data (although this shouldn't be a risk regardless due to release only allowing info and above in logging)
      if (tag.contains("openmls")) {
        return;
      }

      Log.runWithContextSync(context, () {
        if (level == 0 || level == 1) {
          Log.d(event.msg, customLocation: event.tag);
        } else if (level == 2) {
          Log.i(event.msg, customLocation: event.tag);
        } else {
          Log.w(event.msg, customLocation: event.tag);
        }
      });
    });
  }

  Log.d("After createLogStream().listen()");
  await ReviewEnvironment.instance.ensureLoaded();
  await AppStores.init();
  await runMigrations(); // Must run right after App Store initialization

  final cameraNames = await _cameraNamesFromStore();
  await _runStartupPhase(
    _startupPhaseCameraInit,
    cameraNames,
  ); // Must come after App Store and Rust Lib initialization

  // We wait to initialize Firebase and the download scheduler until our cameras have been initialized
  var prefs = await SharedPreferences.getInstance();
  final androidPushPlatform =
      Platform.isAndroid ? AndroidPushTransport.fromPrefs(prefs) : null;
  final useUnifiedPush =
      Platform.isAndroid &&
      androidPushPlatform != null &&
      AndroidPushTransport.isUnifiedValue(androidPushPlatform);

  if (prefs.containsKey(PrefKeys.serverAddr)) {
    if (Platform.isAndroid && !useUnifiedPush) {
      final fcmConfig = FcmConfig.fromPrefs(prefs);
      if (fcmConfig == null) {
        Log.e("Missing cached FCM config; clearing server credentials");
        await _invalidateServerCredentials(prefs);
      } else {
        try {
          await FirebaseInit.ensure(fcmConfig);
        } catch (e, st) {
          Log.e("Firebase init failed: $e\n$st");
        }
      }
    }
  }

  await _runStartupPhase(_startupPhasePostFirebase, cameraNames);
  unawaited(StorageManager.runAutomaticMaintenance());

  QueueProcessor.instance.start();
  QueueProcessor.instance.signalNewFile();

  _mainReceivePort.listen((message) {
    if (message == 'signal_new_file') {
      QueueProcessor.instance.signalNewFile();
    }
  });

  IsolateNameServer.removePortNameMapping(queueProcessorPortName);
  IsolateNameServer.registerPortWithName(
    _mainReceivePort.sendPort,
    queueProcessorPortName,
  );

  if (useUnifiedPush) {
    final hasDistributor =
        await UnifiedPushService.instance.tryUseCurrentOrDefaultDistributor();
    if (hasDistributor) {
      await UnifiedPushService.instance.register();
    } else {
      Log.d('Skipping UnifiedPush register; no distributor selected');
    }
  }

  if (Platform.isIOS || FirebaseInit.isInitialized || useUnifiedPush) {
    await PushNotificationService.instance.init();
  } else {
    Log.d("Skipping PushNotificationService.init; Firebase not initialized");
  }

  // Theme is preloaded before runApp so we do not briefly boot the app in the
  // wrong color scheme and flash light mode during startup.
  Log.d("Using preloaded darkTheme value: ${themeProvider.isDarkMode}");
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    required this.initialDarkMode,
    required this.releaseFirstFrameOnReady,
  });

  final bool initialDarkMode;
  final bool releaseFirstFrameOnReady;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late final ThemeProvider _themeProvider = ThemeProvider(
    widget.initialDarkMode,
  );
  bool _isReady = _designPreviewBoot;
  bool _initStarted = false;
  String? _initError;
  bool _firstFrameReleased = false;

  @override
  void initState() {
    super.initState();
    if (_designPreviewBoot) {
      _releaseFirstFrameIfNeeded();
      return;
    }
    _startInitialization();
  }

  Future<void> _startInitialization() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      await _initializeApp(_themeProvider);
      if (mounted) {
        setState(() {
          _isReady = true;
        });
      }
      _releaseFirstFrameIfNeeded();
    } catch (e, st) {
      Log.e("Initialization failed: $e\n$st");
      if (mounted) {
        setState(() {
          _initError = "Initialization failed";
        });
      }
      _releaseFirstFrameIfNeeded();
    }
  }

  void _releaseFirstFrameIfNeeded() {
    if (!widget.releaseFirstFrameOnReady || _firstFrameReleased) {
      return;
    }
    WidgetsBinding.instance.allowFirstFrame();
    _firstFrameReleased = true;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider.value(value: _themeProvider)],
      child: MyApp(isReady: _isReady, initError: _initError),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.errorMessage});

  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (errorMessage == null) {
      // Keep the normal startup placeholder as plain black only. Android is
      // already showing a native launch splash before Flutter draws, so adding
      // a second centered-icon screen here just makes startup feel like it is
      // stepping through one extra fake page before the real UI appears.
      return const ColoredBox(
        color: Color(0xFF050505),
        child: SizedBox.expand(),
      );
    }

    return SeclusoScaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SeclusoGlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 32,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SeclusoStatusChip(
                      label: 'Startup interrupted',
                      icon: Icons.report_problem_outlined,
                      color: SeclusoColors.warning,
                    ),
                    const SizedBox(height: 24),
                    Image.asset(
                      'assets/icon_centered.png',
                      width: 68,
                      height: 68,
                    ),
                    const SizedBox(height: 18),
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: Theme.of(context).textTheme.headlineMedium,
                        children: [
                          const TextSpan(text: 'Secluso\n'),
                          TextSpan(
                            text: 'Share nothing.',
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(
                              color: SeclusoColors.blueSoft,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VersionBlockScreen extends StatefulWidget {
  const VersionBlockScreen({super.key, required this.info});

  final VersionGateInfo info;

  @override
  State<VersionBlockScreen> createState() => _VersionBlockScreenState();
}

class _VersionBlockScreenState extends State<VersionBlockScreen> {
  late Future<List<String>> _cameraNamesFuture;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _cameraNamesFuture = _cameraNamesFromStore();
  }

  Future<void> _runPrimaryAction(List<String> cameraNames) async {
    if (_isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      if (cameraNames.isNotEmpty) {
        await _removeAllCamerasAndChangeServer(cameraNames: cameraNames);
      } else {
        await _openServerChangeFlow();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _cameraNamesFuture = _cameraNamesFromStore();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SeclusoGlassCard(
                child: FutureBuilder<List<String>>(
                  future: _cameraNamesFuture,
                  builder: (context, snapshot) {
                    final cameraNames = snapshot.data ?? const <String>[];
                    final hasAttachedCameras = cameraNames.isNotEmpty;
                    final primaryLabel =
                        hasAttachedCameras
                            ? cameraNames.length == 1
                                ? 'Remove camera and change server'
                                : 'Remove cameras and change server'
                            : 'Change server';

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SeclusoStatusChip(
                          label: 'Version check required',
                          color: SeclusoColors.warning,
                        ),
                        const SizedBox(height: 20),
                        Image.asset(
                          'assets/icon_centered.png',
                          width: 68,
                          height: 68,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          widget.info.title,
                          style: theme.textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.info.message,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 22),
                        SeclusoGlassCard(
                          borderRadius: 22,
                          padding: const EdgeInsets.all(14),
                          tint: theme.colorScheme.surface.withValues(
                            alpha: 0.46,
                          ),
                          child: Column(
                            children: [
                              _VersionRow(
                                label: 'Server version',
                                value: widget.info.serverVersion,
                              ),
                              const SizedBox(height: 10),
                              _VersionRow(
                                label: 'App version',
                                value: widget.info.clientVersion,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          hasAttachedCameras
                              ? 'A paired camera is still attached to this relay. Remove it here, then the app will take you to relay setup.'
                              : 'Update or install a compatible build to continue.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed:
                              _isProcessing
                                  ? null
                                  : () => _runPrimaryAction(cameraNames),
                          child:
                              _isProcessing
                                  ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : Text(primaryLabel),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _isProcessing ? null : _checkServerVersion,
                          child: const Text('Retry version check'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.labelMedium)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

Future<List<String>> _cameraNamesFromStore() async {
  final cameras = await AppStores.instance.cameraStore.getAllAsync();
  return cameras.map((camera) => camera.name).toList();
}

Future<void> _initAllCameras({List<String>? cameraNames}) async {
  final names = cameraNames ?? await _cameraNamesFromStore();
  for (var cameraName in names) {
    // TODO: Check if false, perhaps there's some weird error we might need to look into...
    await initialize(cameraName);
  }
}

Future<void> _openServerChangeFlow() async {
  final prefs = await SharedPreferences.getInstance();
  await _clearStoredRelayConnection(prefs);
  if (CameraUiBridge.switchShellTabCallback != null) {
    CameraUiBridge.switchShellTabCallback!(2, openRelayScanOnLoad: true);
    return;
  }
  final nav = navigatorKey.currentState;
  if (nav == null) {
    return;
  }
  await nav.pushAndRemoveUntil(
    MaterialPageRoute(
      builder:
          (context) =>
              const AppShell(initialIndex: 2, openRelayScanOnLoad: true),
    ),
    (_) => false,
  );
}

Future<void> _removeAllCamerasAndChangeServer({
  List<String>? cameraNames,
}) async {
  final attachedCameraNames = cameraNames ?? await _cameraNamesFromStore();
  if (attachedCameraNames.isNotEmpty) {
    for (final cameraName in attachedCameraNames) {
      await CameraUiBridge.deleteCamera(cameraName);
    }
    CameraUiBridge.refreshCameraListCallback?.call();
    ScaffoldMessenger.maybeOf(
      navigatorKey.currentState?.context ?? navigatorKey.currentContext!,
    )?.showSnackBar(
      const SnackBar(
        content: Text(
          'Attached cameras removed. Choose a new relay to continue.',
        ),
      ),
    );
  }

  await _openServerChangeFlow();
}

Future<void> _checkServerVersion() async {
  if (_versionCheckInFlight) {
    return;
  }
  _versionCheckInFlight = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    final hasCredentials =
        prefs.containsKey(PrefKeys.serverAddr) &&
        prefs.containsKey(PrefKeys.serverUsername) &&
        prefs.containsKey(PrefKeys.serverPassword);
    if (!hasCredentials) {
      Log.i('Skipping server version check; missing server credentials');
      _cancelVersionCheckRetry();
      return;
    }

    // Call the status endpoint and compare versions
    final serverVersionResult =
        await HttpClientService.instance.fetchServerVersion();

    if (serverVersionResult.isFailure) {
      Log.w("Failed to fetch server version: ${serverVersionResult.error}");

      // Require client to upgrade (or downgrade) their app to go further. Block screen.
      _scheduleVersionCheckRetry();
      return;
    }

    final serverVersion = serverVersionResult.value!;
    final clientVersion = await rustLibVersion();

    if (serverVersion != clientVersion) {
      Log.i(
        "Server version ($serverVersion) differs from client version ($clientVersion)",
      );
      // Require client to upgrade (or downgrade) their app to go further. Block screen.
      VersionGate.block(
        VersionGateInfo.mismatch(
          serverVersion: serverVersion,
          clientVersion: clientVersion,
        ),
      );
      _cancelVersionCheckRetry();
      return;
    }

    VersionGate.clear();
    _cancelVersionCheckRetry();
  } catch (e, st) {
    Log.e("Error checking server version: $e\n$st");
    _scheduleVersionCheckRetry();
  } finally {
    _versionCheckInFlight = false;
  }
}

void _scheduleVersionCheckRetry() {
  if (_versionCheckRetryTimer != null) {
    return;
  }
  _versionCheckRetryTimer = Timer(_versionCheckRetryDelay, () {
    _versionCheckRetryTimer = null;
    _checkServerVersion();
  });
}

void _cancelVersionCheckRetry() {
  _versionCheckRetryTimer?.cancel();
  _versionCheckRetryTimer = null;
}

Future<void> _invalidateServerCredentials(SharedPreferences prefs) async {
  await prefs.remove(PrefKeys.serverAddr);
  await prefs.remove(PrefKeys.serverUsername);
  await prefs.remove(PrefKeys.serverPassword);
  await prefs.remove(PrefKeys.fcmConfigJson);
}

Future<void> _clearStoredRelayConnection(SharedPreferences prefs) async {
  final androidPushPlatform = AndroidPushTransport.fromPrefs(prefs);
  await _invalidateServerCredentials(prefs);
  await prefs.remove(PrefKeys.relayConnectionKind);
  await prefs.remove(PrefKeys.needUpdateFcmToken);
  await prefs.remove(PrefKeys.needUpdateIosRelayBinding);
  await prefs.remove(PrefKeys.needUploadIosNotificationTarget);
  await prefs.remove(PrefKeys.iosApnsToken);
  await prefs.remove(PrefKeys.iosRelayHubToken);
  await prefs.remove(PrefKeys.iosRelayHubTokenExpiryMs);
  await prefs.remove(PrefKeys.iosRelayBindingJson);
  await prefs.remove(PrefKeys.unifiedPushEndpointUrl);
  await prefs.remove(PrefKeys.unifiedPushPubKey);
  await prefs.remove(PrefKeys.unifiedPushAuth);
  HttpClientService.instance.resetVersionGateState();
  VersionGate.clear();
  _cancelVersionCheckRetry();
  if (Platform.isAndroid &&
      AndroidPushTransport.isUnifiedValue(androidPushPlatform)) {
    await UnifiedPushService.instance.deactivate();
  }
}

/// Query server for cameras that have video updates and proceed to queue them for download
Future<void> _checkForUpdates() async {
  final cameraNamesResult = await HttpClientService.instance
      .bulkCheckAvailableCameras(0);

  if (cameraNamesResult.isFailure ||
      (cameraNamesResult.isSuccess && cameraNamesResult.value!.isEmpty)) {
    return;
  }

  var cameraNames = cameraNamesResult.value!;
  final cameraSet = await AppCoordinationState.getCameraSet();
  if (cameraSet.isNotEmpty) {
    final cameraSetLookup = cameraSet.toSet();
    final filtered =
        cameraNames
            .where((cameraName) => cameraSetLookup.contains(cameraName))
            .toList();
    final dropped =
        cameraNames
            .where((cameraName) => !cameraSetLookup.contains(cameraName))
            .toList();
    if (dropped.isNotEmpty) {
      Log.w("Dropping unknown cameras from update queue: $dropped");
    }
    cameraNames = filtered;
  }
  cameraNames =
      cameraNames.where((cameraName) => cameraName.trim().isNotEmpty).toList();
  if (cameraNames.isEmpty) {
    return;
  }

  // TODO: This is essentially a clone of my previous implementation in scheduler.dart
  // Adds the camera to the waiting list if not already in there.
  if (await lock(Constants.cameraWaitingLock)) {
    try {
      Log.d("Adding to queue for $cameraNames");
      for (final camera in cameraNames) {
        final currentCameraList = await AppCoordinationState.getDownloadQueue();
        if (!currentCameraList.contains(camera)) {
          Log.d("Added to pre-existing list for $camera");
          await AppCoordinationState.enqueueDownloadCamera(camera);
        } else {
          Log.d("List already contained $camera");
        }
      }
    } finally {
      // Ensure it's unlocked.
      await unlock(Constants.cameraWaitingLock);
    }
  }

  if (cameraNames.isNotEmpty) {
    DownloadScheduler.scheduleVideoDownload(""); // Empty string means all.
  }
}

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

class StartupRoleGate extends StatefulWidget {
  const StartupRoleGate({super.key});

  @override
  State<StartupRoleGate> createState() => _StartupRoleGateState();
}

class _StartupRoleGateState extends State<StartupRoleGate> {
  Widget? _page;
  late final VoidCallback _roleSelectionListener;

  @override
  void initState() {
    super.initState();

    _roleSelectionListener = () {
      _show(_roleSelectPage());
    };
    DeviceRoleController.roleSelectionRequests.addListener(
      _roleSelectionListener,
    );

    _loadInitialPage();
  }

  @override
  void dispose() {
    DeviceRoleController.roleSelectionRequests.removeListener(
      _roleSelectionListener,
    );
    super.dispose();
  }

  Future<void> _loadInitialPage() async {
    final prefs = await SharedPreferences.getInstance();
    final hasRelay = (prefs.getString(PrefKeys.serverAddr) ?? '').isNotEmpty;
    final role = prefs.getString(PrefKeys.deviceRole);

    if (role == DeviceRoleController.cameraRole && cameraRoleSupported) {
      _show(_pairingPage());
      return;
    }

    if (hasRelay || role == DeviceRoleController.viewerRole || !cameraRoleSupported) {
      _show(const AppShell());
      return;
    }

    _show(_roleSelectPage());
  }

  void _show(Widget page) {
    if (!mounted) return;
    setState(() => _page = page);
  }

  Widget _roleSelectPage() => RoleSelectPage(
    onWatchCameras: _chooseViewerRole,
    onBeCamera: _chooseCameraRole,
  );

  Widget _pairingPage() => CameraRolePairingPage(
    onConnected: (isRunning) => _show(_recordingPage(initialRunning: isRunning)),
    onClose: _returnToRoleSelect,
  );

  Widget _recordingPage({bool initialRunning = false}) => CameraRoleRecordingPage(
    initialRunning: initialRunning,
    onStart: _startCameraRecording,
    onStop: _stopCameraAndReturnToRoleSelect,
    onResetCamera: _resetCameraAndReturnToPairing,
    onSwitchRole: _switchFromCameraRole,
  );

  Future<void> _returnToRoleSelect() async {
    await DeviceRoleController.clearRole();
    _show(_roleSelectPage());
  }

  Widget _cameraStoppingPage() => const Scaffold(
    backgroundColor: Color(0xFF0B0B0B),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Stopping camera…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Wait while we wind down the camera recording.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _stopCameraAndReturnToRoleSelect() async {
    if (!mounted) return;

    _show(_cameraStoppingPage());

    try {
      await AndroidCameraHubLauncher.stopHub();

      if (!mounted) return;

      await _returnToRoleSelect();
    } catch (e) {
      if (!mounted) return;

      _show(_recordingPage(initialRunning: true));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to stop camera: $e'),
          ),
        );
      });
    }
  }

  Future<void> _startCameraRecording() async {
    await AndroidCameraHubLauncher.startHub();
  }

  Future<void> _chooseViewerRole() async {
    await DeviceRoleController.setViewerRole();
    _show(const AppShell(initialIndex: 2));
  }

  Future<void> _chooseCameraRole() async {
    if (!cameraRoleSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera role is only supported on Android.'),
        ),
      );
      return;
    }

    await DeviceRoleController.setCameraRole();
    _show(_pairingPage());
  }

  Future<void> _resetCameraAndReturnToPairing() async {
    await AndroidCameraHubLauncher.resetCameraState();

    if (!mounted) return;
    _show(_pairingPage());
  }

  Future<void> _switchFromCameraRole() async {
    final isStillPaired =
        await AndroidCameraHubLauncher.hasCompletedFirstPairing();

    if (isStillPaired) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reset this camera before switching roles.',
          ),
        ),
      );
      return;
    }

    await DeviceRoleController.clearRole();

    if (!mounted) return;
    _show(_roleSelectPage());
  }

  @override
  Widget build(BuildContext context) {
    return _page ?? const SplashScreen();
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.isReady, this.initError});

  final bool isReady;
  final String? initError;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late SharedPreferences prefs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    Log.d("Initializing prefs");
    prefs = await SharedPreferences.getInstance();
    PushNotificationService.tryUploadIfNeeded(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isReady) {
      Log.i("App Lifecycle State set to RESUMED");
      PushNotificationService.tryUploadIfNeeded(false);
      _initAllCameras(); // I'm not sure if this is necessary or not. It could be good to periodically check for initialization though.
      _checkServerVersion();
      _checkForUpdates();
      ThumbnailManager.checkThumbnailsForAll();
      QueueProcessor.instance
          .signalNewFile(); // Try to process any new uploads now
    }

    if (state == AppLifecycleState.detached) {
      // App is about to be terminated – close the DB to release file locks.
      // No 'await' here since Flutter may be tearing down the isolate; this is best-effort.
      RustLibGuard.shutdownOnce();
      try {
        AppStores.instance.close();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
    IsolateNameServer.removePortNameMapping(queueProcessorPortName);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final Widget home =
        widget.isReady
            ? PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop) return;
                try {
                  await RustLibGuard.shutdownOnce();
                  await AppStores.instance.close();
                } catch (_) {}
                final nav = navigatorKey.currentState;
                if (nav != null && nav.canPop()) {
                  nav.pop(result);
                } else {
                  SystemNavigator.pop();
                }
              },
              child:
                  (kDebugMode || _captureMode)
                      ? (_launchDesignController
                          ? DesignCommandPage(
                            commandFilePath: _designCommandFile,
                          )
                          : designLabTargetPage(
                                _launchDesignTarget,
                                themeName:
                                    themeProvider.isDarkMode ? 'dark' : 'light',
                              ) ??
                              (_launchDesignLab
                                  ? const DesignLabPage()
                                  : const StartupRoleGate()))
                      : const StartupRoleGate(),
            )
            : SplashScreen(errorMessage: widget.initError);

    return MaterialApp(
      title: 'Secluso Camera',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      theme: SeclusoTheme.light(),
      darkTheme: SeclusoTheme.dark(),
      themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: home,
      builder: (context, child) {
        final base = child ?? const SizedBox.shrink();
        final appContent = ValueListenableBuilder<VersionGateInfo?>(
          valueListenable: VersionGate.notifier,
          builder: (context, gateInfo, _) {
            if (gateInfo == null) {
              return base;
            }
            return Stack(
              children: [
                base,
                Positioned.fill(child: VersionBlockScreen(info: gateInfo)),
              ],
            );
          },
        );
        final mediaQuery = MediaQuery.maybeOf(context);
        if (mediaQuery != null) {
          return MediaQuery(
            data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
            child: appContent,
          );
        }
        return appContent;
      },
    );
  }
}
