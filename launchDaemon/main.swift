//
//  main.swift
//  launchedDaemon
//
//  Created by feichao on 2025/1/7.
//

import Foundation

class ServiceDelegate: NSObject, NSXPCListenerDelegate {

    /// This method is where the NSXPCListener configures, accepts, and resumes a new incoming NSXPCConnection.
    func listener(
        _ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {

        // Configure the connection.
        // First, set the interface that the exported object implements.
        newConnection.exportedInterface = NSXPCInterface(with: LaunchDaemonProtocol.self)

        // Next, set the object that the connection exports. All messages sent on the connection to this service will be sent to the exported object to handle. The connection retains the exported object.
        let exportedObject = LaunchDaemon()
        newConnection.exportedObject = exportedObject

        // Resuming the connection allows the system to deliver more incoming messages.
        newConnection.resume()

        // Returning true from this method tells the system that you have accepted this connection. If you want to reject the connection for some reason, call invalidate() on the connection and return false.
        return true
    }
}

// Force unbuffered output for debugging - must be first!
setbuf(stdout, nil)
setbuf(stderr, nil)

print("=== LaunchDaemon main.swift starting ===")
fflush(stdout)

// Create the delegate for the service.
let delegate = ServiceDelegate()

let launchDaemonIdentifier: String = "io.allsunday.seeker.launchDaemon"
print("Service identifier: \(launchDaemonIdentifier)")

// Set up the one NSXPCListener for this service. It will handle all incoming connections.
let listener = NSXPCListener(machServiceName: launchDaemonIdentifier)
listener.delegate = delegate

// Resuming the serviceListener starts this service. This method does not return.
print("Resuming listener...")
listener.resume()

print("Listener resumed and ready to accept connections")

RunLoop.main.run()
