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
    @ObservationIgnored var connectionToService: NSXPCConnection?
    @ObservationIgnored var launchDaemonProxy: (any LaunchDaemonProtocol)?

    init() {
        Task {
            await updateSeekerStatus()
        }
    }

    func start() {
        Task {
            do {
                let success = try await callToDaemon { proxy in
                    await proxy.startSeeker()
                }
                if success {
                    isStarted = true
                    await updateSeekerStatus()
                }
            } catch {
                print("Failed to start seeker: \(error)")
            }
        }
    }

    func stop() {
        Task {
            do {
                let success = try await callToDaemon { proxy in
                    await proxy.stopSeeker()
                }
                if success {
                    isStarted = false
                    await updateSeekerStatus()
                }
            } catch {
                print("Failed to stop seeker: \(error)")
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

    private static func getDaemonStatus() -> SMAppService.Status {
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
        let connectionToService = NSXPCConnection(
            machServiceName: launchDaemonIdentifier, options: .privileged)
        connectionToService.remoteObjectInterface = NSXPCInterface(
            with: LaunchDaemonProtocol.self)

        // Set up error handlers
        connectionToService.invalidationHandler = {
            print("XPC connection invalidated")
        }

        connectionToService.interruptionHandler = {
            print("XPC connection interrupted")
        }

        connectionToService.resume()
        self.connectionToService = connectionToService
        print("XPC connection established")
    }

    func callToDaemon<T: Sendable>(method: (any LaunchDaemonProtocol) async throws -> T)
        async throws -> T
    {
        if connectionToService == nil {
            connectToDaemon()
        }
        let proxy =
            connectionToService?.remoteObjectProxy as? LaunchDaemonProtocol
        
        launchDaemonProxy = proxy

        if let proxy {
            return try await method(proxy)
        }
        throw AnyError("no valid connection")
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
