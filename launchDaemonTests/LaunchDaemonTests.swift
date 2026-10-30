import Darwin
import Foundation
import Testing
import shared
@testable import SeekerDaemon

private enum TestError: Error { case timedOut }

private func eventually(
    timeout: TimeInterval = 5, _ predicate: () async throws -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while try await !predicate() {
        guard Date() < deadline else { throw TestError.timedOut }
        try await Task.sleep(for: .milliseconds(10))
    }
}

private func processExists(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0 || errno != ESRCH
}

private final class ExitResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: (code: Int32, childAlive: Bool)?

    func record(_ code: Int32, pid: Int32) {
        lock.withLock { result = (code, processExists(pid)) }
    }
    var value: (code: Int32, childAlive: Bool)? { lock.withLock { result } }
}

private final class Fixture: @unchecked Sendable {
    let directory: URL
    let config: SeekerConfig
    private let ready: URL

    init(delay: Double = 0, ignoreSignals: Bool = false, exitCode: Int? = nil, closeOutput: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("seeker-daemon-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        ready = directory.appendingPathComponent("pids")
        let script = directory.appendingPathComponent("proxy")
        let exitBody = exitCode.map { "print('fixture failure', file=sys.stderr, flush=True)\nsys.exit(\($0))" } ?? ""
        let program = """
            #!/usr/bin/python3
            import os, signal, sys, time
            def stop(signum, frame):
                time.sleep(\(delay))
                sys.exit(0)
            signal.signal(signal.SIGTERM, \(ignoreSignals ? "signal.SIG_IGN" : "stop"))
            signal.signal(signal.SIGINT, \(ignoreSignals ? "signal.SIG_IGN" : "stop"))
            with open(\(String(reflecting: ready.path)), 'a') as f:
                f.write(str(os.getpid()) + '\\n')
            \(exitBody)
            \(closeOutput ? "os.close(1); os.close(2)" : "")
            while True:
                signal.pause()
            """
        try program.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        config = SeekerConfig(
            binaryPath: script.path, configPath: directory.appendingPathComponent("config.yml").path,
            logPath: directory.appendingPathComponent("proxy.log").path
        )
    }

    var pids: [Int32] {
        (try? String(contentsOf: ready, encoding: .utf8))?
            .split(separator: "\n").compactMap { Int32($0) } ?? []
    }

    func waitForStarts(_ count: Int = 1) async throws {
        try await eventually { self.pids.count >= count }
    }

    func cleanup() {
        // Kill only the fixture processes created by this test, including on assertion failure.
        for pid in pids where processExists(pid) { _ = kill(pid, SIGKILL) }
        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite(.serialized)
struct LaunchDaemonTests {
    @Test func slowStopWaitsForExitAndRejectsPrematureRestart() async throws {
        let fixture = try Fixture(delay: 0.8)
        defer { fixture.cleanup() }
        let daemon = LaunchDaemon()
        try await daemon.startSeeker(config: fixture.config)
        try await fixture.waitForStarts()
        let oldPID = try #require(fixture.pids.first)
        let started = Date()
        let stop = Task { await daemon.stopSeeker() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(await daemon.getSeekerStatus().pid == oldPID)
        #expect(processExists(oldPID))
        await #expect(throws: (any Error).self) {
            try await daemon.startSeeker(config: fixture.config)
        }
        #expect(await stop.value)
        #expect(Date().timeIntervalSince(started) >= 0.7)
        #expect(!processExists(oldPID))

        try await daemon.startSeeker(config: fixture.config)
        try await fixture.waitForStarts(2)
        let newPID = try #require(fixture.pids.last)
        try await Task.sleep(for: .milliseconds(100))
        #expect(newPID != oldPID)
        #expect(await daemon.getSeekerStatus().pid == newPID)
        #expect(await daemon.stopSeeker())
        #expect(!processExists(newPID))
    }

    @Test func unresponsiveChildIsKilledAndReapedBeforeStopReturns() async throws {
        let fixture = try Fixture(ignoreSignals: true)
        defer { fixture.cleanup() }
        let daemon = LaunchDaemon(shutdownTimeout: 0.15)
        try await daemon.startSeeker(config: fixture.config)
        try await fixture.waitForStarts()
        let pid = try #require(fixture.pids.first)
        #expect(await daemon.stopSeeker())
        #expect(!processExists(pid))
        #expect(await daemon.getSeekerStatus().status == .stopped)
    }

    @Test func concurrentStartsCreateOnlyOneChild() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let daemon = LaunchDaemon()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { try await daemon.startSeeker(config: fixture.config) }
            }
            try await group.waitForAll()
        }
        try await fixture.waitForStarts()
        #expect(fixture.pids.count == 1)
        #expect(await daemon.getSeekerStatus().pid == fixture.pids.first)
        #expect(await daemon.stopSeeker())
    }

