import Observation
import ServiceManagement
import SwiftUI
import launchDaemon

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
    var isStarted: Bool = false
    var autoStartOnLogin: SMAppService.Status = SMAppService.mainApp.status
    var daemonStatus: SMAppService.Status = GlobalStateVm.getDaemonStatus()
    var seekerStatus: String = "Unknown"
    var lastError: String?
    @ObservationIgnored var connectionToService: NSXPCConnection?

    init() {
        // Establish connection at init to keep it alive
        connectToDaemon()

        Task {
            await updateSeekerStatus()
        }
    }

    func start() {
        Task {
            do {
                lastError = nil
                let success = try await callToDaemon { proxy in
                    await proxy.startSeeker()
                }
                if success {
                    isStarted = true
                    await updateSeekerStatus()
                } else {
                    lastError = "Failed to start seeker"
                }
            } catch {
                print("Failed to start seeker: \(error)")
                lastError = error.localizedDescription
                seekerStatus = "Error: \(error.localizedDescription)"
            }
        }
    }

    func stop() {
        Task {
            do {
                lastError = nil
                let success = try await callToDaemon { proxy in
                    await proxy.stopSeeker()
                }
                if success {
                    isStarted = false
                    await updateSeekerStatus()
                } else {
                    lastError = "Failed to stop seeker"
                }
            } catch {
                print("Failed to stop seeker: \(error)")
                lastError = error.localizedDescription
                seekerStatus = "Error: \(error.localizedDescription)"
            }
        }
    }

    func toggle() {
        if isStarted {
            stop()
        } else {
            start()
        }
    }

    func updateSeekerStatus() async {
        do {
            let running = try await callToDaemon { proxy in
                await proxy.isSeekerRunning()
            }
            isStarted = running

            let status = try await callToDaemon { proxy in
                await proxy.getSeekerStatus()
            }
            seekerStatus = status
        } catch {
            print("Failed to get seeker status: \(error)")
            seekerStatus = "Error: \(error.localizedDescription)"
        }
    }

    nonisolated private static func getDaemonStatus() -> SMAppService.Status {
        return SMAppService.daemon(plistName: launchedDaemonServiceName).status
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
        try SMAppService.daemon(plistName: launchedDaemonServiceName).register()
        daemonStatus = statusForDaemon()
    }

    func unregisterDaemon() async throws {
        try await SMAppService.daemon(plistName: launchedDaemonServiceName).unregister()
        daemonStatus = statusForDaemon()
    }

    func statusForDaemon() -> SMAppService.Status {
        Self.getDaemonStatus()
    }

    private func connectToDaemon() {
        print("Establishing XPC connection to daemon...")

        // Clean up any existing connection
        if let existing = connectionToService {
            existing.invalidate()
            connectionToService = nil
        }

        let connection = NSXPCConnection(
            machServiceName: launchDaemonIdentifier, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(
            with: LaunchDaemonProtocol.self)

        // Set up error handlers with weak self to avoid retain cycles
        connection.invalidationHandler = { [weak self] in
            print("XPC connection invalidated")
            Task { @MainActor [weak self] in
                self?.connectionToService = nil
            }
        }

        connection.interruptionHandler = {
            print("XPC connection interrupted - will reconnect on next call")
            // Don't clear the connection on interruption - XPC may recover automatically
        }

        // Resume the connection - this is critical!
        connection.resume()

        // Store the connection as a strong reference
        self.connectionToService = connection
        print("XPC connection established and stored")
    }

    func callToDaemon<T: Sendable>(method: (any LaunchDaemonProtocol) async throws -> T)
        async throws -> T
    {
        // Ensure we have a valid connection
        if connectionToService == nil {
            print("No connection exists, establishing new connection...")
            connectToDaemon()
        }

        guard let connection = connectionToService else {
            throw AnyError("Failed to establish XPC connection to daemon")
        }

        // Check daemon status on background thread to avoid UI blocking
        let daemonStatus = await Task.detached {
            Self.getDaemonStatus()
        }.value
        print("Daemon status: \(daemonStatus)")

        if daemonStatus == .notRegistered || daemonStatus == .notFound {
            throw AnyError("Daemon is not registered. Please register it first in Edit Config window.")
        }

        if daemonStatus == .requiresApproval {
            throw AnyError("Daemon requires approval. Please check System Settings → General → Login Items.")
        }

        // Use remoteObjectProxyWithErrorHandler for better error handling
        var errorOccurred: Error?
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            print("XPC proxy error: \(error)")
            errorOccurred = error
        } as? LaunchDaemonProtocol

        // Check if error handler was called during proxy creation
        if let error = errorOccurred {
            throw AnyError("XPC connection error: \(error.localizedDescription)")
        }

        guard let proxy else {
            throw AnyError("Failed to get daemon proxy - daemon may not be running")
        }

        // Execute the method with the proxy
        return try await method(proxy)
    }

    func closeConnectionToDaemon() {
        connectionToService?.invalidate()
        connectionToService = nil
    }

    func openLog() {
        Task {
            do {
                let logPath = try await callToDaemon { proxy in
                    await proxy.getSeekerLogPath()
                }

                // Open the log file in Console.app or default text editor
                let logURL = URL(fileURLWithPath: logPath)

                // Check if log file exists
                if FileManager.default.fileExists(atPath: logPath) {
                    NSWorkspace.shared.open(logURL)
                } else {
                    print("Log file does not exist yet: \(logPath)")
                    // Create an alert to inform the user
                    let alert = NSAlert()
                    alert.messageText = "Log file not found"
                    alert.informativeText =
                        "The log file will be created when you start Seeker for the first time.\nPath: \(logPath)"
                    alert.alertStyle = .informational
                    alert.runModal()
                }
            } catch {
                print("Failed to open log: \(error)")
            }
        }
    }
}
