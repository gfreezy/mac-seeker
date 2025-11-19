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
    private let syncQueue = DispatchQueue(label: "io.allsunday.seeker.daemon.sync")

    @objc func startSeeker(config: SeekerConfig) async throws {
        self.seekerProcessErrorMessage = nil
        print("[Daemon] Starting seeker with config: \(config.configPath)")

        if await isSeekerRunning() {
            print("[Daemon] Seeker already running")
            return
        }

        let workingDirectory = (config.configPath as NSString).deletingLastPathComponent

        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.binaryPath)
        process.arguments = ["-c", config.configPath, "-l", config.logPath]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        process.terminationHandler = { [weak self] process in
            guard let self = self else { return }
            let msg = "Seeker terminated with status: \(process.terminationStatus)"
            print("[Daemon] \(msg)")
            self.syncQueue.async {
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

    @objc func isSeekerRunning() async -> Bool {
        return await withCheckedContinuation { continuation in
            syncQueue.async { [weak self] in
                guard let process = self?.seekerProcess else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: process.isRunning)
            }
        }
    }

    @objc func getSeekerStatus() async -> String {
        return await withCheckedContinuation { continuation in
            syncQueue.async { [weak self] in
                guard let self = self, let process = self.seekerProcess else {
                    continuation.resume(returning: "Stopped")
                    return
                }

                if process.isRunning {
                    let status = "Running (PID: \(process.processIdentifier))"
                    continuation.resume(returning: status)
                } else {
                    continuation.resume(returning: "Stopped")
                }
            }
        }
    }
}
