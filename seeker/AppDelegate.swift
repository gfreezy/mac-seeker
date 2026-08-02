import AppKit

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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            settingsWindowController.show()
        }
        return true
    }
}
