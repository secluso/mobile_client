//! SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Flutter
import Network
import NetworkExtension
import SystemConfiguration.CaptiveNetwork
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var localNetworkPromptBrowser: NWBrowser?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Rust uses raw BSD sockets, which iOS silently denies until the user grants Local Network access.
        // so we trigger them ourselves
        triggerLocalNetworkPrompt()

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
        CameraProxy.shared.register(with: controller.binaryMessenger)
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

                let appState = UIApplication.shared.applicationState
                // Clear any stale/half-installed config for this SSID first
                NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
                NEHotspotConfigurationManager.shared.apply(config) { error in
                    if let error = error {
                        let nsError = error as NSError
                        if nsError.domain == NEHotspotConfigurationErrorDomain,
                            nsError.code == NEHotspotConfigurationError.alreadyAssociated.rawValue
                        {
                            result("connected")
                            return
                        }
                        let diagnostics =
                            "domain=\(nsError.domain) code=\(nsError.code) "
                            + "desc=\(error.localizedDescription) appState=\(appState.rawValue)"
                        print("[WIFI] connectToWifi failed: \(diagnostics)")
                        result(
                            FlutterError(
                                code: "FAILED",
                                message: error.localizedDescription,
                                details: diagnostics))
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

    private func triggerLocalNetworkPrompt() {
        guard localNetworkPromptBrowser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: "_http._tcp", domain: nil),
            using: parameters
        )
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                DispatchQueue.main.async {
                    self?.localNetworkPromptBrowser?.cancel()
                    self?.localNetworkPromptBrowser = nil
                }
            default:
                break
            }
        }
        localNetworkPromptBrowser = browser
        browser.start(queue: .main)
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

// Bridges the Rust camera-pairing sockets through Network.framework.
//
// expose a loopback proxy: Rust connects to 127.0.0.1:12348 (loopback is never gated), and this class forwards the bytes to the camera over a Wi-Fi-pinned NWConnection. 
final class CameraProxy {
    static let shared = CameraProxy()

