import AppKit
import Observation
import ServiceManagement
import shared

#if DEBUG
let launchDaemonIdentifier = "io.allsunday.seeker.debug.launchDaemon"
#else
let launchDaemonIdentifier = "io.allsunday.seeker.launchDaemon"
#endif
let launchedDaemonServiceName = "\(launchDaemonIdentifier).plist"

enum ProxyGroupRestartError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return "The proxy selection was saved, but Seeker could not be restarted: \(message)"
        }
    }
}

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
            // Show alert when status changes to error (only once per start, not during stop)
            if seekerStatus.status == .error, let errorMsg = seekerStatus.errorMessage, !hasShownErrorAlert, !isStopping {
                hasShownErrorAlert = true
                showErrorAlert(message: errorMsg)
            }
        }
    }
    var lastError: String?
    var serverStats: [String: ApiServerStats] = [:]
    var switchingProxyGroupName: String?
    var isSwitchingProxy: Bool { switchingProxyGroupName != nil }
    @ObservationIgnored var connectionToService: NSXPCConnection?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var apiStatsTask: Task<Void, Never>?
    @ObservationIgnored private var hasShownErrorAlert: Bool = false
    @ObservationIgnored private var isStopping: Bool = false

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
        do {
            try self.configService.load()
        } catch {
            self.lastError = error.localizedDescription
        }

        // Establish connection at init to keep it alive
        connectToDaemon()

        Task { @MainActor [weak self] in
            await self?.initializeRuntimeState()
        }
    }

    private func initializeRuntimeState() async {
        let shouldResumeAfterUpdate = UpdateResumeState.consumeIfMatching()
        guard daemonStatus == .enabled else { return }
        await updateSeekerStatus()

        if shouldResumeAfterUpdate, !isStarted {
            do {
                try await start()
            } catch {
                lastError = error.localizedDescription
            }
            return
        }

        startPolling()
        if isStarted {
            startApiStatsPolling()
        }
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

    private func startApiStatsPolling() {
        apiStatsTask?.cancel()
        // configService.configuration may not be loaded yet (loads when Settings window opens),
        // so read apiAddr directly from the config file as a fallback.
        var apiAddr = configService.configuration.apiAddr
        if apiAddr.isEmpty {
            apiAddr = Self.readApiAddrFromConfig(path: configPath) ?? ""
        }
        guard !apiAddr.isEmpty else { return }
        apiStatsTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchApiStats(apiAddr: apiAddr)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private nonisolated static func readApiAddrFromConfig(path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return nil }
        // Simple line-based parse for api_addr: "value" or api_addr: value
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("api_addr:") {
                var value = String(trimmed.dropFirst("api_addr:".count))
                    .trimmingCharacters(in: .whitespaces)
                // Remove surrounding quotes
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private func stopApiStatsPolling() {
        apiStatsTask?.cancel()
        apiStatsTask = nil
        serverStats = [:]
    }

    private func fetchApiStats(apiAddr: String) async {
        guard let url = URL(string: "http://\(apiAddr)/api/stats") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ApiStatsResponse.self, from: data)
            var stats: [String: ApiServerStats] = [:]
            for (_, group) in response.groups {
                for server in group.servers {
                    stats[server.name] = server
                }
            }
            serverStats = stats
        } catch {
            // Silently ignore fetch errors - API may not be ready yet
        }
    }

    func start() async throws {
        do {
            if daemonStatus != .enabled {
                try registerDaemon()
            }
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
        startApiStatsPolling()
    }

    func stop() async {
        isStopping = true
        defer { isStopping = false }

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
        stopApiStatsPolling()
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

    func selectProxy(groupName: String, serverName: String) async {
        await applyProxyGroupChange(groupName: groupName) {
            try configService.selectProxy(groupName: groupName, serverName: serverName)
        }
    }

    func useAutomaticProxySelection(groupName: String) async {
        await applyProxyGroupChange(groupName: groupName) {
            try configService.useAutomaticProxySelection(groupName: groupName)
        }
    }

    private func applyProxyGroupChange(
        groupName: String,
        change: () throws -> Void
    ) async {
        guard !isSwitchingProxy else { return }
        switchingProxyGroupName = groupName
        defer { switchingProxyGroupName = nil }

        if seekerStatus.status == .unknown, daemonStatus == .enabled {
            await updateSeekerStatus()
        }
        let wasRunning = isStarted
        do {
            try change()
            if wasRunning {
                await stop()
                if let stopError = lastError {
                    throw ProxyGroupRestartError.failed(stopError)
                }
                try await Task.sleep(for: .milliseconds(500))
                do {
                    try await start()
                } catch {
                    throw ProxyGroupRestartError.failed(error.localizedDescription)
                }
            }
        } catch {
            lastError = error.localizedDescription
            showErrorAlert(message: error.localizedDescription)
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

    /// NSXPC invokes its callbacks on private dispatch queues. Build these handlers
    /// outside the main-actor context so Swift does not attach a main-executor
    /// precondition to the callback itself.
    nonisolated private static func makeConnectionInvalidationHandler(
        for state: GlobalStateVm,
        connection: NSXPCConnection
    ) -> @Sendable () -> Void {
        let connectionID = ObjectIdentifier(connection)
        return { [weak state] in
            print("[MainApp] XPC connection invalidated")
            Task { @MainActor [weak state] in
                guard let state, let currentConnection = state.connectionToService,
                      ObjectIdentifier(currentConnection) == connectionID else { return }
                state.connectionToService = nil
            }
        }
    }

    nonisolated private static func handleXPCInterruption() {
        print("[MainApp] XPC connection interrupted - will reconnect on next call")
    }

    nonisolated private static func handleXPCProxyError(_ error: Error) {
        print("[MainApp] XPC proxy error handler called: \(error)")
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

        connection.invalidationHandler = Self.makeConnectionInvalidationHandler(
            for: self,
            connection: connection
        )
        connection.interruptionHandler = Self.handleXPCInterruption
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
        let proxy = connection.remoteObjectProxyWithErrorHandler(Self.handleXPCProxyError)
            as? LaunchDaemonProtocol

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
