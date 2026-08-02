import AppKit
import OSLog
import ServiceManagement

private let menuBarLogger = Logger(
    subsystem: "io.allsunday.seeker",
    category: "menu-bar"
)

enum ServiceManagementMenuAction: Equatable {
    case register
    case unregister
    case openApprovalSettings
    case none
}

func serviceManagementMenuAction(for status: SMAppService.Status) -> ServiceManagementMenuAction {
    switch status {
    case .notFound, .notRegistered:
        return .register
    case .enabled:
        return .unregister
    case .requiresApproval:
        return .openApprovalSettings
    @unknown default:
        return .none
    }
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private final class ProxySelection: NSObject {
        let groupName: String
        let serverName: String?

        init(groupName: String, serverName: String?) {
            self.groupName = groupName
            self.serverName = serverName
        }
    }

    private let state: GlobalStateVm
    private let updateService: UpdateService
    private let openSettings: () -> Void
    private let statusItem: NSStatusItem
    private let rootMenu = NSMenu()
    private var statusTimer: Timer?
    private var isMenuOpen = false

    init(
        state: GlobalStateVm,
        updateService: UpdateService,
        openSettings: @escaping () -> Void
    ) {
        self.state = state
        self.updateService = updateService
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        rootMenu.autoenablesItems = false
        rootMenu.delegate = self
        statusItem.menu = rootMenu
        updateStatusItem()
        rebuildMenu()

        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(refreshStatusItem),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        statusTimer = timer
    }

    func invalidate() {
        statusTimer?.invalidate()
        statusTimer = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        updateStatusItem()
    }

    @objc private func refreshStatusItem() {
        guard !isMenuOpen else { return }
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        #if DEBUG
        let title = "Seeker (D)"
        let imageName = state.isStarted ? "ant.fill" : "ant"
        #else
        let title = "Seeker"
        let imageName = state.isStarted ? "fish.fill" : "fish"
        #endif

        let image = NSImage(systemSymbolName: imageName, accessibilityDescription: title)
        image?.isTemplate = true
        button.image = image
        button.toolTip = state.isStarted ? "Seeker is running" : "Seeker is stopped"
    }

    private func rebuildMenu() {
        rootMenu.removeAllItems()

        rootMenu.addItem(
            actionItem(
                title: state.isStarted ? "Stop" : "Start",
                action: #selector(toggleSeeker)
            )
        )
        rootMenu.addItem(.separator())
        rootMenu.addItem(proxyGroupsItem())
        rootMenu.addItem(.separator())
        rootMenu.addItem(
            actionItem(title: "Open Settings", action: #selector(showSettings))
        )

        rootMenu.addItem(actionItem(title: "Open Config", action: #selector(openConfig)))
        rootMenu.addItem(actionItem(title: "Open Log", action: #selector(openLog)))
        rootMenu.addItem(actionItem(title: "Open Folder", action: #selector(openFolder)))
        rootMenu.addItem(autoStartItem())
        rootMenu.addItem(daemonItem())
        rootMenu.addItem(.separator())

        #if !DEBUG
        let updateItem = actionItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates)
        )
        updateItem.isEnabled = updateService.canCheckForUpdates
        rootMenu.addItem(updateItem)
        rootMenu.addItem(.separator())
        #endif

        let quitItem = actionItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        rootMenu.addItem(quitItem)
    }

    private func proxyGroupsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Proxy Groups", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Proxy Groups")
        menu.autoenablesItems = false

        if let loadError = state.configService.loadError {
            menu.addItem(disabledItem(title: "Configuration error: \(loadError)"))
        } else if state.configService.menuProxyGroups.isEmpty {
            menu.addItem(disabledItem(title: "No proxy groups configured"))
        } else {
            if state.configService.isDirty {
                menu.addItem(disabledItem(title: "Save or revert settings before switching"))
                menu.addItem(.separator())
            }

            if state.isSwitchingProxy {
                menu.addItem(disabledItem(title: "Restarting Seeker…"))
                menu.addItem(.separator())
            }

            for group in state.configService.menuProxyGroups {
                let groupItem = proxyGroupItem(group)
                groupItem.isEnabled = !state.configService.isDirty && !state.isSwitchingProxy
                menu.addItem(groupItem)
            }
        }

        item.submenu = menu
        return item
    }

    private func proxyGroupItem(_ group: MenuProxyGroup) -> NSMenuItem {
        let item = NSMenuItem(
            title: "\(group.displayName): \(proxyGroupSummary(group))",
            action: nil,
            keyEquivalent: ""
        )
        let menu = NSMenu(title: group.displayName)
        menu.autoenablesItems = false

        let automaticItem = actionItem(
            title: "Automatic",
            action: #selector(selectProxy)
        )
        automaticItem.representedObject = ProxySelection(
            groupName: group.name,
            serverName: nil
        )
        automaticItem.state = group.groupType == .urlTest ? .on : .off
        automaticItem.isEnabled = group.groupType != .urlTest
        menu.addItem(automaticItem)
        menu.addItem(.separator())

        if group.proxies.isEmpty {
            menu.addItem(disabledItem(title: "No servers available"))
        } else {
            for serverName in group.proxies {
                let serverItem = actionItem(
                    title: serverName,
                    action: #selector(selectProxy)
                )
                serverItem.representedObject = ProxySelection(
                    groupName: group.name,
                    serverName: serverName
                )
                serverItem.state = group.selectedServer == serverName ? .on : .off
                serverItem.isEnabled = group.selectedServer != serverName
                menu.addItem(serverItem)
            }
        }

        item.submenu = menu
        return item
    }

    private func proxyGroupSummary(_ group: MenuProxyGroup) -> String {
        if group.groupType == .urlTest {
            return "Automatic"
        }
        return group.selectedServer ?? "First Server"
    }

    private func autoStartItem() -> NSMenuItem {
        let title: String
        switch state.autoStartOnLogin {
        case .enabled:
            title = "Auto Start Enabled"
        case .notFound, .notRegistered:
            title = "Auto Start Disabled"
        case .requiresApproval:
            title = "Auto Start Needs Approval"
        @unknown default:
            title = "Auto Start Unknown"
        }

        let item = actionItem(title: title, action: #selector(toggleAutoStart))
        item.state = state.autoStartOnLogin == .enabled ? .on : .off
        return item
    }

    private func daemonItem() -> NSMenuItem {
        let title: String
        switch state.daemonStatus {
        case .enabled:
            title = "Daemon Registered"
        case .notFound, .notRegistered:
            title = "Daemon Not Registered"
        case .requiresApproval:
            title = "Daemon Needs Approval"
        @unknown default:
            title = "Daemon Status Unknown"
        }

        let item = actionItem(title: title, action: #selector(toggleDaemon))
        item.state = state.daemonStatus == .enabled ? .on : .off
        return item
    }

    private func actionItem(
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func disabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleSeeker() {
        state.toggle()
    }

    @objc private func selectProxy(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? ProxySelection else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let serverName = selection.serverName {
                await state.selectProxy(
                    groupName: selection.groupName,
                    serverName: serverName
                )
            } else {
                await state.useAutomaticProxySelection(groupName: selection.groupName)
            }
            updateStatusItem()
        }
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func checkForUpdates() {
        updateService.checkForUpdates()
    }

    @objc private func openConfig() {
        state.openConfig()
    }

    @objc private func openLog() {
        state.openLog()
    }

    @objc private func openFolder() {
        state.openFolder()
    }

    @objc private func toggleAutoStart() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                switch serviceManagementMenuAction(for: state.autoStartOnLogin) {
                case .register:
                    try state.registerAutoStart()
                case .unregister:
                    try await state.unregisterAutoStart()
                case .openApprovalSettings:
                    SMAppService.openSystemSettingsLoginItems()
                case .none:
                    break
                }
            } catch {
                menuBarLogger.error("register auto start error: \(error)")
            }
        }
    }

    @objc private func toggleDaemon() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                switch serviceManagementMenuAction(for: state.daemonStatus) {
                case .register:
                    try state.registerDaemon()
                    state.daemonStatus = state.statusForDaemon()
                case .unregister:
                    try await state.unregisterDaemon()
                    state.daemonStatus = state.statusForDaemon()
                case .openApprovalSettings:
                    SMAppService.openSystemSettingsLoginItems()
                case .none:
                    break
                }
            } catch {
                menuBarLogger.error("register/unregister daemon error: \(error)")
            }
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
