//
//  seekerTests.swift
//  seekerTests
//
//  Created by feichao on 2025/1/7.
//

import Foundation
import ServiceManagement
import Testing
import Yams
@testable import seeker

struct seekerTests {

    @Test func serviceManagementMenuActionsMatchStatus() {
        #expect(serviceManagementMenuAction(for: .notFound) == .register)
        #expect(serviceManagementMenuAction(for: .notRegistered) == .register)
        #expect(serviceManagementMenuAction(for: .enabled) == .unregister)
        #expect(serviceManagementMenuAction(for: .requiresApproval) == .openApprovalSettings)
    }

    @Test func legacyProxyGroupDefaultsToUrlTest() throws {
        let yaml = """
            - name: legacy
              proxies:
                - server-1
            """

        let groups = try YAMLDecoder().decode([ProxyGroup].self, from: yaml)

        #expect(groups.count == 1)
        #expect(groups[0].groupType == .urlTest)
        #expect(groups[0].defaultSelected == nil)
    }

    @Test func proxyGroupUsesSnakeCaseYaml() throws {
        let group = ProxyGroup(
            name: "fixed",
            groupType: .select,
            defaultSelected: "server-2",
            proxies: ["server-1", "server-2"]
        )

        let yaml = try YAMLEncoder().encode(group)

        #expect(yaml.contains("type: select"))
        #expect(yaml.contains("default_selected: server-2"))
        #expect(!yaml.contains("default-selected"))
        #expect(!yaml.contains("url-test"))
    }

    @Test func tunDeviceNameDefaultsToAutomaticAndIsOmittedFromYaml() throws {
        let configuration = try YAMLDecoder().decode(SeekerConfiguration.self, from: "{}")

        #expect(configuration.tunName.isEmpty)

        let yaml = try YAMLEncoder().encode(configuration)
        #expect(!yaml.contains("tun_name"))
    }

    @Test func explicitTunDeviceNameIsPreserved() throws {
        var configuration = SeekerConfiguration.defaultConfiguration()
        configuration.tunName = "  utun42  "

        let yaml = try YAMLEncoder().encode(configuration)
        let decoded = try YAMLDecoder().decode(SeekerConfiguration.self, from: yaml)

        #expect(yaml.contains("tun_name: utun42"))
        #expect(decoded.tunName == "utun42")
    }

    @Test func mimicSettingsSurviveYamlAndSubscriptionCacheRoundTrips() throws {
        for padding in ["0", "16", "random"] {
            let yaml = """
                name: mimic
                addr: proxy.example:8443
                protocol: Hysteria2
                mimic:
                  enabled: true
                  interface: en0
                  tun_name: utun42
                  mtu: 1400
                  padding: \(padding)
                """
            let server = try YAMLDecoder().decode(ProxyServer.self, from: yaml)
            let mimic = try #require(server.mimic)
            #expect(mimic.enabled == true)
            #expect(mimic.interface == "en0")
            #expect(mimic.tunName == "utun42")
            #expect(mimic.mtu == 1400)
            #expect(mimic.padding == (padding == "random" ? .random : .fixed(UInt8(padding)!)))

            let encoded = try YAMLEncoder().encode(server)
            let restored = try YAMLDecoder().decode(ProxyServer.self, from: encoded)
            #expect(restored.mimic == mimic)
            #expect(encoded.contains("tun_name: utun42"))

            let cached = try JSONEncoder().encode(server)
            let restoredCache = try JSONDecoder().decode(ProxyServer.self, from: cached)
            #expect(restoredCache.mimic == mimic)
        }
    }

    @Test @MainActor func menuSelectionPreservesMimicSettings() throws {
        let (service, configURL) = try makeService(
            servers: ["server-1", "server-2"],
            groups: [ProxyGroup(name: "work", proxies: ["server-1", "server-2"])],
            rules: ["MATCH,PROXY(work)"]
        )
        defer { try? FileManager.default.removeItem(at: configURL) }
        let mimic = try YAMLDecoder().decode(
            MimicConfig.self, from: "enabled: true\npadding: random\n"
        )
        service.configuration.servers[0].protocol = .hysteria2
        service.configuration.servers[0].mimic = mimic
        try service.save()

        try service.selectProxy(groupName: "work", serverName: "server-1")
        try service.reload()

        #expect(service.configuration.servers[0].mimic == mimic)
        #expect(service.configuration.proxyGroups[0].defaultSelected == "server-1")
    }

