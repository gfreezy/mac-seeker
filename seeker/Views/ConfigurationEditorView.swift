import SwiftUI

enum ConfigSection: String, CaseIterable, Identifiable {
    case general = "General"
    case dns = "DNS"
    case tun = "TUN Device"
    case performance = "Performance"
    case servers = "Servers"
    case groups = "Proxy Groups"
    case rules = "Rules"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .dns: return "network"
        case .tun: return "rectangle.connected.to.line.below"
        case .performance: return "gauge.with.dots.needle.bottom.50percent"
        case .servers: return "server.rack"
        case .groups: return "square.stack.3d.up"
        case .rules: return "list.bullet.rectangle"
        }
    }
}

struct ConfigurationEditorView: View {
    @Bindable var configService: ConfigurationService
    var globalState: GlobalStateVm?
    @State private var selectedSection: ConfigSection = .general
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingRulesApplied = false
    @State private var showingRestartRequired = false

    var body: some View {
        NavigationSplitView {
            List(ConfigSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 220)
        } detail: {
            // Content
            Group {
                switch selectedSection {
                case .general:
                    GeneralSettingsView(config: $configService.configuration)
                case .dns:
                    DNSSettingsView(config: $configService.configuration)
                case .tun:
                    TUNSettingsView(config: $configService.configuration)
                case .performance:
                    PerformanceSettingsView(config: $configService.configuration)
                case .servers:
                    ServersListView(configService: configService)
                case .groups:
                    ProxyGroupsListView(configService: configService)
                case .rules:
                    RulesListView(configService: configService)
                }
            }
            .onChange(of: configService.configuration) {
                configService.markDirty()
            }
            .navigationSplitViewColumnWidth(ideal: 500)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: reloadConfig) {
                    Label(
                        configService.isDirty ? "Revert to Original" : "Reload",
                        systemImage: "arrow.clockwise")
                }
                .labelStyle(.titleAndIcon)
                .help("Reload configuration from file")

                Button(action: saveConfig) {
                    Label("Save", systemImage: "square.and.arrow.down.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!configService.isDirty)
                .labelStyle(.titleAndIcon)
                .help("Save configuration to file")
            }
        }
        .alert("Configuration", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert("Saved", isPresented: $showingRulesApplied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Rules saved and applied automatically.")
        }
        .alert("Restart Required", isPresented: $showingRestartRequired) {
            Button("Later", role: .cancel) {}
            if let globalState = globalState, globalState.isStarted {
                Button("Restart Now") {
                    Task { @MainActor in
                        await globalState.stop()
                        try? await Task.sleep(for: .milliseconds(500))
                        try? await globalState.start()
                    }
                }
            }
        } message: {
            Text("Configuration saved. Restart Seeker to apply changes.")
        }
        .onAppear {
            loadConfigIfNeeded()
            // Crucial for activation!
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)  // Makes window key and brings to front
        }
        .frame(minWidth: 650, minHeight: 500)
    }

    private func loadConfigIfNeeded() {
        guard !configService.isLoaded else { return }
        do {
            try configService.load()
        } catch {
            alertMessage = "Failed to load configuration: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func reloadConfig() {
        do {
            try configService.reload()
        } catch {
            alertMessage = "Failed to reload configuration: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func saveConfig() {
        let onlyRules = configService.onlyRulesChanged()
        do {
            try configService.save()
            if onlyRules {
                showingRulesApplied = true
            } else {
                showingRestartRequired = true
            }
        } catch {
            alertMessage = "Failed to save configuration: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

#Preview {
    let service = ConfigurationService(configPath: "/tmp/config.yml")
    ConfigurationEditorView(configService: service)
        .onAppear {
            service.configuration = SeekerConfiguration.defaultConfiguration()
            service.isLoaded = true
        }
}
