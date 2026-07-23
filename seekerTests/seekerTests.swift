//
//  seekerTests.swift
//  seekerTests
//
//  Created by feichao on 2025/1/7.
//

import Foundation
import Testing
import Yams
@testable import seeker

struct seekerTests {

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
