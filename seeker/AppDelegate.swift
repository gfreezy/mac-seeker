import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state: GlobalStateVm
    private let updateService: UpdateService
    private let settingsWindowController: SettingsWindowController
    private var menuBarController: MenuBarController?

    override init() {
        let state = GlobalStateVm()
        self.state = state
        self.updateService = UpdateService(isSeekerRunning: { state.isStarted })
        self.settingsWindowController = SettingsWindowController(state: state)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(
            state: state,
            updateService: updateService,
            openSettings: { [weak self] in
                self?.settingsWindowController.show()
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.invalidate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
private final class SettingsWindowController {
    private let state: GlobalStateVm
    private var windowController: NSWindowController?

    init(state: GlobalStateVm) {
        self.state = state
    }

    func show() {
        let windowController = windowController ?? makeWindowController()
        self.windowController = windowController
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func makeWindowController() -> NSWindowController {
        let rootView = ConfigurationEditorView(
            configService: state.configService,
            globalState: state
        )
        .environment(state)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentViewController = NSHostingController(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 650, height: 500)
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("SeekerSettingsWindow")
        window.center()

        let controller = NSWindowController(window: window)
        controller.shouldCascadeWindows = false
        return controller
    }
}
