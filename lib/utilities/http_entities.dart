//! SPDX-License-Identifier: GPL-3.0-or-later
// JSON for serialization structure matching the server

// Used in bulk check to contain the group name and epochs for each in the list.
class MotionPair {
  String groupName;
  int epochToCheck;

  /// The hashed object name for the enterprise delivery service.
  String? filename;

  MotionPair(this.groupName, this.epochToCheck, {this.filename});

  Map<String, dynamic> toJson() => {
    'group_name': groupName,
    'epoch_to_check': epochToCheck,
    if (filename != null) 'filename': filename,
  };
}

// Used in bulk check to contain a list of MotionPair (see above)
class MotionPairs {
  List<MotionPair> groupNames;

  MotionPairs(this.groupNames);

  Map<String, dynamic> toJson() => {'group_names': groupNames};
}

// Used in our /pair request to ensure atomically that both sides have paired correctly
class PairingRequest {
  final String pairingToken;
  final String role;
  final NotificationTarget? notificationTarget;

  PairingRequest(this.pairingToken, this.role, {this.notificationTarget});

  Map<String, dynamic> toJson() => {
    'pairing_token': pairingToken,
    'role': role,
    if (notificationTarget != null) 'notification_target': notificationTarget,
  };
}

class IosRelayBindingPayload {
  final String relayBaseUrl;
  final String hubToken;
  final String appInstallId;
  final String hubId;
  final String deviceToken;
  final int expiresAtEpochMs;
  final int refreshedAtEpochMs;

  IosRelayBindingPayload({
    required this.relayBaseUrl,
    required this.hubToken,
    required this.appInstallId,
    required this.hubId,
    required this.deviceToken,
    required this.expiresAtEpochMs,
    required this.refreshedAtEpochMs,
  });

  factory IosRelayBindingPayload.fromJson(Map<String, dynamic> json) {
    return IosRelayBindingPayload(
      relayBaseUrl: (json['relay_base_url'] ?? '').toString(),
      hubToken: (json['hub_token'] ?? '').toString(),
      appInstallId: (json['app_install_id'] ?? '').toString(),
      hubId: (json['hub_id'] ?? '').toString(),
      deviceToken: (json['device_token'] ?? '').toString(),
      expiresAtEpochMs: (json['expires_at_epoch_ms'] ?? 0) as int,
      refreshedAtEpochMs: (json['refreshed_at_epoch_ms'] ?? 0) as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'relay_base_url': relayBaseUrl,
    'hub_token': hubToken,
    'app_install_id': appInstallId,
    'hub_id': hubId,
    'device_token': deviceToken,
    'expires_at_epoch_ms': expiresAtEpochMs,
    'refreshed_at_epoch_ms': refreshedAtEpochMs,
  };
}

class NotificationTarget {
  final String platform;
  final IosRelayBindingPayload? iosRelayBinding;
  final String? unifiedpushEndpointUrl;
  final String? unifiedpushPubKey;
  final String? unifiedpushAuth;

  NotificationTarget({
    required this.platform,
    this.iosRelayBinding,
    this.unifiedpushEndpointUrl,
    this.unifiedpushPubKey,
    this.unifiedpushAuth,
  });

  Map<String, dynamic> toJson() => {
    'platform': platform,
    if (iosRelayBinding != null) 'ios_relay_binding': iosRelayBinding,
    if (unifiedpushEndpointUrl != null)
      'unifiedpush_endpoint_url': unifiedpushEndpointUrl,
    if (unifiedpushPubKey != null) 'unifiedpush_pub_key': unifiedpushPubKey,
    if (unifiedpushAuth != null) 'unifiedpush_auth': unifiedpushAuth,
  };
}

// TODO: Expand on this to store / retrieve settings from the server.
class ClientSettingsMessage {
  String sender;
  String type;
  String status;
  int endTime;

  ClientSettingsMessage({
    required this.sender,
    required this.type,
    required this.status,
    required this.endTime,
  });

  Map<String, dynamic> toJson() => {
    'sender': sender,
    'type': type,
    'status': status,
    'endTime': endTime,
  };
}
