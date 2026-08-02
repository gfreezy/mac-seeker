import AppKit

@MainActor
final class RulesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum ActionKind: String, CaseIterable {
        case direct = "Direct"
        case reject = "Reject"
        case proxy = "Proxy"
        case probe = "Probe"
    }

    private let service: ConfigurationService
    private let onChange: () -> Void
    private let table = NSTableView()
    private let detail = NSView()
    private var selectedIndex: Int?

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
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rule"))
        column.width = 305
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 58
        table.delegate = self
        table.dataSource = self
        table.style = .sourceList
        scroll.documentView = table
        scroll.hasVerticalScroller = true

        let add = CallbackButton(title: "Add") { [weak self] in self?.addRule() }
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        let remove = CallbackButton(title: "Delete") { [weak self] in self?.deleteRule() }
        remove.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        let up = CallbackButton(title: "") { [weak self] in self?.moveRule(offset: -1) }
        up.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Move Up")
        up.toolTip = "Move Up"
        let down = CallbackButton(title: "") { [weak self] in self?.moveRule(offset: 1) }
        down.image = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: "Move Down")
        down.toolTip = "Move Down"
        let buttons = NSStackView(views: [add, remove, NSView(), up, down])
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
        left.widthAnchor.constraint(equalToConstant: 325).isActive = true
        view = split
        showPlaceholder()
    }

    private var rules: [ParsedRule] { service.parsedRules }

    func numberOfRows(in tableView: NSTableView) -> Int { rules.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let rule = rules[row]
        let title = NSTextField(labelWithString: rule.type.displayName)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        let action = NSTextField(labelWithString: rule.action.displayName)
        action.font = .systemFont(ofSize: 11, weight: .semibold)
        action.textColor = .secondaryLabelColor
        let top = NSStackView(views: [title, NSView(), action])
        top.orientation = .horizontal
        let value = NSTextField(labelWithString: rule.value.isEmpty ? rule.toString() : rule.value)
        value.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        value.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [top, value])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        top.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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
        guard rules.indices.contains(row) else {
            selectedIndex = nil
            showPlaceholder()
            return
        }
        selectedIndex = row
        showRule(at: row)
    }

    private func clearDetail() { detail.subviews.forEach { $0.removeFromSuperview() } }

    private func showPlaceholder() {
        clearDetail()
        let label = NSTextField(labelWithString: "Select a rule to edit")
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: detail.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: detail.centerYAnchor),
        ])
    }

    private func mutateRule(at index: Int, _ mutation: (inout ParsedRule) -> Void) {
        var updated = rules
        guard updated.indices.contains(index) else { return }
        mutation(&updated[index])
        service.parsedRules = updated
        onChange()
        table.reloadData()
    }

    private func actionKind(for action: RuleAction) -> ActionKind {
        switch action {
        case .direct: return .direct
        case .reject: return .reject
        case .proxy: return .proxy
        case .probe: return .probe
        }
    }

    private func action(for kind: ActionKind, group: String) -> RuleAction {
        switch kind {
        case .direct: return .direct
        case .reject: return .reject
        case .proxy: return .proxy(groupName: group)
        case .probe: return .probe(groupName: group)
        }
    }

    private func groupName(for action: RuleAction) -> String {
        switch action {
        case .proxy(let name), .probe(let name): return name
        case .direct, .reject: return ""
        }
    }

    private func showRule(at index: Int) {
        guard rules.indices.contains(index) else { return }
        clearDetail()
        let rule = rules[index]
        var currentKind = actionKind(for: rule.action)
        var currentGroup = groupName(for: rule.action)
        var valueControl: CallbackTextField?
        var groupControl: CallbackPopUpButton?
        let preview = NSTextField(wrappingLabelWithString: rule.toString())
        preview.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        preview.textColor = .secondaryLabelColor

        let types = RuleType.allCases
        let typeControl = CallbackPopUpButton(
            items: types.map(\.displayName),
            selectedIndex: types.firstIndex(of: rule.type) ?? 0
        ) { [weak self, weak preview] selected in
            guard types.indices.contains(selected) else { return }
            self?.mutateRule(at: index) {
                $0.type = types[selected]
                if !$0.type.needsValue { $0.value = "" }
                preview?.stringValue = $0.toString()
            }
            valueControl?.isEnabled = types[selected].needsValue
            if !types[selected].needsValue { valueControl?.stringValue = "" }
        }
        let value = CallbackTextField(value: rule.value, placeholder: rule.type.placeholder) { [weak self, weak preview] text in
            self?.mutateRule(at: index) {
                $0.value = text
                preview?.stringValue = $0.toString()
            }
        }
        value.isEnabled = rule.type.needsValue
        valueControl = value

        let actionKinds = ActionKind.allCases
        let actionControl = CallbackPopUpButton(
            items: actionKinds.map(\.rawValue),
            selectedIndex: actionKinds.firstIndex(of: currentKind) ?? 0
        ) { [weak self, weak preview] selected in
            guard actionKinds.indices.contains(selected) else { return }
            currentKind = actionKinds[selected]
            self?.mutateRule(at: index) {
                $0.action = self?.action(for: currentKind, group: currentGroup) ?? .direct
                preview?.stringValue = $0.toString()
            }
            groupControl?.isEnabled = currentKind == .proxy || currentKind == .probe
        }
        let groupNames = [""] + service.availableProxyGroupNames
        let groupPopup = CallbackPopUpButton(
            items: groupNames.map { $0.isEmpty ? "default" : $0 },
            selectedIndex: groupNames.firstIndex(of: currentGroup) ?? 0
        ) { [weak self, weak preview] selected in
            guard groupNames.indices.contains(selected) else { return }
            currentGroup = groupNames[selected]
            self?.mutateRule(at: index) {
                $0.action = self?.action(for: currentKind, group: currentGroup) ?? .direct
                preview?.stringValue = $0.toString()
            }
        }
        groupPopup.isEnabled = currentKind == .proxy || currentKind == .probe
        groupControl = groupPopup

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.addArrangedSubview(makeHeader("Rule \(index + 1)"))
        stack.addArrangedSubview(makeSection("Match", rows: [
            makeFormRow("Type", control: typeControl),
            makeFormRow("Value", control: value),
        ]))
        stack.addArrangedSubview(makeSection("Action", rows: [
            makeFormRow("Action", control: actionControl),
            makeFormRow("Proxy Group", control: groupPopup),
        ]))
        stack.addArrangedSubview(makeSection("Preview", rows: [preview]))

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

    private func addRule() {
        var updated = rules
        let rule = ParsedRule(type: .match, value: "", action: .direct)
        let insertion = min((selectedIndex ?? (updated.count - 1)) + 1, updated.count)
        updated.insert(rule, at: max(0, insertion))
        service.parsedRules = updated
        onChange()
        table.reloadData()
        selectedIndex = max(0, insertion)
        table.selectRowIndexes(IndexSet(integer: max(0, insertion)), byExtendingSelection: false)
    }

    private func deleteRule() {
        guard let selectedIndex, rules.indices.contains(selectedIndex) else { return }
        service.removeRule(at: selectedIndex)
        onChange()
        table.reloadData()
        self.selectedIndex = nil
        table.deselectAll(nil)
        showPlaceholder()
    }

    private func moveRule(offset: Int) {
        guard let selectedIndex else { return }
        let destination = selectedIndex + offset
        guard rules.indices.contains(destination) else { return }
        var updated = rules
        updated.swapAt(selectedIndex, destination)
        service.parsedRules = updated
        onChange()
        self.selectedIndex = destination
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: destination), byExtendingSelection: false)
        table.scrollRowToVisible(destination)
    }
}
