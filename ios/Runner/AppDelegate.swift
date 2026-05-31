//! SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Flutter
import NetworkExtension
import SystemConfiguration.CaptiveNetwork
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        WorkmanagerPlugin.registerPeriodicTask(
            withIdentifier: "periodic_heartbeat_task",
            frequency: NSNumber(value: 6 * 60 * 60)
        )
        WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "com.secluso.task")

        // Ensures all plugins (http, path_provider …) are available
        WorkmanagerPlugin.setPluginRegistrantCallback { registry in
            GeneratedPluginRegistrant.register(with: registry)
        }

        if let registrar = self.registrar(forPlugin: "byte_player_view") {
            // Platform-view factory
            let factory = BytePlayerViewFactory(messenger: registrar.messenger())
            registrar.register(factory, withId: "byte_player_view")

            // MethodChannel that mirrors Android
            BytePlayerChannel.register(with: registrar.messenger())
        }

        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        IosPushRelayBridge.shared.register(with: controller)
        let storage = FlutterMethodChannel(
            name: "secluso.com/storage",
            binaryMessenger: controller.binaryMessenger)
        storage.setMethodCallHandler { call, result in
            guard let args = call.arguments as? [String: Any],
                let path = args["path"] as? String,
                !path.isEmpty
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGS", message: "Missing path", details: nil))
                return
            }

            switch call.method {
            case "excludeFromBackup":
                do {
                    try Self.excludeFromBackup(path: path)
                    result(nil)
                } catch {
                    result(
                        FlutterError(
                            code: "BACKUP_EXCLUDE_FAILED",
                            message: error.localizedDescription,
                            details: nil))
                }
            case "excludeTreeFromBackup":
                do {
                    try Self.excludeTreeFromBackup(path: path)
                    result(nil)
                } catch {
                    result(
                        FlutterError(
                            code: "BACKUP_TREE_EXCLUDE_FAILED",
                            message: error.localizedDescription,
                            details: nil))
                }
            case "isExcludedFromBackup":
                do {
                    result(try Self.isExcludedFromBackup(path: path))
                } catch {
                    result(
                        FlutterError(
                            code: "BACKUP_STATUS_FAILED",
                            message: error.localizedDescription,
                            details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // This is to give Dart access to FileManager.containerURL
        // In app_paths.dart, it needs to find the App Group container path on iOS
        // (as this is where the NSE and main app share state)
        let appGroup = FlutterMethodChannel(
            name: "secluso.com/app_group",
            binaryMessenger: controller.binaryMessenger
        )
        appGroup.setMethodCallHandler { call, result in
            switch call.method {
            case "getContainerPath":
                guard let args = call.arguments as? [String: Any],
                    let identifier = args["identifier"] as? String,
                    !identifier.isEmpty
                else {
                    result(
                        FlutterError(
                            code: "INVALID_ARGS",
                            message: "Missing App Group identifier",
                            details: nil))
                    return
                }
                let url = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: identifier
                )
                result(url?.path)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        let wifi = FlutterMethodChannel(
            name: "secluso.com/wifi",
            binaryMessenger: controller.binaryMessenger)
        wifi.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in

            if call.method == "connectToWifi" {
                guard let args = call.arguments as? [String: String],
                    let ssid = args["ssid"]
                else {
                    result(
                        FlutterError(code: "INVALID_ARGS", message: "Missing SSID", details: nil))
                    return
                }

                let password = args["password"] ?? ""
                let config =
                    password.isEmpty
                    ? NEHotspotConfiguration(ssid: ssid)
                    : NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
                config.joinOnce = true

                NEHotspotConfigurationManager.shared.apply(config) { error in
                    if let error = error {
                        let nsError = error as NSError
                        if nsError.domain == NEHotspotConfigurationErrorDomain,
                            nsError.code == NEHotspotConfigurationError.alreadyAssociated.rawValue
                        {
                            result("connected")
                            return
                        }
                        result(
                            FlutterError(
                                code: "FAILED", message: error.localizedDescription, details: nil))
                    } else {
                        result("connected")
                    }
                }
            } else if call.method == "getCurrentSSID" {
                if let interfaces = CNCopySupportedInterfaces() as? [String] {
                    for interface in interfaces {
                        if let info = CNCopyCurrentNetworkInfo(interface as CFString)
                            as? [String: AnyObject],
                            let ssid = info["SSID"] as? String
                        {
                            result(ssid)
                            return
                        }
                    }
                }
                result("")  // Return empty string if not connected
            } else if call.method == "disconnectFromWifi" {
                guard let args = call.arguments as? [String: String],
                    let ssid = args["ssid"]
                else {
                    result(
                        FlutterError(code: "INVALID_ARGS", message: "Missing SSID", details: nil))
                    return
                }

                NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
                result("disconnected")
            } else {
                result(FlutterMethodNotImplemented)
            }
        })

        let thumb = FlutterMethodChannel(
            name: "secluso.com/thumbnail",
            binaryMessenger: controller.binaryMessenger
        )
        thumb.setMethodCallHandler { call, result in
            guard call.method == "generateThumbnail",
                let args = call.arguments as? [String: Any],
                let path = args["path"] as? String
            else {
                result(FlutterMethodNotImplemented)
                return
            }

            let fullSize = args["fullSize"] as? Bool ?? false

            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVAsset(url: URL(fileURLWithPath: path))
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true

                if !fullSize {
                    gen.maximumSize = CGSize(width: 80, height: 80)
                }

                let durationSeconds = CMTimeGetSeconds(asset.duration)
                let targetSeconds: Double
                if durationSeconds.isFinite && durationSeconds > 0 {
                    targetSeconds = min(max(durationSeconds * 0.25, 0.25), 1.0)
                } else {
                    targetSeconds = 0.5
                }
                let time = CMTime(seconds: targetSeconds, preferredTimescale: 600)

                do {
                    let cgImg = try gen.copyCGImage(at: time, actualTime: nil)
                    let uiImg = UIImage(cgImage: cgImg)
                    if let png = uiImg.pngData() {
                        result(FlutterStandardTypedData(bytes: png))
                    } else {
                        result(
                            FlutterError(
                                code: "PNG_ERROR",
                                message: "Could not encode PNG",
                                details: nil))
                    }
                } catch {
                    result(
                        FlutterError(
                            code: "THUMBNAIL_ERROR",
                            message: error.localizedDescription,
                            details: nil))
                }
            }
        }

        GeneratedPluginRegistrant.register(with: self)
        UNUserNotificationCenter.current().delegate = self
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        IosPushRelayBridge.shared.setApnsToken(deviceToken)
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[IOS PUSH] Failed to register for remote notifications: \(error.localizedDescription)")
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }

    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        IosPushRelayBridge.shared.recordIncomingRemoteNotification(userInfo)
        completionHandler(.newData)
    }

    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        IosPushRelayBridge.shared.recordIncomingRemoteNotification(userInfo)

        if userInfo["body"] != nil {
            completionHandler([])
        } else {
            super.userNotificationCenter(
                center,
                willPresent: notification,
                withCompletionHandler: completionHandler
            )
        }
    }

    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        IosPushRelayBridge.shared.recordIncomingRemoteNotification(response.notification.request.content.userInfo)
        super.userNotificationCenter(
            center,
            didReceive: response,
            withCompletionHandler: completionHandler
        )
    }

    private static func excludeFromBackup(path: String) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        let isDirectory = (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType)
            == .typeDirectory
        var url = URL(fileURLWithPath: path, isDirectory: isDirectory)
        try url.setResourceValues(values)
    }

    private static func excludeTreeFromBackup(path: String) throws {
        let fileManager = FileManager.default
        try excludeFromBackup(path: path)

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path, isDirectory: true),
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return
        }

        for case let url as URL in enumerator {
            try excludeFromBackup(path: url.path)
        }
    }

    private static func isExcludedFromBackup(path: String) throws -> Bool {
        let isDirectory = (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType)
            == .typeDirectory
        let url = URL(fileURLWithPath: path, isDirectory: isDirectory)
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        return values.isExcludedFromBackup ?? false
    }
}