    @Test func mimicSettingsValidateInterfaceNamesAndMtuBounds() throws {
        for yaml in ["{}", "mtu: 1280", "mtu: 9000", "interface: en0\ntun_name: utun42"] {
            let config = try YAMLDecoder().decode(MimicConfig.self, from: yaml)
            #expect(config.validationError == nil)
        }
        for yaml in [
            "mtu: 0", "mtu: 1279", "mtu: 9001", "padding: 17",
            "interface: ''", "interface: 'en 0'", "interface: '网卡'",
            "tun_name: abcdefghijklmnop", "interface: \"en0\\n\"",
        ] {
            let config = try YAMLDecoder().decode(MimicConfig.self, from: yaml)
            #expect(config.validationError != nil)
        }
    }

    @Test @MainActor func invalidMimicSettingsDoNotOverwriteConfiguration() throws {
        let (service, configURL) = try makeService(servers: ["server-1"], groups: [], rules: [])
        defer { try? FileManager.default.removeItem(at: configURL) }
        let original = try String(contentsOf: configURL, encoding: .utf8)
        service.configuration.servers[0].protocol = .hysteria2
        service.configuration.servers[0].mimic = try YAMLDecoder().decode(
            MimicConfig.self, from: "enabled: true\nmtu: 0\n"
        )

        #expect(throws: ConfigurationError.self) { try service.save() }
        #expect(try String(contentsOf: configURL, encoding: .utf8) == original)
    }

    @Test @MainActor func implicitDefaultCanBeMaterializedAndRestored() throws {
        let (service, configURL) = try makeService(
            servers: ["server-1", "server-2"],
            groups: [],
            rules: ["MATCH,PROXY"]
        )
        defer { try? FileManager.default.removeItem(at: configURL) }

        let implicit = try #require(service.menuProxyGroups.first)
        #expect(implicit.name.isEmpty)
        #expect(implicit.groupType == .urlTest)
        #expect(implicit.proxies == ["server-1", "server-2"])
        #expect(!implicit.isMaterialized)

        try service.selectProxy(groupName: "", serverName: "server-2")

        let persisted = try #require(
            service.configuration.proxyGroups.first(where: { $0.name.isEmpty })
        )
        #expect(persisted.groupType == .select)
        #expect(persisted.defaultSelected == "server-2")
        #expect(persisted.proxies == ["server-1", "server-2"])

        try service.useAutomaticProxySelection(groupName: "")

