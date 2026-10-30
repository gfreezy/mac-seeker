//
//  main.swift
//  launchedDaemon
//
//  Created by feichao on 2025/1/7.
//

import Foundation
import Darwin

// Unbuffered output for debugging
setbuf(stdout, nil)
setbuf(stderr, nil)

#if DEBUG
let launchDaemonIdentifier = "io.allsunday.seeker.debug.launchDaemon"
#else
let launchDaemonIdentifier = "io.allsunday.seeker.launchDaemon"
#endif
print("[Daemon] Starting service: \(launchDaemonIdentifier)")

let delegate = ServiceDelegate()
let listener = NSXPCListener(machServiceName: launchDaemonIdentifier)
listener.delegate = delegate

// Disable the default action so Dispatch can deliver the signals on its queue.
// The Rust child installs its own SIGTERM/SIGINT handlers during startup.
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let terminationSources = [SIGTERM, SIGINT].map { signalNumber in
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        print("[Daemon] Received signal \(signalNumber). Shutting down.")
        delegate.requestShutdown()
    }
    source.resume()
    return source
}
listener.resume()

print("[Daemon] Ready to accept connections")

withExtendedLifetime((delegate, listener, terminationSources)) {
    RunLoop.main.run()
}
