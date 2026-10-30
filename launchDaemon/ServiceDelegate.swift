import Foundation
import shared

final class ServiceDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let daemon: LaunchDaemon
    private let connectionQueue = DispatchQueue(label: "io.allsunday.seeker.daemon.connections")
    private let shutdownDelay: TimeInterval
    private let exitHandler: @Sendable (Int32) -> Void
    private var activeConnections = 0
    private var pendingShutdown: UUID?
    private var shuttingDown = false

    init(
        daemon: LaunchDaemon = LaunchDaemon(), shutdownDelay: TimeInterval = 2,
        exitHandler: @Sendable @escaping (Int32) -> Void = { exit($0) }
    ) {
        self.daemon = daemon
        self.shutdownDelay = shutdownDelay
        self.exitHandler = exitHandler
        super.init()
    }

    func listener(
        _ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        guard connectionOpened() else { return false }
        newConnection.exportedInterface = NSXPCInterface(with: LaunchDaemonProtocol.self)
        newConnection.exportedObject = daemon
        newConnection.invalidationHandler = { [weak self] in self?.connectionClosed() }
        newConnection.resume()
        return true
    }

    func connectionOpened() -> Bool {
        connectionQueue.sync {
            guard !shuttingDown else { return false }
            activeConnections += 1
            pendingShutdown = nil
            print("[Daemon] Connection accepted. Active: \(activeConnections)")
            return true
        }
    }

    func connectionClosed() {
        connectionQueue.async {
            self.activeConnections = max(self.activeConnections - 1, 0)
            print("[Daemon] Connection closed. Active: \(self.activeConnections)")
            guard self.activeConnections == 0, !self.shuttingDown else { return }
            let token = UUID()
            self.pendingShutdown = token
            print("[Daemon] No active connections. Shutting down in \(self.shutdownDelay)s...")
            self.connectionQueue.asyncAfter(deadline: .now() + self.shutdownDelay) {
                guard self.pendingShutdown == token, self.activeConnections == 0 else { return }
                self.beginShutdown()
            }
        }
    }

    func requestShutdown() {
        connectionQueue.async { self.beginShutdown() }
    }

    private func beginShutdown() {
        guard !shuttingDown else { return }
        shuttingDown = true
        pendingShutdown = nil
        daemon.shutdown { [self] stopped in
            guard stopped else {
                print("[Daemon] Could not stop seeker; keeping the daemon alive to retain ownership")
                connectionQueue.async { self.shuttingDown = false }
                return
            }
            print("[Daemon] Shutdown complete. Exiting.")
            exitHandler(0)
        }
    }
}
