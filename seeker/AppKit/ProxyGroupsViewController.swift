import AppKit

@MainActor
final class ProxyGroupsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let service: ConfigurationService
    private let onChange: () -> Void
    private let table = NSTableView()
    private let detail = NSView()
    private var selectedName: String?
    private var selectedID: ProxyGroup.ID?

    init(service: ConfigurationService, onChange: @escaping () -> Void) {
        self.service = service
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let left = NSView()
        let scroll = NSScrollView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("group"))
        column.width = 265
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 52
        table.delegate = self
        table.dataSource = self
        table.style = .sourceList
        scroll.documentView = table
        scroll.hasVerticalScroller = true

        let add = CallbackButton(title: "Add") { [weak self] in self?.addGroup() }
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        let remove = CallbackButton(title: "Delete") { [weak self] in self?.deleteGroup() }
        remove.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        let buttons = NSStackView(views: [add, remove, NSView()])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        [scroll, buttons].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            left.addSubview($0)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: left.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -8),
            buttons.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 8),
            buttons.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -8),
            buttons.bottomAnchor.constraint(equalTo: left.bottomAnchor, constant: -8),
            buttons.heightAnchor.constraint(equalToConstant: 30),
        ])

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(left)
        split.addArrangedSubview(detail)
        left.widthAnchor.constraint(equalToConstant: 285).isActive = true
        view = split
        showPlaceholder()
    }

    private var groups: [MenuProxyGroup] { service.menuProxyGroups }

    func numberOfRows(in tableView: NSTableView) -> Int { groups.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let group = groups[row]
        let title = NSTextField(labelWithString: group.displayName)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let mode = group.groupType.displayName
        let selected = group.selectedServer.map { " · \($0)" } ?? ""
        let suffix = group.isMaterialized ? "" : " · implicit"
        let subtitle = NSTextField(labelWithString: "\(group.proxies.count) server(s) · \(mode)\(selected)\(suffix)")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        let cell = NSTableCellView()
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard groups.indices.contains(row) else {
            selectedName = nil
            showPlaceholder()
            return
        }
        selectedName = groups[row].name
        selectedID = service.configuration.proxyGroups.first(where: { $0.name == groups[row].name })?.id
        showGroup(groups[row])
    }

    private func clearDetail() { detail.subviews.forEach { $0.removeFromSuperview() } }

    private func showPlaceholder() {
        clearDetail()
        let label = NSTextField(labelWithString: "Select a proxy group to edit")
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: detail.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: detail.centerYAnchor),
        ])
    }

    @discardableResult
    private func materializedIndex(for name: String) -> Int {
        if let selectedID,
           let index = service.configuration.proxyGroups.firstIndex(where: { $0.id == selectedID }) {
            return index
        }
        if let index = service.configuration.proxyGroups.firstIndex(where: { $0.name == name }) {
            selectedID = service.configuration.proxyGroups[index].id
            return index
        }
        precondition(name.isEmpty)
        service.configuration.proxyGroups.append(
            ProxyGroup(name: "", proxies: service.availableServerNames)
        )
        let index = service.configuration.proxyGroups.count - 1
        selectedID = service.configuration.proxyGroups[index].id
        return index
    }

    private func mutate(name: String, _ mutation: (inout ProxyGroup) -> Void) {
        let index = materializedIndex(for: name)
        mutation(&service.configuration.proxyGroups[index])
        service.markDirty()
        onChange()
        table.reloadData()
    }

    private func showGroup(_ menuGroup: MenuProxyGroup) {
        clearDetail()
        let name = menuGroup.name
        let stored = service.configuration.proxyGroups.first(where: { $0.name == name })
        let group = stored ?? ProxyGroup(
            name: name,
            groupType: menuGroup.groupType,
            defaultSelected: menuGroup.defaultSelected,
            proxies: menuGroup.proxies
        )
        let isDefault = name.isEmpty
        let candidates = isDefault ? service.availableServerNames : group.proxies

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.addArrangedSubview(makeHeader(menuGroup.displayName, detail: isDefault ? "The default group is used by bare PROXY and PROBE rules." : nil))

        let nameControl: NSView
        if isDefault {
            let label = NSTextField(labelWithString: "default")
            label.textColor = .secondaryLabelColor
            nameControl = label
        } else {
            nameControl = CallbackTextField(value: group.name) { [weak self] value in
                guard let self, !value.isEmpty else { return }
                self.mutate(name: name) { $0.name = value }
                self.selectedName = value
            }
        }
        let types = ProxyGroupType.allCases
        let typeControl = CallbackPopUpButton(
            items: types.map(\.displayName),
            selectedIndex: types.firstIndex(of: group.groupType) ?? 0
        ) { [weak self] index in
            guard types.indices.contains(index) else { return }
            self?.mutate(name: name) {
                $0.groupType = types[index]
                if types[index] == .urlTest { $0.defaultSelected = nil }
            }
            if let self, let refreshed = self.groups.first(where: { $0.name == self.selectedName }) {
                self.showGroup(refreshed)
            }
        }
        stack.addArrangedSubview(makeSection("Group", rows: [
            makeFormRow("Name", control: nameControl),
            makeFormRow("Strategy", control: typeControl),
        ]))

        if group.groupType == .select {
            let options = candidates.isEmpty ? ["No servers available"] : candidates
            let current = group.defaultSelected.flatMap { candidates.firstIndex(of: $0) } ?? 0
            let selected = CallbackPopUpButton(items: options, selectedIndex: current) { [weak self] index in
                guard candidates.indices.contains(index) else { return }
                self?.mutate(name: name) { $0.defaultSelected = candidates[index] }
            }
            selected.isEnabled = !candidates.isEmpty
            stack.addArrangedSubview(makeSection("Fixed Selection", rows: [
                makeFormRow("Default Server", control: selected),
            ]))
        }

        if isDefault {
            let serverText = NSTextField(wrappingLabelWithString: candidates.isEmpty ? "No servers available." : candidates.joined(separator: "\n"))
            serverText.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            serverText.textColor = .secondaryLabelColor
            stack.addArrangedSubview(makeSection("Servers · all available servers", rows: [serverText]))
        } else {
            let editor = makeMultilineEditor(text: group.proxies.joined(separator: "\n"), height: 160) { [weak self] value in
                self?.mutate(name: name) { target in
                    target.proxies = nonemptyLines(value)
                    if let selected = target.defaultSelected, !target.proxies.contains(selected) {
                        target.defaultSelected = nil
                    }
                }
            }
            stack.addArrangedSubview(makeSection("Servers (one per line)", rows: [editor]))
        }

        let timeout = CallbackTextField(value: group.pingTimeout ?? "", placeholder: "Use global timeout") { [weak self] value in
            self?.mutate(name: name) { $0.pingTimeout = value.isEmpty ? nil : value }
        }
        let pings = makeMultilineEditor(text: pingUrlsText(group.pingUrls ?? []), height: 110) { [weak self] value in
            self?.mutate(name: name) {
                let urls = parsePingUrls(value)
                $0.pingUrls = urls.isEmpty ? nil : urls
            }
        }
        stack.addArrangedSubview(makeSection("Health Check", rows: [
            makeFormRow("Ping Timeout", control: timeout),
            pings,
            NSTextField(labelWithString: "Ping URLs use host|port|path. Leave empty to use global URLs."),
        ]))

        let scroll = makeFormScrollView(stack: stack)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: detail.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: detail.bottomAnchor),
        ])
    }

    private func addGroup() {
        let name = promptText(window: view.window, title: "Add Proxy Group", message: "Enter a unique group name")
        guard let name, !name.isEmpty,
              !service.configuration.proxyGroups.contains(where: { $0.name == name }) else { return }
        service.addProxyGroup(ProxyGroup(name: name))
        onChange()
        table.reloadData()
        if let row = groups.firstIndex(where: { $0.name == name }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    private func deleteGroup() {
        guard let selectedName,
              let index = service.configuration.proxyGroups.firstIndex(where: { $0.name == selectedName }) else { return }
        service.removeProxyGroup(at: index)
        onChange()
        table.reloadData()
        table.deselectAll(nil)
        self.selectedName = nil
        selectedID = nil
        showPlaceholder()
    }
}
