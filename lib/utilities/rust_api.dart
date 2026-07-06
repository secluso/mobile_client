//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb show Uint64List;
import 'package:secluso_flutter/src/rust/api.dart' as raw;
import 'package:secluso_flutter/utilities/logger.dart';

const String _traceSep = '|trace=';

String _cameraNameWithTrace(String cameraName) {
  final traceId = Log.currentContextId();
  if (traceId.isEmpty) {
    return cameraName;
  }
  return '$cameraName$_traceSep$traceId';
}

Future<bool> initializeCamera({
  required String cameraName,
  required String fileDir,
  required bool firstTime,
}) => raw.initializeCamera(
  cameraName: _cameraNameWithTrace(cameraName),
  fileDir: fileDir,
  firstTime: firstTime,
);

Future<void> deregisterCamera({required String cameraName}) =>
    raw.deregisterCamera(cameraName: _cameraNameWithTrace(cameraName));

Future<String> decryptVideo({
  required String cameraName,
  required String encFilename,
  required BigInt assumedEpoch,
}) => raw.decryptVideo(
  cameraName: _cameraNameWithTrace(cameraName),
  encFilename: encFilename,
  assumedEpoch: assumedEpoch,
);

Future<String> decryptThumbnail({
  required String cameraName,
  required String encFilename,
  required String pendingMetaDirectory,
  required BigInt assumedEpoch,
}) => raw.decryptThumbnail(
  cameraName: _cameraNameWithTrace(cameraName),
  encFilename: encFilename,
  pendingMetaDirectory: pendingMetaDirectory,
  assumedEpoch: assumedEpoch,
);

Future<String> flutterAddCamera({
  required String cameraName,
  required String ip,
  required List<int> secret,
  required bool standalone,
  required String ssid,
  required String password,
  required String pairingToken,
  required String credentialsFull,
  required bool android,
}) => raw.flutterAddCamera(
  cameraName: _cameraNameWithTrace(cameraName),
  ip: ip,
  secret: secret,
  standalone: standalone,
  ssid: ssid,
  password: password,
  pairingToken: pairingToken,
  credentialsFull: credentialsFull,
  android: android,
);

Future<void> shutdownApp() => raw.shutdownApp();

Future<bool> pingProprietaryDevice({required String cameraIp}) =>
    raw.pingProprietaryDevice(cameraIp: cameraIp);

Future<Uint8List> encryptSettingsMessage({
  required String cameraName,
  required List<int> data,
}) => raw.encryptSettingsMessage(
  cameraName: _cameraNameWithTrace(cameraName),
  data: data,
);

Future<String> decryptMessage({
  required String clientTag,
  required String cameraName,
  required List<int> data,
}) => raw.decryptMessage(
  clientTag: clientTag,
  cameraName: _cameraNameWithTrace(cameraName),
  data: data,
);

Future<String> getGroupName({
  required String clientTag,
  required String cameraName,
}) => raw.getGroupName(
  clientTag: clientTag,
  cameraName: _cameraNameWithTrace(cameraName),
);

Future<bool> livestreamUpdate({
  required String cameraName,
  required List<int> msg,
}) => raw.livestreamUpdate(
  cameraName: _cameraNameWithTrace(cameraName),
  msg: msg,
);

Future<Uint8List> livestreamDecrypt({
  required String cameraName,
  required List<int> data,
  required BigInt expectedChunkNumber,
}) => raw.livestreamDecrypt(
  cameraName: _cameraNameWithTrace(cameraName),
  data: data,
  expectedChunkNumber: expectedChunkNumber,
);

Future<String> rustLibVersion() => raw.rustLibVersion();

Future<Uint8List> generateHeartbeatRequestConfigCommand({
  required String cameraName,
  required BigInt timestamp,
}) => raw.generateHeartbeatRequestConfigCommand(
  cameraName: _cameraNameWithTrace(cameraName),
  timestamp: timestamp,
);

Future<String> processHeartbeatConfigResponse({
  required String cameraName,
  required List<int> configResponse,
  required BigInt expectedTimestamp,
}) => raw.processHeartbeatConfigResponse(
  cameraName: _cameraNameWithTrace(cameraName),
  configResponse: configResponse,
  expectedTimestamp: expectedTimestamp,
);

Future<String> getAddAppSecret() => raw.getAddAppSecret();

Future<Uint8List> getKeyPackages({required String cameraName}) =>
    raw.getKeyPackages(cameraName: _cameraNameWithTrace(cameraName));

Future<Uint8List> generateAddAppRequestConfigCommand({
  required String cameraName,
  required List<int> newAppKeyPackagesVec,
  required List<int> secret,
}) => raw.generateAddAppRequestConfigCommand(
  cameraName: _cameraNameWithTrace(cameraName),
  newAppKeyPackagesVec: newAppKeyPackagesVec,
  secret: secret,
);

Future<Uint8List> processAddAppConfigResponse({
  required String cameraName,
  required List<int> configResponse,
  required List<int> secret,
}) => raw.processAddAppConfigResponse(
  cameraName: _cameraNameWithTrace(cameraName),
  configResponse: configResponse,
  secret: secret,
);

Future<frb.Uint64List> joinCameraGroups({
  required String cameraName,
  required List<int> secret,
  required List<int> newAppDataVec,
}) => raw.joinCameraGroups(
  cameraName: _cameraNameWithTrace(cameraName),
  secret: secret,
  newAppDataVec: newAppDataVec,
);
