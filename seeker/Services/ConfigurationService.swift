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

struct MenuProxyGroup: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let groupType: ProxyGroupType
    let defaultSelected: String?
    let proxies: [String]
    let isMaterialized: Bool

    var displayName: String { name.isEmpty ? "default" : name }

    var selectedServer: String? {
        guard groupType == .select else { return nil }
        if let defaultSelected, proxies.contains(defaultSelected) {
            return defaultSelected
        }
        return proxies.first
    }
}

enum ProxyGroupSelectionError: LocalizedError {
    case unsavedChanges
    case groupNotFound(String)
    case serverNotFound(String, String)

    var errorDescription: String? {
        switch self {
        case .unsavedChanges:
            return "Save or revert the settings changes before switching proxies."
        case .groupNotFound(let group):
            return "Proxy group '\(group.isEmpty ? "default" : group)' was not found."
        case .serverNotFound(let server, let group):
            return "Server '\(server)' is not available in proxy group '\(group.isEmpty ? "default" : group)'."
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

    func addRule(_ rule: ParsedRule, after id: ParsedRule.ID? = nil) {
        var rules = parsedRules
        if let id = id, let index = rules.firstIndex(where: { $0.id == id }) {
            rules.insert(rule, at: index + 1)
        } else {
            rules.append(rule)
        }
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
        var seen = Set<String>()
        return configuration.proxyGroups.compactMap { group in
            guard !group.name.isEmpty, seen.insert(group.name).inserted else { return nil }
            return group.name
        }
    }

    // MARK: - Menu Bar Proxy Groups

    var menuProxyGroups: [MenuProxyGroup] {
        var groups = configuration.proxyGroups.map { group in
            let proxies = group.name.isEmpty ? uniqueServerNames(availableServerNames) : group.proxies
            return MenuProxyGroup(
                name: group.name,
                groupType: group.groupType,
                defaultSelected: group.defaultSelected,
                proxies: proxies,
                isMaterialized: true
            )
        }

        if usesImplicitDefaultGroup && !groups.contains(where: { $0.name.isEmpty }) {
            groups.insert(
                MenuProxyGroup(
                    name: "",
                    groupType: .urlTest,
                    defaultSelected: nil,
                    proxies: uniqueServerNames(availableServerNames),
                    isMaterialized: false
                ),
                at: 0
            )
        } else if let defaultIndex = groups.firstIndex(where: { $0.name.isEmpty }), defaultIndex != 0 {
            groups.insert(groups.remove(at: defaultIndex), at: 0)
        }

        return groups
    }

    func selectProxy(groupName: String, serverName: String) throws {
        try prepareForMenuSelection()

        let previousConfiguration = configuration
        do {
            if groupName.isEmpty {
                let candidates = uniqueServerNames(availableServerNames)
                guard candidates.contains(serverName) else {
                    throw ProxyGroupSelectionError.serverNotFound(serverName, groupName)
                }

                if let index = configuration.proxyGroups.firstIndex(where: { $0.name.isEmpty }) {
                    configuration.proxyGroups[index].groupType = .select
                    configuration.proxyGroups[index].defaultSelected = serverName
                    configuration.proxyGroups[index].proxies = candidates
                } else {
                    configuration.proxyGroups.append(
                        ProxyGroup(
                            name: "",
                            groupType: .select,
                            defaultSelected: serverName,
                            proxies: candidates
                        )
                    )
                }
            } else {
                guard let index = configuration.proxyGroups.firstIndex(where: { $0.name == groupName }) else {
                    throw ProxyGroupSelectionError.groupNotFound(groupName)
                }
                guard configuration.proxyGroups[index].proxies.contains(serverName) else {
                    throw ProxyGroupSelectionError.serverNotFound(serverName, groupName)
                }
                configuration.proxyGroups[index].groupType = .select
                configuration.proxyGroups[index].defaultSelected = serverName
            }

            markDirty()
            try save()
        } catch {
            configuration = previousConfiguration
            markDirty()
            throw error
        }
    }

    func useAutomaticProxySelection(groupName: String) throws {
        try prepareForMenuSelection()

        let previousConfiguration = configuration
        do {
            if groupName.isEmpty {
                guard configuration.proxyGroups.contains(where: { $0.name.isEmpty }) else {
                    return
                }
                configuration.proxyGroups.removeAll { $0.name.isEmpty }
            } else {
                guard let index = configuration.proxyGroups.firstIndex(where: { $0.name == groupName }) else {
                    throw ProxyGroupSelectionError.groupNotFound(groupName)
                }
                configuration.proxyGroups[index].groupType = .urlTest
                configuration.proxyGroups[index].defaultSelected = nil
            }

            markDirty()
            try save()
        } catch {
            configuration = previousConfiguration
            markDirty()
            throw error
        }
    }

    private var usesImplicitDefaultGroup: Bool {
        parsedRules.contains { rule in
            switch rule.action {
            case .proxy(let groupName), .probe(let groupName):
                return groupName.isEmpty
            case .direct, .reject:
                return false
            }
        }
    }

    private func prepareForMenuSelection() throws {
        guard !isDirty else {
            throw ProxyGroupSelectionError.unsavedChanges
        }
        if isLoaded {
            try reload()
        } else {
            try load()
        }
        guard !isDirty else {
            throw ProxyGroupSelectionError.unsavedChanges
        }
    }

    private func uniqueServerNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    // MARK: - Available Server Names (for proxy groups)

    var availableServerNames: [String] {
        allServers.map { $0.name }
    }
}
