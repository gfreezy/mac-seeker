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
        MenuBarExtra("Seeker", systemImage: "fish.fill") {
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

            Divider()

            Button("Quit") {

                NSApplication.shared.terminate(nil)

            }.keyboardShortcut("q")
        }

        WindowGroup("Settings", id: WindowId.settings) {
            ContentView()
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
}
