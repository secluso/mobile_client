//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/android_push_transport.dart';
import 'package:secluso_flutter/notifications/firebase.dart';
import 'package:secluso_flutter/notifications/unified_push_service.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'home_page.dart';
import 'package:secluso_flutter/utilities/firebase_init.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/server_backend.dart';
import 'package:secluso_flutter/utilities/enterprise_session.dart';
import 'package:secluso_flutter/utilities/billing_service.dart';
import 'package:secluso_flutter/utilities/distribution.dart';
import 'package:secluso_flutter/utilities/relay_environment.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:secluso_flutter/routes/system/relay_account_page.dart';
import 'package:secluso_flutter/routes/system/account_page.dart';
import 'package:secluso_flutter/routes/system/camera_plan_page.dart';
import 'package:secluso_flutter/routes/system/plans_page.dart';
import 'package:secluso_flutter/routes/system/relay_detail_page.dart';
import 'package:secluso_flutter/routes/system/setup_choice_page.dart';
import 'package:secluso_flutter/routes/camera-role/platform.dart';
import 'package:secluso_flutter/routes/system/share_camera_page.dart';
import 'package:secluso_flutter/routes/system/system_models.dart';
import 'package:secluso_flutter/routes/system/system_page.dart';
import 'package:secluso_flutter/routes/system/system_theme.dart';
import 'package:secluso_flutter/ui/secluso_qr_reader.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_shell_ui.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/utilities/version_gate.dart';
import 'package:secluso_flutter/routes/camera/camera_ui_bridge.dart';
import 'package:secluso_flutter/utilities/review_environment.dart';
import 'camera/new/qr_scan.dart';
import 'camera/view_camera.dart';

class UserCredentialsQrPayload {
  final String serverUsername;
  final String serverPassword;
  final String serverAddress;
  final String? reviewRelayId;
  final String? reviewRelayLabel;

  /// When these credentials came from the account login page
  final bool isAccountLogin;

  /// Which of the account's subscriptions this device works under.
  final String? subscriptionUuid;

  UserCredentialsQrPayload({
    required this.serverUsername,
    required this.serverPassword,
    required this.serverAddress,
    this.reviewRelayId,
    this.reviewRelayLabel,
    this.isAccountLogin = false,
    this.subscriptionUuid,
  });

  factory UserCredentialsQrPayload.accountLogin({
    required String serverUsername,
    required String serverPassword,
    required String serverAddress,
    String? subscriptionUuid,
  }) {
    return UserCredentialsQrPayload(
      serverUsername: serverUsername,
      serverPassword: serverPassword,
      serverAddress: serverAddress,
      isAccountLogin: true,
      subscriptionUuid: subscriptionUuid,
    );
  }

  factory UserCredentialsQrPayload.review({
    required String relayId,
    required String relayLabel,
    required String relayAddress,
  }) {
    return UserCredentialsQrPayload(
      serverUsername: '',
      serverPassword: '',
      serverAddress: relayAddress,
      reviewRelayId: relayId,
      reviewRelayLabel: relayLabel,
    );
  }

  bool get isReviewRelay => reviewRelayId != null;
}

const String _officialRelayConnectionKind = 'official';

/// Where the official relay is (not self hosted).
/// Prod/staging
String get _officialRelayAddress => RelayEnvironment.officialAddress;
const String _selfHostedRelayConnectionKind = 'self_hosted';

class ServerPage extends StatefulWidget {
  final bool showBackButton;
  final bool? previewHasSynced;
  final String? previewServerAddr;
  final List<String>? previewCameraNames;
  final bool showShellChrome;
  final bool openRelayScanOnLoad;
  final int relayScanRequestId;

  final VoidCallback? onRelayConnected;

  const ServerPage({
    super.key,
    required this.showBackButton,
    this.previewHasSynced,
    this.previewServerAddr,
    this.previewCameraNames,
    this.showShellChrome = false,
    this.openRelayScanOnLoad = false,
    this.relayScanRequestId = 0,
    this.onRelayConnected,
  });

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  String? serverAddr;
  List<String> _cameraNames = const [];
  String? _accountEmail;
  CameraPlan? _accountPlan;
  AccountPlanSummary? _accountPlanSummary;
  // camera name -> stored object bytes on the relay, from /usage by_group.
  Map<String, int> _perCameraBytes = const {};
  // The account plan's storage cap in bytes
  int _planCapBytes = 10 * 1024 * 1024 * 1024;

  final TextEditingController _ipController = TextEditingController();
  bool hasSynced = false;
  final ValueNotifier<bool> _isDialogOpen = ValueNotifier(false);
  bool _didAutoOpenRelayScan = false;

  bool _relayAuthInFlight = false;
  int _lastHandledRelayScanRequestId = -1;
  String? _pendingRelayConnectionKind;

  bool get _isPreviewMode => widget.previewHasSynced != null;

  void _applyPreviewState() {
    hasSynced = widget.previewHasSynced!;
    serverAddr = widget.previewServerAddr;
    _cameraNames =
        widget.previewCameraNames ??
        (hasSynced && !widget.showShellChrome
            ? const ['Front Door', 'Living Room', 'Backyard']
            : const []);
    _ipController.text = widget.previewServerAddr ?? '';
  }

  @override
  void initState() {
    super.initState();
    if (_isPreviewMode) {
      _applyPreviewState();
      _maybeAutoOpenRelayScan();
      return;
    }
    _loadServerSettings();
  }

