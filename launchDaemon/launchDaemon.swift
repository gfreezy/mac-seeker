//
//  launchedDaemon.swift
//  launchedDaemon
//
//  Created by feichao on 2025/1/7.
//

import Foundation

/// This object implements the protocol which we have defined. It provides the actual behavior for the service. It is 'exported' by the service to make it available to the process hosting the service over an NSXPCConnection.
final class LaunchDaemon: NSObject, LaunchDaemonProtocol {
    private nonisolated(unsafe) var seekerProcess: Process?
    private let seekerBinaryPath: String
    private let configPath: String
    private let workingDirectory: String
    private let logFilePath: String
    private nonisolated(unsafe) var logFileHandle: FileHandle?

    override init() {
        // Get the path to the main app bundle from the daemon
        // The daemon is inside: seeker.app/Contents/Library/LaunchDaemons/io.allsunday.seeker.launchDaemon
        // The binary is inside: seeker.app/Contents/MacOS/seeker-proxy
        let mainBundlePath = Bundle.main.bundlePath
            .replacingOccurrences(of: "/Contents/Library/LaunchDaemons/io.allsunday.seeker.launchDaemon", with: "")

        self.seekerBinaryPath = "\(mainBundlePath)/Contents/MacOS/seeker-proxy"

        // Use system Application Support directory for logs and config
        // This is accessible to all users and doesn't require sandbox permissions
        let appSupportDir = "/Library/Application Support/seeker"
        try? FileManager.default.createDirectory(atPath: appSupportDir, withIntermediateDirectories: true)

        // Config and working directory
        self.configPath = "\(appSupportDir)/config.yml"
        self.workingDirectory = appSupportDir

        // Log file
        self.logFilePath = "\(appSupportDir)/seeker.log"

        super.init()

        print("=== LaunchDaemon initialized ===")
        print("Seeker binary path: \(seekerBinaryPath)")
        print("Config path: \(configPath)")
        print("Log file path: \(logFilePath)")
    }

    @objc func startSeeker() async -> Bool {
        print("LaunchDaemon: Starting seeker process...")

        if await isSeekerRunning() {
            print("LaunchDaemon: Seeker is already running")
            return true
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: seekerBinaryPath)
        process.arguments = ["-c", configPath]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        // Create log file
        FileManager.default.createFile(atPath: logFilePath, contents: nil)

        // Set log file permissions to be readable and writable by everyone (666)
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o666],
                ofItemAtPath: logFilePath
            )
            print("LaunchDaemon: Set log file permissions to 666 (rw-rw-rw-)")
            fflush(stdout)
        } catch {
            print("LaunchDaemon: Failed to set log file permissions: \(error)")
            fflush(stdout)
        }

        // Open log file for writing
        if let logHandle = FileHandle(forWritingAtPath: logFilePath) {
            logHandle.seekToEndOfFile()
            logFileHandle = logHandle

            // Write startup log
            let startupLog = "\n=== Seeker started at \(Date()) ===\n"
            if let data = startupLog.data(using: .utf8) {
                logHandle.write(data)
            }

            process.standardOutput = logHandle
            process.standardError = logHandle
        } else {
            // Fallback to pipes if log file can't be opened
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
        }

        // Handle process termination
        process.terminationHandler = { [weak self] process in
            let terminationLog = "LaunchDaemon: Seeker process terminated with status: \(process.terminationStatus) at \(Date())\n"
            print(terminationLog)

            // Write termination to log
            if let logHandle = self?.logFileHandle, let data = terminationLog.data(using: .utf8) {
                logHandle.write(data)
            }

            self?.seekerProcess = nil
        }

        do {
            try process.run()
            seekerProcess = process
            print("LaunchDaemon: Seeker process started successfully with PID: \(process.processIdentifier)")
            return true
        } catch {
            print("LaunchDaemon: Failed to start seeker process: \(error)")
            return false
        }
    }

    @objc func stopSeeker() async -> Bool {
        print("LaunchDaemon: Stopping seeker process...")

        guard let process = seekerProcess else {
            print("LaunchDaemon: No seeker process to stop")
            return true
        }

        if process.isRunning {
            process.terminate()
            // Wait a bit for graceful termination
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Force kill if still running
            if process.isRunning {
                print("LaunchDaemon: Force killing seeker process")
                process.interrupt()
            }

            seekerProcess = nil
            print("LaunchDaemon: Seeker process stopped")
            return true
        } else {
            seekerProcess = nil
            print("LaunchDaemon: Seeker process was not running")
            return true
        }
    }

    @objc func isSeekerRunning() async -> Bool {
        guard let process = seekerProcess else {
            return false
        }
        return process.isRunning
    }

    @objc func getSeekerStatus() async -> String {
        if await isSeekerRunning() {
            if let pid = seekerProcess?.processIdentifier {
                return "Running (PID: \(pid))"
            }
            return "Running"
        } else {
            return "Stopped"
        }
    }

    @objc func getSeekerLogPath() async -> String {
        return logFilePath
    }
}
