//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/android_push_transport.dart';
import 'package:secluso_flutter/notifications/unified_push_service.dart';
import 'package:secluso_flutter/routes/camera/camera_ui_bridge.dart';
import 'package:secluso_flutter/routes/theme_provider.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_shell_ui.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/storage_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/utilities/app_coordination_state.dart';
import 'package:secluso_flutter/utilities/device_role_controller.dart';

enum SettingsPreviewScrollPosition { top, bottom, veryBottom }

const bool _captureMode = bool.fromEnvironment(
  'SECLUSO_CAPTURE_MODE',
  defaultValue: false,
);

final Uri _privacyPolicyUri = Uri.parse('https://secluso.com/privacy-policy');
final Uri _termsOfServiceUri = Uri.parse('https://secluso.com/terms');

String _formatStorageDisplayBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }

  final formatter =
      (value - value.roundToDouble()).abs() < 0.05
          ? NumberFormat('#,##0')
          : NumberFormat('#,##0.#');
  return '${formatter.format(value)} ${units[unitIndex]}';
}

class SettingsPage extends StatefulWidget {
  final bool? previewNightTheme;
  final bool? previewNotificationsOn;
  final bool showShellChrome;
  final SettingsPreviewScrollPosition? previewScrollPosition;

  const SettingsPage({
    super.key,
    this.previewNightTheme,
    this.previewNotificationsOn,
    this.showShellChrome = false,
    this.previewScrollPosition,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ScrollController _scrollController = ScrollController();
  static const StorageSummary _previewStorageSummary = StorageSummary(
    totalBytes: 1058013184,
    videoBytes: 888143872,
    thumbnailBytes: 130023424,
    encryptedBytes: 39845888,
    otherBytes: 0,
    videoCount: 148,
    thumbnailCount: 148,
  );

  bool isNightTheme = false;
  bool isNotificationsOn = true;
  bool biometricLock = false;
  bool personAlerts = true;
  bool motionAlerts = true;
  bool showErrorNotifications = true;
  bool storageAutoCleanupEnabled = true;
  int? storageRetentionDays = StorageManager.defaultRetentionDays;
  StorageSummary? storageSummary;
  bool _showRecentErrorHint = false;
  String _appVersionDisplay = 'Loading...';
  bool _hasRelayConnection = false;
  String _androidPushPlatform = AndroidPushTransport.defaultValue;
  late final VoidCallback _logErrorListener;

  bool get _isPreviewMode => widget.previewNightTheme != null;

  @override
  void initState() {
    super.initState();
    _logErrorListener = () {
      unawaited(_refreshRecentErrorHint());
    };
    Log.errorNotifier.addListener(_logErrorListener);
    if (_isPreviewMode) {
      isNightTheme = widget.previewNightTheme!;
      isNotificationsOn = widget.previewNotificationsOn ?? true;
      personAlerts = widget.previewNotificationsOn ?? true;
      motionAlerts = widget.previewNotificationsOn ?? true;
      showErrorNotifications = true;
      storageAutoCleanupEnabled = true;
      storageRetentionDays = StorageManager.defaultRetentionDays;
      storageSummary = _previewStorageSummary;
      _showRecentErrorHint = false;
      _hasRelayConnection = false;
      _androidPushPlatform = AndroidPushTransport.defaultValue;
      unawaited(_loadAppVersionDisplay());
      return;
    }
    unawaited(_loadAppVersionDisplay());
    _loadSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.previewScrollPosition == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      double target = 0;
      switch (widget.previewScrollPosition!) {
        case SettingsPreviewScrollPosition.top:
          target = 0;
        case SettingsPreviewScrollPosition.bottom:
          target = max * 0.62;
        case SettingsPreviewScrollPosition.veryBottom:
          target = max;
      }
      _scrollController.jumpTo(target.clamp(0, max));
    });
  }

