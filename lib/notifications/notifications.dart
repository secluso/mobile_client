//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:secluso_flutter/utilities/logger.dart';

import 'package:secluso_flutter/routes/camera/view_video.dart';
import 'package:secluso_flutter/routes/camera/view_camera.dart';
import 'package:secluso_flutter/main.dart';
import 'package:secluso_flutter/database/app_stores.dart';

final FlutterLocalNotificationsPlugin _notifs =
    FlutterLocalNotificationsPlugin();
bool _notificationsInitialized = false;
Future<void>? _notificationsInitFuture;

// Initialization method
Future<void> initLocalNotifications() async {
  if (_notificationsInitialized) {
    return;
  }
  if (_notificationsInitFuture != null) {
    return _notificationsInitFuture!;
  }
  _notificationsInitFuture = _doInitLocalNotifications();
  try {
    await _notificationsInitFuture!;
  } finally {
    _notificationsInitFuture = null;
  }
}

Future<void> _doInitLocalNotifications() async {
  Log.d("Init local notifications called");
  // basic engine bootstrap (no permissions yet)
  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('ic_notification'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
    ),
  );
  await _notifs.initialize(
    settings: initSettings,
    // optional deep-link handler
    onDidReceiveNotificationResponse: (resp) async {
      final callInfo = _parseNotificationPayload(resp.payload);
      if (callInfo == null) {
        return;
      }

      if (callInfo.containsKey("cameraName") &&
          callInfo.containsKey("timestamp")) {
        String cameraName = callInfo["cameraName"].toString();
        String timestamp = callInfo["timestamp"].toString();

        final foundVideo = await AppStores.instance.videoStore
            .findFirstForNotification(cameraName, timestamp);

        final navCtx = navigatorKey.currentContext;

        if (foundVideo == null) {
          Log.i("Not in database yet. Send to $cameraName");

          if (navCtx != null) {
            ScaffoldMessenger.of(navCtx).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.red,
                content: Text(
                  "Video from notification is being downloaded",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            );

            navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => CameraViewPage(cameraName: cameraName),
              ),
            );
          }
        } else {
          Log.i("Found video. ${foundVideo.video}");

          if (navCtx != null) {
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder:
                    (_) => VideoViewPage(
                      cameraName: foundVideo.camera,
                      videoTitle: foundVideo.video,
                      visibleVideoTitle: repackageVideoTitle(foundVideo.video),
                      isLivestream: !foundVideo.motion,
                      canDownload: foundVideo.received,
                    ),
              ),
            );
          }
        }
      }
    },
  );

  // Ask OS for notification permission
  // await _ensureNotificationPermissions();

  // Create Android channel (no effect on iOS)
  if (Platform.isAndroid) {
    await _ensureMotionChannelAndroid();
    await _ensureSupportChannelAndroid();
    await _ensureCameraAccessChannelAndroid();
  }
  _notificationsInitialized = true;
}

Map<String, dynamic>? _parseNotificationPayload(String? payload) {
  final raw = payload?.trim();
  if (raw == null || raw.isEmpty) {
    Log.w('Notification tap missing payload');
    return null;
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      Log.d("On video tap");
      return decoded;
    }
    if (decoded is Map) {
      Log.d("On video tap");
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    Log.w('Notification tap payload was not a JSON object');
  } catch (e, st) {
    Log.w('Invalid notification tap payload: $e\n$st');
  }
  return null;
}

int _motionNotifId(String cameraName, String timestamp) {
  // deterministic id
  final ts = int.tryParse(timestamp) ?? 0;
  return cameraName.hashCode ^ ts;
}

int motionNotificationId(String cameraName, String timestamp) {
  return _motionNotifId(cameraName, timestamp);
}

int upgradedMotionNotificationId(String cameraName, String timestamp) {
  return _motionNotifId(cameraName, timestamp) ^ 0x40000000;
}

Future<void> showMotionNotification({
  required String cameraName,
  required String timestamp, // unix seconds
  String? thumbnailPath, // local file path
  int? notificationId, // optional explicit id
  bool onlyAlertOnce = false,
  String alertLabel = 'Motion',
}) async {
  final formatted = _formatTimestamp(timestamp);
  final id = notificationId ?? _motionNotifId(cameraName, timestamp);
  final titleText = '$cameraName: $alertLabel detected';
  final bodyText = formatted;

  // Android
  AndroidNotificationDetails androidDetails;
  if (thumbnailPath != null) {
    final thumbBitmap = FilePathAndroidBitmap(thumbnailPath);
    final bigPic = BigPictureStyleInformation(
      thumbBitmap,
      hideExpandedLargeIcon: true,
      contentTitle: titleText,
      summaryText: bodyText,
    );

    androidDetails = AndroidNotificationDetails(
      'motion_channel',
      'Motion Events',
      channelDescription: 'Camera motion alerts',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
      largeIcon: thumbBitmap,
      vibrationPattern: Int64List.fromList([500, 500, 500, 500, 500]),
      enableLights: true,
      color: const Color(0xFF8BB3EE),
      ledColor: const Color(0xFF8BB3EE),
      ledOnMs: 2000,
      ledOffMs: 2000,
      styleInformation: bigPic,
      onlyAlertOnce: onlyAlertOnce,
    );
  } else {
    androidDetails = AndroidNotificationDetails(
      'motion_channel',
      'Motion Events',
      channelDescription: 'Camera motion alerts',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
      vibrationPattern: Int64List.fromList([500, 500, 500, 500, 500]),
      enableLights: true,
      color: const Color(0xFF8BB3EE),
      ledColor: const Color(0xFF8BB3EE),
      ledOnMs: 2000,
      ledOffMs: 2000,
      onlyAlertOnce: onlyAlertOnce,
    );
  }

  // iOS
  DarwinNotificationDetails iosDetails;
  if (thumbnailPath != null) {
    iosDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      sound: onlyAlertOnce ? null : 'default',
      badgeNumber: 1,
      attachments: [
        DarwinNotificationAttachment(
          thumbnailPath,
          identifier: 'motion-thumb-$cameraName-$timestamp',
        ),
      ],
    );
  } else {
    iosDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      sound: onlyAlertOnce ? null : 'default',
      badgeNumber: 1,
    );
  }

  final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

  await _notifs.show(
    id: id, // unique id
    title: titleText, // title
    body: bodyText, // body
    notificationDetails: details,
    payload: jsonEncode({"cameraName": cameraName, "timestamp": timestamp}),
  );
}

