import AppKit

enum ConfigSection: String, CaseIterable {
    case general = "General"
    case dns = "DNS"
    case tun = "TUN Device"
    case performance = "Performance"
    case servers = "Servers"
    case groups = "Proxy Groups"
    case rules = "Rules"

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .dns: return "network"
        case .tun: return "rectangle.connected.to.line.below"
        case .performance: return "gauge.with.dots.needle.bottom.50percent"
        case .servers: return "server.rack"
        case .groups: return "square.stack.3d.up"
        case .rules: return "list.bullet.rectangle"
        }
    }
}

@MainActor
final class SettingsWindowController {
    private let state: GlobalStateVm
    private var windowController: NSWindowController?

    init(state: GlobalStateVm) {
        self.state = state
    }

    func show() {
        let controller = windowController ?? makeWindowController()
        windowController = controller
        controller.showWindow(nil)
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        if let window = controller.window, let screen = activeScreen ?? NSScreen.main ?? window.screen {
            let visible = screen.visibleFrame
            let width = min(1100, visible.width)
            let height = min(750, visible.height)
            let frame = NSRect(
                x: visible.midX - width / 2,
                y: visible.midY - height / 2,
                width: width,
                height: height
            )
            window.setFrame(frame, display: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            controller.window?.makeKeyAndOrderFront(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func makeWindowController() -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentViewController = SettingsViewController(state: state)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.minSize = NSSize(width: 760, height: 540)
        window.tabbingMode = .disallowed
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.center()

        let controller = NSWindowController(window: window)
        controller.shouldCascadeWindows = false
        return controller
    }
}

@MainActor
final class SettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let state: GlobalStateVm
    private var service: ConfigurationService { state.configService }
    private let sidebar = NSTableView()
    private let detailContainer = NSView()
    private let reloadButton = NSButton()
    private let saveButton = NSButton()
    private var contentController: NSViewController?
    private var selectedSection: ConfigSection = .general

    init(state: GlobalStateVm) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()

        let toolbar = makeToolbar()
        let sidebarScroll = makeSidebar()
        let divider = NSBox()
        divider.boxType = .separator

        [toolbar, sidebarScroll, divider, detailContainer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 56),

            sidebarScroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            sidebarScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarScroll.widthAnchor.constraint(equalToConstant: 210),

            divider.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            detailContainer.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            detailContainer.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        sidebar.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        showSection(.general)
        updateButtons()
    }

    private func makeToolbar() -> NSView {
        let container = NSVisualEffectView()
        container.material = .headerView
        container.blendingMode = .withinWindow

        let title = NSTextField(labelWithString: "Settings")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        reloadButton.title = "Reload"
        reloadButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        reloadButton.bezelStyle = .rounded
        reloadButton.target = self
        reloadButton.action = #selector(reloadConfiguration)

        saveButton.title = "Save"
        saveButton.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = [.command]
        saveButton.target = self
        saveButton.action = #selector(saveConfiguration)

        let stack = NSStackView(views: [title, NSView(), reloadButton, saveButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func makeSidebar() -> NSScrollView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        column.width = 208
        sidebar.addTableColumn(column)
        sidebar.headerView = nil
        sidebar.rowHeight = 42
        sidebar.backgroundColor = .clear
        sidebar.style = .sourceList
        sidebar.dataSource = self
        sidebar.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = sidebar
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .windowBackgroundColor
        return scroll
    }

    func numberOfRows(in tableView: NSTableView) -> Int { ConfigSection.allCases.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let section = ConfigSection.allCases[row]
        let cell = NSTableCellView()
        let image = NSImageView(image: NSImage(systemSymbolName: section.iconName, accessibilityDescription: nil) ?? NSImage())
        image.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        let label = NSTextField(labelWithString: section.rawValue)
        label.font = .systemFont(ofSize: 14)
        let stack = NSStackView(views: [image, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 22),
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebar.selectedRow
        guard ConfigSection.allCases.indices.contains(row) else { return }
        showSection(ConfigSection.allCases[row])
    }

    private func showSection(_ section: ConfigSection) {
        selectedSection = section
        contentController?.view.removeFromSuperview()
        contentController?.removeFromParent()

        let changeHandler: () -> Void = { [weak self] in self?.configurationDidChange() }
        let controller: NSViewController
        switch section {
        case .general, .dns, .tun, .performance:
            controller = SimpleSettingsViewController(section: section, service: service, onChange: changeHandler)
        case .servers:
            controller = ServersViewController(service: service, serverStats: state.serverStats, onChange: changeHandler)
        case .groups:
            controller = ProxyGroupsViewController(service: service, onChange: changeHandler)
        case .rules:
            controller = RulesViewController(service: service, onChange: changeHandler)
        }

        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
        ])
        contentController = controller
    }

    private func configurationDidChange() {
        service.markDirty()
        updateButtons()
    }

    private func updateButtons() {
        reloadButton.title = service.isDirty ? "Revert" : "Reload"
        saveButton.isEnabled = service.isDirty
    }

    @objc private func reloadConfiguration() {
        do {
            if service.isDirty {
                service.revert()
            } else {
                try service.reload()
            }
            showSection(selectedSection)
            updateButtons()
        } catch {
            showAlert(title: "Configuration", message: "Failed to reload configuration: \(error.localizedDescription)")
        }
    }

    @objc private func saveConfiguration() {
        let onlyRules = service.onlyRulesChanged()
        do {
            try service.save()
            updateButtons()
            if onlyRules {
                showAlert(title: "Saved", message: "Rules saved and applied automatically.")
            } else {
                showRestartAlert()
            }
        } catch {
            showAlert(title: "Configuration", message: "Failed to save configuration: \(error.localizedDescription)")
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func showRestartAlert() {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "Configuration saved. Restart Seeker to apply changes."
        if state.isStarted {
            alert.addButton(withTitle: "Restart Now")
            alert.addButton(withTitle: "Later")
        } else {
            alert.addButton(withTitle: "OK")
        }

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn, self?.state.isStarted == true else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.state.stop()
                try? await Task.sleep(for: .milliseconds(500))
                do {
                    try await self.state.start()
                } catch {
                    self.showAlert(title: "Restart Failed", message: error.localizedDescription)
                }
            }
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}
