//
//  seekerApp.swift
//  seeker
//
//  Created by feichao on 2025/1/7.
//

import SwiftUI

enum WindowId {
    static let settings = "settings"
}

@main
struct seekerApp: App {
    @State var state: GlobalStateVm
    @State private var updateService: UpdateService
    @Environment(\.openWindow) var openWindow

    init() {
        let state = GlobalStateVm()
        _state = State(initialValue: state)
        _updateService = State(
            initialValue: UpdateService(isSeekerRunning: { state.isStarted })
        )
    }

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
            MenuBarPanelView(
                state: state,
                updateService: updateService,
                openSettings: { openWindow(id: WindowId.settings) }
            )
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Settings", id: WindowId.settings) {
            ConfigurationEditorView(configService: state.configService, globalState: state)
                .environment(state)
        }
    }
}
