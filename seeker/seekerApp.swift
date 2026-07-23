//
//  seekerApp.swift
//  seeker
//
//  Created by feichao on 2025/1/7.
//

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "io.allsunday.seeker", category: "")

enum WindowId {
    static let settings = "settings"
}

@main
struct seekerApp: App {
    @State var state = GlobalStateVm()
    @Environment(\.openWindow) var openWindow

    private var menuBarTitle: String {
        #if DEBUG
        "Seeker (D)"
        #else
        "Seeker"
        #endif
    }

    private var menuBarIcon: String {
        #if DEBUG
        state.isStarted ? "ant.fill" : "ant"
        #else
        state.isStarted ? "fish.fill" : "fish"
        #endif
    }

    var body: some Scene {
        MenuBarExtra(menuBarTitle, systemImage: menuBarIcon) {
            Button(state.isStarted ? "􀆅 Stop" : "Start") {
                state.toggle()
            }

            proxyGroupsMenu

            Button("Open Settings") {
                openWindow(id: WindowId.settings)
            }

            Button("Open Config") {
                state.openConfig()
            }

            Button("Open Log") {
                state.openLog()
            }

            Button("Open Folder") {
                state.openFolder()
            }

            autoStartButton

            daemonButton

            Divider()

            Button("Quit") {

                NSApplication.shared.terminate(nil)

            }.keyboardShortcut("q")
        }

        WindowGroup("Settings", id: WindowId.settings) {
            ConfigurationEditorView(configService: state.configService, globalState: state)
                .environment(state)
        }

    }

    @ViewBuilder
    var proxyGroupsMenu: some View {
        Divider()

        Menu("Proxy Groups") {
            if let loadError = state.configService.loadError {
                Text("Configuration error: \(loadError)")
            } else if state.configService.menuProxyGroups.isEmpty {
                Text("No proxy groups configured")
            } else {
                if state.configService.isDirty {
                    Text("Save or revert settings changes before switching")
                    Divider()
                }

                if state.isSwitchingProxy {
                    ProgressView("Restarting Seeker…")
                    Divider()
                }

                ForEach(state.configService.menuProxyGroups) { group in
                    proxyGroupMenu(group)
                }
            }
        }
    }

    @ViewBuilder
    func proxyGroupMenu(_ group: MenuProxyGroup) -> some View {
        Menu {
            Button {
                Task {
                    await state.useAutomaticProxySelection(groupName: group.name)
                }
            } label: {
                if group.groupType == .urlTest {
                    Label("Automatic", systemImage: "checkmark")
                } else {
                    Text("Automatic")
                }
            }
            .disabled(group.groupType == .urlTest)

            Divider()

            if group.proxies.isEmpty {
                Text("No servers available")
            } else {
                ForEach(group.proxies, id: \.self) { serverName in
                    Button {
                        Task {
                            await state.selectProxy(
                                groupName: group.name,
                                serverName: serverName
                            )
                        }
                    } label: {
                        if group.selectedServer == serverName {
                            Label(serverName, systemImage: "checkmark")
                        } else {
                            Text(serverName)
                        }
                    }
                    .disabled(group.selectedServer == serverName)
                }
            }
        } label: {
            Text("\(group.displayName): \(proxyGroupSummary(group))")
        }
        .disabled(state.configService.isDirty || state.isSwitchingProxy)
    }

    private func proxyGroupSummary(_ group: MenuProxyGroup) -> String {
        if group.groupType == .urlTest {
            return "Automatic"
        }
        return group.selectedServer ?? "First Server"
    }

    @ViewBuilder
    var autoStartButton: some View {
        let text =
            switch state.autoStartOnLogin {
            case .enabled:
                "􀆅 Auto Start Enabled"
            case .notFound:
                "Auto Start Disabled"
            case .notRegistered:
                "Auto Start Disabled"
            case .requiresApproval:
                "Auto Start Needs Approval"
            @unknown default:
                "Unknown"
            }
        Button(text) {
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
                    logger.error("register auto start error: \(error)")
                }
            }
        }
    }

    @ViewBuilder
    var daemonButton: some View {
        let text =
            switch state.daemonStatus {
            case .enabled:
                "􀆅 Daemon Registered"
            case .notFound:
                "Daemon Not Registered"
            case .notRegistered:
                "Daemon Not Registered"
            case .requiresApproval:
                "Daemon Needs Approval"
            @unknown default:
                "Unknown"
            }
        Button(text) {
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
                    logger.error("register/unregister daemon error: \(error)")
                }
            }
        }
    }
}
