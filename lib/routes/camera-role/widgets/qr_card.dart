//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;

class QrCard extends StatelessWidget {
  const QrCard({required this.scale, required this.payload, super.key});

  static const _qrPixelSize = 256;

  final double scale;
  final String payload;

  @override
  Widget build(BuildContext context) {
    final encoded = zxing.zx.encodeBarcode(
      contents: payload,
      params: zxing.EncodeParams(
        format: zxing.Format.qrCode,
        width: _qrPixelSize,
        height: _qrPixelSize,
        margin: 8,
        eccLevel: zxing.EccLevel.quartile,
      ),
    );

    return Container(
      padding: EdgeInsets.all(scale * 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(scale * 20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: scale * 28,
            offset: Offset(0, scale * 14),
          ),
        ],
      ),
      child: SizedBox(
        width: scale * 200,
        height: scale * 200,
        child:
            encoded.isValid && encoded.data != null
                ? Image.memory(
                  zxing.pngFromBytes(encoded.data!, _qrPixelSize, _qrPixelSize),
                  filterQuality: FilterQuality.none,
                  gaplessPlayback: true,
                )
                : Icon(
                  Icons.qr_code_2_rounded,
                  color: Colors.black.withValues(alpha: 0.25),
                  size: scale * 64,
                ),
      ),
    );
  }
}
