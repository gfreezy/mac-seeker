import OSLog
import ServiceManagement
import SwiftUI

private let menuBarLogger = Logger(subsystem: "io.allsunday.seeker", category: "menu-bar")

struct MenuBarPanelView: View {
    let state: GlobalStateVm
    let updateService: UpdateService
    let openSettings: () -> Void

    @State private var expandedGroupName: String?

    var body: some View {
        VStack(spacing: 0) {
            statusHeader

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    proxyGroupsSection

                    Divider()

                    applicationActions

                    Divider()

                    serviceActions
                }
                .padding(12)
            }
            .scrollIndicators(.visible)

            Divider()

            MenuBarActionButton(title: "Quit Seeker", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .padding(10)
        }
        .frame(width: 340, height: 560)
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: state.isStarted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(state.isStarted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Seeker")
                    .font(.headline)
                Text(state.isStarted ? "Proxy is running" : "Proxy is stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(state.isStarted ? "Stop" : "Start") {
                state.toggle()
            }
            .buttonStyle(.borderedProminent)
            .tint(state.isStarted ? .red : .accentColor)
            .disabled(state.isSwitchingProxy)
        }
        .padding(12)
    }

    @ViewBuilder
    private var proxyGroupsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Proxy Groups", systemImage: "square.stack.3d.up")
                .font(.headline)

            if let loadError = state.configService.loadError {
                MenuBarMessageView(
                    text: "Configuration error: \(loadError)",
                    systemImage: "exclamationmark.triangle.fill",
                    color: .red
                )
            } else if state.configService.menuProxyGroups.isEmpty {
                MenuBarMessageView(
                    text: "No proxy groups configured",
                    systemImage: "tray",
                    color: .secondary
                )
            } else {
                if state.configService.isDirty {
                    MenuBarMessageView(
                        text: "Save or revert settings changes before switching.",
                        systemImage: "pencil.circle.fill",
                        color: .orange
                    )
                }

                ForEach(state.configService.menuProxyGroups) { group in
                    ProxyGroupPickerView(
                        group: group,
                        isExpanded: expandedGroupName == group.name,
                        isDisabled: state.configService.isDirty || state.isSwitchingProxy,
                        isSwitching: state.switchingProxyGroupName == group.name,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                expandedGroupName = expandedGroupName == group.name ? nil : group.name
                            }
                        },
                        onAutomatic: {
                            Task {
                                await state.useAutomaticProxySelection(groupName: group.name)
                            }
                        },
                        onSelect: { serverName in
                            Task {
                                await state.selectProxy(
                                    groupName: group.name,
                                    serverName: serverName
                                )
                            }
                        }
                    )
                }
            }
        }
    }

    private var applicationActions: some View {
        VStack(spacing: 4) {
            MenuBarActionButton(title: "Open Settings", systemImage: "gearshape") {
                openSettings()
            }

            #if !DEBUG
            MenuBarActionButton(
                title: "Check for Updates…",
                systemImage: "arrow.triangle.2.circlepath",
                isDisabled: !updateService.canCheckForUpdates
            ) {
                updateService.checkForUpdates()
            }
            #endif

            MenuBarActionButton(title: "Open Config", systemImage: "doc.text") {
                state.openConfig()
            }

            MenuBarActionButton(title: "Open Log", systemImage: "text.document") {
                state.openLog()
            }

            MenuBarActionButton(title: "Open Folder", systemImage: "folder") {
                state.openFolder()
            }
        }
    }

    private var serviceActions: some View {
        VStack(spacing: 4) {
            MenuBarActionButton(title: autoStartTitle, systemImage: "arrow.clockwise.circle") {
                Task {
                    do {
                        if state.autoStartOnLogin == .notRegistered
                            || state.autoStartOnLogin == .notFound
                        {
                            try state.registerAutoStart()
                        } else {
                            try await state.unregisterAutoStart()
                        }
                    } catch {
                        menuBarLogger.error("register auto start error: \(error)")
                    }
                }
            }

            MenuBarActionButton(title: daemonTitle, systemImage: "gearshape.2") {
                Task {
                    do {
                        if state.daemonStatus == .notRegistered
                            || state.daemonStatus == .notFound
                        {
                            try state.registerDaemon()
                            state.daemonStatus = state.statusForDaemon()
                        } else {
                            try await state.unregisterDaemon()
                            state.daemonStatus = state.statusForDaemon()
                        }
                    } catch {
                        menuBarLogger.error("register/unregister daemon error: \(error)")
                    }
                }
            }
        }
    }

    private var autoStartTitle: String {
        switch state.autoStartOnLogin {
        case .enabled:
            "Auto Start Enabled"
        case .notFound, .notRegistered:
            "Auto Start Disabled"
        case .requiresApproval:
            "Auto Start Needs Approval"
        @unknown default:
            "Auto Start Unknown"
        }
    }

    private var daemonTitle: String {
        switch state.daemonStatus {
        case .enabled:
            "Daemon Registered"
        case .notFound, .notRegistered:
            "Daemon Not Registered"
        case .requiresApproval:
            "Daemon Needs Approval"
        @unknown default:
            "Daemon Status Unknown"
        }
    }
}

private struct ProxyGroupPickerView: View {
    let group: MenuProxyGroup
    let isExpanded: Bool
    let isDisabled: Bool
    let isSwitching: Bool
    let onToggle: () -> Void
    let onAutomatic: () -> Void
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.displayName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if isSwitching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.leading, 10)

                VStack(spacing: 2) {
                    selectionButton(
                        title: "Automatic",
                        isSelected: group.groupType == .urlTest,
                        isDisabled: group.groupType == .urlTest,
                        action: onAutomatic
                    )

                    if group.proxies.isEmpty {
                        Text("No servers available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(group.proxies, id: \.self) { serverName in
                            selectionButton(
                                title: serverName,
                                isSelected: group.selectedServer == serverName,
                                isDisabled: group.selectedServer == serverName,
                                action: { onSelect(serverName) }
                            )
                        }
                    }
                }
                .padding(6)
            }
        }
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
        .disabled(isDisabled)
    }

    private var summary: String {
        if group.groupType == .urlTest {
            return "Automatic"
        }
        return group.selectedServer ?? "First Server"
    }

    private func selectionButton(
        title: String,
        isSelected: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 14)

                Text(title)
                    .lineLimit(1)

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct MenuBarActionButton: View {
    let title: String
    let systemImage: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct MenuBarMessageView: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}
