//
//  seekerApp.swift
//  seeker
//
//  Created by feichao on 2025/1/7.
//

import SwiftUI

@main
struct seekerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