  void _maybeAutoOpenRelayScan() {
    final shouldAutoOpen =
        (widget.openRelayScanOnLoad && !_didAutoOpenRelayScan) ||
        (widget.relayScanRequestId > 0 &&
            widget.relayScanRequestId > _lastHandledRelayScanRequestId);
    if (!shouldAutoOpen || hasSynced) {
      return;
    }
    _didAutoOpenRelayScan = true;
    _lastHandledRelayScanRequestId = widget.relayScanRequestId;
    if (!_isPreviewMode) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || hasSynced) return;
      unawaited(_openRelayScanFlow());
    });
  }

  @override
  void didUpdateWidget(covariant ServerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasPreviewMode = oldWidget.previewHasSynced != null;
    if (_isPreviewMode) {
      if (!wasPreviewMode ||
          oldWidget.previewHasSynced != widget.previewHasSynced ||
          oldWidget.previewServerAddr != widget.previewServerAddr ||
          oldWidget.previewCameraNames != widget.previewCameraNames) {
        setState(_applyPreviewState);
      }
    } else if (wasPreviewMode) {
      unawaited(_loadServerSettings());
    }
    if (oldWidget.relayScanRequestId != widget.relayScanRequestId ||
        (!oldWidget.openRelayScanOnLoad && widget.openRelayScanOnLoad)) {
      if (_isPreviewMode) {
        _maybeAutoOpenRelayScan();
      } else {
        unawaited(_loadServerSettings());
      }
    }
  }

  Future<void> _loadServerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedServerAddr = prefs.getString(PrefKeys.serverAddr);
    final synced = savedServerAddr != null && savedServerAddr.isNotEmpty;
    final cameraNames = synced ? await _fetchCameraNames() : const <String>[];
    if (!mounted) return;
    setState(() {
      serverAddr = savedServerAddr;
      hasSynced = synced;
      _cameraNames = cameraNames;
      _accountEmail = prefs.getString(PrefKeys.serverUsername);
      _ipController.text = serverAddr ?? '';
    });
    CameraUiBridge.relayConnected.value = synced;
    if (synced) {
      unawaited(_loadAccountPlan());
    }
    _maybeAutoOpenRelayScan();
  }

  /// What the System tab shows per camera
  Future<void> _loadAccountPlan() async {
    if (_isSelfHostedRelay) return;
    final result = await HttpClientService.instance.fetchAccountUsage();
    // Renewal rides in the token
    final sub = await HttpClientService.instance
        .currentSubscription()
        .catchError((_) => null);
    // Server-settable price copy
    final pricing = await HttpClientService.instance.fetchPricing().catchError(
      (_) => (premium: null, updatedAtSeconds: null),
    );
    // Attribute stored bytes per camera from the relay's group totals.
    final perCamera = await result.fold(
      (usage) => HttpClientService.instance.perCameraBytes(usage.byGroup),
      (_) async => const <String, int>{},
    );
    if (!mounted) return;
    result.fold((usage) {
      final tier = _planTierFromName(usage.tier);
      const gb = 1024 * 1024 * 1024;
      final cap = tier == PlanTier.free ? 10 * gb : 1024 * gb;
      final fraction =
          cap > 0 ? (usage.storedBytes / cap).clamp(0.0, 1.0) : 0.0;
      _perCameraBytes = perCamera;
      _planCapBytes = cap;
      setState(() {
        _accountPlan = CameraPlan(
          tier: tier,
          usage: '${_formatBytes(usage.storedBytes)} of ${_formatBytes(cap)}',
        );
        _accountPlanSummary = AccountPlanSummary(
          tier: tier,
          price: _priceLabelFor(
            tier,
            pricing.premium,
            pricing.updatedAtSeconds,
          ),
          renewal: _renewalLabel(sub?.expiresAt),
          usedLabel: _formatBytes(usage.storedBytes),
          limitLabel: _formatBytes(cap),
          usedFraction: fraction.toDouble(),
          viewersNote: _viewersNote(tier),
          // Cameras are filled in fresh when the page opens.
          cameras: const [],
        );
      });
    }, (_) {});
  }

  // A server-provided price with a newer date wins
  // A fresh app build (newer date) wins back over an old server value.
  static const _bundledPremiumPrice = r'$6/mo';
  static const _bundledAnonymousPrice = r'$10/mo';
  static final DateTime _bundledPriceAsOf = DateTime.utc(2026, 8, 23);

  static String _priceLabelFor(
    PlanTier tier,
    String? serverPremiumPrice,
    int? serverUpdatedAtSeconds,
  ) => switch (tier) {
    // Free shows no price; the tier name already says "Free".
    PlanTier.free => '',
    PlanTier.premium => _premiumPriceLabel(
      serverPremiumPrice,
      serverUpdatedAtSeconds,
    ),
    PlanTier.anonymous => _bundledAnonymousPrice,
  };

  static String _premiumPriceLabel(String? serverPrice, int? serverUpdatedAt) {
    final storePrice = BillingService.instance.premiumProduct?.price;
    if (storePrice != null && storePrice.isNotEmpty) return storePrice;
    if (serverPrice != null &&
        serverPrice.isNotEmpty &&
        serverUpdatedAt != null) {
      final serverDate = DateTime.fromMillisecondsSinceEpoch(
        serverUpdatedAt * 1000,
        isUtc: true,
      );
      if (serverDate.isAfter(_bundledPriceAsOf)) return serverPrice;
    }
    return _bundledPremiumPrice;
  }

  static PlanTier _planTierFromName(String name) => switch (name) {
    'premium' => PlanTier.premium,
    'anonymous' => PlanTier.anonymous,
    _ => PlanTier.free,
  };

  /// Member cap per tier, mirroring the server's tier registry.
  static String _viewersNote(PlanTier tier) =>
      tier == PlanTier.free ? '1 viewer' : 'up to 6 viewers';

  /// "renews <date>" from unix seconds, or "" when there's nothing to show
  static String _renewalLabel(int? expiresAtSeconds) {
    if (expiresAtSeconds == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final date = DateTime.fromMillisecondsSinceEpoch(expiresAtSeconds * 1000);
    return 'renews ${months[date.month - 1]} ${date.day}';
  }

  static String _formatBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    const tb = gb * 1024;
    String trim(double value) =>
        value == value.roundToDouble()
            ? value.toStringAsFixed(0)
            : value.toStringAsFixed(1);
    if (bytes >= tb) return '${trim(bytes / tb)} TB';
    if (bytes >= gb) return '${trim(bytes / gb)} GB';
    if (bytes >= mb) return '${trim(bytes / mb)} MB';
    return '${(bytes / kb).toStringAsFixed(0)} KB';
  }

  Future<List<String>> _fetchCameraNames() async {
    try {
      if (!AppStores.isInitialized) {
        await AppStores.init();
      }
      final cameras = await AppStores.instance.cameraStore.getAllAsync();
      return cameras.map((camera) => camera.name).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Uri? _validatedRelayUri(String rawValue) {
    final parsed = Uri.tryParse(rawValue.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return null;
    }
    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      return null;
    }
    return parsed;
  }

  Future<bool> _connectReviewRelayWithFlow(ReviewRelayQrPayload payload) async {
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => _ReviewRelayConnectionPage(payload: payload),
      ),
    );
    return connected ?? false;
  }

  Future<void> _saveServerSettings(
    UserCredentialsQrPayload credentialsFull,
  ) async {
    final relayConnectionKind = _resolvedRelayConnectionKind();
    try {
      if (credentialsFull.isReviewRelay) {
        final prefs = await SharedPreferences.getInstance();
        final prevServerAddr = prefs.getString(PrefKeys.serverAddr);
        final currentCameraNames =
            _isPreviewMode ? _cameraNames : await _fetchCameraNames();
        final hasExistingRelay =
            prevServerAddr != null && prevServerAddr.isNotEmpty;
        if (hasExistingRelay || currentCameraNames.isNotEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'The App Review relay QR only works on a clean app state. Remove your current relay and cameras first.',
              ),
            ),
          );
          return;
        }

        final reviewPayload = ReviewRelayQrPayload(
          relayId: credentialsFull.reviewRelayId!,
          relayLabel: credentialsFull.reviewRelayLabel ?? 'Review Relay',
          relayAddress: credentialsFull.serverAddress,
        );
        final connected = await _connectReviewRelayWithFlow(reviewPayload);
        if (!connected || !mounted) return;
        await _persistRelayConnectionKind(relayConnectionKind);
        if (!mounted) return;
        setState(() {
          serverAddr = credentialsFull.serverAddress;
          hasSynced = true;
          _cameraNames =
              ReviewEnvironment.instance.session?.cameraNames ?? const [];
          _ipController.text = credentialsFull.serverAddress;
        });
        CameraUiBridge.relayConnected.value = true;
        CameraUiBridge.refreshCameraListCallback?.call();
        widget.onRelayConnected?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${credentialsFull.reviewRelayLabel ?? 'Review relay'} connected.',
            ),
          ),
        );
        return;
      }

      if (ReviewEnvironment.instance.isActive) {
        await ReviewEnvironment.instance.clear();
      }

      // TODO: Check how this handles on failure... bad QR code
      if (!credentialsFull.isAccountLogin &&
          (credentialsFull.serverUsername.length != Constants.usernameLength ||
              credentialsFull.serverPassword.length !=
                  Constants.passwordLength)) {
        Log.e(
          "Server Page Save: User credentials should be more than 28 characters.",
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error processing QR code. Please try again"),
            backgroundColor: Colors.red,
          ),
        );

        return;
      }

      var newServerAddr = credentialsFull.serverAddress;
      var serverUsername = credentialsFull.serverUsername;
      var serverPassword = credentialsFull.serverPassword;

      final validatedRelayUri = _validatedRelayUri(newServerAddr);
      if (validatedRelayUri == null) {
        Log.w(
          'Server QR scan rejected: invalid relay URL extracted from payload: $newServerAddr',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              'That QR code is not a valid relay QR code.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
        return;
      }
      final normalizedServerAddr = validatedRelayUri.toString();

      //TODO: check to make sure serverIp is a valid IP address.

      final prefs = await SharedPreferences.getInstance();
      final androidPushPlatform =
          Platform.isAndroid
              ? AndroidPushTransport.fromPrefs(prefs)
              : AndroidPushTransport.fcm;
      final prevServerAddr = prefs.getString(PrefKeys.serverAddr);
      final prevHasSynced = prevServerAddr != null && prevServerAddr.isNotEmpty;
      final currentCameraNames =
          _isPreviewMode ? _cameraNames : await _fetchCameraNames();
      if (VersionGate.isBlocked &&
          prevHasSynced &&
          currentCameraNames.isNotEmpty) {
        if (!mounted) return;
        await _showRemoveAllCamerasRequiredDialog(currentCameraNames);
        return;
      }

      FcmConfig? fetchedFcmConfig;
      if (Platform.isAndroid &&
          !AndroidPushTransport.isUnifiedValue(androidPushPlatform)) {
        final fetched = await HttpClientService.instance
            .fetchFcmConfigWithCredentials(
              serverAddr: normalizedServerAddr,
              username: serverUsername,
              password: serverPassword,
              // The backend pref isn't written until the save below
              backend:
                  credentialsFull.isAccountLogin
                      ? ServerBackend.enterprise
                      : ServerBackend.selfHosted,
            );
        final fetchedError = fetched.error?.toString() ?? '';
        if (fetched.isFailure &&
            credentialsFull.isAccountLogin &&
            fetchedError.contains('404')) {
          // The official relay may not have FCM configured yet..
          // that shouldn't hold the account hostage.
          Log.w('Relay has no FCM config; connecting without push for now');
        } else if (fetched.isFailure || fetched.value == null) {
          setState(() {
            serverAddr = prevServerAddr;
            hasSynced = prevHasSynced;
            _ipController.text = prevServerAddr ?? '';
          });

          final failureMessage =
              fetchedError.contains('401 Unauthorized') ||
                      fetchedError.contains('Failed to fetch fcm config: 401')
                  ? 'This QR code is not authorized in the server.'
                  : 'Failed to fetch FCM config. Server settings not saved.';

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red,
              content: Text(
                failureMessage,
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
          return;
        } else {
          fetchedFcmConfig = fetched.value;
        }
      }
      if (Platform.isAndroid &&
          AndroidPushTransport.isUnifiedValue(androidPushPlatform)) {
        final distributorReady = await _ensureUnifiedPushDistributorReady();
        if (!distributorReady) {
          return;
        }
      }
      await prefs.setString(PrefKeys.serverAddr, normalizedServerAddr);
      await prefs.setString(PrefKeys.serverUsername, serverUsername);
      await prefs.setString(PrefKeys.serverPassword, serverPassword);
      if (credentialsFull.subscriptionUuid != null) {
        await prefs.setString(
          PrefKeys.subscriptionUuid,
          credentialsFull.subscriptionUuid!,
        );
      } else {
        // A different relay, or one that doesn't do subscriptions.
        await prefs.remove(PrefKeys.subscriptionUuid);
      }
      await prefs.setString(PrefKeys.relayConnectionKind, relayConnectionKind);
      // Which DS the credentials correspond to is needed for the Rust side to know which auth scheme to use.
      await HttpClientService.instance.setServerBackend(
        credentialsFull.isAccountLogin
            ? ServerBackend.enterprise
            : ServerBackend.selfHosted,
      );
      if (Platform.isAndroid) {
        await prefs.setString(
          PrefKeys.androidPushPlatform,
          androidPushPlatform,
        );
      } else {
        await prefs.remove(PrefKeys.androidPushPlatform);
      }
      await prefs.setBool(
        PrefKeys.needUpdateFcmToken,
        !Platform.isAndroid ||
            !AndroidPushTransport.isUnifiedValue(androidPushPlatform),
      );
      await prefs.setBool(PrefKeys.needUpdateIosRelayBinding, true);
      await prefs.remove(PrefKeys.needUploadIosNotificationTarget);
      await prefs.remove(PrefKeys.iosRelayHubToken);
      await prefs.remove(PrefKeys.iosRelayHubTokenExpiryMs);
      await prefs.remove(PrefKeys.iosRelayBindingJson);
      HttpClientService.instance.resetVersionGateState();

      if (Platform.isAndroid &&
          !AndroidPushTransport.isUnifiedValue(androidPushPlatform) &&
          fetchedFcmConfig != null) {
        await prefs.setString(
          PrefKeys.fcmConfigJson,
          jsonEncode(fetchedFcmConfig.toJson()),
        );
      } else {
        await prefs.remove(PrefKeys.fcmConfigJson);
      }

      setState(() {
        serverAddr = normalizedServerAddr;
        hasSynced = true;
        _cameraNames = const [];
      });
      CameraUiBridge.relayConnected.value = true;
      CameraUiBridge.refreshCameraListCallback?.call();

      //initialize all cameras again
      final allCameras = await AppStores.instance.cameraStore.getAllAsync();
      for (var camera in allCameras) {
        // TODO: Check if false, perhaps there's some weird error we might need to look into...
        await initialize(camera.name);
      }

      if (Platform.isAndroid) {
        if (AndroidPushTransport.isUnifiedValue(androidPushPlatform)) {
          await UnifiedPushService.instance.init();
          if (!await UnifiedPushService.instance.hasStoredEndpoint()) {
            await UnifiedPushService.instance.register();
          }
          await PushNotificationService.instance.init();
          await PushNotificationService.tryUploadIfNeeded(true);
        } else {
          await UnifiedPushService.instance.deactivate();
          bool firebaseReady = false;
          try {
            if (fetchedFcmConfig != null) {
              await FirebaseInit.ensure(fetchedFcmConfig);
              firebaseReady = true;
            }
          } catch (e, st) {
            Log.e("Firebase init failed: $e\n$st");
          }

          if (firebaseReady) {
            await PushNotificationService.instance.init();
            Log.d("Before try upload");
            await PushNotificationService.tryUploadIfNeeded(true);
            Log.d("After try upload");
          } else {
            Log.d("Skipping push setup; Firebase not initialized");
          }
        }
      } else {
        await PushNotificationService.instance.init();
        await PushNotificationService.tryUploadIfNeeded(true);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Server settings saved!")));

      // A first connection's next step is adding a camera
      if (!prevHasSynced) {
        CameraUiBridge.switchShellTabCallback?.call(0);
      }
      widget.onRelayConnected?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            credentialsFull.isAccountLogin
                ? "Could not finish setting up the relay. Please try again"
                : "Potentially invalid QR code. Please try again",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    } finally {
      _pendingRelayConnectionKind = null;
    }
  }

  Future<bool> _ensureUnifiedPushDistributorReady() async {
    await UnifiedPushService.instance.init();
    final hasDistributor =
        await UnifiedPushService.instance.tryUseCurrentOrDefaultDistributor();
    if (hasDistributor) {
      return true;
    }

    final distributors = await UnifiedPushService.instance.getDistributors();
    if (distributors.isNotEmpty && mounted) {
      final distributor = await _chooseUnifiedPushDistributor(distributors);
      if (distributor != null) {
        await UnifiedPushService.instance.saveDistributor(distributor);
        return true;
      }
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose a UnifiedPush distributor before connecting a relay.',
          ),
        ),
      );
      return false;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Install a UnifiedPush distributor before connecting a relay.',
          ),
        ),
      );
    }
    return false;
  }

  Future<void> _removeServerConnection() async {
    if (_isPreviewMode && ReviewEnvironment.instance.isActive) {
      await _resetReviewEnvironment();
      return;
    }

    final currentCameraNames =
        _isPreviewMode ? _cameraNames : await _fetchCameraNames();
    if (currentCameraNames.isNotEmpty) {
      if (!mounted) return;
      if (VersionGate.isBlocked) {
        await _showRemoveAllCamerasRequiredDialog(currentCameraNames);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remove all cameras before removing the relay.'),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final androidPushPlatform = AndroidPushTransport.fromPrefs(prefs);
    await prefs.remove(PrefKeys.serverAddr);
    await prefs.remove(PrefKeys.serverUsername);
    await prefs.remove(PrefKeys.serverPassword);
    await prefs.remove(PrefKeys.relayConnectionKind);
    await prefs.remove(PrefKeys.fcmConfigJson);
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
    if (Platform.isAndroid &&
        AndroidPushTransport.isUnifiedValue(androidPushPlatform)) {
      await UnifiedPushService.instance.deactivate();
    }
    _isDialogOpen.value = false;
    setState(() {
      serverAddr = null;
      hasSynced = false;
      _cameraNames = const [];
      _ipController.clear();
    });
    CameraUiBridge.relayConnected.value = false;
    CameraUiBridge.refreshCameraListCallback?.call();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("Relay removed.")));
  }

  Future<void> _openAddCameraFlow() async {
    await GenericCameraQrScanPage.show(context);
    if (_isPreviewMode) return;
    final cameraNames = await _fetchCameraNames();
    if (!mounted) return;
    setState(() => _cameraNames = cameraNames);
  }

  Future<void> _openCameraDetails(String cameraName) async {
    final reviewSession = ReviewEnvironment.instance.session;
    final reviewCamera = reviewSession?.cameraByName(cameraName);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) =>
                reviewCamera != null
                    ? _buildReviewCameraViewPage(reviewCamera)
                    : CameraViewPage(cameraName: cameraName),
      ),
    );
    if (_isPreviewMode) return;
    final cameraNames = await _fetchCameraNames();
    if (!mounted) return;
    setState(() => _cameraNames = cameraNames);
  }

  CameraViewPage _buildReviewCameraViewPage(ReviewCameraFixture camera) {
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

  Future<void> _checkForUpdates() async {
    if (ReviewEnvironment.instance.isActive) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review relay is up to date.')),
      );
      return;
    }

    if (_isPreviewMode) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preview relay is up to date.')),
      );
      return;
    }

    if (!hasSynced ||
        !await HttpClientService.instance.hasStoredServerCredentials()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Connect a relay first.')));
      return;
    }

    final serverVersionResult =
        await HttpClientService.instance.fetchServerVersion();
    if (!mounted) return;
    if (serverVersionResult.isFailure || serverVersionResult.value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to check relay version right now.'),
        ),
      );
      return;
    }

    final serverVersion = serverVersionResult.value!;
    final clientVersion = await rustLibVersion();
    if (!mounted) return;

    final message =
        serverVersion == clientVersion
            ? 'Relay and app are up to date ($serverVersion).'
            : 'Relay version $serverVersion differs from app version $clientVersion.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _persistRelayConnectionKind(String relayConnectionKind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.relayConnectionKind, relayConnectionKind);
  }

  String _resolvedRelayConnectionKind() =>
      _pendingRelayConnectionKind ?? _officialRelayConnectionKind;

  Future<String?> _chooseUnifiedPushDistributor(
    List<String> distributors,
  ) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.72;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose a UnifiedPush distributor',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This app is installed on your phone and delivers UnifiedPush notifications.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.66,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ...distributors.map(
                          (distributor) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(distributor),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap:
                                () =>
                                    Navigator.of(sheetContext).pop(distributor),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _resetReviewEnvironment() async {
    await ReviewEnvironment.instance.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.relayConnectionKind);
    _pendingRelayConnectionKind = null;
    _isDialogOpen.value = false;
    if (!mounted) return;
    setState(() {
      serverAddr = null;
      hasSynced = false;
      _cameraNames = const [];
      _ipController.clear();
    });
    CameraUiBridge.relayConnected.value = false;
    CameraUiBridge.refreshCameraListCallback?.call();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Review environment reset.')));
  }

  /// The official relay supports account creation and login
  /// Self-hosted relays are expected to be pre-provisioned with credentials (so QR is used)
  Future<void> _openRelayLoginFlow() async {
    _pendingRelayConnectionKind = _officialRelayConnectionKind;
    final credentialsFull = await Navigator.push<UserCredentialsQrPayload?>(
      context,
      MaterialPageRoute(
        builder:
            (pageContext) => RelayAccountPage(
              onCreateAccount:
                  () => _pushRelaySignUp(pageContext, AuthMode.create),
              onSignIn: () => _pushRelaySignUp(pageContext, AuthMode.signIn),
            ),
      ),
    );
    if (credentialsFull == null || !mounted) {
      _pendingRelayConnectionKind = null;
      return;
    }
    await _saveServerSettings(credentialsFull);
  }

  Future<void> _pushRelaySignUp(BuildContext pageContext, AuthMode mode) async {
    final payload = await Navigator.push<UserCredentialsQrPayload?>(
      pageContext,
      MaterialPageRoute(
        builder:
            (formContext) => RelaySignUpPage(
              initialMode: mode,
              onSubmit:
                  (mode, email, password) =>
                      _verifyRelayAccount(formContext, mode, email, password),
            ),
      ),
    );
    // The form verified the credentials; hand them up through the intro page too.
    if (payload != null && pageContext.mounted) {
      Navigator.of(pageContext).pop(payload);
    }
  }

  Future<void> _verifyRelayAccount(
    BuildContext formContext,
    AuthMode mode,
    String email,
    String password,
  ) async {
    final username = email.trim();

    String? complaint;
    if (username.isEmpty || password.isEmpty) {
      complaint = 'Enter an email and a password.';
    } else if (mode == AuthMode.create &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(username)) {
      // The relay stores this as an opaque username
      // Form mentions an email.
      // TODO: Not sure what we should do.
      complaint = 'Enter a real email address.';
    } else if (mode == AuthMode.create && password.length < 12) {
      complaint = 'Passwords need at least 12 characters.';
    } else if (mode == AuthMode.create &&
        !(password.contains(RegExp(r'[A-Za-z]')) &&
            password.contains(RegExp(r'[0-9]')) &&
            password.contains(RegExp(r'[^A-Za-z0-9\s]')))) {
      complaint = 'Passwords need a letter, a number, and a symbol.';
    }
    if (complaint != null) {
      ScaffoldMessenger.of(
        formContext,
      ).showSnackBar(SnackBar(content: Text(complaint)));
      return;
    }

    if (_relayAuthInFlight) {
      return;
    }
    _relayAuthInFlight = true;

    // The form's button has no busy state of its own, so a barrier stands in.
    unawaited(
      showDialog<void>(
        context: formContext,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      ),
    );

    String? subscriptionUuid;
    final session = EnterpriseSession();
    try {
      if (mode == AuthMode.create) {
        await session.registerStrict(
          serverAddr: _officialRelayAddress,
          username: username,
          password: password,
        );

        try {
          subscriptionUuid = await session.claimFreeTier(
            serverAddr: _officialRelayAddress,
            username: username,
            password: password,
          );
        } catch (e) {
          Log.w('Free tier claim after signup did not take: $e');
        }
      } else {
        final token = await session.accessToken(
          serverAddr: _officialRelayAddress,
          username: username,
          password: password,
        );
        final subs = EnterpriseSession.subsFromToken(token);
        if (subs.isNotEmpty) {
          // One subscription picks itself.
          subscriptionUuid = subs.first['uuid'] as String?;
          if (subs.length > 1) {
            Log.w(
              'Account holds ${subs.length} subscriptions; using the first',
            );
          }
        }
      }
    } catch (e) {
      Log.w(
        'Relay account ${mode == AuthMode.create ? 'signup' : 'login'} failed: $e',
      );
      if (!formContext.mounted) return;
      ScaffoldMessenger.of(
        formContext,
      ).showSnackBar(SnackBar(content: Text(_relayAuthError(e.toString()))));
      return;
    } finally {
      _relayAuthInFlight = false;
      if (formContext.mounted) {
        Navigator.of(formContext, rootNavigator: true).pop();
      }
    }

    if (!formContext.mounted) return;
    Navigator.of(formContext).pop(
      UserCredentialsQrPayload.accountLogin(
        serverUsername: username,
        serverPassword: password,
        serverAddress: _officialRelayAddress,
        subscriptionUuid: subscriptionUuid,
      ),
    );
  }

  String _relayAuthError(String raw) {
    if (raw.contains('401')) {
      return 'Wrong email or password.';
    }
    if (raw.contains('409')) {
      return 'That email already has an account. Try signing in.';
    }
    if (raw.contains('400')) {
      if (raw.contains('username')) {
        return 'That email has characters the relay does not accept.';
      }
      if (raw.contains('password')) {
        return 'Passwords need a letter, a number, and a symbol.';
      }
      return 'The relay rejected those credentials.';
    }
    return 'Could not reach the relay. Check your connection and try again.';
  }

  Future<void> _openRelayScanFlow({
    String relayConnectionKind = _officialRelayConnectionKind,
  }) async {
    _pendingRelayConnectionKind = relayConnectionKind;
    final credentialsFull = await Navigator.push<UserCredentialsQrPayload?>(
      context,
      MaterialPageRoute(builder: (_) => const _RelayQrScanPage()),
    );
    if (credentialsFull == null || !mounted) {
      _pendingRelayConnectionKind = null;
      return;
    }
    await _saveServerSettings(credentialsFull);
  }

  Future<void> _showRemoveAllCamerasRequiredDialog(
    List<String> currentCameraNames,
  ) async {
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Remove all cameras first'),
            content: const Text(
              'This relay cannot be changed or removed while a version mismatch is active and cameras are still attached.\n\nIf you want to proceed, remove all cameras by clicking the button below.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  for (final cameraName in currentCameraNames) {
                    await CameraUiBridge.deleteCamera(cameraName);
                  }
                  if (!mounted) return;
                  setState(() {
                    _cameraNames = const [];
                  });
                  CameraUiBridge.refreshCameraListCallback?.call();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'All cameras removed. You can now change or remove the relay.',
                      ),
                    ),
                  );
                },
                child: const Text('Remove All Cameras'),
              ),
            ],
          ),
    );
  }

  Widget _linkedRelayCard(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    final endpoint = serverAddr ?? 'relay.local:8443';
    return ShellCard(
      radius: 28,
      color: dark ? const Color(0xFF0D1410) : const Color(0xFFF8FFFB),
      borderColor: dark ? const Color(0xFF0E5A41) : const Color(0xFFBCE4D1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF1ECF89).withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF1ECF89),
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Relay Connected',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color:
                            dark
                                ? const Color(0xFF37D695)
                                : const Color(0xFF118E5E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Phone linked · System ready',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.56,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color:
                  theme.brightness == Brightness.dark
                      ? Colors.black.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              children: [
                _systemMetaRow(theme, 'Endpoint', endpoint),
                const SizedBox(height: 12),
                _systemMetaRow(theme, 'Protocol', 'MLS v1.0 (RFC 9420)'),
                const SizedBox(height: 12),
                _systemMetaRow(theme, 'Last Sync', 'Just now'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // The relay without a camera does nothing; point at the next step until the first one is paired.
          if (_cameraNames.isEmpty) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.videocam_rounded, size: 20),
                label: const Text('Add your first camera'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => CameraUiBridge.switchShellTabCallback?.call(0),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: _SystemActionButton(
                  label: 'Remove Relay',
                  onTap: _removeServerConnection,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SystemActionButton(
                  label: 'Check for Updates',
                  onTap: _checkForUpdates,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pairingCard(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShellCard(
          radius: 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set up your relay server',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'The relay is the encrypted bridge between your cameras and this app.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              _setupOptionCard(
                theme,
                title: 'Secluso Relay',
                subtitle: 'Sign in with your Secluso account',
                icon: Icons.person_rounded,
                highlighted: true,
                onTap: _openRelayLoginFlow,
              ),
              const SizedBox(height: 14),
              _setupOptionCard(
                theme,
                title: 'Self-Hosted',
                subtitle: 'Run on your own server (VPS or dedicated host)',
                icon: Icons.terminal_rounded,
                highlighted: false,
                onTap:
                    () => _openRelayScanFlow(
                      relayConnectionKind: _selfHostedRelayConnectionKind,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ShellCard(
          radius: 18,
          color:
              dark
                  ? Colors.white.withValues(alpha: 0.02)
                  : Colors.white.withValues(alpha: 0.68),
          borderColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.26),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pairing credentials stay on this device. Nothing is sent to any server.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.32),
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ShellCard(
          radius: 22,
          color: dark ? const Color(0xFF0F1714) : const Color(0xFFF2FCF8),
          borderColor: dark ? const Color(0xFF174E39) : const Color(0xFFBFE7D7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline_rounded, color: Color(0xFF1ECF89)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'End-to-end encryption is always on',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color:
                            dark
                                ? const Color(0xFF28D08B)
                                : const Color(0xFF118E5E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'All credentials and encryption keys stay on this device. Secluso cannot access your footage.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.56,
                        ),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool get _isSelfHostedRelay =>
      _resolvedRelayConnectionKind() == _selfHostedRelayConnectionKind;

  String? _systemAccountEmail() => _isSelfHostedRelay ? null : _accountEmail;

  List<SystemCamera> _systemCameras() => [
    for (final name in _cameraNames) SystemCamera(name: name),
  ];

  /// The relay's own page
  Future<void> _openRelayDetail() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder:
            (_) => RelayDetailPage(
              relay: SystemRelay(
                kind:
                    _isSelfHostedRelay
                        ? RelayKind.selfHosted
                        : RelayKind.secluso,
                endpoint: serverAddr ?? 'relay.local:8443',
              ),
              cameraCount: _cameraNames.length,
              onSwitchRelay:
                  () => unawaited(
                    _openRelayScanFlow(
                      relayConnectionKind:
                          _isSelfHostedRelay
                              ? _officialRelayConnectionKind
                              : _selfHostedRelayConnectionKind,
                    ),
                  ),
              onRemoveRelay:
                  _isSelfHostedRelay
                      ? () => unawaited(
                        ReviewEnvironment.instance.isActive
                            ? _resetReviewEnvironment()
                            : _removeServerConnection(),
                      )
                      : null,
            ),
      ),
    );
  }

  Future<void> _openAccount() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder:
            (_) => AccountPage(
              email: _systemAccountEmail() ?? '',
              plan: _accountPlanForDisplay(),
              onOpenCamera: (camera) => _openCameraPlan(camera.name),
              onChangePlan: () => unawaited(_openPlans()),
              onCancel: _openBillingPortal,
              onSignOut: () => unawaited(_removeServerConnection()),
            ),
      ),
    );
  }

  AccountPlanSummary _accountPlanForDisplay() {
    final cameras = [
      for (final name in _cameraNames)
        AccountCamera(
          name: name,
          usage:
              _perCameraBytes.containsKey(name)
                  ? _formatBytes(_perCameraBytes[name]!)
                  : null,
        ),
    ];
    final loaded = _accountPlanSummary;
    if (loaded == null) {
      const gb = 1024 * 1024 * 1024;
      return AccountPlanSummary(
        tier: PlanTier.free,
        price: '',
        renewal: '',
        usedLabel: _formatBytes(0),
        limitLabel: _formatBytes(10 * gb),
        usedFraction: 0,
        viewersNote: _viewersNote(PlanTier.free),
        cameras: cameras,
      );
    }
    return AccountPlanSummary(
      tier: loaded.tier,
      price: loaded.price,
      renewal: loaded.renewal,
      usedLabel: loaded.usedLabel,
      limitLabel: loaded.limitLabel,
      usedFraction: loaded.usedFraction,
      viewersNote: loaded.viewersNote,
      cameras: cameras,
    );
  }

  Future<void> _choosePlan(PlanOffer offer) async {
    final storeSells =
        offer.tier == PlanTier.premium && Distribution.supportsInAppPurchase;
    if (!storeSells) {
      await _openBillingPortal();
      return;
    }

    final started = await BillingService.instance.buyPremium();
    if (!mounted) return;
    if (!started) {
      // Store not usable or product missing: fall back to the web portal.
      await _openBillingPortal();
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Opening the store…')));
  }

  /// Send the user to the web to subscribe or manage a plan.
  /// Used by F-Droid
  Future<void> _openBillingPortal() async {
    final uri = Uri.parse(Distribution.billingPortalUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open ${Distribution.billingPortalUrl}'),
        ),
      );
    }
  }

  Future<void> _openCameraPlan(String cameraName) async {
    // Sharing (who else can watch) isn't wired yet, so show just the owner.
    const people = [SharedPerson(name: 'You', role: 'Owner', isOwner: true)];
    final tier = _accountPlan?.tier ?? PlanTier.free;
    // camera's stored bytes, when the relay could attribute them.
    final bytes = _perCameraBytes[cameraName];
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder:
            (routeContext) => CameraPlanPage(
              detail: CameraPlanDetail(
                cameraName: cameraName,
                tier: tier,
                line: 'Encrypted end-to-end.',
                storedOnRelay: bytes != null ? _formatBytes(bytes) : null,
                storedLimit: bytes != null ? _formatBytes(_planCapBytes) : null,
                people: people,
              ),
              onShare:
                  () => Navigator.of(routeContext).push(
                    MaterialPageRoute<void>(
                      builder:
                          (_) => ShareCameraPage(
                            cameraName: cameraName,
                            people: people,
                            onAddPerson: () {},
                            onRemovePerson: (_) {},
                          ),
                    ),
                  ),
            ),
      ),
    );
  }

  /// Reached from Account -> Change plan.
  Future<void> _openPlans() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder:
            (_) => PlansPage(
              offers: _placeholderPlanOffers,
              onChoose: _choosePlan,
              webBilling: !Distribution.supportsInAppPurchase,
            ),
      ),
    );
  }

  /// PLACEHOLDER.
  static const _placeholderPlanOffers = [
    PlanOffer(
      tier: PlanTier.free,
      cost: r'$0',
      period: '',
      allowance: '10 GB motion · 10 GB live · 720p',
      note: 'End-to-end encrypted · 1 viewer',
    ),
    PlanOffer(
      tier: PlanTier.premium,
      cost: r'$6',
      period: '/mo',
      allowance: '1 TB motion · 1 TB live · up to 2K',
      note: '100× the bandwidth · multiple viewers',
      popular: true,
    ),
    PlanOffer(
      tier: PlanTier.anonymous,
      cost: r'$10',
      period: '/mo',
      allowance: '1 TB motion · 1 TB live · up to 2K',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final shellBackgroundColor =
        dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7);
    if (widget.showShellChrome && !hasSynced) {
      return ShellScaffold(
        backgroundColor: SystemPalette.of(context).bg,
        safeTop: true,
        body: RelayChoicePage(
          hasRoleStep: cameraRoleSupported,
          onSeclusoRelay: () => unawaited(_openRelayLoginFlow()),
          onSelfHosted:
              () => unawaited(
                _openRelayScanFlow(
                  relayConnectionKind: _selfHostedRelayConnectionKind,
                ),
              ),
        ),
      );
    }
    if (widget.showShellChrome && hasSynced) {
      return ShellScaffold(
        backgroundColor: SystemPalette.of(context).bg,
        safeTop: true,
        body: SystemPage(
          relay: SystemRelay(
            kind:
                _resolvedRelayConnectionKind() == _selfHostedRelayConnectionKind
                    ? RelayKind.selfHosted
                    : RelayKind.secluso,
            endpoint: serverAddr ?? 'relay.local:8443',
          ),
          cameras: _systemCameras(),
          accountEmail: _systemAccountEmail(),
          plan: _isSelfHostedRelay ? null : _accountPlan,
          onManageAccount: _systemAccountEmail() == null ? null : _openAccount,
          onOpenRelay: _openRelayDetail,
          onAddCamera: _openAddCameraFlow,
          onOpenCamera: (camera) => _openCameraDetails(camera.name),
        ),
      );
    }
    final content = ListView(
      padding: EdgeInsets.fromLTRB(
        28,
        widget.showShellChrome ? 24 : 18,
        28,
        widget.showShellChrome ? 20 : 32,
      ),
      children: [
        Text(
          'System',
          style:
              widget.showShellChrome
                  ? shellTitleStyle(
                    context,
                    fontSize: 22,
                    designLetterSpacing: 0.55,
                  )
                  : theme.textTheme.headlineLarge?.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
        ),
        const SizedBox(height: 8),
        Text(
          hasSynced
              ? 'Your private relay and connected devices.'
              : 'Your private relay, ready when you are.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.56),
            fontSize: widget.showShellChrome ? 11 : null,
            height: widget.showShellChrome ? 1.5 : null,
          ),
        ),
        const SizedBox(height: 18),
        if (hasSynced) ...[
          _linkedRelayCard(theme),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: ShellSectionLabel('Cameras')),
              TextButton(
                onPressed: _openAddCameraFlow,
                child: const Text('+ Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_cameraNames.isEmpty)
            ShellCard(
              child: Column(
                children: [
                  Text(
                    'No cameras connected yet.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _openAddCameraFlow,
                    child: const Text('Add your first camera'),
                  ),
                ],
              ),
            )
          else
            ShellCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < _cameraNames.length; i++) ...[
                    _SystemCameraRow(name: _cameraNames[i]),
                    if (i != _cameraNames.length - 1) _divider(theme),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 18),
          ShellCard(
            radius: 24,
            color:
                theme.brightness == Brightness.dark
                    ? const Color(0xFF0F1714)
                    : const Color(0xFFF7FFFB),
            borderColor:
                theme.brightness == Brightness.dark
                    ? const Color(0xFF174E39)
                    : const Color(0xFFC7E8D8),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF1ECF89),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'End-to-end encryption is always on',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color:
                          theme.brightness == Brightness.dark
                              ? const Color(0xFF28D08B)
                              : const Color(0xFF118E5E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else
          _pairingCard(theme),
      ],
    );

    if (widget.showShellChrome) {
      return ShellScaffold(
        body: content,
        backgroundColor: shellBackgroundColor,
        safeTop: true,
      );
    }

    return SeclusoScaffold(
      appBar: seclusoAppBar(
        context,
        title: '',
        leading:
            widget.showBackButton
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
                : Builder(
                  builder:
                      (context) => IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: () => scaffoldKey.currentState?.openDrawer(),
                      ),
                ),
      ),
      body: SafeArea(top: true, child: content),
    );
  }
}

