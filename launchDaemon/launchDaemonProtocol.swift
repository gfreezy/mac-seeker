//
//  launchedDaemonProtocol.swift
//  launchedDaemon
//
//  Created by feichao on 2025/1/7.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc public protocol LaunchDaemonProtocol: Sendable {
    /// Start the Rust seeker process
    func startSeeker() async -> Bool

    /// Stop the Rust seeker process
    func stopSeeker() async -> Bool

    /// Check if the Rust seeker process is running
    func isSeekerRunning() async -> Bool

    /// Get the status of the seeker process
    func getSeekerStatus() async -> String

    /// Get the path to the seeker log file
    func getSeekerLogPath() async -> String
}
