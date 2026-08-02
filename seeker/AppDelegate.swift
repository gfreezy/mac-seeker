import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state: GlobalStateVm
    private let updateService: UpdateService
    private var menuBarController: MenuBarController?

    override init() {
        let state = GlobalStateVm()
        self.state = state
        self.updateService = UpdateService(isSeekerRunning: { state.isStarted })
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(
            state: state,
            updateService: updateService,
            openSettings: { [weak self] in
                self?.showSettings()
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.invalidate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let didShow = NSApplication.shared.sendAction(
            Selector(("showSettingsWindow:")),
            to: nil,
            from: nil
        )
        if !didShow {
            NSApplication.shared.sendAction(
                Selector(("showPreferencesWindow:")),
                to: nil,
                from: nil
            )
        }
    }
}
