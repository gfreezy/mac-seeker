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

    var body: some Scene {
        MenuBarExtra("Seeker", systemImage: state.isStarted ? "fish.fill" : "fish") {
            Button(state.isStarted ? "􀆅 Stop" : "Start") {
                state.toggle()
            }

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
