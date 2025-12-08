//
//  launchedDaemon.swift
//  launchedDaemon
//
//  Created by feichao on 2025/1/7.
//

import Foundation
import shared

final class LaunchDaemon: NSObject, LaunchDaemonProtocol {
    private nonisolated(unsafe) var seekerProcess: Process?
    private nonisolated(unsafe) var seekerProcessErrorMessage: String?
    private nonisolated(unsafe) var seekerProcessOutput: String = ""
    private let syncQueue = DispatchQueue(label: "io.allsunday.seeker.daemon.sync")

    @objc func startSeeker(config: SeekerConfig) async throws {
        self.seekerProcessErrorMessage = nil
        self.seekerProcessOutput = ""
        print("[Daemon] Starting seeker with config: \(config.configPath)")

        let status = await getSeekerStatus()
        if status.isRunning {
            print("[Daemon] Seeker already running")
            return
        }

        let workingDirectory = (config.configPath as NSString).deletingLastPathComponent
        print("[Daemon] Working directory: \(workingDirectory)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.binaryPath)
        process.arguments = ["-c", config.configPath, "-l", config.logPath]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        // Create pipes to capture stdout and stderr
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Read stdout asynchronously
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                print("[Seeker stdout] \(str)", terminator: "")
                self.syncQueue.async { [weak self] in
                    self?.seekerProcessOutput += str
                }
            }
        }

        // Read stderr asynchronously
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                print("[Seeker stderr] \(str)", terminator: "")
                self.syncQueue.async { [weak self] in
                    self?.seekerProcessOutput += str
                }
            }
        }

        process.terminationHandler = { [weak self] process in
            guard let self = self else { return }

            // Clean up readability handlers
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            // Read any remaining data
            let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            self.syncQueue.async {
                if !remainingStdout.isEmpty, let str = String(data: remainingStdout, encoding: .utf8) {
                    self.seekerProcessOutput += str
                }
                if !remainingStderr.isEmpty, let str = String(data: remainingStderr, encoding: .utf8) {
                    self.seekerProcessOutput += str
                }

                let exitStatus = process.terminationStatus
                let msg: String
                if exitStatus == 0 {
                    msg = "Seeker terminated normally"
                } else {
                    // Include captured output in error message for non-zero exit
                    let output = self.seekerProcessOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if output.isEmpty {
                        msg = "Seeker terminated with status: \(exitStatus)"
                    } else {
                        // Keep last 1000 characters of output to avoid too long message
                        let truncatedOutput = output.count > 1000 ? String(output.suffix(1000)) : output
                        msg = "Seeker terminated with status: \(exitStatus)\n\(truncatedOutput)"
                    }
                }
                print("[Daemon] \(msg)")
                self.seekerProcessErrorMessage = msg
                self.seekerProcess = nil
            }
        }

        try process.run()

        syncQueue.sync {
            self.seekerProcess = process
        }

        print("[Daemon] Seeker started with PID: \(process.processIdentifier)")

        let msg = syncQueue.sync { self.seekerProcessErrorMessage }
        if let msg = msg {
            throw AnyError(msg)
        }
    }

    @objc func stopSeeker() async -> Bool {
        return await withCheckedContinuation { continuation in
            stopSeekerInternal { result in
                continuation.resume(returning: result)
            }
        }
    }

    func stopSeekerSync() {
        let semaphore = DispatchSemaphore(value: 0)
        stopSeekerInternal { _ in
            semaphore.signal()
        }
        semaphore.wait()
    }

    private func stopSeekerInternal(_ completion: @Sendable @escaping (Bool) -> Void) {
        syncQueue.async { [weak self] in
            guard let self = self else {
                completion(true)
                return
            }

            guard let process = self.seekerProcess else {
                print("[Daemon] No process to stop")
                completion(true)
                return
            }

            if process.isRunning {
                print("[Daemon] Stopping seeker (PID: \(process.processIdentifier))")
                process.terminate()

                let processToCheck = process
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else {
                        completion(true)
                        return
                    }

                    self.syncQueue.async {
                        if processToCheck.isRunning {
                            print("[Daemon] Force killing seeker")
                            processToCheck.interrupt()
                        }
                        self.seekerProcess = nil
                        print("[Daemon] Seeker stopped")
                        completion(true)
                    }
                }
            } else {
                self.seekerProcess = nil
                print("[Daemon] Seeker was not running")
                completion(true)
            }
        }
    }

    @objc func getSeekerStatus() async -> SeekerStatusInfo {
        return await withCheckedContinuation { continuation in
            syncQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: .unknown)
                    return
                }

                guard let process = self.seekerProcess else {
                    if let errorMsg = self.seekerProcessErrorMessage {
                        continuation.resume(returning: .error(errorMsg))
                    } else {
                        continuation.resume(returning: .stopped)
                    }
                    return
                }

                if process.isRunning {
                    continuation.resume(returning: .running(pid: process.processIdentifier))
                } else {
                    continuation.resume(returning: .stopped)
                }
            }
        }
    }
}