class _ReviewRelayConnectionPage extends StatefulWidget {
  const _ReviewRelayConnectionPage({required this.payload});

  final ReviewRelayQrPayload payload;

  @override
  State<_ReviewRelayConnectionPage> createState() =>
      _ReviewRelayConnectionPageState();
}

class _ReviewRelayConnectionPageState
    extends State<_ReviewRelayConnectionPage> {
  String _statusText = 'Validating App Review relay QR...';
  bool _completed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_runConnectionFlow());
  }

  Future<void> _runConnectionFlow() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() {
      _statusText = 'Establishing secure relay link...';
    });

    await Future<void>.delayed(const Duration(milliseconds: 900));
    try {
      await ReviewEnvironment.instance.activateRelay(widget.payload);
    } catch (e, st) {
      Log.e('Failed to activate review relay: $e\n$st');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to connect the App Review relay.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _completed = true;
      _statusText = 'Relay connected.';
    });
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final titleColor = dark ? Colors.white : const Color(0xFF111827);
    final subtitleColor =
        dark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF6B7280);
    final cardColor = dark ? const Color(0xFF111113) : Colors.white;
    final borderColor =
        dark ? Colors.white.withValues(alpha: 0.06) : const Color(0x14000000);
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              width: 360,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color:
                          _completed
                              ? const Color(0xFF10B981).withValues(alpha: 0.16)
                              : const Color(0xFF8BB3EE).withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child:
                          _completed
                              ? const Icon(
                                Icons.check_rounded,
                                color: Color(0xFF10B981),
                                size: 34,
                              )
                              : const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF8BB3EE),
                                ),
                              ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _completed ? 'Relay Connected' : 'Connecting Relay',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: titleColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _errorMessage ?? _statusText,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          _errorMessage != null
                              ? const Color(0xFFEF4444)
                              : subtitleColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.payload.relayAddress,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.22)
                              : const Color(0xFF9CA3AF),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(false),
                      child: const Text('Back'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RelayQrScanPage extends StatefulWidget {
  const _RelayQrScanPage();

  @override
  State<_RelayQrScanPage> createState() => _RelayQrScanPageState();
}

class _RelayQrScanPageState extends State<_RelayQrScanPage>
    with WidgetsBindingObserver {
  PermissionStatus? _cameraPermissionStatus;
  bool _handlingScan = false;
  String? _indicatorMessage;
  Timer? _indicatorTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshCameraPermission(requestIfNeeded: true);
  }

  @override
  void dispose() {
    _indicatorTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshCameraPermission();
    }
  }

  Future<void> _refreshCameraPermission({bool requestIfNeeded = false}) async {
    PermissionStatus status = await Permission.camera.status;
    if (requestIfNeeded &&
        !status.isGranted &&
        !status.isPermanentlyDenied &&
        !status.isRestricted) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    setState(() {
      _cameraPermissionStatus = status;
    });
  }

  String? _cameraPermissionMessage() {
    final status = _cameraPermissionStatus;
    if (status == null || status.isGranted) {
      return null;
    }
    if (status.isPermanentlyDenied) {
      return 'Camera access is required to scan QR codes. Enable it in Settings.';
    }
    if (status.isRestricted) {
      return 'Camera access is restricted on this device.';
    }
    return 'Camera access is required to scan QR codes.';
  }

  Widget? _cameraPermissionActions(BuildContext context) {
    final status = _cameraPermissionStatus;
    if (status == null || status.isGranted) {
      return null;
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Back'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed:
                status.isPermanentlyDenied
                    ? openAppSettings
                    : () => _refreshCameraPermission(requestIfNeeded: true),
            child: Text(
              status.isPermanentlyDenied ? 'Open Settings' : 'Try Again',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleDetection(Code code) async {
    if (_handlingScan || !code.isValid) return;

    final rawValue = code.text?.trim();
    if (rawValue == null || rawValue.isEmpty) {
      return;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(rawValue);
    } catch (_) {
      decoded = null;
    }

    UserCredentialsQrPayload? credentials;

    if (decoded is Map) {
      final reviewRelayPayload = ReviewRelayQrPayload.tryParseMap(decoded);
      if (reviewRelayPayload != null) {
        credentials = UserCredentialsQrPayload.review(
          relayId: reviewRelayPayload.relayId,
          relayLabel: reviewRelayPayload.relayLabel,
          relayAddress: reviewRelayPayload.relayAddress,
        );
      }

      final versionKey = decoded['v'];
      final serverUsername = decoded['u'];
      final serverPassword = decoded['p'];
      final serverAddress = decoded['sa'];
      if (credentials == null &&
          versionKey is String &&
          serverUsername is String &&
          serverPassword is String &&
          serverAddress is String &&
          versionKey == Constants.userCredentialsQrCodeVersion) {
        credentials = UserCredentialsQrPayload(
          serverUsername: serverUsername,
          serverPassword: serverPassword,
          serverAddress: serverAddress,
        );
        try {} catch (_) {}
      }
    }

    if (credentials == null) {
      _showNonSeclusoQrIndicator(
        'QR code detected, but it is not a Secluso user credentials QR code.',
      );
      return;
    }

    setState(() {
      _handlingScan = true;
    });
    if (!mounted) return;
    Navigator.of(context).pop(credentials);
  }

  void _showNonSeclusoQrIndicator(String message) {
    if (_indicatorMessage == message) return;

    setState(() {
      _indicatorMessage = message;
    });

    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _indicatorMessage = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasCameraPermission = _cameraPermissionStatus?.isGranted ?? false;
    return SeclusoQrScanScreen(
      title: 'Scan Relay QR',
      belowFrameText: "Point at your relay's QR\ncode",
      bottomMessage:
          hasCameraPermission
              ? 'Relay credentials are stored only on this phone and used only to connect to your relay.'
              : 'Camera access is used only to scan relay QR codes on this phone.',
      background:
          !hasCameraPermission
              ? const ColoredBox(color: Color(0xFF050505))
              : Stack(
                fit: StackFit.expand,
                children: [
                  SeclusoQrReader(
                    onScan: _handleDetection,
                    codeFormat: Format.qrCode,
                    cropPercent: 1.0,
                    tryHarder: true,
                    loading: const ColoredBox(color: Color(0xFF050505)),
                  ),
                  if (_handlingScan)
                    const IgnorePointer(
                      child: ColoredBox(color: Color(0xFF050505)),
                    ),
                ],
              ),
      onBack: () => Navigator.of(context).maybePop(),
      indicatorMessage:
          _cameraPermissionStatus == null
              ? 'Checking camera access…'
              : _indicatorMessage,
      errorMessage: _cameraPermissionMessage(),
      actionArea: _cameraPermissionActions(context),
    );
  }
}

Widget _divider(ThemeData theme) =>
    Divider(height: 1, color: theme.colorScheme.outlineVariant);

class _SystemActionButton extends StatelessWidget {
  const _SystemActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor:
              dark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.82),
          foregroundColor:
              dark
                  ? Colors.white.withValues(alpha: 0.84)
                  : const Color(0xFF3E4352),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color:
                dark
                    ? Colors.white.withValues(alpha: 0.84)
                    : const Color(0xFF3E4352),
          ),
        ),
      ),
    );
  }
}

Widget _systemMetaRow(ThemeData theme, String label, String value) {
  return Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.48),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _SystemCameraRow extends StatelessWidget {
  const _SystemCameraRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            const ShellStatusDot(Color(0xFF1ECF89)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontSize: 17),
              ),
            ),
            Text(
              'Online',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.42),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _setupOptionCard(
  ThemeData theme, {
  required String title,
  required String subtitle,
  required IconData icon,
  required bool highlighted,
  required VoidCallback onTap,
}) {
  final dark = theme.brightness == Brightness.dark;
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color:
              highlighted
                  ? (dark ? const Color(0xFF1B2433) : const Color(0xFFF2ECD7))
                  : (dark
                      ? Colors.white.withValues(alpha: 0.03)
                      : const Color(0xFFF5F6FA)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                highlighted
                    ? (dark ? const Color(0xFF445C8C) : const Color(0xFFE3C15B))
                    : theme.colorScheme.outlineVariant,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color:
                    dark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color:
                    highlighted
                        ? const Color(0xFF8BB1F4)
                        : const Color(0xFFB0BCD4),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.58,
                      ),
                      height: 1.4,
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
