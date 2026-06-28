//! SPDX-License-Identifier: GPL-3.0-or-later

class PrefKeys {
  static const androidPushPlatform = 'android_push_platform';
  static const needUpdateFcmToken = 'need_update_fcm_token';
  static const needUpdateIosRelayBinding = 'need_update_ios_relay_binding';
  static const needUploadIosNotificationTarget =
      'need_upload_ios_notification_target';
  static const cameraSet = 'camera_set';
  static const needNotification = 'saved_need_notification_state';
  static const fcmToken = 'fcm_token';
  static const fcmConfigJson = 'fcm_config_json';
  static const iosApnsToken = 'ios_apns_token';
  static const iosAppInstallId = 'ios_app_install_id';
  static const iosAppAttestKeyId = 'ios_app_attest_key_id';
  static const iosRelayAttested = 'ios_relay_attested';
  static const iosRelayAttestedKeyId = 'ios_relay_attested_key_id';
  static const iosRelayHubToken = 'ios_relay_hub_token';
  static const iosRelayHubTokenExpiryMs = 'ios_relay_hub_token_expiry_ms';
  static const iosRelayBindingJson = 'ios_relay_binding_json';
  static const serverAddr = "server_addr";
  static const serverUsername = "server_username";
  static const serverPassword = "server_password";
  static const deviceRole = "device_role";
  static const relayConnectionKind = "relay_connection_kind";
  static const recordingMotionVideosPrefix = "recording_motion_videos_";
  static const lastRecordingTimestampPrefix = "last_recording_timestamp_";
  static const cameraNameKey = "camera_name_key";
  static const lastCameraAdd = "last_camera_add";
  static const downloadCameraQueue = "download_camera_queue";
  static const backupDownloadCameraQueue = "backup_download_camera_queue";
  static const downloadActiveCameras = "download_active_cameras";
  static const notificationsEnabled = "notifications_enabled";
  static const lastNotificationCheck = "last_notification_check";
  static const storageAutoCleanupEnabled = "storage_auto_cleanup_enabled";
  static const storageRetentionDays = "storage_retention_days";
  static const storageLastCleanupMs = "storage_last_cleanup_ms";
  static const numIgnoredHeartbeatsPrefix = "num_ignored_heartbeat_";
  static const cameraStatusPrefix = "camera_status_";
  static const numHeartbeatNotificationsPrefix = "num_heartbeat_notifications_";
  static const lastHeartbeatTimestampPrefix = "last_heartbeat_timestamp_";
  static const firmwareVersionPrefix = "firmware_version_";
  static const cameraOsVersionPrefix = "camera_os_version_";
  static const lastOutdatedNotification = "last_outdated_notification";
  static const cameraNotificationsEnabledPrefix =
      "camera_notifications_enabled_";
  static const cameraNotificationEventsPrefix = "camera_notification_events_";
  static const reviewEnvironmentJson = "review_environment_json";
  static const unifiedPushDistributor = 'unified_push_distributor';
  static const unifiedPushEndpointUrl = 'unified_push_endpoint_url';
  static const unifiedPushPubKey = 'unified_push_pub_key';
  static const unifiedPushAuth = 'unified_push_auth';
}
