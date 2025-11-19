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

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@available(macOS 10.15.0, *)
@objc public protocol LaunchDaemonProtocol: Sendable {
    /// Start the Rust seeker process with specified configuration
    func startSeeker(config: SeekerConfig) async throws

    /// Stop the Rust seeker process
    func stopSeeker() async -> Bool

    /// Check if the Rust seeker process is running
    func isSeekerRunning() async -> Bool

    /// Get the status of the seeker process
    func getSeekerStatus() async -> String
}