        #expect(!service.configuration.proxyGroups.contains(where: { $0.name.isEmpty }))
        let restored = try #require(service.menuProxyGroups.first)
        #expect(restored.name.isEmpty)
        #expect(restored.groupType == .urlTest)
        #expect(!restored.isMaterialized)
    }

    @Test @MainActor func namedGroupSelectionIsPersisted() throws {
        let group = ProxyGroup(
            name: "work",
            proxies: ["server-1", "server-2"]
        )
        let (service, configURL) = try makeService(
            servers: ["server-1", "server-2"],
            groups: [group],
            rules: ["MATCH,PROXY(work)"]
        )
        defer { try? FileManager.default.removeItem(at: configURL) }

        try service.selectProxy(groupName: "work", serverName: "server-2")

        #expect(service.configuration.proxyGroups[0].groupType == .select)
        #expect(service.configuration.proxyGroups[0].defaultSelected == "server-2")
        #expect(!service.isDirty)

        try service.useAutomaticProxySelection(groupName: "work")

        #expect(service.configuration.proxyGroups[0].groupType == .urlTest)
        #expect(service.configuration.proxyGroups[0].defaultSelected == nil)
    }

    @Test @MainActor func menuSelectionRejectsUnsavedSettings() throws {
        let group = ProxyGroup(name: "work", proxies: ["server-1"])
        let (service, configURL) = try makeService(
            servers: ["server-1"],
            groups: [group],
            rules: ["MATCH,PROXY(work)"]
        )
        defer { try? FileManager.default.removeItem(at: configURL) }
        service.configuration.verbose.toggle()
        service.markDirty()

        #expect(throws: ProxyGroupSelectionError.self) {
            try service.selectProxy(groupName: "work", serverName: "server-1")
        }
    }

    @Test @MainActor func ruleGroupNamesExcludeTheImplicitDefaultAndDuplicates() {
        let service = ConfigurationService(configPath: "/tmp/unused-seeker-test.yml")
        service.configuration.proxyGroups = [
            ProxyGroup(name: ""),
            ProxyGroup(name: "openai"),
            ProxyGroup(name: "openai"),
        ]

        #expect(service.availableProxyGroupNames == ["openai"])
    }

    @Test @MainActor func rulesCanBeReorderedWithoutSwiftUIHelpers() {
        let service = ConfigurationService(configPath: "/tmp/unused-seeker-test.yml")
        service.configuration.rules = [
            "DOMAIN,first.example,DIRECT",
            "DOMAIN,second.example,DIRECT",
            "MATCH,REJECT",
        ]

        service.moveRule(from: IndexSet(integer: 0), to: 3)

        #expect(service.configuration.rules == [
            "DOMAIN,second.example,DIRECT",
            "MATCH,REJECT",
            "DOMAIN,first.example,DIRECT",
        ])
    }

    @Test func updaterInfoConfigurationIsEmbedded() throws {
        let info = try #require(Bundle.main.infoDictionary)

        #expect(
            info["SUFeedURL"] as? String
                == "https://github.com/gfreezy/mac-seeker/releases/latest/download/appcast.xml"
        )
        #expect(
            info["SUPublicEDKey"] as? String
                == "l6OWJQk1eZvfrxilEHA0vrvuUt7xFw9NxuLA9miO7sM="
        )
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUScheduledCheckInterval"] as? Int == 86_400)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == false)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(info["SURequireSignedFeed"] as? Bool == true)
    }

    @Test func updateResumeStateRequiresAMatchingInstalledVersion() throws {
        let suiteName = "seeker-tests-update-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        UpdateResumeState.record(targetVersion: "2.0.0", wasRunning: false, defaults: defaults)
        #expect(!UpdateResumeState.consumeIfMatching(currentVersion: "2.0.0", defaults: defaults))

        UpdateResumeState.record(targetVersion: "2.0.0", wasRunning: true, defaults: defaults)
        #expect(!UpdateResumeState.consumeIfMatching(currentVersion: "1.0.0", defaults: defaults))
        #expect(!UpdateResumeState.consumeIfMatching(currentVersion: "2.0.0", defaults: defaults))

        UpdateResumeState.record(targetVersion: "2.0.0", wasRunning: true, defaults: defaults)
        #expect(UpdateResumeState.consumeIfMatching(currentVersion: "2.0.0", defaults: defaults))
        #expect(!UpdateResumeState.consumeIfMatching(currentVersion: "2.0.0", defaults: defaults))
    }

    #if DEBUG
    @Test @MainActor func updaterIsDisabledInDebugBuilds() {
        let service = UpdateService(isSeekerRunning: { false })

        #expect(!UpdateService.updatesEnabled)
        #expect(!service.canCheckForUpdates)
    }
    #endif

    @MainActor
    private func makeService(
        servers: [String],
        groups: [ProxyGroup],
        rules: [String]
    ) throws -> (ConfigurationService, URL) {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("seeker-tests-\(UUID().uuidString).yml")
        let service = ConfigurationService(configPath: configURL.path)
        var configuration = SeekerConfiguration.defaultConfiguration()
        configuration.servers = servers.enumerated().map { index, name in
            ProxyServer(
                name: name,
                addr: "127.0.0.1:\(1080 + index)",
                protocol: .http
            )
        }
        configuration.proxyGroups = groups
        configuration.rules = rules
        service.configuration = configuration
        try service.save()
        service.isLoaded = true
        return (service, configURL)
    }

}
