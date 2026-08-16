//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;
import 'package:secluso_flutter/routes/camera-role/theme.dart';
import 'package:secluso_flutter/routes/camera-role/widgets/marks.dart';

/// The pairing code, printed on warm paper inside a sketched frame.
class PairingQr extends StatelessWidget {
  const PairingQr({required this.payload, super.key});

  /// Side of the whole stage, frame included.
  static const size = 216.0;

  /// How far the paper sits inside the sketched frame.
  static const _inset = 17.0;
  static const _quietZone = 13.0;

  /// Rendered at a fixed size and scaled down, so modules stay square.
  static const _pixels = 256;

  final String payload;

  @override
  Widget build(BuildContext context) {
    final encoded = zxing.zx.encodeBarcode(
      contents: payload,
      params: zxing.EncodeParams(
        format: zxing.Format.qrCode,
        width: _pixels,
        height: _pixels,
        // The card's padding is the quiet zone, so the code itself needs only
        // a hair of margin.
        margin: 4,
        eccLevel: zxing.EccLevel.quartile,
      ),
    );

    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          const Positioned.fill(child: SketchFrame()),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(_inset),
              child: Container(
                padding: const EdgeInsets.all(_quietZone),
                decoration: BoxDecoration(
                  color: CamRole.qrPaper,
                  borderRadius: BorderRadius.circular(6),
                ),
                child:
                    encoded.isValid && encoded.data != null
                        // The encoder only draws black on white.
                        ? Image.memory(
                          zxing.pngFromBytes(encoded.data!, _pixels, _pixels),
                          filterQuality: FilterQuality.none,
                          gaplessPlayback: true,
                          color: CamRole.qrPaper,
                          colorBlendMode: BlendMode.multiply,
                        )
                        : const _QrUnavailable(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrUnavailable extends StatelessWidget {
  const _QrUnavailable();

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(
      Icons.qr_code_2_rounded,
      size: 64,
      color: Colors.black.withValues(alpha: 0.25),
    ),
  );
}
