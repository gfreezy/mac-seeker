//
//  main.swift
//  launchedDaemon
//
//  Created by feichao on 2025/1/7.
//

import Foundation
import shared

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let daemon = LaunchDaemon()
    private let connectionQueue = DispatchQueue(label: "io.allsunday.seeker.daemon.connections")
    private var activeConnections = 0
    private var pendingShutdownWorkItem: DispatchWorkItem?
    private let shutdownDelay: TimeInterval = 2

    func listener(
        _ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        let interface = NSXPCInterface(with: LaunchDaemonProtocol.self)
        newConnection.exportedInterface = interface
        newConnection.exportedObject = daemon

        connectionQueue.sync {
            activeConnections += 1
            pendingShutdownWorkItem?.cancel()
            pendingShutdownWorkItem = nil
            print("[Daemon] Connection accepted. Active: \(activeConnections)")
        }

        newConnection.invalidationHandler = { [weak self] in
            self?.connectionClosed()
        }

        newConnection.resume()
        return true
    }

    private func connectionClosed() {
        var shutdownWorkItem: DispatchWorkItem?

        connectionQueue.sync {
            activeConnections = max(activeConnections - 1, 0)
            print("[Daemon] Connection closed. Active: \(activeConnections)")

            guard activeConnections == 0 else { return }

            let workItem = DispatchWorkItem { [weak self] in
                self?.performShutdown()
            }
            pendingShutdownWorkItem = workItem
            shutdownWorkItem = workItem
        }

        if let workItem = shutdownWorkItem {
            print("[Daemon] No active connections. Shutting down in \(shutdownDelay)s...")
            DispatchQueue.global().asyncAfter(deadline: .now() + shutdownDelay, execute: workItem)
        }
    }

    private func performShutdown() {
        connectionQueue.sync {
            pendingShutdownWorkItem = nil
        }
        daemon.stopSeekerSync()
        print("[Daemon] Shutdown complete. Exiting.")
        exit(0)
    }
}

// Unbuffered output for debugging
setbuf(stdout, nil)
setbuf(stderr, nil)

let launchDaemonIdentifier = "io.allsunday.seeker.launchDaemon"
print("[Daemon] Starting service: \(launchDaemonIdentifier)")

let delegate = ServiceDelegate()
let listener = NSXPCListener(machServiceName: launchDaemonIdentifier)
listener.delegate = delegate
listener.resume()

print("[Daemon] Ready to accept connections")

RunLoop.main.run()
