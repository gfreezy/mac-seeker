import AppKit
import Observation
import ServiceManagement
import SwiftUI
import shared

let launchDaemonIdentifier = "io.allsunday.seeker.launchDaemon"
let launchedDaemonServiceName = "\(launchDaemonIdentifier).plist"

extension SMAppService.Status: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .enabled:
            return "Enabled"
        case .notFound:
            return "Not Found"
        case .notRegistered:
            return "Not Registered"
        case .requiresApproval:
            return "Requires Approval"
        @unknown default:
            return "Unknown"
        }
    }
}

@MainActor
@Observable
class GlobalStateVm {
    var isStarted: Bool { seekerStatus.isRunning }
    var autoStartOnLogin: SMAppService.Status = SMAppService.mainApp.status
    var daemonStatus: SMAppService.Status = GlobalStateVm.getDaemonStatus()
    var seekerStatus: SeekerStatusInfo = .unknown {
        didSet {
            // Show alert when status changes to error (only once per start)
            if seekerStatus.status == .error, let errorMsg = seekerStatus.errorMessage, !hasShownErrorAlert {
                hasShownErrorAlert = true
                showErrorAlert(message: errorMsg)
            }
        }
    }
    var lastError: String?
    @ObservationIgnored var connectionToService: NSXPCConnection?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var hasShownErrorAlert: Bool = false

    // Configuration service for editing config
    var configService: ConfigurationService

    // Paths for binary, config and log files
    let binaryPath: String
    let configPath: String
    let logPath: String