Future<void> cancelMotionNotification({
  required String cameraName,
  required String timestamp,
}) async {
  await _notifs.cancel(id: _motionNotifId(cameraName, timestamp));
}

Future<void> _ensureMotionChannelAndroid() async {
  const channel = AndroidNotificationChannel(
    'motion_channel', // id
    'Motion Events', // visible name
    description: 'Camera motion alerts',
    importance: Importance.high,
  );

  await _notifs
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);
}

Future<void> _ensureSupportChannelAndroid() async {
  const channel = AndroidNotificationChannel(
    'support_channel',
    'Support Alerts',
    description: 'Support and diagnostic notifications',
    importance: Importance.high,
  );

  await _notifs
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);
}

Future<void> _ensureCameraAccessChannelAndroid() async {
  const channel = AndroidNotificationChannel(
    'camera_access_channel',
    'Camera Access',
    description: 'Changes to this phone’s access to the security camera',
    importance: Importance.high,
  );

  await _notifs
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);
}

String _formatTimestamp(String unixSeconds) {
  final secs = int.tryParse(unixSeconds) ?? 0;
  final date =
      DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true).toLocal();
  return DateFormat('HH:mm:ss, yyyy-MM-dd').format(date);
}

Future<void> showCameraStatusNotification({
  required String cameraName,
  required String msg,
}) async {
  // Android
  final androidDetails = AndroidNotificationDetails(
    'camera_status_channel', // must match channel id below
    'Camera Status Events',
    channelDescription: 'Camera status alerts',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_notification',
    vibrationPattern: Int64List.fromList([500, 500, 500, 500, 500]),
    enableLights: true,
    color: const Color(0xFF8BB3EE),
    ledColor: const Color(0xFF8BB3EE),
    ledOnMs: 2000,
    ledOffMs: 2000,
  );

  // iOS
  final iosDetails = const DarwinNotificationDetails(
    interruptionLevel: InterruptionLevel.timeSensitive,
    sound: 'default',
    badgeNumber: 1,
  );

  // Cross-platform wrapper
  final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
  Log.d("Sent camera status notification!");

  await _notifs.show(
    id: DateTime.now().millisecondsSinceEpoch ~/ 1000, // unique id
    title: cameraName, // title
    body: msg, // body
    notificationDetails: details,
  );
}

Future<void> showCameraArchivedNotification({
  required String cameraName,
}) async {
  await initLocalNotifications();

  final androidDetails = AndroidNotificationDetails(
    'camera_access_channel',
    'Camera Access',
    channelDescription: 'Changes to this phone’s camera access',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_notification',
    vibrationPattern: Int64List.fromList([200, 200, 200]),
    enableLights: true,
    color: const Color(0xFF8BB3EE),
    ledColor: const Color(0xFF8BB3EE),
    ledOnMs: 1000,
    ledOffMs: 1000,
  );
  const iosDetails = DarwinNotificationDetails(
    interruptionLevel: InterruptionLevel.timeSensitive,
    sound: 'default',
    badgeNumber: 1,
  );

  await _notifs.show(
    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title: 'Access to ${cameraName} camera removed',
    body:
        'The main phone discontinued this phone from receiving new videos.',
    notificationDetails: NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    ),
  );
}

Future<void> showSupportLogNotification() async {
  // Android
  final androidDetails = AndroidNotificationDetails(
    'support_channel',
    'Support Alerts',
    channelDescription: 'Support and diagnostic notifications',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_notification',
    vibrationPattern: Int64List.fromList([200, 200, 200]),
    enableLights: true,
    color: const Color(0xFF8BB3EE),
    ledColor: const Color(0xFF8BB3EE),
    ledOnMs: 1000,
    ledOffMs: 1000,
  );

  // iOS
  final iosDetails = const DarwinNotificationDetails(
    interruptionLevel: InterruptionLevel.timeSensitive,
    sound: 'default',
    badgeNumber: 1,
  );

  final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

  await _notifs.show(
    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title: 'Secluso support',
    body:
        'An error occurred in the background. Open the app to copy logs for support.',
    notificationDetails: details,
  );
}

Future<void> showOutdatedNotification() async {
  // Android
  final androidDetails = AndroidNotificationDetails(
    'support_channel',
    'Support Alerts',
    channelDescription: 'Support and diagnostic notifications',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_notification',
    vibrationPattern: Int64List.fromList([200, 200, 200]),
    enableLights: true,
    color: const Color(0xFF8BB3EE),
    ledColor: const Color(0xFF8BB3EE),
    ledOnMs: 1000,
    ledOffMs: 1000,
  );

  // iOS
  final iosDetails = const DarwinNotificationDetails(
    interruptionLevel: InterruptionLevel.timeSensitive,
    sound: 'default',
    badgeNumber: 1,
  );

  final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

  await _notifs.show(
    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title: 'Secluso support',
    body:
        'Your app is outdated. Please update to continue receiving notifications and use your cameras',
    notificationDetails: details,
  );
}