  Future<void> _switchRoleFromViewer() async {
    if (_isPreviewMode) return;
  
    final coordinatedCameras = await AppCoordinationState.getCameraSet();
    final storedCameras = await AppStores.instance.cameraStore.getAllAsync();
  
    final cameraNames = <String>{
      ...coordinatedCameras.map((name) => name.trim()).where((name) => name.isNotEmpty),
      ...storedCameras.map((camera) => camera.name.trim()).where((name) => name.isNotEmpty),
    }.toList();
  
    if (cameraNames.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cameraNames.length == 1
                ? 'Delete your paired camera before switching roles.'
                : 'Delete all ${cameraNames.length} paired cameras before switching roles.',
          ),
        ),
      );
      return;
    }
  
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Switch device role?'),
          content: const Text(
            'This returns to role selection for this phone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Switch Role'),
            ),
          ],
        );
      },
    );
  
    if (confirmed != true) return;
  
    await DeviceRoleController.clearRole();
    DeviceRoleController.requestRoleSelection();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final notificationsEnabled =
        prefs.getBool(PrefKeys.notificationsEnabled) ??
        prefs.getBool('notifications') ??
        true;
    final savedServerAddr = prefs.getString(PrefKeys.serverAddr);
    StorageSummary loadedStorageSummary;
    try {
      loadedStorageSummary = await StorageManager.calculateSummary();
    } catch (e) {
      Log.w('Failed to load storage summary: $e');
      loadedStorageSummary = const StorageSummary(
        totalBytes: 0,
        videoBytes: 0,
        thumbnailBytes: 0,
        encryptedBytes: 0,
        otherBytes: 0,
        videoCount: 0,
        thumbnailCount: 0,
      );
    }
    final loadedAutoCleanupEnabled =
        await StorageManager.isAutoCleanupEnabled();
    final loadedRetentionDays = await StorageManager.getRetentionDays();
    final hasRecentError = await Log.hasRecentError();
    final errorNotificationsEnabled = await Log.errorNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      isNightTheme = prefs.getBool('darkTheme') ?? true;
      isNotificationsOn = notificationsEnabled;
      personAlerts = prefs.getBool('personAlerts') ?? true;
      motionAlerts = prefs.getBool('motionAlerts') ?? true;
      biometricLock = prefs.getBool('biometricLock') ?? false;
      showErrorNotifications = prefs.getBool('showErrorNotifications') ?? true;
      storageAutoCleanupEnabled = loadedAutoCleanupEnabled;
      storageRetentionDays = loadedRetentionDays;
      storageSummary = loadedStorageSummary;
      _showRecentErrorHint = errorNotificationsEnabled && hasRecentError;
      _hasRelayConnection = (savedServerAddr ?? '').trim().isNotEmpty;
      _androidPushPlatform = AndroidPushTransport.fromPrefs(prefs);
    });
  }

  Future<void> _refreshRecentErrorHint() async {
    if (_isPreviewMode) return;
    final enabled = await Log.errorNotificationsEnabled();
    final hasRecentError = await Log.hasRecentError();
    if (!mounted) return;
    setState(() {
      _showRecentErrorHint = enabled && hasRecentError;
    });
  }

  Future<void> _loadAppVersionDisplay() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersionDisplay = '${info.version} (${info.buildNumber})';
      });
    } catch (e) {
      Log.w('Failed to load app version display: $e');
      if (!mounted) return;
      setState(() {
        _appVersionDisplay = 'Unavailable';
      });
    }
  }

  Future<void> _saveSettings() async {
    if (_isPreviewMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkTheme', isNightTheme);
    await prefs.setBool(PrefKeys.notificationsEnabled, isNotificationsOn);
    await prefs.remove('notifications');
    await prefs.setBool('personAlerts', personAlerts);
    await prefs.setBool('motionAlerts', motionAlerts);
    await prefs.setBool('biometricLock', biometricLock);
    await prefs.setBool('showErrorNotifications', showErrorNotifications);
    Log.errorNotifier.value++;
  }

  Future<void> _copyLogs() async {
    final logs = await Log.getCopySafeLogDump();
    final exportText = logs.trim().isEmpty ? 'No logs available yet.' : logs;
    await Clipboard.setData(ClipboardData(text: exportText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          logs.trim().isEmpty
              ? 'No logs available yet. Placeholder copied.'
              : 'Logs copied to clipboard.',
        ),
      ),
    );
  }

  Future<void> _openExternalUrl(Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not open $uri')));
  }

  String get _androidPushPlatformLabel =>
      AndroidPushTransport.isUnifiedValue(_androidPushPlatform)
          ? 'UnifiedPush'
          : 'Firebase';

  Future<void> _changeAndroidPushPlatform() async {
    if (_isPreviewMode || !Platform.isAndroid) return;
    if (!AndroidPushTransport.allowsChoice) return;
    if (_hasRelayConnection) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Remove the relay before changing Android push delivery.',
          ),
        ),
      );
      return;
    }

    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder:
            (_) =>
                AndroidPushDeliveryPage(currentPlatform: _androidPushPlatform),
      ),
    );
    if (selected == null || selected == _androidPushPlatform) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.androidPushPlatform, selected);
    if (!AndroidPushTransport.isUnifiedValue(selected)) {
      await UnifiedPushService.instance.deactivate();
    }
    if (!mounted) return;
    setState(() {
      _androidPushPlatform = selected;
    });
  }

  Future<void> _triggerDebugSampleError() async {
    await _leaveSettingsThen(() async {
      Log.e(
        'Debug sample error trigger from Settings.',
        customLocation: 'settings_page.dart:debug',
      );
    });
  }

  Future<void> _triggerDebugSampleBackgroundError() async {
    await _leaveSettingsThen(() async {
      Log.e(
        'Debug sample background error trigger from Settings.',
        customLocation: 'settings_page.dart:debug-bg',
      );
      await Log.saveBackgroundSnapshot(reason: 'Debug sample background error');
      CameraUiBridge.showBackgroundLogDialogCallback?.call();
    });
  }

  Future<void> _leaveSettingsThen(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (widget.showShellChrome &&
        CameraUiBridge.switchShellTabCallback != null) {
      CameraUiBridge.switchShellTabCallback!(0);
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await action();
    messenger?.showSnackBar(
      const SnackBar(content: Text('Sample error triggered.')),
    );
  }

  Future<void> _openStorageSettings() async {
    if (_isPreviewMode) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => StorageSettingsPage(
              initialSummary:
                  storageSummary ??
                  const StorageSummary(
                    totalBytes: 0,
                    videoBytes: 0,
                    thumbnailBytes: 0,
                    encryptedBytes: 0,
                    otherBytes: 0,
                    videoCount: 0,
                    thumbnailCount: 0,
                  ),
              initialAutoCleanupEnabled: storageAutoCleanupEnabled,
              initialRetentionDays: storageRetentionDays,
            ),
      ),
    );
    if (!mounted) return;
    await _loadSettings();
  }

  @override
  void dispose() {
    Log.errorNotifier.removeListener(_logErrorListener);
    if (!_isPreviewMode && _showRecentErrorHint) {
      unawaited(Log.markCurrentErrorSeen());
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final dark = theme.brightness == Brightness.dark;
    final shell = widget.showShellChrome;
    final shellMetrics = _ShellSettingsMetrics.forWidth(
      MediaQuery.sizeOf(context).width,
    );
    final displayNightTheme =
        _isPreviewMode
            ? (shell ? dark : isNightTheme)
            : themeProvider.isDarkMode;
    final shellPrimaryTextColor = dark ? Colors.white : const Color(0xFF111827);
    final shellSecondaryTextColor =
        dark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF6B7280);
    final shellSectionTextColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final shellChevronColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final shellSurfaceColor =
        dark ? Colors.white.withValues(alpha: 0.03) : Colors.white;
    final shellSurfaceBorderColor =
        dark ? Colors.white.withValues(alpha: 0.05) : const Color(0x0A000000);
    final shellDividerColor =
        dark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFE5E7EB);
    const shellToggleActiveColor = Color(0xFF8BB3EE);
    const shellToggleInactiveColor = Color(0xFFD1D5DB);
    final shellToggleThumbShadow = [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
    final sectionTitleStyle =
        !shell
            ? null
            : GoogleFonts.inter(
              color: shellSectionTextColor,
              fontSize: shellMetrics.sectionTitleSize,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.normal,
              letterSpacing: shellMetrics.sectionTitleLetterSpacing,
              height: 13.5 / 9,
            );
    final shellRowTitleStyle =
        !shell
            ? null
            : GoogleFonts.inter(
              color: shellPrimaryTextColor,
              fontSize: shellMetrics.rowTitleSize,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.normal,
              letterSpacing: 0,
              height: 19.5 / 13,
            );
    final shellRowValueStyle =
        !shell
            ? null
            : GoogleFonts.inter(
              color: shellSecondaryTextColor,
              fontSize: shellMetrics.rowValueSize,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.normal,
              letterSpacing: 0,
              height: 16.5 / 11,
            );
    final shellCardShadow =
        !shell
            ? null
            : dark
            ? const <BoxShadow>[]
            : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ];
    final showDevOnlyRows = kDebugMode && !_captureMode;
    final storageManageRowStyle = GoogleFonts.inter(
      color: shell ? shellPrimaryTextColor : theme.colorScheme.onSurface,
      fontSize: shell ? shellMetrics.rowTitleSize : 11.05,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
      height: shell ? 19.5 / shellMetrics.rowTitleSize : 19 / 11.05,
    );
    final currentStorageSummary =
        storageSummary ??
        (_isPreviewMode
            ? _previewStorageSummary
            : const StorageSummary(
              totalBytes: 0,
              videoBytes: 0,
              thumbnailBytes: 0,
              encryptedBytes: 0,
              otherBytes: 0,
              videoCount: 0,
              thumbnailCount: 0,
            ));
    final managedStorageBytes = currentStorageSummary.managedMediaBytes;
    final totalManagedText =
        '${_formatStorageDisplayBytes(managedStorageBytes)} used';

    final content = ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        shell ? shellMetrics.pageInset : 28,
        shell ? shellMetrics.topPadding : 18,
        shell ? shellMetrics.pageInset : 28,
        shell ? shellMetrics.bottomPadding : 28,
      ),
      children: [
        Text(
          'Settings',
          style:
              shell
                  ? GoogleFonts.inter(
                    color: shellPrimaryTextColor,
                    fontSize: shellMetrics.titleSize,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.normal,
                    letterSpacing: -shellMetrics.titleLetterSpacing,
                    height: 33 / 22,
                  )
                  : theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
        ),
        SizedBox(height: shell ? shellMetrics.subtitleGap : 8),
        Text(
          'App preferences for this device.',
          style:
              shell
                  ? GoogleFonts.inter(
                    color: shellSecondaryTextColor,
                    fontSize: shellMetrics.subtitleSize,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.normal,
                    height: 16.5 / 11,
                  )
                  : theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.56),
                  ),
        ),
        SizedBox(height: shell ? shellMetrics.headerBottomGap : 26),
        if (showDevOnlyRows) ...[
          ShellSettingsGroup(
            title: 'Security',
            titleStyle: sectionTitleStyle,
            titleGap: shell ? shellMetrics.sectionTitleGap : 12,
            radius: shell ? shellMetrics.groupRadius : 22,
            cardColor: shell ? shellSurfaceColor : null,
            borderColor: shell ? shellSurfaceBorderColor : null,
            dividerColor: shell ? shellDividerColor : null,
            boxShadow: shell ? shellCardShadow : null,
            children: [
              ShellSettingsRow(
                title: 'Biometric Lock',
                trailing: const ShellBadge(
                  label: 'UNIMPLEMENTED',
                  color: Color(0xFF9CA3AF),
                ),
                height: shell ? shellMetrics.rowHeight : 56,
                horizontalPadding:
                    shell ? shellMetrics.rowHorizontalPadding : 18,
                titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
                valueFontSize: shell ? shellMetrics.rowValueSize : 16,
                titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
                valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
                chevronSize: shell ? shellMetrics.chevronSize : 24,
                titleColor: shell ? shellPrimaryTextColor : null,
                titleStyle: shellRowTitleStyle,
              ),
              ShellSettingsRow(
                title: 'Auto-Lock Timeout',
                trailing: const ShellBadge(
                  label: 'UNIMPLEMENTED',
                  color: Color(0xFF9CA3AF),
                ),
                height: shell ? shellMetrics.rowHeight : 56,
                horizontalPadding:
                    shell ? shellMetrics.rowHorizontalPadding : 18,
                titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
                valueFontSize: shell ? shellMetrics.rowValueSize : 16,
                titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
                valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
                chevronSize: shell ? shellMetrics.chevronSize : 24,
                valueChevronGap: shell ? 8 : 10,
                titleColor: shell ? shellPrimaryTextColor : null,
                valueColor: shell ? shellSecondaryTextColor : null,
                chevronColor: shell ? shellChevronColor : null,
                titleStyle: shellRowTitleStyle,
                valueStyle: shellRowValueStyle,
              ),
            ],
          ),
          SizedBox(height: shell ? shellMetrics.sectionGap : 22),
        ],
        ShellSettingsGroup(
          title: 'Device',
          titleStyle: sectionTitleStyle,
          titleGap: shell ? shellMetrics.sectionTitleGap : 12,
          radius: shell ? shellMetrics.groupRadius : 22,
          cardColor: shell ? shellSurfaceColor : null,
          borderColor: shell ? shellSurfaceBorderColor : null,
          dividerColor: shell ? shellDividerColor : null,
          boxShadow: shell ? shellCardShadow : null,
          children: [
            ShellSettingsRow(
              title: 'Switch Role',
              value: 'Viewer',
              onTap: _switchRoleFromViewer,
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              valueChevronGap: shell ? 8 : 10,
              titleColor: shell ? shellPrimaryTextColor : null,
              valueColor: shell ? shellSecondaryTextColor : null,
              chevronColor: shell ? shellChevronColor : null,
              titleStyle: shellRowTitleStyle,
              valueStyle: shellRowValueStyle,
            ),
          ],
        ),
        SizedBox(height: shell ? shellMetrics.sectionGap : 22),
        ShellSettingsGroup(
          title: 'Appearance',
          titleStyle: sectionTitleStyle,
          titleGap: shell ? shellMetrics.sectionTitleGap : 12,
          radius: shell ? shellMetrics.groupRadius : 22,
          cardColor: shell ? shellSurfaceColor : null,
          borderColor: shell ? shellSurfaceBorderColor : null,
          dividerColor: shell ? shellDividerColor : null,
          boxShadow: shell ? shellCardShadow : null,
          children: [
            ShellSettingsRow(
              title: 'Dark Mode',
              trailing: ShellToggle(
                value: displayNightTheme,
                onChanged: (value) {
                  setState(() => isNightTheme = value);
                  if (!_isPreviewMode) {
                    unawaited(themeProvider.setTheme(value));
                  }
                  unawaited(_saveSettings());
                },
                width: shell ? shellMetrics.toggleWidth : 50,
                height: shell ? shellMetrics.toggleHeight : 30,
                padding: shell ? shellMetrics.togglePadding : 3,
                thumbSize: shell ? shellMetrics.toggleThumbSize : 24,
                activeColor: shell ? shellToggleActiveColor : null,
                inactiveColor: shell ? shellToggleInactiveColor : null,
                thumbShadow: shell ? shellToggleThumbShadow : null,
              ),
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              titleColor: shell ? shellPrimaryTextColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            if (showDevOnlyRows)
              ShellSettingsRow(
                title: 'App Icon',
                trailing: const ShellBadge(
                  label: 'UNIMPLEMENTED',
                  color: Color(0xFF9CA3AF),
                ),
                height: shell ? shellMetrics.rowHeight : 56,
                horizontalPadding:
                    shell ? shellMetrics.rowHorizontalPadding : 18,
                titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
                valueFontSize: shell ? shellMetrics.rowValueSize : 16,
                titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
                valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
                valueChevronGap: shell ? 8 : 10,
                titleColor: shell ? shellPrimaryTextColor : null,
                valueColor: shell ? shellSecondaryTextColor : null,
                titleStyle: shellRowTitleStyle,
                valueStyle: shellRowValueStyle,
              ),
          ],
        ),
        SizedBox(height: shell ? shellMetrics.sectionGap : 22),
        ShellSettingsGroup(
          title: 'Notifications',
          titleStyle: sectionTitleStyle,
          titleGap: shell ? shellMetrics.sectionTitleGap : 12,
          radius: shell ? shellMetrics.groupRadius : 22,
          cardColor: shell ? shellSurfaceColor : null,
          borderColor: shell ? shellSurfaceBorderColor : null,
          dividerColor: shell ? shellDividerColor : null,
          boxShadow: shell ? shellCardShadow : null,
          children: [
            ShellSettingsRow(
              title: 'Push Notifications',
              trailing: ShellToggle(
                value: isNotificationsOn,
                onChanged: (value) {
                  setState(() => isNotificationsOn = value);
                  _saveSettings();
                },
                width: shell ? shellMetrics.toggleWidth : 50,
                height: shell ? shellMetrics.toggleHeight : 30,
                padding: shell ? shellMetrics.togglePadding : 3,
                thumbSize: shell ? shellMetrics.toggleThumbSize : 24,
                activeColor: shell ? shellToggleActiveColor : null,
                inactiveColor: shell ? shellToggleInactiveColor : null,
                thumbShadow: shell ? shellToggleThumbShadow : null,
              ),
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              titleColor: shell ? shellPrimaryTextColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            if (Platform.isAndroid)
              ShellSettingsRow(
                title: 'Push Delivery',
                value:
                    AndroidPushTransport.allowsChoice
                        ? _androidPushPlatformLabel
                        : 'UnifiedPush only',
                onTap:
                    AndroidPushTransport.allowsChoice
                        ? _changeAndroidPushPlatform
                        : null,
                height: shell ? shellMetrics.rowHeight : 56,
                horizontalPadding:
                    shell ? shellMetrics.rowHorizontalPadding : 18,
                titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
                valueFontSize: shell ? shellMetrics.rowValueSize : 16,
                titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
                valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
                chevronSize: shell ? shellMetrics.chevronSize : 24,
                valueChevronGap: shell ? 8 : 10,
                titleColor: shell ? shellPrimaryTextColor : null,
                valueColor: shell ? shellSecondaryTextColor : null,
                chevronColor: shell ? shellChevronColor : null,
                titleStyle: shellRowTitleStyle,
                valueStyle: shellRowValueStyle,
              ),
            ShellSettingsRow(
              title: 'Person Alerts',
              trailing: ShellToggle(
                value: personAlerts,
                onChanged: (value) {
                  setState(() => personAlerts = value);
                  _saveSettings();
                },
                width: shell ? shellMetrics.toggleWidth : 50,
                height: shell ? shellMetrics.toggleHeight : 30,
                padding: shell ? shellMetrics.togglePadding : 3,
                thumbSize: shell ? shellMetrics.toggleThumbSize : 24,
                activeColor: shell ? shellToggleActiveColor : null,
                inactiveColor: shell ? shellToggleInactiveColor : null,
                thumbShadow: shell ? shellToggleThumbShadow : null,
              ),
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              titleColor: shell ? shellPrimaryTextColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            ShellSettingsRow(
              title: 'Motion Alerts',
              trailing: ShellToggle(
                value: motionAlerts,
                onChanged: (value) {
                  setState(() => motionAlerts = value);
                  _saveSettings();
                },
                width: shell ? shellMetrics.toggleWidth : 50,
                height: shell ? shellMetrics.toggleHeight : 30,
                padding: shell ? shellMetrics.togglePadding : 3,
                thumbSize: shell ? shellMetrics.toggleThumbSize : 24,
                activeColor: shell ? shellToggleActiveColor : null,
                inactiveColor: shell ? shellToggleInactiveColor : null,
                thumbShadow: shell ? shellToggleThumbShadow : null,
              ),
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              titleColor: shell ? shellPrimaryTextColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            ShellSettingsRow(
              title: 'System Alerts',
              trailing: ShellToggle(
                value: showErrorNotifications,
                onChanged: (value) {
                  setState(() => showErrorNotifications = value);
                  _saveSettings();
                },
                width: shell ? shellMetrics.toggleWidth : 50,
                height: shell ? shellMetrics.toggleHeight : 30,
                padding: shell ? shellMetrics.togglePadding : 3,
                thumbSize: shell ? shellMetrics.toggleThumbSize : 24,
                activeColor: shell ? shellToggleActiveColor : null,
                inactiveColor: shell ? shellToggleInactiveColor : null,
                thumbShadow: shell ? shellToggleThumbShadow : null,
              ),
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              titleColor: shell ? shellPrimaryTextColor : null,
              titleStyle: shellRowTitleStyle,
            ),
          ],
        ),
        SizedBox(height: shell ? shellMetrics.sectionGap : 22),
        if (!shell)
          ShellSectionLabel('Storage')
        else
          Text('STORAGE', style: sectionTitleStyle),
        SizedBox(height: shell ? shellMetrics.sectionTitleGap : 12),
        ShellCard(
          padding: EdgeInsets.zero,
          radius: 12,
          color: shell ? shellSurfaceColor : null,
          borderColor: shell ? shellSurfaceBorderColor : null,
          boxShadow: shell ? shellCardShadow : null,
          child: Column(
            children: [
              _StorageSettingsCard(
                summary: currentStorageSummary,
                title: 'Local Storage',
                totalText: totalManagedText,
                padding:
                    shell
                        ? EdgeInsets.fromLTRB(14, 16, 14, 17)
                        : const EdgeInsets.fromLTRB(14, 16, 14, 17),
              ),
              Divider(
                height: 1,
                color:
                    shell
                        ? shellDividerColor
                        : theme.colorScheme.outlineVariant,
              ),
              _StorageChevronRow(
                title: 'Manage Storage',
                onTap: _openStorageSettings,
                height: shell ? shellMetrics.manageRowHeight : 53,
                horizontalPadding:
                    shell ? shellMetrics.rowHorizontalPadding : 14,
                titleStyle: storageManageRowStyle,
                chevronColor:
                    shell
                        ? shellChevronColor
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                chevronSize: shell ? shellMetrics.chevronSize : 14,
              ),
            ],
          ),
        ),
        SizedBox(height: shell ? shellMetrics.sectionGap : 22),
        ShellSettingsGroup(
          title: 'Diagnostics',
          titleStyle: sectionTitleStyle,
          titleGap: shell ? shellMetrics.sectionTitleGap : 12,
          radius: shell ? shellMetrics.groupRadius : 22,
          cardColor: shell ? shellSurfaceColor : null,
          borderColor: shell ? shellSurfaceBorderColor : null,
          dividerColor: shell ? shellDividerColor : null,
          boxShadow: shell ? shellCardShadow : null,
          children: [
            ShellSettingsRow(
              title: 'Show Error Notifications',
              trailing: ShellToggle(
                value: showErrorNotifications,
                onChanged: (value) {
                  setState(() => showErrorNotifications = value);
                  _saveSettings();
                },
                width: shell ? shellMetrics.toggleWidth : 50,
                height: shell ? shellMetrics.toggleHeight : 30,
                padding: shell ? shellMetrics.togglePadding : 3,
                thumbSize: shell ? shellMetrics.toggleThumbSize : 24,
                activeColor: shell ? shellToggleActiveColor : null,
                inactiveColor: shell ? shellToggleInactiveColor : null,
                thumbShadow: shell ? shellToggleThumbShadow : null,
              ),
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              titleColor: shell ? shellPrimaryTextColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            ShellSettingsRow(
              title: 'Export Logs',
              value: _showRecentErrorHint ? 'RECENT ERROR' : null,
              onTap: _copyLogs,
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              valueChevronGap: shell ? 8 : 10,
              titleColor: shell ? shellPrimaryTextColor : null,
              valueColor: const Color(0xFFEF4444),
              chevronColor: shell ? shellChevronColor : null,
              titleStyle: shellRowTitleStyle,
              valueStyle:
                  _showRecentErrorHint
                      ? (shell
                          ? GoogleFonts.inter(
                            color: const Color(0xFFEF4444),
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            fontStyle: FontStyle.normal,
                            letterSpacing: 0.3,
                            height: 13 / 9,
                          )
                          : theme.textTheme.titleMedium?.copyWith(
                            color: const Color(0xFFEF4444),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3,
                          ))
                      : null,
            ),
          ],
        ),
        if (kDebugMode && !_isPreviewMode) ...[
          SizedBox(height: shell ? shellMetrics.sectionGap : 22),
          ShellSettingsGroup(
            title: 'Developer Settings',
            titleStyle: sectionTitleStyle,
            titleGap: shell ? shellMetrics.sectionTitleGap : 12,
            radius: shell ? shellMetrics.groupRadius : 22,
            cardColor: shell ? shellSurfaceColor : null,
            borderColor: shell ? shellSurfaceBorderColor : null,
            dividerColor: shell ? shellDividerColor : null,
            boxShadow: shell ? shellCardShadow : null,
            children: [
              ShellSettingsRow(
                title: 'Trigger Sample Error',
                value: 'debug only',
                onTap: _triggerDebugSampleError,
                height: shell ? shellMetrics.rowHeight : 56,
                horizontalPadding:
                    shell ? shellMetrics.rowHorizontalPadding : 18,
                titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
                valueFontSize: shell ? shellMetrics.rowValueSize : 16,
                titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
                valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
                chevronSize: shell ? shellMetrics.chevronSize : 24,
                valueChevronGap: shell ? 8 : 10,
                titleColor: shell ? shellPrimaryTextColor : null,
                valueColor:
                    shell
                        ? Colors.white.withValues(alpha: 0.36)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.52),
                chevronColor: shell ? shellChevronColor : null,
                titleStyle: shellRowTitleStyle,
                valueStyle: shell ? shellRowValueStyle : null,
              ),
              ShellSettingsRow(
                title: 'Trigger Sample BG Error',
                value: 'debug only',
                onTap: _triggerDebugSampleBackgroundError,
                height: shell ? shellMetrics.rowHeight : 56,
                horizontalPadding:
                    shell ? shellMetrics.rowHorizontalPadding : 18,
                titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
                valueFontSize: shell ? shellMetrics.rowValueSize : 16,
                titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
                valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
                chevronSize: shell ? shellMetrics.chevronSize : 24,
                valueChevronGap: shell ? 8 : 10,
                titleColor: shell ? shellPrimaryTextColor : null,
                valueColor:
                    shell
                        ? Colors.white.withValues(alpha: 0.36)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.52),
                chevronColor: shell ? shellChevronColor : null,
                titleStyle: shellRowTitleStyle,
                valueStyle: shell ? shellRowValueStyle : null,
              ),
            ],
          ),
        ],
        SizedBox(height: shell ? shellMetrics.sectionGap : 22),
        ShellSettingsGroup(
          title: 'About',
          titleStyle: sectionTitleStyle,
          titleGap: shell ? shellMetrics.sectionTitleGap : 12,
          radius: shell ? shellMetrics.groupRadius : 22,
          cardColor: shell ? shellSurfaceColor : null,
          borderColor: shell ? shellSurfaceBorderColor : null,
          dividerColor: shell ? shellDividerColor : null,
          boxShadow: shell ? shellCardShadow : null,
          children: [
            ShellSettingsRow(
              title: 'Version',
              value: _appVersionDisplay,
              trailing: const SizedBox.shrink(),
              height: shell ? shellMetrics.aboutVersionRowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueChevronGap: shell ? 8 : 10,
              titleColor: shell ? shellPrimaryTextColor : null,
              valueColor: shell ? shellSecondaryTextColor : null,
              titleStyle: shellRowTitleStyle,
              valueStyle: shellRowValueStyle,
            ),
            ShellSettingsRow(
              title: 'Terms of Service',
              onTap: () => _openExternalUrl(_termsOfServiceUri),
              height: shell ? shellMetrics.aboutLinkRowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              valueChevronGap: shell ? 8 : 10,
              titleColor: shell ? shellPrimaryTextColor : null,
              chevronColor: shell ? shellChevronColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            ShellSettingsRow(
              title: 'Privacy Policy',
              onTap: () => _openExternalUrl(_privacyPolicyUri),
              height: shell ? shellMetrics.aboutLinkRowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              valueChevronGap: shell ? 8 : 10,
              titleColor: shell ? shellPrimaryTextColor : null,
              chevronColor: shell ? shellChevronColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            ShellSettingsRow(
              title: 'Open Source Licenses',
              onTap: () => showLicensePage(context: context),
              height: shell ? shellMetrics.aboutLinkRowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              valueChevronGap: shell ? 8 : 10,
              titleColor: shell ? shellPrimaryTextColor : null,
              chevronColor: shell ? shellChevronColor : null,
              titleStyle: shellRowTitleStyle,
            ),
          ],
        ),
        SizedBox(height: shell ? shellMetrics.sectionGap : 22),
        ShellCard(
          radius: shell ? shellMetrics.infoRadius : 22,
          color:
              shell
                  ? (dark
                      ? Colors.white.withValues(alpha: 0.02)
                      : const Color(0xFFF9FAFB))
                  : (dark
                      ? Colors.white.withValues(alpha: 0.02)
                      : Colors.white.withValues(alpha: 0.7)),
          borderColor:
              shell
                  ? (dark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFE5E7EB))
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          boxShadow: shell ? const [] : null,
          padding:
              shell
                  ? EdgeInsets.fromLTRB(
                    shellMetrics.infoInset,
                    shellMetrics.infoInset,
                    shellMetrics.infoInset,
                    shellMetrics.infoInset,
                  )
                  : const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsFooterLockIcon(
                size: shell ? shellMetrics.infoIconSize : 18,
                color:
                    shell
                        ? (dark
                            ? Colors.white.withValues(alpha: 0.35)
                            : const Color(0xFF9CA3AF))
                        : theme.colorScheme.onSurface.withValues(alpha: 0.28),
              ),
              SizedBox(width: shell ? shellMetrics.infoGap : 12),
              Expanded(
                child: Text(
                  'These settings apply only to this phone. They do not affect how footage is encrypted, stored, or transmitted by your cameras.',
                  style:
                      shell
                          ? GoogleFonts.inter(
                            color: shellSecondaryTextColor,
                            fontSize: shellMetrics.infoTextSize,
                            fontWeight: FontWeight.w400,
                            fontStyle: FontStyle.normal,
                            letterSpacing: 0,
                            height: 16.25 / 10,
                          )
                          : theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.44,
                            ),
                            height: 1.5,
                          ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.showShellChrome) {
      final backgroundColor =
          dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7);
      return ShellScaffold(
        backgroundColor: backgroundColor,
        body: ColoredBox(color: backgroundColor, child: content),
        safeTop: true,
      );
    }

    return SeclusoScaffold(
      appBar: seclusoAppBar(
        context,
        title: 'Settings',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(top: true, child: content),
    );
  }
}

class StorageSettingsPage extends StatefulWidget {
  const StorageSettingsPage({
    super.key,
    required this.initialSummary,
    required this.initialAutoCleanupEnabled,
    required this.initialRetentionDays,
  });

  final StorageSummary initialSummary;
  final bool initialAutoCleanupEnabled;
  final int? initialRetentionDays;

  @override
  State<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends State<StorageSettingsPage> {
  late StorageSummary _summary;
  late bool _autoCleanupEnabled;
  late int? _retentionDays;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _summary = widget.initialSummary;
    _autoCleanupEnabled = widget.initialAutoCleanupEnabled;
    _retentionDays = widget.initialRetentionDays;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refreshSummary() async {
    final summary = await StorageManager.calculateSummary();
    if (!mounted) return;
    setState(() {
      _summary = summary;
    });
  }

  Future<void> _setAutoCleanupEnabled(bool enabled) async {
    setState(() => _autoCleanupEnabled = enabled);
    await StorageManager.setAutoCleanupEnabled(enabled);
    _showSnack(
      enabled ? 'Automatic cleanup is on.' : 'Automatic cleanup is off.',
    );
  }

  Future<void> _pickRetentionDays() async {
    final selection = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        final options = <int?>[null, ...StorageManager.retentionOptions];
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('Retention window'),
                  subtitle: Text(
                    'Choose how long motion clips stay on this device.',
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final option in options)
                        ListTile(
                          title: Text(StorageManager.retentionLabel(option)),
                          trailing:
                              option == _retentionDays
                                  ? Icon(
                                    Icons.check_rounded,
                                    color: theme.colorScheme.primary,
                                  )
                                  : null,
                          onTap: () => Navigator.of(context).pop(option ?? -1),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selection == null) return;
    final newValue = selection < 0 ? null : selection;
    await StorageManager.setRetentionDays(newValue);
    if (!mounted) return;
    setState(() {
      _retentionDays = newValue;
    });
    _showSnack('Retention set to ${StorageManager.retentionLabel(newValue)}.');
  }

  Future<void> _runStorageAction({
    required String emptyMessage,
    required Future<StorageCleanupResult> Function() action,
    bool refreshMediaViews = true,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action();
      await _refreshSummary();
      if (refreshMediaViews) {
        CameraUiBridge.refreshCameraListCallback?.call();
        CameraUiBridge.refreshActivityCallback?.call();
      }
      _showSnack(_storageResultMessage(result, emptyMessage));
    } catch (e) {
      Log.e('Storage action failed: $e');
      _showSnack('Storage action failed.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _cleanOldVideosNow() async {
    if (_retentionDays == null) {
      _showSnack('Set a retention window first.');
      return;
    }
    await _runStorageAction(
      emptyMessage:
          'No clips older than ${StorageManager.retentionLabel(_retentionDays)}.',
      action:
          () => StorageManager.deleteVideosOlderThan(
            Duration(days: _retentionDays!),
          ),
    );
  }

  Future<void> _clearEncryptedFiles() async {
    await _runStorageAction(
      emptyMessage: 'No encrypted temp files to clear.',
      action: StorageManager.clearEncryptedTempFiles,
      refreshMediaViews: false,
    );
  }

  Future<void> _confirmDeleteAllVideos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete all saved videos?'),
          content: const Text(
            'This removes every saved motion clip from this device. Camera recordings will not be recoverable after deletion.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete all'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _runStorageAction(
      emptyMessage: 'No saved videos to delete.',
      action: StorageManager.deleteAllVideos,
    );
  }

  String _storageResultMessage(
    StorageCleanupResult result,
    String emptyMessage,
  ) {
    if (!result.didWork) return emptyMessage;
    final parts = <String>[];
    if (result.deletedVideos > 0) {
      parts.add(
        '${result.deletedVideos} clip${result.deletedVideos == 1 ? '' : 's'}',
      );
    }
    if (result.deletedThumbnails > 0) {
      parts.add(
        '${result.deletedThumbnails} thumbnail${result.deletedThumbnails == 1 ? '' : 's'}',
      );
    }
    if (result.deletedTempFiles > 0) {
      parts.add(
        '${result.deletedTempFiles} temp file${result.deletedTempFiles == 1 ? '' : 's'}',
      );
    }
    if (result.removedVideoRows > 0) {
      parts.add(
        '${result.removedVideoRows} video entr${result.removedVideoRows == 1 ? 'y' : 'ies'}',
      );
    }
    if (result.removedDetectionRows > 0) {
      parts.add(
        '${result.removedDetectionRows} detection entr${result.removedDetectionRows == 1 ? 'y' : 'ies'}',
      );
    }
    final detail =
        parts.isEmpty ? 'Cleanup complete.' : 'Removed ${parts.join(', ')}';
    return '$detail Freed ${StorageManager.formatBytes(result.bytesFreed)}.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final managedStorageBytes = _summary.managedMediaBytes;
    final totalManagedText = _formatStorageDisplayBytes(managedStorageBytes);
    final sectionTitleStyle = GoogleFonts.inter(
      color: theme.colorScheme.onSurface,
      fontSize: 9,
      fontWeight: FontWeight.w600,
      fontStyle: FontStyle.normal,
      letterSpacing: 0.9,
      height: 13.5 / 9,
    );
    final rowTitleStyle = GoogleFonts.inter(
      color: theme.colorScheme.onSurface,
      fontSize: 11.05,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
      height: 19 / 11.05,
    );
    final rowValueStyle = GoogleFonts.inter(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      fontSize: 9.35,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
      height: 16 / 9.35,
    );
    final headerTitleStyle = GoogleFonts.inter(
      color: theme.colorScheme.onSurface,
      fontSize: 18.7,
      fontWeight: FontWeight.w600,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
      height: 27 / 18.7,
    );
    final headerButtonColor =
        theme.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.04);
    final storageDividerColor =
        theme.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06);

    return SeclusoScaffold(
      body: SafeArea(
        top: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: headerButtonColor,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                const SizedBox(width: 8),
                Text('Manage Storage', style: headerTitleStyle),
              ],
            ),
            const SizedBox(height: 28),
            ShellCard(
              padding: EdgeInsets.zero,
              radius: 12,
              child: _StorageTotalUsedCard(
                summary: _summary,
                totalText: totalManagedText,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              ),
            ),
            const SizedBox(height: 32),
            _StorageSection(
              title: 'Auto-Cleanup',
              titleStyle: sectionTitleStyle,
              child: ShellCard(
                padding: EdgeInsets.zero,
                radius: 12,
                child: Column(
                  children: [
                    _StorageToggleRow(
                      title: 'Enable Auto-Cleanup',
                      value: _autoCleanupEnabled,
                      onChanged: _setAutoCleanupEnabled,
                      height: 53,
                      horizontalPadding: 14,
                      titleStyle: rowTitleStyle,
                    ),
                    Divider(height: 1, color: storageDividerColor),
                    _StorageChevronRow(
                      title: 'Retention Window',
                      value: StorageManager.retentionLabel(_retentionDays),
                      onTap: _pickRetentionDays,
                      height: 53,
                      horizontalPadding: 14,
                      titleStyle: rowTitleStyle,
                      valueStyle: rowValueStyle,
                      chevronColor: theme.colorScheme.onSurface.withValues(
                        alpha: 0.5,
                      ),
                      chevronSize: 14,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _StorageSection(
              title: 'Manual Deletion',
              titleStyle: sectionTitleStyle,
              child: ShellCard(
                padding: EdgeInsets.zero,
                radius: 12,
                child: Column(
                  children: [
                    _StorageChevronRow(
                      title: 'Delete Old Clips Now',
                      value:
                          _retentionDays == null
                              ? 'Never'
                              : '> ${StorageManager.retentionLabel(_retentionDays)}',
                      onTap: _busy ? null : _cleanOldVideosNow,
                      height: 53,
                      horizontalPadding: 14,
                      titleStyle: rowTitleStyle,
                      valueStyle: rowValueStyle,
                      chevronColor: theme.colorScheme.onSurface.withValues(
                        alpha: 0.5,
                      ),
                      chevronSize: 14,
                    ),
                    Divider(height: 1, color: storageDividerColor),
                    _StorageChevronRow(
                      title: 'Clear Temp Files',
                      value: _formatStorageDisplayBytes(
                        _summary.encryptedBytes,
                      ),
                      onTap: _busy ? null : _clearEncryptedFiles,
                      height: 53,
                      horizontalPadding: 14,
                      titleStyle: rowTitleStyle,
                      valueStyle: rowValueStyle,
                      chevronColor: theme.colorScheme.onSurface.withValues(
                        alpha: 0.5,
                      ),
                      chevronSize: 14,
                    ),
                    Divider(height: 1, color: storageDividerColor),
                    _DangerStorageRow(
                      title: 'Delete All Videos',
                      onTap: _busy ? null : _confirmDeleteAllVideos,
                      height: 53,
                      horizontalPadding: 14,
                      textStyle: GoogleFonts.inter(
                        color: const Color(0xFFEF4444),
                        fontSize: 11.05,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.normal,
                        letterSpacing: 0,
                        height: 19 / 11.05,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AndroidPushDeliveryPage extends StatelessWidget {
  const AndroidPushDeliveryPage({super.key, required this.currentPlatform});

  final String currentPlatform;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          dark ? theme.scaffoldBackgroundColor : const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Push Delivery'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            Text(
              'ANDROID',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose how this Android phone should receive relay notifications before you connect a relay.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            _AndroidPushChoiceCard(
              title: 'Firebase Cloud Messaging',
              subtitle:
                  'Recommended. Works on most Android phones with no extra setup.',
              tradeoff: 'Depends on Google Play Services.',
              icon: Icons.notifications_active_rounded,
              highlighted:
                  !AndroidPushTransport.isUnifiedValue(currentPlatform),
              onTap: () => Navigator.of(context).pop(AndroidPushTransport.fcm),
            ),
            const SizedBox(height: 12),
            _AndroidPushChoiceCard(
              title: 'UnifiedPush',
              subtitle:
                  'More private and works on de-Googled phones with a distributor app.',
              tradeoff:
                  'Requires a UnifiedPush distributor app to be installed.',
              icon: Icons.hub_outlined,
              highlighted: AndroidPushTransport.isUnifiedValue(currentPlatform),
              onTap:
                  () => Navigator.of(context).pop(AndroidPushTransport.unified),
            ),
            const SizedBox(height: 18),
            Text(
              'You can only change this before a relay is connected.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsFooterLockIcon extends StatelessWidget {
  const _SettingsFooterLockIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SettingsFooterLockPainter(color)),
    );
  }
}

class _StorageSettingsCard extends StatelessWidget {
  const _StorageSettingsCard({
    required this.summary,
    required this.title,
    required this.totalText,
    required this.padding,
  });

  final StorageSummary summary;
  final String title;
  final String totalText;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = GoogleFonts.inter(
      color: theme.colorScheme.onSurface,
      fontSize: 11.05,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
      height: 19 / 11.05,
    );
    final valueStyle = GoogleFonts.inter(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
      fontSize: 9.35,
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
      height: 16 / 9.35,
    );

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: titleStyle)),
              Text(totalText, style: valueStyle),
            ],
          ),
          const SizedBox(height: 18),
          _StorageUsageBar(summary: summary),
          const SizedBox(height: 18),
          _StorageLegendRow(
            label: 'Videos',
            value: _formatStorageDisplayBytes(summary.videoBytes),
            color: const Color(0xFF8BB3EE),
          ),
          const SizedBox(height: 12),
          _StorageLegendRow(
            label: 'Thumbnails',
            value: _formatStorageDisplayBytes(summary.thumbnailBytes),
            color: const Color(0xFFA78BFA),
          ),
          const SizedBox(height: 12),
          _StorageLegendRow(
            label: 'Temp Files',
            value: _formatStorageDisplayBytes(summary.encryptedBytes),
            color: const Color(0xFFF59E0B),
          ),
        ],
      ),
    );
  }
}

class _StorageTotalUsedCard extends StatelessWidget {
  const _StorageTotalUsedCard({
    required this.summary,
    required this.totalText,
    required this.padding,
  });

  final StorageSummary summary;
  final String totalText;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = GoogleFonts.inter(
      color: theme.colorScheme.onSurface,
      fontSize: 11.05,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
      height: 19 / 11.05,
    );
    final valueStyle = GoogleFonts.inter(
      color: theme.colorScheme.onSurface,
      fontSize: 11.05,
      fontWeight: FontWeight.w600,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
      height: 19 / 11.05,
    );

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Total Used', style: titleStyle)),
              Text(totalText, style: valueStyle),
            ],
          ),
          const SizedBox(height: 18),
          _StorageUsageBar(summary: summary),
        ],
      ),
    );
  }
}

class _StorageUsageBar extends StatelessWidget {
  const _StorageUsageBar({required this.summary});

  final StorageSummary summary;

  @override
  Widget build(BuildContext context) {
    final total = summary.managedMediaBytes;
    final segments = <({Color color, int flex})>[];
    final values = [
      (summary.videoBytes, const Color(0xFF8BB3EE)),
      (summary.thumbnailBytes, const Color(0xFFA78BFA)),
      (summary.encryptedBytes, const Color(0xFFF59E0B)),
    ];

    if (total > 0) {
      for (final (value, color) in values) {
        if (value <= 0) continue;
        final flex = ((value / total) * 1000).round().clamp(1, 1000);
        segments.add((color: color, flex: flex));
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        child:
            segments.isEmpty
                ? Container(color: Colors.white.withValues(alpha: 0.1))
                : Row(
                  children: [
                    for (final segment in segments)
                      Expanded(
                        flex: segment.flex,
                        child: Container(color: segment.color),
                      ),
                  ],
                ),
      ),
    );
  }
}

class _StorageLegendRow extends StatelessWidget {
  const _StorageLegendRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = GoogleFonts.inter(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      fontSize: 9.35,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
      height: 16 / 9.35,
    );
    final valueStyle = GoogleFonts.inter(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      fontSize: 9.35,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
      height: 16 / 9.35,
    );
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: labelStyle)),
        Text(value, style: valueStyle),
      ],
    );
  }
}

