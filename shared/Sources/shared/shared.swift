// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation


public struct AnyError: LocalizedError {
    public let errorDescription: String?
    public init(_ errorDescription: String) {
        self.errorDescription = errorDescription
    }
}


/// Configuration for starting the seeker process
@objc public final class SeekerConfig: NSObject, NSSecureCoding, Codable, Sendable {
    public static let supportsSecureCoding: Bool = true

    public func encode(with coder: NSCoder) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self)
            coder.encode(data, forKey: CodingKeys.coderPayloadKey)
            print("Encoded SeekerConfig: \(self)")
        } catch {
            assertionFailure("Failed to encode SeekerConfig: \(error)")
        }
    }

    public required init?(coder: NSCoder) {
        guard
            let data = coder.decodeObject(
                of: NSData.self, forKey: CodingKeys.coderPayloadKey) as Data?
        else {
            print("Failed to decode SeekerConfig: missing payload")
            return nil
        }

        let decoder = JSONDecoder()
        guard let config = try? decoder.decode(Self.self, from: data) else {
            print("Failed to decode SeekerConfig: invalid payload")
            return nil
        }

        self.binaryPath = config.binaryPath
        self.configPath = config.configPath
        self.logPath = config.logPath
        super.init()
        print("Decoded SeekerConfig: \(self)")
    }

    public let binaryPath: String
    public let configPath: String
    public let logPath: String

    public init(binaryPath: String, configPath: String, logPath: String) {
        self.binaryPath = binaryPath
        self.configPath = configPath
        self.logPath = logPath
        super.init()
    }

    private enum CodingKeys: String, CodingKey {
        case binaryPath
        case configPath
        case logPath

        static let coderPayloadKey = "configPayload"
    }
}

/// Seeker process status
@objc public final class SeekerStatusInfo: NSObject, NSSecureCoding, Sendable {
    public static let supportsSecureCoding: Bool = true

    public enum Status: Int, Sendable {
        case unknown = 0
        case stopped = 1
        case running = 2
        case error = 3
    }

    public let status: Status
    public let pid: Int32
    public let errorMessage: String?

    public var isRunning: Bool { status == .running }

    public override var description: String {
        switch status {
        case .unknown: return "Unknown"
        case .stopped: return "Stopped"
        case .running: return "Running (PID: \(pid))"
        case .error: return "Error: \(errorMessage ?? "Unknown error")"
        }
    }

    public init(status: Status, pid: Int32 = 0, errorMessage: String? = nil) {
        self.status = status
        self.pid = pid
        self.errorMessage = errorMessage
        super.init()
    }

    public static var unknown: SeekerStatusInfo { SeekerStatusInfo(status: .unknown) }
    public static var stopped: SeekerStatusInfo { SeekerStatusInfo(status: .stopped) }
    public static func running(pid: Int32) -> SeekerStatusInfo { SeekerStatusInfo(status: .running, pid: pid) }
    public static func error(_ message: String) -> SeekerStatusInfo { SeekerStatusInfo(status: .error, errorMessage: message) }

    public func encode(with coder: NSCoder) {
        coder.encode(status.rawValue, forKey: "status")
        coder.encode(pid, forKey: "pid")
        coder.encode(errorMessage, forKey: "errorMessage")
    }

    public required init?(coder: NSCoder) {
        let statusRaw = coder.decodeInteger(forKey: "status")
        self.status = Status(rawValue: statusRaw) ?? .unknown
        self.pid = coder.decodeInt32(forKey: "pid")
        self.errorMessage = coder.decodeObject(of: NSString.self, forKey: "errorMessage") as String?
        super.init()
    }
}

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@available(macOS 10.15.0, *)
@objc public protocol LaunchDaemonProtocol: Sendable {
    /// Start the Rust seeker process with specified configuration
    func startSeeker(config: SeekerConfig) async throws

    /// Stop the Rust seeker process
    func stopSeeker() async -> Bool

    /// Get the status of the seeker process
    func getSeekerStatus() async -> SeekerStatusInfo
}
