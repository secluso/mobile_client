//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/utilities/app_coordination_state.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/routes/camera/new/ip_camera_waiting.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';
import 'package:flutter/services.dart';

class IpCameraDialog extends StatefulWidget {
  const IpCameraDialog({
    super.key,
    this.initialCameraName,
    this.initialCameraIp,
  });

  final String? initialCameraName;
  final String? initialCameraIp;

  @override
  State<IpCameraDialog> createState() => _IpCameraDialogState();

  static Future<Map<String, Object>?> showIpCameraPopup(
    BuildContext context, {
    String? initialCameraName,
    String? initialCameraIp,
  }) async {
    return Navigator.of(context).push<Map<String, Object>?>(
      MaterialPageRoute<Map<String, Object>?>(
        fullscreenDialog: true,
        builder:
            (ctx) => IpCameraDialog(
              initialCameraName: initialCameraName,
              initialCameraIp: initialCameraIp,
            ),
      ),
    );
  }
}

class _IpCameraDialogState extends State<IpCameraDialog> {
  final _cameraNameController = TextEditingController();
  final _cameraIpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cameraNameController.text = widget.initialCameraName ?? '';
    _cameraIpController.text = widget.initialCameraIp ?? '';
  }

  @override
  void dispose() {
    _cameraNameController.dispose();
    _cameraIpController.dispose();
    super.dispose();
  }

  void _onCancel() {
    Navigator.of(context).pop(null); // Return null => canceled
  }

  void _onAddCamera() async {
    final cameraName = _cameraNameController.text.trim();
    final cameraIp = _cameraIpController.text.trim();

    try {
      final prefs = await SharedPreferences.getInstance();

      // Reset these as they are no longer needed.
      if (prefs.containsKey(PrefKeys.lastCameraAdd)) {
        var lastCameraName = prefs.getString(PrefKeys.lastCameraAdd)!;
        await deregisterCamera(cameraName: lastCameraName);
        invalidateCameraInit(lastCameraName);
        HttpClientService.instance.clearGroupNameCache(lastCameraName);
        prefs.remove(PrefKeys.lastCameraAdd);

        final camDir = await AppPaths.cameraDirectory(lastCameraName);
        if (await camDir.exists()) {
          try {
            await camDir.delete(recursive: true);
            Log.d('Deleted camera folder: ${camDir.path}');
          } catch (e) {
            Log.e('Error deleting folder: $e');
          }
        }
      }

      if (!await AppCoordinationState.containsCamera(cameraName)) {
        if (!mounted) {
          return;
        }

        final result = <String, Object>{
          "type": "ip",
          "cameraName": cameraName,
          "qrCode": Uint8List(0),
          "cameraIp": cameraIp,
        };

        await CameraSetupStatusDialog.show(context, result);
      } else {
        if (!mounted) {
          return;
        }
        FocusManager.instance.primaryFocus?.unfocus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              "Please use a unique name for the camera",
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
        return;
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      FocusManager.instance.primaryFocus?.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            "Failed to add camera: $e",
            style: TextStyle(color: Colors.red),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isFormComplete =
        _cameraNameController.text.trim().isNotEmpty &&
        _cameraIpController.text.trim().isNotEmpty;
    final backgroundColor =
        dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7);
    final titleColor = dark ? Colors.white : const Color(0xFF111827);
    final sectionLabelColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final cardColor =
        dark ? Colors.white.withValues(alpha: 0.03) : Colors.white;
    final cardBorderColor =
        dark ? Colors.white.withValues(alpha: 0.05) : const Color(0x0A000000);
    final inputBorderColor =
        dark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E7EB);
    final fieldLabelColor =
        dark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF4B5563);
    final hintColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final noteColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final buttonFill =
        isFormComplete
            ? (dark ? Colors.white : const Color(0xFF0A0A0A))
            : (dark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFE5E7EB));
    final buttonTextColor =
        isFormComplete
            ? (dark ? const Color(0xFF050505) : Colors.white)
            : (dark
                ? Colors.white.withValues(alpha: 0.2)
                : const Color(0xFF9CA3AF));

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = constraints.maxWidth / 290;
            double scaled(double value) => value * scale;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                scaled(16),
                scaled(16),
                scaled(16),
                scaled(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: scaled(54),
                    child: Row(
                      children: [
                        _IpSetupBackButton(
                          size: scaled(32),
                          iconSize: scaled(16),
                          fillColor:
                              dark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : const Color(0xFFE5E7EB),
                          iconColor:
                              dark ? Colors.white : const Color(0xFF6B7280),
                          onTap: _onCancel,
                        ),
                        SizedBox(width: scaled(12)),
                        Text(
                          'IP Camera Setup',
                          style: GoogleFonts.inter(
                            color: titleColor,
                            fontSize: scaled(18),
                            fontWeight: FontWeight.w600,
                            height: 28 / 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: scaled(16)),
                  Text(
                    'CAMERA DETAILS',
                    style: GoogleFonts.inter(
                      color: sectionLabelColor,
                      fontSize: scaled(9),
                      fontWeight: FontWeight.w600,
                      letterSpacing: scaled(0.9),
                      height: 13.5 / 9,
                    ),
                  ),
                  SizedBox(height: scaled(10)),
                  Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(scaled(12)),
                      border: Border.all(color: cardBorderColor),
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
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            scaled(16),
                            scaled(16),
                            scaled(16),
                            scaled(17),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Camera Name',
                                style: GoogleFonts.inter(
                                  color: fieldLabelColor,
                                  fontSize: scaled(11),
                                  fontWeight: FontWeight.w500,
                                  height: 16.5 / 11,
                                ),
                              ),
                              SizedBox(height: scaled(17)),
                              _IpSetupInput(
                                controller: _cameraNameController,
                                hintText: 'e.g. Garage Cam',
                                scale: scale,
                                borderColor: inputBorderColor,
                                hintColor: hintColor,
                                keyboardType: TextInputType.text,
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 1,
                          color:
                              dark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : const Color(0xFFE5E7EB),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            scaled(16),
                            scaled(14),
                            scaled(16),
                            scaled(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Camera Hub IP Address',
                                style: GoogleFonts.inter(
                                  color: fieldLabelColor,
                                  fontSize: scaled(11),
                                  fontWeight: FontWeight.w500,
                                  height: 16.5 / 11,
                                ),
                              ),
                              SizedBox(height: scaled(17)),
                              _IpSetupInput(
                                controller: _cameraIpController,
                                hintText: 'e.g. 192.168.1.100',
                                scale: scale,
                                borderColor: inputBorderColor,
                                hintColor: hintColor,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                useMonospace: true,
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: scaled(22)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: scaled(12),
                        height: scaled(12),
                        child: CustomPaint(
                          painter: _IpSetupLockPainter(noteColor),
                        ),
                      ),
                      SizedBox(width: scaled(10)),
                      Expanded(
                        child: Text(
                          'Your camera must be on the same network as\nyour relay. Connection details are encrypted\nend-to-end.',
                          style: GoogleFonts.inter(
                            color: noteColor,
                            fontSize: scaled(10),
                            fontWeight: FontWeight.w400,
                            height: 16.25 / 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: scaled(26)),
                  SizedBox(
                    width: double.infinity,
                    height: scaled(46),
                    child: FilledButton(
                      onPressed: isFormComplete ? _onAddCamera : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: buttonFill,
                        foregroundColor: buttonTextColor,
                        disabledBackgroundColor: buttonFill,
                        disabledForegroundColor: buttonTextColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(scaled(12)),
                        ),
                        padding: EdgeInsets.zero,
                        textStyle: GoogleFonts.inter(
                          fontSize: scaled(12),
                          fontWeight: FontWeight.w600,
                          letterSpacing: scaled(0.6),
                          height: 18 / 12,
                        ),
                      ),
                      child: const Text('CONNECT CAMERA'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _IpSetupInput extends StatelessWidget {
  const _IpSetupInput({
    required this.controller,
    required this.hintText,
    required this.scale,
    required this.borderColor,
    required this.hintColor,
    required this.keyboardType,
    required this.onChanged,
    this.useMonospace = false,
  });

  final TextEditingController controller;
  final String hintText;
  final double scale;
  final Color borderColor;
  final Color hintColor;
  final TextInputType keyboardType;
  final ValueChanged<String> onChanged;
  final bool useMonospace;

  @override
  Widget build(BuildContext context) {
    double scaled(double value) => value * scale;

    return SizedBox(
      height: scaled(45.5),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style:
            useMonospace
                ? TextStyle(
                  fontFamily: 'Menlo',
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : const Color(0xFF111827),
                  fontSize: scaled(13),
                  height: 15 / 13,
                )
                : GoogleFonts.inter(
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : const Color(0xFF111827),
                  fontSize: scaled(13),
                  fontWeight: FontWeight.w400,
                  height: 15.5 / 13,
                ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle:
              useMonospace
                  ? TextStyle(
                    fontFamily: 'Menlo',
                    color: hintColor,
                    fontSize: scaled(13),
                    height: 15 / 13,
                  )
                  : GoogleFonts.inter(
                    color: hintColor,
                    fontSize: scaled(13),
                    fontWeight: FontWeight.w400,
                    height: 15.5 / 13,
                  ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: scaled(16),
            vertical: scaled(14),
          ),
          filled: true,
          fillColor:
              Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.02)
                  : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(scaled(12)),
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(scaled(12)),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(scaled(12)),
            borderSide: BorderSide(
              color: const Color(0xFF8BB3EE),
              width: scaled(1.2),
            ),
          ),
        ),
      ),
    );
  }
}

class _IpSetupBackButton extends StatelessWidget {
  const _IpSetupBackButton({
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
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: SizedBox(
              width: iconSize,
              height: iconSize,
              child: CustomPaint(painter: _IpSetupBackIconPainter(iconColor)),
            ),
          ),
        ),
      ),
    );
  }
}

class _IpSetupBackIconPainter extends CustomPainter {
  const _IpSetupBackIconPainter(this.color);

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
          ..moveTo(size.width * (10.5 / 16), size.height * (3.0 / 16))
          ..lineTo(size.width * (5.0 / 16), size.height * (8.0 / 16))
          ..lineTo(size.width * (10.5 / 16), size.height * (13.0 / 16));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _IpSetupBackIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _IpSetupLockPainter extends CustomPainter {
  const _IpSetupLockPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (0.95 / 12)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (2.0 / 12),
        size.height * (5.5 / 12),
        size.width * (8.0 / 12),
        size.height * (4.5 / 12),
      ),
      Radius.circular(size.width * (0.9 / 12)),
    );
    canvas.drawRRect(body, stroke);
    final shackle =
        Path()
          ..moveTo(size.width * (3.6 / 12), size.height * (5.5 / 12))
          ..lineTo(size.width * (3.6 / 12), size.height * (3.6 / 12))
          ..arcToPoint(
            Offset(size.width * (8.4 / 12), size.height * (3.6 / 12)),
            radius: Radius.circular(size.width * (2.4 / 12)),
          )
          ..lineTo(size.width * (8.4 / 12), size.height * (5.5 / 12));
    canvas.drawPath(shackle, stroke);
  }

  @override
  bool shouldRepaint(covariant _IpSetupLockPainter oldDelegate) =>
      oldDelegate.color != color;
}