    init() {
        // Binary path - from main app bundle
        if let appPath = Bundle.main.bundlePath
            .components(separatedBy: "/Contents/MacOS").first
        {
            self.binaryPath = "\(appPath)/Contents/MacOS/seeker-proxy"
        } else {
            self.binaryPath = Bundle.main.bundlePath + "/Contents/MacOS/seeker-proxy"
        }

        // Use system Application Support directory for logs and config
        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let appSupportDir = supportDir.appendingPathComponent("seeker")
        do {
            try FileManager.default.createDirectory(
                at: appSupportDir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create seeker directory: \(error)")
        }
        self.configPath = appSupportDir.appendingPathComponent("config.yml").path
        self.logPath = appSupportDir.appendingPathComponent("seeker.log").path

        print("[MainApp] configPath: \(self.configPath)")
        // Initialize configuration service
        self.configService = ConfigurationService(configPath: self.configPath)

        // Establish connection at init to keep it alive
        connectToDaemon()
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateSeekerStatus()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func start() async throws {
        do {
            print("[MainApp] start() called")
            lastError = nil
            hasShownErrorAlert = false

            // Check daemon status and auto-register if needed
            let status = Self.getDaemonStatus()
            if status == .notRegistered || status == .notFound {
                print("[MainApp] Daemon not registered, registering automatically...")
                try registerDaemon()
            }

            print("[MainApp] Creating config")
            let config = SeekerConfig(
                binaryPath: binaryPath,
                configPath: configPath,
                logPath: logPath
            )
            print("[MainApp] Calling daemon to start seeker")
            try await callToDaemon { proxy in
                try await proxy.startSeeker(config: config)
            }
            await updateSeekerStatus()
        } catch {
            print("[MainApp] start() exception: \(error)")
            lastError = error.localizedDescription
            seekerStatus = .error(error.localizedDescription)
            throw error
        }

        // Start polling for seeker status
        startPolling()
    }

    func stop() async {
        do {
            print("[MainApp] stop() called")
            lastError = nil
            let success = try await callToDaemon { proxy in
                print("[MainApp] inside callToDaemon closure, about to call proxy.stopSeeker")
                let r = await proxy.stopSeeker()
                print("[MainApp] proxy.stopSeeker returned: \(r)")
                return r
            }
            print("[MainApp] daemon call completed, success: \(success)")
            if success {
                print("[MainApp] stop() completed successfully")
            } else {
                lastError = "Failed to stop seeker"
                print("[MainApp] stop() failed")
            }
            await updateSeekerStatus()
        } catch {
            print("[MainApp] stop() exception: \(error)")
            lastError = error.localizedDescription
            seekerStatus = .error(error.localizedDescription)
        }

        // Stop polling for seeker status
        stopPolling()
    }

    func toggle() {
        Task {
            if isStarted {
                await stop()
            } else {
                try await start()
            }
        }
    }

    func updateSeekerStatus() async {
        do {
            let status = try await callToDaemon { proxy in
                await proxy.getSeekerStatus()
            }
            seekerStatus = status
        } catch {
            print("Failed to get seeker status: \(error)")
            seekerStatus = .error(error.localizedDescription)
        }
    }

    nonisolated private static func getDaemonStatus() -> SMAppService.Status {
        print("[MainApp] getDaemonStatus() called, checking thread...")

        // CRITICAL: SMAppService MUST be called on the main thread
        // This prevents dispatch queue assertion crashes
        var status: SMAppService.Status!
        if Thread.isMainThread {
            print("[MainApp] Already on main thread, getting status...")
            status = SMAppService.daemon(plistName: launchedDaemonServiceName).status
        } else {
            print("[MainApp] Not on main thread, dispatching to main thread...")
            DispatchQueue.main.sync {
                print("[MainApp] Now on main thread, getting status...")
                status = SMAppService.daemon(plistName: launchedDaemonServiceName).status
            }
        }

        print("[MainApp] Daemon status: \(status!)")
        return status
    }

    func registerAutoStart() throws {
        try SMAppService.mainApp.register()
        autoStartOnLogin = SMAppService.mainApp.status
    }

    func unregisterAutoStart() async throws {
        try await SMAppService.mainApp.unregister()
        autoStartOnLogin = SMAppService.mainApp.status
    }

    func registerDaemon() throws {
        print("[MainApp] registerDaemon() called")

        // Close any existing connection before registering
        closeConnectionToDaemon()

        try SMAppService.daemon(plistName: launchedDaemonServiceName).register()
        daemonStatus = statusForDaemon()

        // Wait a bit for daemon to start
        Thread.sleep(forTimeInterval: 0.5)

        // Establish new connection to the newly registered daemon
        connectToDaemon()

        print("[MainApp] registerDaemon() completed, status: \(daemonStatus)")
    }

    func unregisterDaemon() async throws {
        print("[MainApp] unregisterDaemon() called")

        // Stop seeker if running
        if isStarted {
            print("[MainApp] Stopping seeker before unregistering daemon...")
            await stop()
            // Wait for stop to complete
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
        }

        // Close XPC connection before unregistering
        closeConnectionToDaemon()

        try await SMAppService.daemon(plistName: launchedDaemonServiceName).unregister()
        daemonStatus = statusForDaemon()

        print("[MainApp] unregisterDaemon() completed, status: \(daemonStatus)")
    }

    func statusForDaemon() -> SMAppService.Status {
        Self.getDaemonStatus()
    }

    private func connectToDaemon() {
        print("[MainApp] connectToDaemon() called")

        // Clean up any existing connection
        if connectionToService != nil {
            closeConnectionToDaemon()
        }

        let connection = NSXPCConnection(
            machServiceName: launchDaemonIdentifier, options: .privileged)
        let interface = NSXPCInterface(with: LaunchDaemonProtocol.self)
        connection.remoteObjectInterface = interface

        // Set up error handlers with weak self to avoid retain cycles
        connection.invalidationHandler = { [weak self] in
            print("[MainApp] XPC connection invalidated")
            Task { @MainActor [weak self] in
                self?.connectionToService = nil
            }
        }

        connection.interruptionHandler = {
            print("[MainApp] XPC connection interrupted - will reconnect on next call")
            // Don't clear the connection on interruption - XPC may recover automatically
        }
        connection.exportedInterface = NSXPCInterface(with: LaunchDaemonProtocol.self)
        // Resume the connection - this is critical!
        connection.resume()

        // Store the connection as a strong reference
        self.connectionToService = connection
        print("[MainApp] XPC connection established and stored")
    }

    func callToDaemon<T: Sendable>(method: (any LaunchDaemonProtocol) async throws -> T)
        async throws -> T
    {
        print("[MainApp] callToDaemon() entered")
        // Ensure we have a valid connection
        if connectionToService == nil {
            print("[MainApp] No connection exists, establishing new connection...")
            connectToDaemon()
        }

        guard let connection = connectionToService else {
            print("[MainApp] Failed to establish XPC connection")
            throw AnyError("Failed to establish XPC connection to daemon")
        }

        print("[MainApp] Checking daemon status...")
        // Query daemon status synchronously; ServiceManagement expects main-thread usage.
        let daemonStatus = Self.getDaemonStatus()
        print("[MainApp] Daemon status: \(daemonStatus)")

        if daemonStatus == .notRegistered || daemonStatus == .notFound {
            throw AnyError(
                "Daemon is not registered. Please register it first in Edit Config window.")
        }

        if daemonStatus == .requiresApproval {
            throw AnyError(
                "Daemon requires approval. Please check System Settings → General → Login Items.")
        }

        print("[MainApp] Getting remote proxy...")
        // Use remoteObjectProxyWithErrorHandler for better error logging
        let proxy =
            connection.remoteObjectProxyWithErrorHandler { error in
                print("[MainApp] XPC proxy error handler called: \(error)")
            } as? LaunchDaemonProtocol

        guard let proxy else {
            print("[MainApp] Failed to get daemon proxy")
            throw AnyError("Failed to get daemon proxy - daemon may not be running")
        }

        print("[MainApp] Executing XPC method...")
        // Execute the method with the proxy
        let result = try await method(proxy)
        print("[MainApp] XPC method completed successfully")
        return result
    }

    func closeConnectionToDaemon() {
        print("[MainApp] closeConnectionToDaemon() called")
        connectionToService?.invalidate()
        connectionToService = nil
    }

    func openLog() {
        print("[MainApp] openLog() called")

        // Create log file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        // Create a temporary shell script that runs tail -f
        let scriptContent = "#!/bin/bash\ntail -f '\(logPath)'\n"
        let scriptPath = NSTemporaryDirectory() + "seeker-tail-log.command"

        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            // Make it executable
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

            // Open the .command file which will launch Terminal and run the script
            NSWorkspace.shared.open(URL(fileURLWithPath: scriptPath))
        } catch {
            print("[MainApp] Failed to create/open log script: \(error)")
        }
    }

    func openConfig() {
        print("[MainApp] openConfig() called")
        let configURL = URL(fileURLWithPath: configPath)

        if !FileManager.default.fileExists(atPath: configPath) {
            let template = """
                # Seeker Configuration
                # Add your seeker settings below.
                """

            do {
                try template.write(to: configURL, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to create config file"
                alert.informativeText =
                    "Path: \(configPath)\nError: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.runModal()
                return
            }
        }

        NSWorkspace.shared.open(configURL)
    }

    func openFolder() {
        print("[MainApp] openFolder() called")
        // Open the Application Support/seeker directory
        let folderPath = (configPath as NSString).deletingLastPathComponent
        let folderURL = URL(fileURLWithPath: folderPath)

        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: folderPath) {
            do {
                try FileManager.default.createDirectory(
                    at: folderURL, withIntermediateDirectories: true)
            } catch {
                print("[MainApp] Failed to create directory: \(error)")
                let alert = NSAlert()
                alert.messageText = "Failed to create folder"
                alert.informativeText =
                    "Path: \(folderPath)\nError: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.runModal()
                return
            }
        }

        NSWorkspace.shared.open(folderURL)
    }

    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Seeker Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
