//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_shell_ui.dart';
import 'camera_ui_bridge.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/notifications/epoch.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/utilities/connected_apps.dart';
import 'package:secluso_flutter/utilities/lock.dart';

enum CameraSettingsAction { removeCamera }

class SettingsPage extends StatefulWidget {
  final String cameraName;
  final String? previewFirmwareVersion;
  final String? previewOsVersion;
  final String? previewSelectedResolution;
  final int? previewSelectedFps;
  final bool? previewNotificationsEnabled;
  final Set<String>? previewSelectedNotificationEvents;

  const SettingsPage({
    super.key,
    required this.cameraName,
    this.previewFirmwareVersion,
    this.previewOsVersion,
    this.previewSelectedResolution,
    this.previewSelectedFps,
    this.previewNotificationsEnabled,
    this.previewSelectedNotificationEvents,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Video Quality settings
  String selectedResolution = '1080p';
  int selectedFps = 30;

  // Mapping from resolution to available FPS options
  final Map<String, List<int>> fpsMapping = {
    '4K': [15, 30],
    '1080p': [15, 30, 60],
    '720p': [15, 30, 60],
  };

  // Notification settings
  bool notificationsEnabled = true;
  bool preRollEnabled = true;
  String? firmwareVersion;
  String? osVersion;

  // Options: user can select "All" or choose specific events like Motion, Humans, Vehicles, or Pets.
  final List<String> notificationOptions = [
    'All',
    'Humans',
    'Vehicles',
    'Pets',
  ];
  List<String> selectedNotificationEvents = ['All'];

  bool get _isPreviewMode => widget.previewFirmwareVersion != null;

  @override
  void initState() {
    super.initState();
    if (_isPreviewMode) {
      firmwareVersion = widget.previewFirmwareVersion;
      osVersion = widget.previewOsVersion;
      selectedResolution =
          widget.previewSelectedResolution ?? selectedResolution;
      selectedFps = widget.previewSelectedFps ?? selectedFps;
      notificationsEnabled =
          widget.previewNotificationsEnabled ?? notificationsEnabled;
      preRollEnabled = widget.previewNotificationsEnabled ?? preRollEnabled;
      selectedNotificationEvents =
          widget.previewSelectedNotificationEvents?.toList() ??
          selectedNotificationEvents;
      return;
    }
    _loadLiveUiState();
  }

  Future<void> _loadLiveUiState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      firmwareVersion = prefs.getString(
        PrefKeys.firmwareVersionPrefix + widget.cameraName,
      );
      osVersion = prefs.getString(
        PrefKeys.cameraOsVersionPrefix + widget.cameraName,
      );
      notificationsEnabled =
          prefs.getBool(
            PrefKeys.cameraNotificationsEnabledPrefix + widget.cameraName,
          ) ??
          notificationsEnabled;
      selectedNotificationEvents =
          prefs.getStringList(
            PrefKeys.cameraNotificationEventsPrefix + widget.cameraName,
          ) ??
          selectedNotificationEvents;
    });
  }

  Future<void> _saveLiveUiState() async {
    if (_isPreviewMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      PrefKeys.cameraNotificationsEnabledPrefix + widget.cameraName,
      notificationsEnabled,
    );
    await prefs.setStringList(
      PrefKeys.cameraNotificationEventsPrefix + widget.cameraName,
      selectedNotificationEvents.isEmpty
          ? const ['All']
          : selectedNotificationEvents,
    );
  }

  Future<void> _confirmRemoveCamera() async {
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
    if (confirm == true && mounted) {
      await CameraUiBridge.deleteCamera(widget.cameraName);
      CameraUiBridge.refreshCameraListCallback?.call();
      if (!mounted) return;
      Navigator.of(context).pop(CameraSettingsAction.removeCamera);
    }
  }

  Future<String> _buildAugmentedQrData(String qrData) async {
    final prefs = await SharedPreferences.getInstance();

    final serverAddr = prefs.getString(PrefKeys.serverAddr)?.trim();
    final serverUsername = prefs.getString(PrefKeys.serverUsername)?.trim();

    if (serverAddr == null ||
        serverAddr.isEmpty ||
        serverUsername == null ||
        serverUsername.isEmpty) {
      throw Exception('Missing relay settings');
    }

    final decoded = jsonDecode(qrData);
    if (decoded is! Map) {
      throw const FormatException('Invalid add-phone QR data');
    }

    final payload = Map<String, dynamic>.from(decoded);
    payload['sa'] = serverAddr;
    payload['su'] = serverUsername;

    return jsonEncode(payload);
  }

  Widget _buildAddAppQrCode(String augmentedQrData) {
    const qrPixels = 220;
    const qrSize = 220.0;

    final result = zx.encodeBarcode(
      contents: augmentedQrData,
      params: EncodeParams(
        format: Format.qrCode,
        width: qrPixels,
        height: qrPixels,
        margin: 10,
        eccLevel: EccLevel.low,
      ),
    );

    if (!result.isValid || result.data == null) {
      return const SizedBox(
        width: qrSize,
        height: qrSize,
        child: Center(child: Text('Could not generate QR code')),
      );
    }

    return Container(
      width: qrSize,
      height: qrSize,
      color: Colors.white,
      child: Image.memory(
        pngFromBytes(result.data!, qrPixels, qrPixels),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
        gaplessPlayback: true,
      ),
    );
  }

  Future<void> _addApp() async {
    final prefs = await SharedPreferences.getInstance();
    final addedViaAddApp =
        prefs.getBool(PrefKeys.cameraAddedViaAddAppPrefix + widget.cameraName) ??
        false;

    if (addedViaAddApp) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Adding another phone is only available on the primary phone.',
          ),
        ),
      );
      return;
    }

    final displayName = await _promptForPhoneName();
    if (displayName == null || !mounted) return;

    final qrData = await getAddAppSecret();
    final augmentedQrData = await _buildAugmentedQrData(qrData);

    late final Uint8List addAppSecret;
    try {
      addAppSecret = decodeAddAppSecret(qrData);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not decode add-phone secret: $e')),
        );
      }
      return;
    }

    var started = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        if (!started) {
          started = true;

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            String? error;

            try {
              await _handleAddApp(addAppSecret, displayName);
            } catch (e) {
              error = e.toString();
            }

            if (dialogCtx.mounted) {
              Navigator.of(dialogCtx).pop();
            }

            if (!mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  error == null
                      ? 'Phone added successfully.'
                      : 'Could not add phone: $error',
                ),
              ),
            );
          });
        }

        return AlertDialog(
          title: const Text('Add another phone'),
          content: SizedBox(
            width: 240,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAddAppQrCode(augmentedQrData),
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                const Text(
                  'Waiting for the other phone...',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptForPhoneName() async {
    final controller = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Name the new phone'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: maxConnectedAppDisplayNameLength,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'For example, green phone',
              errorText: error,
            ),
            onSubmitted: (_) {
              try {
                Navigator.of(ctx).pop(
                  validateConnectedAppDisplayName(controller.text),
                );
              } on FormatException catch (e) {
                setDialogState(() => error = e.message);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.of(ctx).pop(
                    validateConnectedAppDisplayName(controller.text),
                  );
                } on FormatException catch (e) {
                  setDialogState(() => error = e.message);
                }
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Uint8List decodeAddAppSecret(String qrData) {
    dynamic decoded;
    try {
      decoded = jsonDecode(qrData);
    } catch (_) {
      decoded = null;
    }

    if (decoded is Map) {
      final versionKey = decoded['v'];
      final cameraSecret = decoded['cs'];
      if (versionKey is String &&
          cameraSecret is String &&
          versionKey == Constants.cameraQrCodeVersion) {
        try {
          final rawBytes = base64Decode(cameraSecret);
          if (rawBytes.length == Constants.numCameraSecretBytes) {
            final hotspotPassword = decoded['wp'];
            if (!(hotspotPassword is String && hotspotPassword.isNotEmpty)) {
              return rawBytes;
            }
          }
        } catch (_) {}
      }
    }

    throw FormatException('Could not decide add-phone secret');
  }

  Future<void> _handleAddApp(
    Uint8List addAppSecret,
    String displayName,
  ) async {
    final configLock = 'heartbeat${widget.cameraName}.lock';
    if (!await lock(configLock)) {
      throw Exception('Camera configuration is busy. Try again.');
    }
    try {
      await _handleAddAppLocked(addAppSecret, displayName);
    } finally {
      await unlock(configLock);
    }
  }

  Future<void> _handleAddAppLocked(
    Uint8List addAppSecret,
    String displayName,
  ) async {
    final httpClient = HttpClientService.instance;

    final newAppKeyPackagesResult =
        await httpClient.receiveMsg("add_app_start");

    if (newAppKeyPackagesResult.isFailure) {
      throw Exception(
        'failed to wait for new phone: ${newAppKeyPackagesResult.error}',
      );
    }

    final newAppKeyPackages = newAppKeyPackagesResult.value;
    if (newAppKeyPackages == null) {
      throw Exception('failed to wait for new phone: missing key packages');
    }

    final configMsgEnc = await generateAddAppRequestConfigCommand(
      cameraName: widget.cameraName,
      newAppKeyPackagesVec: newAppKeyPackages,
      secret: addAppSecret,
    );

    if (configMsgEnc.isEmpty) {
      throw Exception('failed to generate the add-phone config command');
    }

    final configCommandResult = await httpClient.configCommand(
      cameraName: widget.cameraName,
      command: configMsgEnc,
    );

    if (configCommandResult.isFailure) {
      throw Exception(
        'failed to send config command: ${configCommandResult.error}',
      );
    }

    Uint8List? configResponse;
    for (var attempt = 0; attempt < 30; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));

      final response = await httpClient.fetchConfigResponse(
        cameraName: widget.cameraName,
      );

      if (response.isSuccess) {
        configResponse = response.value;
        break;
      }
    }

    if (configResponse == null) {
      throw Exception(
        "couldn't fetch the add-phone config response. Camera might be offline.",
      );
    }

    final processedResp = await processAddAppConfigResponse(
      cameraName: widget.cameraName,
      configResponse: configResponse,
      secret: addAppSecret,
    );

    if (processedResp.isEmpty) {
      throw Exception('failed to process the camera add-phone response');
    }
    final newApp = decodeAddAppResp(processedResp);

    final videoEpoch = await readEpoch(widget.cameraName, 'video');
    await writeEpoch(widget.cameraName, 'video', videoEpoch + 1);

    final thumbnailEpoch = await readEpoch(widget.cameraName, 'thumbnail');
    await writeEpoch(widget.cameraName, 'thumbnail', thumbnailEpoch + 1);

    final addAppRequestResult =
        await httpClient.sendMsg("add_app_finish", processedResp);

    if (addAppRequestResult.isFailure) {
      throw Exception(
        'failed to send add-phone response: ${addAppRequestResult.error}',
      );
    }
    await saveConnectedApp(
      widget.cameraName,
      ConnectedApp(appName: newApp.appName, displayName: displayName),
    );
  }

  Future<bool> _isSecondaryApp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(
          PrefKeys.cameraAddedViaAddAppPrefix + widget.cameraName,
        ) ??
        false;
  }

  Future<void> _manageConnectedPhones() async {
    if (await _isSecondaryApp()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Managing connected phones is only available on the primary phone.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ConnectedPhonesDialog(
        cameraName: widget.cameraName,
        onRemove: _removeConnectedPhone,
      ),
    );
  }

  Future<void> _removeConnectedPhone(ConnectedApp app) async {
    if (await _isSecondaryApp()) {
      throw Exception('Only the primary phone can remove connected phones.');
    }
    final configLock = 'heartbeat${widget.cameraName}.lock';
    if (!await lock(configLock)) {
      throw Exception('Camera configuration is busy. Try again.');
    }
    try {
      await _removeConnectedPhoneLocked(app);
    } finally {
      await unlock(configLock);
    }
  }

  Future<void> _removeConnectedPhoneLocked(ConnectedApp app) async {
    final knownApps = await loadConnectedApps(widget.cameraName);
    if (!knownApps.any((known) => known.appName == app.appName)) {
      throw Exception('This phone is no longer in the connected list.');
    }
    final command = await generateRemoveAppRequestConfigCommand(
      cameraName: widget.cameraName,
      appName: app.appName,
    );
    if (command.isEmpty) throw Exception('Could not generate remove command.');
    final client = HttpClientService.instance;
    final sent = await client.configCommand(
      cameraName: widget.cameraName,
      command: command,
    );
    if (sent.isFailure) throw Exception('Could not send remove command.');

    Uint8List? response;
    for (var attempt = 0; attempt < 30; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final fetched = await client.fetchConfigResponse(
        cameraName: widget.cameraName,
      );
      if (fetched.isSuccess) {
        response = fetched.value;
        break;
      }
    }
    if (response == null) {
      throw Exception('Camera did not confirm removal.');
    }
    final processed = await processRemoveAppConfigResponse(
      cameraName: widget.cameraName,
      configResponse: response,
    );
    if (!processed) {
      throw Exception('Could not verify the camera removal response.');
    }
    await _incrementEpochs();
    await removeConnectedApp(widget.cameraName, app.appName);
  }

  Future<void> _incrementEpochs() async {
    final videoEpoch = await readEpoch(widget.cameraName, 'video');
    await writeEpoch(widget.cameraName, 'video', videoEpoch + 1);
    final thumbnailEpoch = await readEpoch(widget.cameraName, 'thumbnail');
    await writeEpoch(widget.cameraName, 'thumbnail', thumbnailEpoch + 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final metrics = _CameraSettingsMetrics.forWidth(
      MediaQuery.sizeOf(context).width,
    );
    final titleStyle = GoogleFonts.inter(
      color: dark ? Colors.white : const Color(0xFF111827),
      fontSize: metrics.headerTitleSize,
      fontWeight: FontWeight.w600,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
      height: 28 / 18,
    );
    final sectionTitleStyle = GoogleFonts.inter(
      color:
          dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF),
      fontSize: metrics.sectionTitleSize,
      fontWeight: FontWeight.w600,
      fontStyle: FontStyle.normal,
      letterSpacing: metrics.sectionTitleLetterSpacing,
      height: 13.5 / 9,
    );
    final rowTitleStyle = GoogleFonts.inter(
      color: dark ? Colors.white : const Color(0xFF111827),
      fontSize: metrics.rowTitleSize,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
      height: 19.5 / 13,
    );
    final rowValueStyle = GoogleFonts.inter(
      color:
          dark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF6B7280),
      fontSize: metrics.rowValueSize,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
      height: 19.5 / 13,
    );
    final cardShadow =
        dark
            ? const <BoxShadow>[]
            : const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ];
    final personDetectionEnabled =
        selectedNotificationEvents.contains('All') ||
        selectedNotificationEvents.contains('Humans');
    final showDevOnlyRows = kDebugMode;

    return SeclusoScaffold(
      body: ColoredBox(
        color: dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.only(
              top: metrics.pageTopPadding,
              bottom: metrics.pageBottomPadding,
            ),
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: metrics.headerLeftInset,
                  right: metrics.headerRightInset,
                ),
                child: Row(
                  children: [
                    _CameraSettingsBackButton(
                      size: metrics.backButtonSize,
                      iconSize: metrics.backButtonIconSize,
                      fillColor:
                          dark
                              ? Colors.white.withValues(alpha: 0.06)
                              : const Color(0xFFE5E7EB),
                      iconColor: dark ? Colors.white : const Color(0xFF6B7280),
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    SizedBox(width: metrics.headerGap),
                    Expanded(
                      child: Text(
                        '${widget.cameraName} Settings',
                        style: titleStyle,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: metrics.headerBottomGap),
              _buildGroup(
                context,
                metrics: metrics,
                title: 'GENERAL',
                titleStyle: sectionTitleStyle,
                cardShadow: cardShadow,
                rows: [
                  ShellSettingsRow(
                    title: 'Camera Name',
                    value: widget.cameraName,
                    trailing: const SizedBox.shrink(),
                    height: metrics.shortRowHeight,
                    horizontalPadding: metrics.rowHorizontalPadding,
                    titleStyle: rowTitleStyle,
                    valueStyle: rowValueStyle,
                    valueChevronGap: 0,
                  ),
                  if (firmwareVersion != null)
                    ShellSettingsRow(
                      title: 'Firmware',
                      value: firmwareVersion!,
                      trailing: const SizedBox.shrink(),
                      height: metrics.shortRowHeight,
                      horizontalPadding: metrics.rowHorizontalPadding,
                      titleStyle: rowTitleStyle,
                      valueStyle: rowValueStyle,
                      valueChevronGap: 0,
                    ),
                  if (osVersion != null)
                    ShellSettingsRow(
                      title: 'OS Version',
                      value: osVersion!,
                      trailing: const SizedBox.shrink(),
                      height: metrics.shortRowHeight,
                      horizontalPadding: metrics.rowHorizontalPadding,
                      titleStyle: rowTitleStyle,
                      valueStyle: rowValueStyle,
                      valueChevronGap: 0,
                    ),
                  if (showDevOnlyRows)
                    ShellSettingsRow(
                      title: 'Location',
                      trailing: const ShellBadge(
                        label: 'UNIMPLEMENTED',
                        color: Color(0xFF9CA3AF),
                      ),
                      height: metrics.shortRowHeight + metrics.shortRowDelta,
                      horizontalPadding: metrics.rowHorizontalPadding,
                      titleStyle: rowTitleStyle,
                    ),
                ],
              ),
              SizedBox(height: metrics.sectionGap),
              _buildGroup(
                context,
                metrics: metrics,
                title: 'NOTIFICATIONS',
                titleStyle: sectionTitleStyle,
                cardShadow: cardShadow,
                rows: [
                  ShellSettingsRow(
                    title: 'Alerts',
                    trailing: ShellToggle(
                      value: notificationsEnabled,
                      onChanged: (value) {
                        setState(() => notificationsEnabled = value);
                        _saveLiveUiState();
                      },
                      width: metrics.toggleWidth,
                      height: metrics.toggleHeight,
                      padding: metrics.togglePadding,
                      thumbSize: metrics.toggleThumbSize,
                      activeColor: const Color(0xFF8BB3EE),
                      inactiveColor: const Color(0xFFD1D5DB),
                      thumbShadow: const [
                        BoxShadow(
                          color: Color(0x0D000000),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    height: metrics.toggleRowHeight,
                    horizontalPadding: metrics.rowHorizontalPadding,
                    titleStyle: rowTitleStyle,
                  ),
                  ShellSettingsRow(
                    title: 'Person Alerts',
                    trailing: ShellToggle(
                      value: personDetectionEnabled,
                      onChanged: (value) {
                        setState(() {
                          if (value) {
                            if (!selectedNotificationEvents.contains(
                              'Humans',
                            )) {
                              selectedNotificationEvents = [
                                ...selectedNotificationEvents.where(
                                  (e) => e != 'All',
                                ),
                                'Humans',
                              ];
                            }
                          } else {
                            selectedNotificationEvents.remove('Humans');
                            selectedNotificationEvents.remove('All');
                          }
                        });
                        _saveLiveUiState();
                      },
                      width: metrics.toggleWidth,
                      height: metrics.toggleHeight,
                      padding: metrics.togglePadding,
                      thumbSize: metrics.toggleThumbSize,
                      activeColor: const Color(0xFF8BB3EE),
                      inactiveColor: const Color(0xFFD1D5DB),
                      thumbShadow: const [
                        BoxShadow(
                          color: Color(0x0D000000),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    height: metrics.toggleRowHeight,
                    horizontalPadding: metrics.rowHorizontalPadding,
                    titleStyle: rowTitleStyle,
                  ),
                ],
              ),
              SizedBox(height: metrics.sectionGap),
              if (showDevOnlyRows) ...[
                _buildGroup(
                  context,
                  metrics: metrics,
                  title: 'DETECTION',
                  titleStyle: sectionTitleStyle,
                  cardShadow: cardShadow,
                  rows: [
                    ShellSettingsRow(
                      title: 'Motion Sensitivity',
                      trailing: const ShellBadge(
                        label: 'UNIMPLEMENTED',
                        color: Color(0xFF9CA3AF),
                      ),
                      height: metrics.shortRowHeight,
                      horizontalPadding: metrics.rowHorizontalPadding,
                      titleStyle: rowTitleStyle,
                    ),
                    ShellSettingsRow(
                      title: 'Detection Zones',
                      trailing: const ShellBadge(
                        label: 'UNIMPLEMENTED',
                        color: Color(0xFF9CA3AF),
                      ),
                      height: metrics.bottomRowHeight,
                      horizontalPadding: metrics.rowHorizontalPadding,
                      titleStyle: rowTitleStyle,
                    ),
                  ],
                ),
                SizedBox(height: metrics.sectionGap),
                _buildGroup(
                  context,
                  metrics: metrics,
                  title: 'RECORDING',
                  titleStyle: sectionTitleStyle,
                  cardShadow: cardShadow,
                  rows: [
                    ShellSettingsRow(
                      title: 'Clip Length',
                      trailing: const ShellBadge(
                        label: 'UNIMPLEMENTED',
                        color: Color(0xFF9CA3AF),
                      ),
                      height: metrics.shortRowHeight,
                      horizontalPadding: metrics.rowHorizontalPadding,
                      titleStyle: rowTitleStyle,
                    ),
                    ShellSettingsRow(
                      title: 'Pre-roll',
                      trailing: const ShellBadge(
                        label: 'UNIMPLEMENTED',
                        color: Color(0xFF9CA3AF),
                      ),
                      height: metrics.toggleRowHeight + metrics.shortRowDelta,
                      horizontalPadding: metrics.rowHorizontalPadding,
                      titleStyle: rowTitleStyle,
                    ),
                  ],
                ),
                SizedBox(height: metrics.sectionGap),
              ],
              _buildGroup(
                context,
                metrics: metrics,
                title: 'ADVANCED',
                titleStyle: sectionTitleStyle,
                cardShadow: cardShadow,
                rows: [
                  if (showDevOnlyRows)
                    ShellSettingsRow(
                      title: 'Restart Camera',
                      trailing: const ShellBadge(
                        label: 'UNIMPLEMENTED',
                        color: Color(0xFF9CA3AF),
                      ),
                      height: metrics.shortRowHeight,
                      horizontalPadding: metrics.rowHorizontalPadding,
                      titleStyle: rowTitleStyle,
                    ),
                  ShellSettingsRow(
                    title: 'Add another phone',
                    onTap: _addApp,
                    trailing: const SizedBox.shrink(),
                    height: metrics.advancedBottomRowHeight,
                    horizontalPadding: metrics.rowHorizontalPadding,
                    titleStyle: rowTitleStyle,
                  ),
                  ShellSettingsRow(
                    title: 'Manage connected phones',
                    onTap: _manageConnectedPhones,
                    trailing: const Icon(Icons.chevron_right),
                    height: metrics.advancedBottomRowHeight,
                    horizontalPadding: metrics.rowHorizontalPadding,
                    titleStyle: rowTitleStyle,
                  ),
                  ShellSettingsRow(
                    title: 'Remove Camera',
                    onTap: _confirmRemoveCamera,
                    trailing: const SizedBox.shrink(),
                    height: metrics.advancedBottomRowHeight,
                    horizontalPadding: metrics.rowHorizontalPadding,
                    titleStyle: rowTitleStyle.copyWith(
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroup(
    BuildContext context, {
    required _CameraSettingsMetrics metrics,
    required String title,
    required TextStyle titleStyle,
    required List<BoxShadow> cardShadow,
    required List<Widget> rows,
  }) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: metrics.sectionTitleLeftInset),
          child: Text(title, style: titleStyle),
        ),
        SizedBox(height: metrics.sectionTitleGap),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: metrics.cardSideInset),
          child: ShellCard(
            padding: EdgeInsets.zero,
            radius: metrics.cardRadius,
            color: dark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
            borderColor:
                dark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0x0A000000),
            boxShadow: cardShadow,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i != rows.length - 1)
                    Divider(
                      height: 1,
                      color:
                          dark
                              ? Colors.white.withValues(alpha: 0.04)
                              : const Color(0xFFE5E7EB),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectedPhonesDialog extends StatefulWidget {
  const _ConnectedPhonesDialog({
    required this.cameraName,
    required this.onRemove,
  });

  final String cameraName;
  final Future<void> Function(ConnectedApp app) onRemove;

  @override
  State<_ConnectedPhonesDialog> createState() => _ConnectedPhonesDialogState();
}

class _ConnectedPhonesDialogState extends State<_ConnectedPhonesDialog> {
  late Future<List<ConnectedApp>> _apps;
  String? _removingAppName;
  String? _error;

  @override
  void initState() {
    super.initState();
    _apps = loadConnectedApps(widget.cameraName);
  }

  Future<void> _remove(ConnectedApp app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${app.displayName}?'),
        content: const Text(
          'This phone will stop receiving updates from this camera.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _removingAppName = app.appName;
      _error = null;
    });
    try {
      await widget.onRemove(app);
      if (!mounted) return;
      setState(() {
        _removingAppName = null;
        _apps = loadConnectedApps(widget.cameraName);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _removingAppName = null;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connected phones'),
      content: SizedBox(
        width: 360,
        child: FutureBuilder<List<ConnectedApp>>(
          future: _apps,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final apps = snapshot.data!;
            if (apps.isEmpty) {
              return const Text('No secondary phones are connected.');
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                for (final app in apps)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(app.displayName),
                    trailing:
                        _removingAppName == app.appName
                            ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : IconButton(
                              tooltip: 'Remove phone',
                              onPressed:
                                  _removingAppName == null
                                      ? () => _remove(app)
                                      : null,
                              icon: const Icon(Icons.delete_outline),
                            ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _removingAppName == null
                  ? () => Navigator.of(context).pop()
                  : null,
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _CameraSettingsBackButton extends StatelessWidget {
  const _CameraSettingsBackButton({
    required this.size,
    required this.iconSize,
    required this.fillColor,
    required this.iconColor,
    required this.onTap,
  });

  final double size;
  final double iconSize;
  final Color fillColor;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fillColor,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: _CameraSettingsBackIcon(size: iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}

class _CameraSettingsBackIcon extends StatelessWidget {
  const _CameraSettingsBackIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CameraSettingsBackPainter(color)),
    );
  }
}

class _CameraSettingsMetrics {
  const _CameraSettingsMetrics({
    required this.scale,
    required this.pageTopPadding,
    required this.pageBottomPadding,
    required this.headerLeftInset,
    required this.headerRightInset,
    required this.backButtonSize,
    required this.backButtonIconSize,
    required this.headerGap,
    required this.headerTitleSize,
    required this.headerBottomGap,
    required this.sectionGap,
    required this.sectionTitleLeftInset,
    required this.sectionTitleGap,
    required this.sectionTitleSize,
    required this.sectionTitleLetterSpacing,
    required this.cardSideInset,
    required this.cardRadius,
    required this.rowHorizontalPadding,
    required this.rowTitleSize,
    required this.rowValueSize,
    required this.chevronSize,
    required this.shortRowHeight,
    required this.shortRowDelta,
    required this.toggleRowHeight,
    required this.bottomRowHeight,
    required this.advancedBottomRowHeight,
    required this.toggleWidth,
    required this.toggleHeight,
    required this.togglePadding,
    required this.toggleThumbSize,
  });

  final double scale;
  final double pageTopPadding;
  final double pageBottomPadding;
  final double headerLeftInset;
  final double headerRightInset;
  final double backButtonSize;
  final double backButtonIconSize;
  final double headerGap;
  final double headerTitleSize;
  final double headerBottomGap;
  final double sectionGap;
  final double sectionTitleLeftInset;
  final double sectionTitleGap;
  final double sectionTitleSize;
  final double sectionTitleLetterSpacing;
  final double cardSideInset;
  final double cardRadius;
  final double rowHorizontalPadding;
  final double rowTitleSize;
  final double rowValueSize;
  final double chevronSize;
  final double shortRowHeight;
  final double shortRowDelta;
  final double toggleRowHeight;
  final double bottomRowHeight;
  final double advancedBottomRowHeight;
  final double toggleWidth;
  final double toggleHeight;
  final double togglePadding;
  final double toggleThumbSize;

  factory _CameraSettingsMetrics.forWidth(double width) {
    final scale = width / 290;
    double s(double value) => value * scale;
    return _CameraSettingsMetrics(
      scale: scale,
      pageTopPadding: s(20),
      pageBottomPadding: s(24),
      headerLeftInset: s(20),
      headerRightInset: s(20),
      backButtonSize: s(32),
      backButtonIconSize: s(16),
      headerGap: s(12),
      headerTitleSize: s(18),
      headerBottomGap: s(20),
      sectionGap: s(18),
      sectionTitleLeftInset: s(20),
      sectionTitleGap: s(8),
      sectionTitleSize: s(9),
      sectionTitleLetterSpacing: s(0.9),
      cardSideInset: s(16),
      cardRadius: s(12),
      rowHorizontalPadding: s(14),
      rowTitleSize: s(13),
      rowValueSize: s(13),
      chevronSize: s(14),
      shortRowHeight: s(48.5),
      shortRowDelta: s(1),
      toggleRowHeight: s(53),
      bottomRowHeight: s(49.5),
      advancedBottomRowHeight: s(47.5),
      toggleWidth: s(40),
      toggleHeight: s(24),
      togglePadding: s(2),
      toggleThumbSize: s(20),
    );
  }
}

class _CameraSettingsBackPainter extends CustomPainter {
  const _CameraSettingsBackPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.5 / 16)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (10 / 16), size.height * (3 / 16))
          ..lineTo(size.width * (5 / 16), size.height * (8 / 16))
          ..lineTo(size.width * (10 / 16), size.height * (13 / 16));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _CameraSettingsBackPainter oldDelegate) =>
      oldDelegate.color != color;
}
