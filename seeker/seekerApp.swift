//
//  seekerApp.swift
//  seeker
//
//  Created by feichao on 2025/1/7.
//

import AppKit

@main
@MainActor
enum SeekerApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        _ = delegate
    }
}