    @Test func concurrentStopsAllWaitForTheSameChild() async throws {
        let fixture = try Fixture(delay: 0.2)
        defer { fixture.cleanup() }
        let daemon = LaunchDaemon()
        try await daemon.startSeeker(config: fixture.config)
        try await fixture.waitForStarts()
        let pid = try #require(fixture.pids.first)
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<10 { group.addTask { await daemon.stopSeeker() } }
            for await stopped in group {
                #expect(stopped)
                #expect(!processExists(pid))
            }
        }
        #expect(await daemon.getSeekerStatus().status == .stopped)
    }

    @Test func repeatedRestartNeverLosesTheCurrentChild() async throws {
        let fixture = try Fixture(delay: 0.01)
        defer { fixture.cleanup() }
        let daemon = LaunchDaemon()
        for count in 1...10 {
            try await daemon.startSeeker(config: fixture.config)
            try await fixture.waitForStarts(count)
            let pid = try #require(fixture.pids.last)
            #expect(await daemon.getSeekerStatus().pid == pid)
            #expect(await daemon.stopSeeker())
            #expect(!processExists(pid))
        }
        #expect(fixture.pids.count == 10)
    }

    @Test func failedChildReportsOutputAndCanBeReplaced() async throws {
        let failed = try Fixture(exitCode: 7)
        let healthy = try Fixture()
        defer { failed.cleanup(); healthy.cleanup() }
        let daemon = LaunchDaemon()
        try await daemon.startSeeker(config: failed.config)
        try await eventually { await daemon.getSeekerStatus().status == .error }
        let error = await daemon.getSeekerStatus()
        #expect(error.errorMessage?.contains("status: 7") == true)
        #expect(error.errorMessage?.contains("fixture failure") == true)
        try await daemon.startSeeker(config: healthy.config)
        try await healthy.waitForStarts()
        #expect(await daemon.getSeekerStatus().isRunning)
        #expect(await daemon.stopSeeker())
    }

    @Test func failedLaunchDoesNotLeaveAStaleProcessRecord() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let daemon = LaunchDaemon()
        let bad = SeekerConfig(
            binaryPath: "/nonexistent/seeker-daemon-test", configPath: fixture.config.configPath,
            logPath: fixture.config.logPath
        )
        await #expect(throws: (any Error).self) { try await daemon.startSeeker(config: bad) }
        #expect(await daemon.getSeekerStatus().status == .error)
        try await daemon.startSeeker(config: fixture.config)
        try await fixture.waitForStarts()
        #expect(await daemon.stopSeeker())
    }

    @Test func closingOutputDoesNotBlockStatusOrShutdown() async throws {
        let fixture = try Fixture(closeOutput: true)
        defer { fixture.cleanup() }
        let daemon = LaunchDaemon()
        try await daemon.startSeeker(config: fixture.config)
        try await fixture.waitForStarts()
        try await Task.sleep(for: .milliseconds(50))
        #expect(await daemon.getSeekerStatus().isRunning)
        #expect(await daemon.stopSeeker())
    }

    @Test func xpcDisconnectStopsChildBeforeDaemonExits() async throws {
        let fixture = try Fixture(delay: 0.7)
        defer { fixture.cleanup() }
        let daemon = LaunchDaemon()
        let result = ExitResult()
        // The listener and client use a real XPC connection, without registering a system daemon.
        let service = ServiceDelegate(daemon: daemon, shutdownDelay: 0.02) { code in
            if let pid = fixture.pids.first { result.record(code, pid: pid) }
        }
        let listener = NSXPCListener.anonymous()
        listener.delegate = service
        listener.resume()
        defer { listener.invalidate() }
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: LaunchDaemonProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        let proxy = try #require(connection.remoteObjectProxy as? LaunchDaemonProtocol)
        try await proxy.startSeeker(config: fixture.config)
        try await fixture.waitForStarts()
        let pid = try #require(fixture.pids.first)
        #expect(await proxy.getSeekerStatus().pid == pid)
        connection.invalidate()
        try await eventually { result.value != nil }
        #expect(result.value?.code == 0)
        #expect(result.value?.childAlive == false)
        #expect(!processExists(pid))
    }

    @Test func reconnectCancelsPendingShutdown() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let daemon = LaunchDaemon()
        try await daemon.startSeeker(config: fixture.config)
        try await fixture.waitForStarts()
        let pid = try #require(fixture.pids.first)
        let result = ExitResult()
        let service = ServiceDelegate(daemon: daemon, shutdownDelay: 0.15) {
            result.record($0, pid: pid)
        }
        #expect(service.connectionOpened())
        service.connectionClosed()
        try await Task.sleep(for: .milliseconds(30))
        #expect(service.connectionOpened())
        try await Task.sleep(for: .milliseconds(200))
        #expect(result.value == nil)
        #expect(await daemon.getSeekerStatus().pid == pid)
        service.connectionClosed()
        try await eventually { result.value != nil }
        #expect(result.value?.childAlive == false)
    }

    @Test func committedShutdownRejectsNewConnectionsAndStarts() async throws {
        let fixture = try Fixture(delay: 0.3)
        defer { fixture.cleanup() }
        let daemon = LaunchDaemon()
        try await daemon.startSeeker(config: fixture.config)
        try await fixture.waitForStarts()
        let pid = try #require(fixture.pids.first)
        let result = ExitResult()
        let service = ServiceDelegate(daemon: daemon) { result.record($0, pid: pid) }
        #expect(service.connectionOpened())
        service.requestShutdown()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!service.connectionOpened())
        await #expect(throws: (any Error).self) {
            try await daemon.startSeeker(config: fixture.config)
        }
        try await eventually { result.value != nil }
        #expect(result.value?.childAlive == false)
        await #expect(throws: (any Error).self) {
            try await daemon.startSeeker(config: fixture.config)
        }
    }
}