    private let channelName = "secluso.com/camera_proxy"
    // qualify it to resolve the ambiguity.
    private let cameraHost: Network.NWEndpoint.Host = "10.42.0.1"
    private let cameraPort: Network.NWEndpoint.Port = 12348
    private let loopbackPort: Network.NWEndpoint.Port = 12348
    private let queue = DispatchQueue(label: "com.secluso.cameraproxy")

    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: ProxySession] = [:]
    private var channel: FlutterMethodChannel?

    private init() {}

    func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        self.channel = channel
    }

    // Mirror native diagnostics into the Flutter in-app log stream
    fileprivate func log(_ message: String) {
        let line = "[CameraProxy] \(message)"
        print(line)
        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod("nativeLog", arguments: line)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "probe":
            probeCamera(result: result)
        case "startProxy":
            // hop onto it so the method-channel (main) thread never races the Network.framework callbacks.
            queue.async { [weak self] in self?.startProxy(result: result) }
        case "stopProxy":
            queue.async { [weak self] in
                self?.stopProxy()
                DispatchQueue.main.async { result(nil) }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // forces the camera connection onto the Wi-Fi interface so iOS scoped routing can't send it out cellular.
    private func cameraParameters() -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 5
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.requiredInterfaceType = .wifi
        params.prohibitedInterfaceTypes = [.cellular]
        return params
    }

    private func probeCamera(result: @escaping FlutterResult) {
        let conn = NWConnection(host: cameraHost, port: cameraPort, using: cameraParameters())
        var settled = false
        let settle: (Bool, String) -> Void = { reachable, reason in
            DispatchQueue.main.async {
                if settled { return }
                settled = true
                conn.cancel()
                self.log("probe result reachable=\(reachable) (\(reason))")
                // Return the detail too so the Dart side can log it into the in-app log stream 
                result(["reachable": reachable, "detail": reason])
            }
        }
        conn.stateUpdateHandler = { (state: NWConnection.State) in
            switch state {
            case .ready:
                let ifaces = conn.currentPath?.availableInterfaces
                    .map { "\($0.type)" }.joined(separator: ",") ?? "?"
                self.log("probe ready (interfaces=\(ifaces))")
                settle(true, "ready")
            case .preparing:
                self.log("probe preparing")
            case .waiting(let error):
                // A transient .waiting can still recover to .ready
                self.log("probe waiting: \(error)")
            case .failed(let error):
                self.log("probe failed: \(error)")
                settle(false, "failed: \(error)")
            case .cancelled:
                settle(false, "cancelled")
            default:
                break
            }
        }
        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3) {
            settle(false, "timeout")
        }
    }

    // Replies on the main thread.
    private func startProxy(result: @escaping FlutterResult) {
        let reply: (Any?) -> Void = { value in
            DispatchQueue.main.async { result(value) }
        }
        if listener != nil {
            reply(NSNumber(value: loopbackPort.rawValue))
            return
        }
        do {
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback
            params.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: params, on: loopbackPort)
            newListener.newConnectionHandler = { [weak self] inbound in
                self?.handleInbound(inbound)
            }
            newListener.stateUpdateHandler = { [weak self] (state: NWListener.State) in
                switch state {
                case .failed(let error):
                    self?.log("listener failed: \(error)")
                    self?.listener = nil
                case .ready:
                    self?.log("listener ready on 127.0.0.1")
                default:
                    break
                }
            }
            newListener.start(queue: queue)
            listener = newListener
            reply(NSNumber(value: loopbackPort.rawValue))
        } catch {
            log("startProxy failed: \(error)")
            reply(FlutterError(code: "PROXY_START_FAILED", message: "\(error)", details: nil))
        }
    }

    private func stopProxy() {
        listener?.cancel()
        listener = nil
        for session in sessions.values {
            session.close()
        }
        sessions.removeAll()
    }

    // Runs on queue
    private func handleInbound(_ inbound: NWConnection) {
        log("proxy: inbound loopback connection, dialing camera")
        let session = ProxySession(
            inbound: inbound,
            outbound: NWConnection(host: cameraHost, port: cameraPort, using: cameraParameters()),
            queue: queue,
            log: { [weak self] message in self?.log(message) }
        )
        let id = ObjectIdentifier(session)
        sessions[id] = session
        session.onClose = { [weak self] in
            self?.sessions[id] = nil
        }
        session.start()
    }
}

// loopback connection
private final class ProxySession {
    private let inbound: NWConnection
    private let outbound: NWConnection
    private let queue: DispatchQueue
    private let log: (String) -> Void
    private var closed = false
    var onClose: (() -> Void)?

    init(
        inbound: NWConnection,
        outbound: NWConnection,
        queue: DispatchQueue,
        log: @escaping (String) -> Void
    ) {
        self.inbound = inbound
        self.outbound = outbound
        self.queue = queue
        self.log = log
    }

    func start() {
        outbound.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.log("proxy: camera connection ready, forwarding bytes")
                self.pump(from: self.inbound, to: self.outbound)
                self.pump(from: self.outbound, to: self.inbound)
            case .waiting(let error):
                self.log("proxy: camera connection waiting: \(error)")
                self.close()
            case .failed(let error):
                self.log("proxy: camera connection failed: \(error)")
                self.close()
            case .cancelled:
                self.close()
            default:
                break
            }
        }
        inbound.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
            switch state {
            case .failed, .cancelled:
                self?.close()
            default:
                break
            }
        }
        inbound.start(queue: queue)
        outbound.start(queue: queue)
    }

    private func pump(from src: NWConnection, to dst: NWConnection) {
        src.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                dst.send(
                    content: data,
                    completion: .contentProcessed { sendError in
                        if sendError != nil {
                            self.close()
                        } else {
                            self.pump(from: src, to: dst)
                        }
                    })
            } else if isComplete || error != nil {
                self.close()
            } else {
                self.pump(from: src, to: dst)
            }
        }
    }

    func close() {
        queue.async { [weak self] in
            guard let self = self, !self.closed else { return }
            self.closed = true
            self.inbound.cancel()
            self.outbound.cancel()
            self.log("proxy: session closed")
            self.onClose?()
        }
    }
}
