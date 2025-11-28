import Foundation
import Yams

enum ConfigurationError: LocalizedError {
    case fileNotFound
    case parseError(String)
    case saveError(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Configuration file not found"
        case .parseError(let message):
            return "Failed to parse configuration: \(message)"
        case .saveError(let message):
            return "Failed to save configuration: \(message)"
        }
    }
}

@MainActor
@Observable
class ConfigurationService {
    var configuration: SeekerConfiguration = SeekerConfiguration()
    var isDirty: Bool = false
    var loadError: String?
    var isLoaded: Bool = false

    // Remote config service for fetching Clash subscriptions
    let remoteConfigService = RemoteConfigService()

    private let configPath: String
    private var originalConfiguration: SeekerConfiguration = SeekerConfiguration()

    init(configPath: String) {
        self.configPath = configPath
    }

    // MARK: - All Servers (local + remote merged)

    /// All servers including both local and remote
    var allServers: [ProxyServer] {
        var servers = configuration.servers
        servers.append(contentsOf: remoteConfigService.remoteServers)
        return servers
    }

    /// Local servers only (editable)
    var localServers: [ProxyServer] {
        get { configuration.servers }
        set {
            configuration.servers = newValue
            markDirty()
        }
    }

    /// Remote servers only (read-only)
    var remoteServers: [ProxyServer] {
        remoteConfigService.remoteServers
    }

    /// Fetch remote servers from configured URLs
    func refreshRemoteServers() async {
        await remoteConfigService.fetchRemoteServers(from: configuration.remoteConfigUrls)
    }

    func load() throws {
        // If config file doesn't exist, create default configuration
        guard FileManager.default.fileExists(atPath: configPath) else {
            configuration = SeekerConfiguration.defaultConfiguration()
            originalConfiguration = configuration
            isDirty = true  // Mark as dirty so user can save it
            isLoaded = true
            loadError = nil
            loadRemoteServersCache()
            return
        }

        do {
            let content = try String(contentsOfFile: configPath, encoding: .utf8)

            // Handle empty file
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                configuration = SeekerConfiguration.defaultConfiguration()
                originalConfiguration = configuration
                isDirty = true
                isLoaded = true
                loadError = nil
                loadRemoteServersCache()
                return
            }

            let decoder = YAMLDecoder()
            configuration = try decoder.decode(SeekerConfiguration.self, from: content)
            originalConfiguration = configuration
            isDirty = false
            isLoaded = true
            loadError = nil
            loadRemoteServersCache()
        } catch {
            loadError = error.localizedDescription
            throw ConfigurationError.parseError(error.localizedDescription)
        }
    }

    /// Load cached remote servers for configured URLs
    private func loadRemoteServersCache() {
        if !configuration.remoteConfigUrls.isEmpty {
            remoteConfigService.loadCache(for: configuration.remoteConfigUrls)
        }
    }

    func save() throws {
        do {
            let encoder = YAMLEncoder()
            let yamlString = try encoder.encode(configuration)
            try yamlString.write(toFile: configPath, atomically: true, encoding: .utf8)
            originalConfiguration = configuration
            isDirty = false
        } catch {
            throw ConfigurationError.saveError(error.localizedDescription)
        }
    }

    func reload() throws {
        try load()
    }

    func revert() {
        configuration = originalConfiguration
        isDirty = false
    }

    func markDirty() {
        isDirty = configuration != originalConfiguration
    }

    /// Check if only rules changed compared to original configuration
    func onlyRulesChanged() -> Bool {
        guard isDirty else { return false }

        // Compare everything except rules
        var currentWithoutRules = configuration
        var originalWithoutRules = originalConfiguration
        currentWithoutRules.rules = []
        originalWithoutRules.rules = []

        return currentWithoutRules == originalWithoutRules
    }

    func exportTo(url: URL) throws {
        let encoder = YAMLEncoder()
        let yamlString = try encoder.encode(configuration)
        try yamlString.write(to: url, atomically: true, encoding: .utf8)
    }

    func importFrom(url: URL) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        let decoder = YAMLDecoder()
        configuration = try decoder.decode(SeekerConfiguration.self, from: content)
        isDirty = true
    }

    // MARK: - Convenience Methods for Rules

    var parsedRules: [ParsedRule] {
        get {
            configuration.rules.compactMap { ParsedRule(from: $0) }
        }
        set {
            configuration.rules = newValue.map { $0.toString() }
            markDirty()
        }
    }

    func addRule(_ rule: ParsedRule) {
        var rules = parsedRules
        rules.append(rule)
        parsedRules = rules
    }

    func removeRule(at index: Int) {
        var rules = parsedRules
        guard index >= 0, index < rules.count else { return }
        rules.remove(at: index)
        parsedRules = rules
    }

    func moveRule(from source: IndexSet, to destination: Int) {
        var rules = parsedRules
        rules.move(fromOffsets: source, toOffset: destination)
        parsedRules = rules
    }

    // MARK: - Convenience Methods for Servers

    func addServer(_ server: ProxyServer) {
        configuration.servers.append(server)
        markDirty()
    }

    func removeServer(at index: Int) {
        guard index >= 0, index < configuration.servers.count else { return }
        configuration.servers.remove(at: index)
        markDirty()
    }

    // MARK: - Convenience Methods for Proxy Groups

    func addProxyGroup(_ group: ProxyGroup) {
        configuration.proxyGroups.append(group)
        markDirty()
    }

    func removeProxyGroup(at index: Int) {
        guard index >= 0, index < configuration.proxyGroups.count else { return }
        configuration.proxyGroups.remove(at: index)
        markDirty()
    }

    // MARK: - Available Proxy Group Names (for rule actions)

    var availableProxyGroupNames: [String] {
        configuration.proxyGroups.map { $0.name }
    }

    // MARK: - Available Server Names (for proxy groups)

    var availableServerNames: [String] {
        allServers.map { $0.name }
    }
}