class _StorageChevronRow extends StatelessWidget {
  const _StorageChevronRow({
    required this.title,
    this.value,
    this.onTap,
    required this.height,
    required this.horizontalPadding,
    required this.titleStyle,
    this.valueStyle,
    required this.chevronColor,
    required this.chevronSize,
  });

  final String title;
  final String? value;
  final VoidCallback? onTap;
  final double height;
  final double horizontalPadding;
  final TextStyle titleStyle;
  final TextStyle? valueStyle;
  final Color chevronColor;
  final double chevronSize;

  @override
  Widget build(BuildContext context) {
    final row = SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Row(
          children: [
            Expanded(child: Text(title, style: titleStyle)),
            if (value != null) ...[
              Text(value!, style: valueStyle),
              const SizedBox(width: 8),
            ],
            Icon(
              Icons.chevron_right_rounded,
              size: chevronSize,
              color: chevronColor,
            ),
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

class _StorageToggleRow extends StatelessWidget {
  const _StorageToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.height,
    required this.horizontalPadding,
    required this.titleStyle,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final double height;
  final double horizontalPadding;
  final TextStyle titleStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Row(
          children: [
            Expanded(child: Text(title, style: titleStyle)),
            ShellToggle(
              value: value,
              onChanged: onChanged,
              width: 40,
              height: 24,
              padding: 2,
              thumbSize: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _DangerStorageRow extends StatelessWidget {
  const _DangerStorageRow({
    required this.title,
    this.onTap,
    this.height = 56,
    this.horizontalPadding = 18,
    this.textStyle,
  });

  final String title;
  final VoidCallback? onTap;
  final double height;
  final double horizontalPadding;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final row = SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Row(
          children: [
            const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: Color(0xFFEF4444),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style:
                    textStyle ??
                    Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFEF4444),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

class _StorageSection extends StatelessWidget {
  const _StorageSection({
    required this.title,
    required this.titleStyle,
    required this.child,
  });

  final String title;
  final TextStyle titleStyle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(title, style: titleStyle),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ShellSettingsMetrics {
  const _ShellSettingsMetrics({
    required this.pageInset,
    required this.topPadding,
    required this.bottomPadding,
    required this.titleSize,
    required this.titleLetterSpacing,
    required this.subtitleGap,
    required this.subtitleSize,
    required this.headerBottomGap,
    required this.sectionGap,
    required this.sectionTitleGap,
    required this.sectionTitleSize,
    required this.sectionTitleLetterSpacing,
    required this.groupRadius,
    required this.rowHeight,
    required this.rowHorizontalPadding,
    required this.rowTitleSize,
    required this.rowValueSize,
    required this.chevronSize,
    required this.toggleWidth,
    required this.toggleHeight,
    required this.togglePadding,
    required this.toggleThumbSize,
    required this.storageInset,
    required this.storageBottomInset,
    required this.storageBarTopGap,
    required this.storageBarHeight,
    required this.storageTextTopGap,
    required this.storageInfoSize,
    required this.manageRowHeight,
    required this.aboutVersionRowHeight,
    required this.aboutLinkRowHeight,
    required this.infoRadius,
    required this.infoInset,
    required this.infoIconSize,
    required this.infoGap,
    required this.infoTextSize,
  });

  final double pageInset;
  final double topPadding;
  final double bottomPadding;
  final double titleSize;
  final double titleLetterSpacing;
  final double subtitleGap;
  final double subtitleSize;
  final double headerBottomGap;
  final double sectionGap;
  final double sectionTitleGap;
  final double sectionTitleSize;
  final double sectionTitleLetterSpacing;
  final double groupRadius;
  final double rowHeight;
  final double rowHorizontalPadding;
  final double rowTitleSize;
  final double rowValueSize;
  final double chevronSize;
  final double toggleWidth;
  final double toggleHeight;
  final double togglePadding;
  final double toggleThumbSize;
  final double storageInset;
  final double storageBottomInset;
  final double storageBarTopGap;
  final double storageBarHeight;
  final double storageTextTopGap;
  final double storageInfoSize;
  final double manageRowHeight;
  final double aboutVersionRowHeight;
  final double aboutLinkRowHeight;
  final double infoRadius;
  final double infoInset;
  final double infoIconSize;
  final double infoGap;
  final double infoTextSize;

  factory _ShellSettingsMetrics.forWidth(double width) {
    final scale = (width / 290).clamp(0.88, 1.6);
    double s(double value) => value * scale;
    return _ShellSettingsMetrics(
      pageInset: s(20),
      topPadding: s(20),
      bottomPadding: s(28),
      titleSize: s(22),
      titleLetterSpacing: 0.55,
      subtitleGap: s(4),
      subtitleSize: s(11),
      headerBottomGap: s(12),
      sectionGap: s(20),
      sectionTitleGap: s(8),
      sectionTitleSize: s(9),
      sectionTitleLetterSpacing: 0.9,
      groupRadius: s(12),
      rowHeight: s(50.75),
      rowHorizontalPadding: s(14),
      rowTitleSize: s(13),
      rowValueSize: s(11),
      chevronSize: s(14),
      toggleWidth: s(40),
      toggleHeight: s(24),
      togglePadding: s(2),
      toggleThumbSize: s(20),
      storageInset: s(14),
      storageBottomInset: s(12.5),
      storageBarTopGap: s(14),
      storageBarHeight: s(8),
      storageTextTopGap: s(10),
      storageInfoSize: s(10),
      manageRowHeight: s(49.5),
      aboutVersionRowHeight: s(48.5),
      aboutLinkRowHeight: s(48.5),
      infoRadius: s(12),
      infoInset: s(16),
      infoIconSize: s(14),
      infoGap: s(12),
      infoTextSize: s(10),
    );
  }
}

class _AndroidPushChoiceCard extends StatelessWidget {
  const _AndroidPushChoiceCard({
    required this.title,
    required this.subtitle,
    required this.tradeoff,
    required this.icon,
    required this.highlighted,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String tradeoff;
  final IconData icon;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cardColor =
        highlighted
            ? (dark ? const Color(0xFF12201A) : const Color(0xFFF3FBF7))
            : (dark ? Colors.white.withValues(alpha: 0.03) : Colors.white);
    final borderColor =
        highlighted
            ? const Color(0xFF1ECF89)
            : (dark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE2E8F0));
    final iconBackgroundColor =
        highlighted
            ? (dark ? const Color(0xFF163324) : const Color(0xFFE7F8F0))
            : (dark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFF3F4F6));
    final iconColor =
        highlighted ? const Color(0xFF1ECF89) : const Color(0xFF64748B);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
            boxShadow:
                dark
                    ? null
                    : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor),
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
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.72,
                        ),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tradeoff,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.56,
                        ),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                highlighted
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color:
                    highlighted
                        ? const Color(0xFF1ECF89)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.28),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsFooterLockPainter extends CustomPainter {
  const _SettingsFooterLockPainter(this.color);

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
  bool shouldRepaint(covariant _SettingsFooterLockPainter oldDelegate) =>
      oldDelegate.color != color;
}
