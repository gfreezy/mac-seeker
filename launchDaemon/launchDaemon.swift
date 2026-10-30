import Darwin
import Foundation
import shared

// All process state, including output and stop completions, belongs to syncQueue.
final class LaunchDaemon: NSObject, LaunchDaemonProtocol, @unchecked Sendable {
    private final class OutputCapture: @unchecked Sendable {
        let pipe = Pipe()
        var reader: DispatchSourceRead?
        var closed = false
    }

    private final class Session: @unchecked Sendable {
        let process = Process()
        let stdout = OutputCapture()
        let stderr = OutputCapture()
        var output = ""
        var stopping = false
        var stopCompletions: [@Sendable (Bool) -> Void] = []
        var killTimer: DispatchWorkItem?
    }

    private let syncQueue = DispatchQueue(label: "io.allsunday.seeker.daemon.sync")
    private let shutdownTimeout: TimeInterval
    private var session: Session?
    private var errorMessage: String?
    private var shuttingDown = false

    init(shutdownTimeout: TimeInterval = 3) {
        self.shutdownTimeout = shutdownTimeout
        super.init()
    }

    @objc func startSeeker(config: SeekerConfig) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            syncQueue.async { [self] in
                do {
                    guard !self.shuttingDown else {
                        throw AnyError("The daemon is shutting down")
                    }
                    if let session = self.session {
                        guard !session.stopping else {
                            throw AnyError("Seeker is still stopping; wait for stop to complete")
                        }
                        if session.process.isRunning {
                            print("[Daemon] Seeker already running")
                            continuation.resume()
                            return
                        }
                        self.processExited(session)
                    }

                    let session = Session()
                    let process = session.process
                    process.executableURL = URL(fileURLWithPath: config.binaryPath)
                    process.arguments = ["-c", config.configPath, "-l", config.logPath]
                    process.currentDirectoryURL = URL(
                        fileURLWithPath: (config.configPath as NSString).deletingLastPathComponent
                    )
                    process.standardOutput = session.stdout.pipe
                    process.standardError = session.stderr.pipe
                    process.terminationHandler = { [weak self, weak session] _ in
                        guard let self, let session else { return }
                        self.syncQueue.async { self.processExited(session) }
                    }

                    self.errorMessage = nil
                    self.session = session
                    do {
                        try process.run()
                    } catch {
                        self.session = nil
                        self.errorMessage = error.localizedDescription
                        throw error
                    }
                    self.captureOutput(session.stdout, label: "stdout", session: session)
                    self.captureOutput(session.stderr, label: "stderr", session: session)
                    print("[Daemon] Seeker started with PID: \(process.processIdentifier)")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @objc func stopSeeker() async -> Bool {
        await withCheckedContinuation { continuation in
            syncQueue.async {
                self.stopOnQueue { continuation.resume(returning: $0) }
            }
        }
    }

    // Once shutdown starts, even requests already queued by an XPC client cannot start a child.
    func shutdown(completion: @Sendable @escaping (Bool) -> Void) {
        syncQueue.async {
            self.shuttingDown = true
            self.stopOnQueue(completion)
        }
    }

    private func stopOnQueue(_ completion: @Sendable @escaping (Bool) -> Void) {
        guard let session else {
            completion(true)
            return
        }
        session.stopCompletions.append(completion)
        guard session.process.isRunning else {
            processExited(session)
            return
        }
        guard !session.stopping else { return }
        session.stopping = true
        print("[Daemon] Stopping seeker (PID: \(session.process.processIdentifier))")
        session.process.terminate()

        let timer = DispatchWorkItem { [weak self, weak session] in
            guard let self, let session, self.session === session else { return }
            guard session.process.isRunning else {
                self.processExited(session)
                return
            }
            let pid = session.process.processIdentifier
            print("[Daemon] Seeker did not exit within \(self.shutdownTimeout)s; sending SIGKILL (PID: \(pid))")
            if kill(pid, SIGKILL) != 0, errno != ESRCH {
                let code = errno
                print("[Daemon] Cannot kill seeker (PID: \(pid), errno: \(code))")
                session.stopping = false
                let completions = session.stopCompletions
                session.stopCompletions.removeAll()
                completions.forEach { $0(false) }
            }
            // Keep ownership and wait for terminationHandler, including after SIGKILL.
        }
        session.killTimer = timer
        syncQueue.asyncAfter(deadline: .now() + shutdownTimeout, execute: timer)
    }

    private func processExited(_ session: Session) {
        // A late callback must never clear a different, newly started process.
        guard self.session === session, !session.process.isRunning else { return }
        session.killTimer?.cancel()
        session.killTimer = nil
        drainOutput(session.stdout, label: "stdout", session: session)
        drainOutput(session.stderr, label: "stderr", session: session)
        closeOutput(session.stdout)
        closeOutput(session.stderr)

        let pid = session.process.processIdentifier
        let status = session.process.terminationStatus
        if session.stopping || status == 0 {
            errorMessage = nil
            print("[Daemon] Seeker stopped (PID: \(pid), status: \(status))")
        } else {
            let output = session.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = "Seeker terminated with status: \(status)"
                + (output.isEmpty ? "" : "\n\(output.suffix(1000))")
            errorMessage = message
            print("[Daemon] \(message) (PID: \(pid))")
        }
        self.session = nil
        let completions = session.stopCompletions
        session.stopCompletions.removeAll()
        completions.forEach { $0(true) }
    }

    // Nonblocking readers share the state queue. A descendant holding a pipe open
    // cannot delay process reaping or the stop reply by keeping read-to-EOF blocked.
    private func captureOutput(_ capture: OutputCapture, label: String, session: Session) {
        let handle = capture.pipe.fileHandleForReading
        let fd = handle.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            print("[Daemon] Cannot capture seeker \(label)")
            capture.closed = true
            try? handle.close()
            return
        }
        let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: syncQueue)
        reader.setEventHandler { [weak self, weak session, weak capture] in
            guard let self, let session, let capture else { return }
            self.drainOutput(capture, label: label, session: session)
        }
        reader.setCancelHandler { try? handle.close() }
        capture.reader = reader
        reader.resume()
    }

    private func closeOutput(_ capture: OutputCapture) {
        capture.closed = true
        capture.reader?.cancel()
        capture.reader = nil
    }

    private func drainOutput(_ capture: OutputCapture, label: String, session: Session) {
        guard !capture.closed else { return }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var drained = 0
        // Bound each read pass so a noisy child cannot starve stop requests or timers.
        while drained < 65536 {
            let count = read(capture.pipe.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            if count == 0 || (count < 0 && errno != EAGAIN) {
                closeOutput(capture)
                return
            }
            guard count > 0 else { return }
            drained += count
            let text = String(decoding: buffer.prefix(count), as: UTF8.self)
            print("[Seeker \(label)] \(text)", terminator: "")
            session.output = String((session.output + text).suffix(8192))
        }
    }

    @objc func getSeekerStatus() async -> SeekerStatusInfo {
        await withCheckedContinuation { continuation in
            syncQueue.async {
                if let session = self.session {
                    if session.process.isRunning {
                        continuation.resume(returning: .running(pid: session.process.processIdentifier))
                        return
                    }
                    self.processExited(session)
                }
                continuation.resume(returning: self.errorMessage.map(SeekerStatusInfo.error) ?? .stopped)
            }
        }
    }
}
