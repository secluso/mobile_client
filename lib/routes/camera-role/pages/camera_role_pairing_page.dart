//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Allow another phone to pair to this one; act in the role of Bluetooth advertising.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/camera-role/pages/camera_role_recording_page.dart';
import 'package:secluso_flutter/routes/camera-role/theme.dart';
import 'package:secluso_flutter/routes/camera-role/widgets/qr_card.dart';
import 'package:secluso_flutter/routes/camera-role/widgets/shared_widgets.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';

/// Shows the camera QR + live Bluetooth advertising state, waiting for the primary app to connect.
class CameraRolePairingPage extends StatelessWidget {
  const CameraRolePairingPage({super.key, this.onConnected});

  /// In production this fires automatically when the MLS handshake completes.
  final VoidCallback? onConnected;

  // A representative camera-QR payload for dummy testing until we get to swap this out
  static const _samplePayload =
      '{"v":"v1.2","cs":"k7Qm2Zr9Yx1Bv3Nw8Lp5Td0Hs6Jf4Gc","wp":"a1b2c3d4"}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cameraRoleBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final s = cameraRoleFlowScale(constraints);
            double sz(double v) => v * s;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(sz(24), sz(8), sz(24), sz(24)),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: sz(22),
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  SizedBox(height: sz(8)),
                  CameraRoleFlowHeading(
                    scale: s,
                    title: 'Scan from your main phone',
                    body:
                        'On the phone you watch your cameras from, add a '
                        'camera and scan this code.',
                  ),
                  SizedBox(height: sz(28)),
                  QrCard(scale: s, payload: _samplePayload),
                  SizedBox(height: sz(24)),
                  CameraRoleTintedCard(
                    scale: s,
                    accent: cameraRoleBlue,
                    icon: Icons.bluetooth_rounded,
                    title: 'Advertising over Bluetooth',
                    body:
                        'Keep both phones nearby and unlocked. Pairing '
                        'completes automatically once it connects.',
                  ),
                  SizedBox(height: sz(16)),
                  CameraRoleInfoCard(
                    scale: s,
                    rows: [
                      CameraRoleInfoRow(
                        scale: s,
                        label: 'Status',
                        value: 'Advertising',
                        valueColor: cameraRoleAmber,
                        leading: cameraRoleDot(sz(6), cameraRoleAmber),
                        showDivider: false,
                      ),
                    ],
                  ),
                  SizedBox(height: sz(18)),
                  TextButton.icon(
                    onPressed:
                        onConnected ??
                        () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => const CameraRoleRecordingPage(),
                          ),
                        ),
                    style: TextButton.styleFrom(
                      foregroundColor: cameraRoleWhite20,
                    ),
                    icon: Icon(
                      Icons.check_circle_outline_rounded,
                      size: sz(15),
                    ),
                    label: Text(
                      'Simulate "camera connected"',
                      style: GoogleFonts.inter(
                        fontSize: sz(11),
                        fontWeight: FontWeight.w500,
                      ),
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
