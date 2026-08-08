//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

bool shouldNotifyFirmwareUpdate(String? currentFirmware, String newFirmware) {
  return currentFirmware != null &&
      currentFirmware.isNotEmpty &&
      currentFirmware != newFirmware;
}

class CameraVersionInfo {
  final String firmwareVersion;
  final String osVersion;

  const CameraVersionInfo({
    required this.firmwareVersion,
    required this.osVersion,
  });

  factory CameraVersionInfo.fromJsonString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Camera version info must be a JSON object');
    }
    return CameraVersionInfo.fromJson(decoded);
  }

  factory CameraVersionInfo.fromJson(Map<String, dynamic> json) {
    final firmwareVersion = json['firmware_version'];
    final osVersion = json['os_version'];
    if (firmwareVersion is! String || osVersion is! String) {
      throw FormatException('Invalid camera version info');
    }
    return CameraVersionInfo(
      firmwareVersion: firmwareVersion,
      osVersion: osVersion,
    );
  }
}

class HeartbeatStatus {
  final String status;
  final CameraVersionInfo? versionInfo;

  const HeartbeatStatus({required this.status, required this.versionInfo});

  factory HeartbeatStatus.fromJsonString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Heartbeat status must be a JSON object');
    }

    final status = decoded['status'];
    final versionInfo = decoded['version_info'];
    if (status is! String) {
      throw FormatException('Invalid heartbeat status');
    }

    return HeartbeatStatus(
      status: status,
      versionInfo:
          versionInfo is Map<String, dynamic>
              ? CameraVersionInfo.fromJson(versionInfo)
              : null,
    );
  }
}
