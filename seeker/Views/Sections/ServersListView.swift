import SwiftUI

struct ServersListView: View {
    @Bindable var configService: ConfigurationService
    @State private var selectedServerId: ProxyServer.ID?
    @State private var showingAddServer = false
    @State private var searchText = ""

    private var allServers: [ProxyServer] {
        configService.allServers
    }

    private var filteredServers: [ProxyServer] {
        if searchText.isEmpty {
            return allServers
        }
        return allServers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.addr.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var localServers: [ProxyServer] {
        filteredServers.filter { !$0.source.isRemote }
    }

    private var remoteServers: [ProxyServer] {
        filteredServers.filter { $0.source.isRemote }
    }

    private var selectedServer: ProxyServer? {
        guard let id = selectedServerId else { return nil }
        return allServers.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            // Server list
            List(selection: $selectedServerId) {
                if !localServers.isEmpty {
                    Section("Local Servers") {
                        ForEach(localServers) { server in
                            ServerRowView(server: server)
                                .tag(server.id)
                        }
                        .onDelete(perform: deleteLocalServers)
                        .onMove(perform: moveLocalServers)
                    }
                }

                if !remoteServers.isEmpty {
                    Section("Remote Servers") {
                        ForEach(remoteServers) { server in
                            ServerRowView(server: server)
                                .tag(server.id)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .searchable(text: $searchText, prompt: "Search servers")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(action: { showingAddServer = true }) {
                        Label("Add Server", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)

                    Button(action: { Task { await configService.refreshRemoteServers() } }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(configService.remoteConfigService.isLoading)
                    .opacity(configService.remoteConfigService.isLoading ? 0.5 : 1.0)

                    Spacer()

                    if let server = selectedServer, !server.source.isRemote {
                        Button(action: deleteSelectedServer) {
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
                // Server editor
                if let server = selectedServer {
                    if server.source.isRemote {
                        // Read-only view for remote servers
                        ServerDetailView(server: server)
                    } else if let index = configService.configuration.servers.firstIndex(where: { $0.id == server.id }) {
                        ServerEditorView(server: $configService.configuration.servers[index])
                    }
                } else {
                    ContentUnavailableView(
                        "No Server Selected",
                        systemImage: "server.rack",
                        description: Text("Select a server to edit or click + to add a new one")
                    )
                }
            }
            .frame(minWidth: 500, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingAddServer) {
            AddServerSheet(
                servers: $configService.configuration.servers,
                selectedServerId: $selectedServerId
            )
        }
        .onAppear {
            // Only auto-refresh if cache is older than 1 hour
            let urls = configService.configuration.remoteConfigUrls
            if !urls.isEmpty,
               configService.remoteConfigService.needsRefresh(for: urls) {
                Task {
                    await configService.refreshRemoteServers()
                }
            }
        }
    }

    private func deleteLocalServers(at offsets: IndexSet) {
        // Map filtered indices to original indices
        let serversToDelete = offsets.map { localServers[$0] }
        for server in serversToDelete {
            if let index = configService.configuration.servers.firstIndex(where: { $0.id == server.id }) {
                configService.configuration.servers.remove(at: index)
            }
        }
        configService.markDirty()
    }

    private func moveLocalServers(from source: IndexSet, to destination: Int) {
        // Only works when not searching
        guard searchText.isEmpty else { return }
        configService.configuration.servers.move(fromOffsets: source, toOffset: destination)
        configService.markDirty()
    }

    private func deleteSelectedServer() {
        guard let selectedId = selectedServerId,
              let index = configService.configuration.servers.firstIndex(where: { $0.id == selectedId })
        else { return }
        configService.configuration.servers.remove(at: index)
        configService.markDirty()
        selectedServerId = nil
    }
}

// MARK: - Read-only view for remote servers

struct ServerDetailView: View {
    let server: ProxyServer
    @State private var showPassword = false

    var body: some View {
        Form {
            Section {
                if case .remote(let url) = server.source {
                    LabeledContent("Source") {
                        Text(url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Section("Basic") {
                LabeledContent("Name", value: server.name)
                LabeledContent("Address", value: server.addr)
                LabeledContent("Protocol", value: server.protocol.displayName)
            }

            if server.protocol == .shadowsocks {
                Section("Shadowsocks") {
                    LabeledContent("Method", value: server.method ?? "-")
                }
            }

            if server.username != nil || server.password != nil {
                Section("Authentication") {
                    if let username = server.username {
                        LabeledContent("Username", value: username)
                    }
                    if let password = server.password {
                        LabeledContent("Password") {
                            HStack {
                                Text(showPassword ? password : "••••••••")
                                    .font(.system(.body, design: .monospaced))
                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

struct ServerRowView: View {
    let server: ProxyServer

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(server.name.isEmpty ? "(unnamed)" : server.name)
                .font(.headline)
            Text("\(server.protocol.displayName) - \(server.addr)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct AddServerSheet: View {
    @Binding var servers: [ProxyServer]
    @Binding var selectedServerId: ProxyServer.ID?
    @Environment(\.dismiss) private var dismiss

    @State private var newServer = ProxyServer()

    var body: some View {
        VStack(spacing: 0) {
            Text("Add New Server")
                .font(.headline)
                .padding()

            Divider()

            ServerEditorView(server: $newServer)
                .padding()

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    servers.append(newServer)
                    selectedServerId = newServer.id
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newServer.name.isEmpty || newServer.addr.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 400)
    }
}

struct ServerEditorView: View {
    @Binding var server: ProxyServer
    @State private var showPassword = false

    var body: some View {
        Form {
            Section("Basic") {
                TextField("Name", text: $server.name)
                TextField("Address", text: $server.addr)
                    .help("host:port or domain:port")

                Picker("Protocol", selection: $server.protocol) {
                    ForEach(ProxyProtocol.allCases, id: \.self) { proto in
                        Text(proto.displayName).tag(proto)
                    }
                }
            }

            Section("Authentication") {
                TextField(
                    "Username",
                    text: Binding(
                        get: { server.username ?? "" },
                        set: { server.username = $0.isEmpty ? nil : $0 }
                    ))

                HStack {
                    if showPassword {
                        TextField(
                            "Password",
                            text: Binding(
                                get: { server.password ?? "" },
                                set: { server.password = $0.isEmpty ? nil : $0 }
                            ))
                    } else {
                        SecureField(
                            "Password",
                            text: Binding(
                                get: { server.password ?? "" },
                                set: { server.password = $0.isEmpty ? nil : $0 }
                            ))
                    }
                    Button(action: { showPassword.toggle() }) {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if server.protocol == .shadowsocks {
                Section("Shadowsocks") {
                    Picker("Encryption Method", selection: Binding(
                        get: { ShadowsocksMethod(from: server.method) ?? .chacha20IetfPoly1305 },
                        set: { server.method = $0.rawValue }
                    )) {
                        ForEach(ShadowsocksMethod.allCases, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }

                    Toggle(
                        "Enable Obfuscation",
                        isOn: Binding(
                            get: { server.obfs != nil },
                            set: { enabled in
                                if enabled {
                                    server.obfs = ObfsConfig()
                                } else {
                                    server.obfs = nil
                                }
                            }
                        ))

                    if server.obfs != nil {
                        TextField(
                            "Obfs Mode",
                            text: Binding(
                                get: { server.obfs?.mode ?? "Http" },
                                set: { server.obfs?.mode = $0 }
                            ))

                        TextField(
                            "Obfs Host",
                            text: Binding(
                                get: { server.obfs?.host ?? "" },
                                set: { server.obfs?.host = $0 }
                            ))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

#Preview("Servers List") {
    let service = ConfigurationService(configPath: "/tmp/config.yml")
    ServersListView(configService: service)
        .frame(width: 600, height: 500)
        .onAppear {
            service.configuration = SeekerConfiguration.defaultConfiguration()
            service.isLoaded = true
        }
}

#Preview("Server Editor") {
    @Previewable @State var server = ProxyServer(
        name: "Test Server",
        addr: "127.0.0.1:1080",
        protocol: .shadowsocks,
        method: "chacha20-ietf"
    )
    ServerEditorView(server: $server)
        .frame(width: 400, height: 400)
}
