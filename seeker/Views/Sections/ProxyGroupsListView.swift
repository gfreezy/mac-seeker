import SwiftUI

struct ProxyGroupsListView: View {
    @Bindable var configService: ConfigurationService
    @State private var selectedGroupId: ProxyGroup.ID?
    @State private var showingAddGroup = false
    @State private var searchText = ""

    private var filteredGroups: [ProxyGroup] {
        if searchText.isEmpty {
            return configService.configuration.proxyGroups
        }
        return configService.configuration.proxyGroups.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.proxies.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        HSplitView {
            // Group list
            List(selection: $selectedGroupId) {
                ForEach(filteredGroups) { group in
                    ProxyGroupRowView(group: group)
                        .tag(group.id)
                }
                .onDelete(perform: deleteGroups)
                .onMove(perform: moveGroups)
            }
            .listStyle(.inset)
            .searchable(text: $searchText, prompt: "Search groups")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(action: { showingAddGroup = true }) {
                        Label("Add Group", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    if selectedGroupId != nil {
                        Button(action: deleteSelectedGroup) {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                    }
                }
                .padding(8)
                .background(.bar)
            }
            .frame(idealWidth: 150)

            Group {
                // Group editor
                if let selectedId = selectedGroupId,
                    let index = configService.configuration.proxyGroups.firstIndex(where: {
                        $0.id == selectedId
                    })
                {
                    ProxyGroupEditorView(
                        group: $configService.configuration.proxyGroups[index],
                        availableServers: configService.availableServerNames,
                        defaultPingUrls: configService.configuration.pingUrls
                    )
                } else {
                    ContentUnavailableView(
                        "No Group Selected",
                        systemImage: "square.stack.3d.up",
                        description: Text("Select a group to edit or click + to add a new one")
                    )
                }
            }
            .frame(minWidth: 500, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingAddGroup) {
            AddProxyGroupSheet(
                groups: $configService.configuration.proxyGroups,
                availableServers: configService.availableServerNames,
                defaultPingUrls: configService.configuration.pingUrls,
                selectedGroupId: $selectedGroupId
            )
        }
    }

    private func deleteGroups(at offsets: IndexSet) {
        configService.configuration.proxyGroups.remove(atOffsets: offsets)
        configService.markDirty()
    }

    private func moveGroups(from source: IndexSet, to destination: Int) {
        configService.configuration.proxyGroups.move(fromOffsets: source, toOffset: destination)
        configService.markDirty()
    }

    private func deleteSelectedGroup() {
        guard let selectedId = selectedGroupId,
            let index = configService.configuration.proxyGroups.firstIndex(where: {
                $0.id == selectedId
            })
        else { return }
        configService.configuration.proxyGroups.remove(at: index)
        configService.markDirty()
        selectedGroupId = nil
    }
}

struct ProxyGroupRowView: View {
    let group: ProxyGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.name.isEmpty ? "(unnamed)" : group.name)
                .font(.headline)
            Text("\(group.proxies.count) server(s)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct AddProxyGroupSheet: View {
    @Binding var groups: [ProxyGroup]
    let availableServers: [String]
    var defaultPingUrls: [PingUrl] = []
    @Binding var selectedGroupId: ProxyGroup.ID?
    @Environment(\.dismiss) private var dismiss

    @State private var newGroup = ProxyGroup()

    var body: some View {
        VStack(spacing: 0) {
            Text("Add New Proxy Group")
                .font(.headline)
                .padding()

            Divider()

            ProxyGroupEditorView(
                group: $newGroup,
                availableServers: availableServers,
                defaultPingUrls: defaultPingUrls
            )
            .padding()

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    groups.append(newGroup)
                    selectedGroupId = newGroup.id
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newGroup.name.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
    }
}

struct ProxyGroupEditorView: View {
    @Binding var group: ProxyGroup
    let availableServers: [String]
    var defaultPingUrls: [PingUrl] = []
    @State private var showingServerPicker = false

    // Servers that can be added (not already in the group)
    private var serversToAdd: [String] {
        availableServers.filter { !group.proxies.contains($0) }
    }

    // Whether using default or custom ping URLs
    private var isUsingDefaultPingUrls: Bool {
        group.pingUrls == nil || group.pingUrls?.isEmpty == true
    }

    var body: some View {
        Form {
            Section("Basic") {
                TextField("Name", text: $group.name)
            }

            Section("Servers") {
                // Current servers with delete buttons
                ForEach(group.proxies, id: \.self) { serverName in
                    HStack {
                        Text(serverName)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(action: {
                            group.proxies.removeAll { $0 == serverName }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove server")
                    }
                }
                .onMove { source, destination in
                    group.proxies.move(fromOffsets: source, toOffset: destination)
                }

                // Add server button
                Button(action: { showingServerPicker = true }) {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(serversToAdd.isEmpty)

                if availableServers.isEmpty {
                    Text("No servers available. Add servers first.")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }

            Section("Ping Settings") {
                TextField(
                    "Ping Timeout",
                    text: Binding(
                        get: { group.pingTimeout ?? "" },
                        set: { group.pingTimeout = $0.isEmpty ? nil : $0 }
                    )
                )
                .help("e.g., 1s, 2s (leave empty to use global setting)")
            }

            Section {
                if isUsingDefaultPingUrls {
                    // Show default URLs as read-only
                    if defaultPingUrls.isEmpty {
                        Text("No default ping URLs configured")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(defaultPingUrls) { pingUrl in
                            Text(pingUrl.displayString)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    // Show custom URLs with editor
                    PingUrlListEditor(
                        pingUrls: Binding(
                            get: { group.pingUrls ?? [] },
                            set: { group.pingUrls = $0.isEmpty ? nil : $0 }
                        ))
                }
            } header: {
                HStack {
                    Text("Ping URLs")
                    if isUsingDefaultPingUrls {
                        Text("(Default)")
                            .foregroundColor(.orange)
                            .font(.caption)
                    } else {
                        Text("(Custom)")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }

                    Spacer()

                    if isUsingDefaultPingUrls {
                        Button("Customize", action: { group.pingUrls = defaultPingUrls })
                            .buttonStyle(.borderless)
                            .font(.caption)
                    } else {
                        Button("Use Default", action: { group.pingUrls = nil })
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showingServerPicker) {
            ServerPickerSheet(
                servers: serversToAdd,
                onSelect: { selectedServers in
                    group.proxies.append(contentsOf: selectedServers)
                    showingServerPicker = false
                }
            )
        }
    }
}

struct ServerPickerSheet: View {
    let servers: [String]
    let onSelect: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedServers: Set<String> = []

    private var filteredServers: [String] {
        if searchText.isEmpty {
            return servers
        }
        return servers.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Select Servers")
                .font(.headline)
                .padding()

            Divider()

            if servers.isEmpty {
                ContentUnavailableView(
                    "No Servers",
                    systemImage: "server.rack",
                    description: Text("All servers have been added")
                )
                .frame(maxHeight: .infinity)
            } else {
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                List(filteredServers, id: \.self, selection: $selectedServers) { serverName in
                    Text(serverName)
                        .tag(serverName)
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if !selectedServers.isEmpty {
                    Text("\(selectedServers.count) selected")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                Button("Add") {
                    onSelect(Array(selectedServers))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedServers.isEmpty)
            }
            .padding()
        }
        .frame(width: 350, height: 400)
    }
}

#Preview("Proxy Groups List") {
    let service = ConfigurationService(configPath: "/tmp/config.yml")
    ProxyGroupsListView(configService: service)
        .frame(width: 600, height: 500)
        .onAppear {
            service.configuration = SeekerConfiguration.defaultConfiguration()
            service.isLoaded = true
        }
}

#Preview("Proxy Group Editor") {
    @Previewable @State var group = ProxyGroup(name: "Test Group", proxies: ["Server1"])
    ProxyGroupEditorView(group: $group, availableServers: ["Server1", "Server2", "Server3"])
        .frame(width: 400, height: 400)
}

#Preview("Server Picker") {
    ServerPickerSheet(
        servers: ["Server1", "Server2", "Server3"],
        onSelect: { _ in }
    )
}
