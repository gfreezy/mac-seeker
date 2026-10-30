import AppKit

@MainActor
final class ServersViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let service: ConfigurationService
    private let serverStats: [String: ApiServerStats]
    private let onChange: () -> Void
    private let table = NSTableView()
    private let detail = NSView()
    private var selectedID: ProxyServer.ID?

    init(service: ConfigurationService, serverStats: [String: ApiServerStats], onChange: @escaping () -> Void) {
        self.service = service
        self.serverStats = serverStats
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        let left = NSView()
        let scroll = NSScrollView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("server"))
        column.width = 265
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 52
        table.delegate = self
        table.dataSource = self
        table.style = .plain
        table.backgroundColor = .windowBackgroundColor
        table.usesAlternatingRowBackgroundColors = false
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .windowBackgroundColor
        scroll.contentView.drawsBackground = true
        scroll.contentView.backgroundColor = .windowBackgroundColor

        let add = CallbackButton(title: "Add") { [weak self] in self?.addServer() }
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        let remove = CallbackButton(title: "Delete") { [weak self] in self?.deleteServer() }
        remove.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        let refresh = CallbackButton(title: "Refresh") { [weak self] in self?.refreshRemote() }
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        let buttons = NSStackView(views: [add, remove, NSView(), refresh])
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

    func numberOfRows(in tableView: NSTableView) -> Int { service.allServers.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let server = service.allServers[row]
        let title = NSTextField(labelWithString: server.name.isEmpty ? "(unnamed)" : server.name)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        let source = server.source.isRemote ? "Remote · \(server.protocol.displayName)" : "Local · \(server.protocol.displayName)"
        let subtitle = NSTextField(labelWithString: "\(source)  \(server.addr)")
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
        guard service.allServers.indices.contains(row) else {
            selectedID = nil
            showPlaceholder()
            return
        }
        selectedID = service.allServers[row].id
        showServer(service.allServers[row])
    }

    private func mutateLocal(id: ProxyServer.ID, _ mutation: (inout ProxyServer) -> Void) {
        guard let index = service.configuration.servers.firstIndex(where: { $0.id == id }) else { return }
        mutation(&service.configuration.servers[index])
        service.markDirty()
        onChange()
    }

    private func clearDetail() {
        detail.subviews.forEach { $0.removeFromSuperview() }
    }

    private func showPlaceholder() {
        clearDetail()
        let label = NSTextField(labelWithString: "Select a server to edit")
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: detail.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: detail.centerYAnchor),
        ])
    }

    private func showServer(_ server: ProxyServer) {
        clearDetail()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.addArrangedSubview(makeHeader(server.name.isEmpty ? "Unnamed Server" : server.name, detail: server.source.isRemote ? "Remote configuration · read only" : "Local server"))

        if server.source.isRemote {
            stack.addArrangedSubview(makeSection("Connection", rows: [
                makeFormRow("Name", control: NSTextField(labelWithString: server.name)),
                makeFormRow("Address", control: NSTextField(labelWithString: server.addr)),
                makeFormRow("Protocol", control: NSTextField(labelWithString: server.protocol.displayName)),
            ]))
            if server.protocol == .hysteria2 {
                stack.addArrangedSubview(makeMimicSection(server))
            }
        } else {
            let id = server.id
            let name = CallbackTextField(value: server.name) { [weak self] value in
                self?.mutateLocal(id: id) { $0.name = value }
                self?.table.reloadData()
            }
            let address = CallbackTextField(value: server.addr, placeholder: "host:port") { [weak self] value in
                self?.mutateLocal(id: id) { $0.addr = value }
            }
            let protocols = ProxyProtocol.allCases
            let proto = CallbackPopUpButton(
                items: protocols.map(\.displayName),
                selectedIndex: protocols.firstIndex(of: server.protocol) ?? 0
            ) { [weak self] index in
                guard protocols.indices.contains(index) else { return }
                self?.mutateLocal(id: id) {
                    $0.protocol = protocols[index]
                    if $0.protocol != .hysteria2 { $0.mimic = nil }
                }
                self?.table.reloadData()
                if let updated = self?.service.configuration.servers.first(where: { $0.id == id }) {
                    self?.showServer(updated)
                }
            }
            stack.addArrangedSubview(makeSection("Connection", rows: [
                makeFormRow("Name", control: name),
                makeFormRow("Address", control: address),
                makeFormRow("Protocol", control: proto),
            ]))

            func optionalField(_ label: String, value: String?, update: @escaping (inout ProxyServer, String?) -> Void) -> NSView {
                let field = CallbackTextField(value: value ?? "") { [weak self] text in
                    self?.mutateLocal(id: id) { update(&$0, text.isEmpty ? nil : text) }
                }
                return makeFormRow(label, control: field)
            }
            stack.addArrangedSubview(makeSection("Authentication", rows: [
                optionalField("Username / UUID", value: server.username) { $0.username = $1 },
                optionalField("Password", value: server.password) { $0.password = $1 },
            ]))
            stack.addArrangedSubview(makeSection("Protocol Options", rows: [
                optionalField("Method / Cipher", value: server.method) { $0.method = $1 },
                optionalField("SNI", value: server.sni) { $0.sni = $1 },
                optionalField("Obfs Password", value: server.obfsPassword) { $0.obfsPassword = $1 },
                optionalField("VMess Security", value: server.vmessSecurity) { $0.vmessSecurity = $1 },
                optionalField("VLESS Flow", value: server.flow) { $0.flow = $1 },
                optionalField("Receive Window", value: server.recvWindow.map(String.init)) { target, value in
                    target.recvWindow = value.flatMap(UInt64.init)
                },
                makeCheckbox(title: "Skip certificate verification", value: server.insecure == true) { [weak self] value in
                    self?.mutateLocal(id: id) { $0.insecure = value ? true : nil }
                },
            ]))
            stack.addArrangedSubview(makeSection("Obfuscation", rows: [
                optionalField("Mode", value: server.obfs?.mode) { target, value in
                    if let value {
                        var obfs = target.obfs ?? ObfsConfig()
                        obfs.mode = value
                        target.obfs = obfs
                    } else if target.obfs?.host.isEmpty != false {
                        target.obfs = nil
                    }
                },
                optionalField("Host", value: server.obfs?.host) { target, value in
                    if let value {
                        var obfs = target.obfs ?? ObfsConfig()
                        obfs.host = value
                        target.obfs = obfs
                    } else if target.obfs?.mode.isEmpty != false {
                        target.obfs = nil
                    } else {
                        target.obfs?.host = ""
                    }
                },
            ]))
            if server.protocol == .hysteria2 {
                stack.addArrangedSubview(makeMimicSection(server))
            }
        }

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

    private func makeMimicSection(_ server: ProxyServer) -> NSView {
        let config = server.mimic
        if server.source.isRemote {
            let padding: String
            switch config?.padding {
            case .some(.fixed(let bytes)): padding = "\(bytes) bytes"
            case .some(.random): padding = "Random"
            case .none: padding = "Default (0 bytes)"
            }
            return makeSection("Mimic", rows: [
                makeFormRow("Enabled", control: NSTextField(labelWithString: config?.enabled == true ? "Yes" : "No")),
                makeFormRow("Interface", control: NSTextField(labelWithString: config?.interface ?? "Automatic")),
                makeFormRow("TUN Device", control: NSTextField(labelWithString: config?.tunName ?? "Automatic")),
                makeFormRow("MTU", control: NSTextField(labelWithString: config?.mtu.map(String.init) ?? "1500 (default)")),
                makeFormRow("Padding", control: NSTextField(labelWithString: padding)),
            ])
        }

        let id = server.id
        let error = NSTextField(wrappingLabelWithString: config?.validationError ?? "")
        error.textColor = .systemRed
        error.font = .systemFont(ofSize: 12)
        error.isHidden = error.stringValue.isEmpty

        let update: ((inout MimicConfig) -> Void) -> Void = { [weak self, weak error] mutation in
            guard let self else { return }
            self.mutateLocal(id: id) {
                var mimic = $0.mimic ?? MimicConfig()
                mutation(&mimic)
                $0.mimic = mimic
            }
            let current = self.service.configuration.servers.first { $0.id == id }
            error?.stringValue = current?.mimic?.validationError ?? ""
            error?.isHidden = error?.stringValue.isEmpty != false
        }

        let enabled = makeCheckbox(title: "Enable Mimic", value: config?.enabled == true) { value in
            update { $0.enabled = value }
        }
        enabled.setAccessibilityIdentifier("mimic.enabled")

        let interface = CallbackTextField(value: config?.interface ?? "", placeholder: "Automatic") { value in
            let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            update { $0.interface = name.isEmpty ? nil : name }
        }
        interface.setAccessibilityIdentifier("mimic.interface")

        let tunName = CallbackTextField(value: config?.tunName ?? "", placeholder: "Automatic, e.g. utun42") { value in
            let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            update { $0.tunName = name.isEmpty ? nil : name }
        }
        tunName.setAccessibilityIdentifier("mimic.tun_name")

        let mtu = CallbackTextField(value: config?.mtu.map(String.init) ?? "", placeholder: "1500 (default)") { value in
            let number = value.trimmingCharacters(in: .whitespacesAndNewlines)
            update { $0.mtu = number.isEmpty ? nil : (Int(number) ?? 0) }
        }
        mtu.setAccessibilityIdentifier("mimic.mtu")

        var paddingValues: [MimicPadding?] = [nil]
        paddingValues.append(contentsOf: (0...16).map { MimicPadding.fixed(UInt8($0)) })
        paddingValues.append(MimicPadding.random)
        var paddingLabels = ["Default (0 bytes)"] + (0...16).map { "\($0) bytes" } + ["Random"]
        if let padding = config?.padding, !paddingValues.contains(padding) {
            paddingValues.append(padding)
            if case .fixed(let bytes) = padding { paddingLabels.append("\(bytes) bytes (invalid)") }
        }
        let paddingOptions = paddingValues
        let padding = CallbackPopUpButton(
            items: paddingLabels, selectedIndex: paddingOptions.firstIndex(of: config?.padding) ?? 0
        ) { index in
            guard paddingOptions.indices.contains(index) else { return }
            update { $0.padding = paddingOptions[index] }
        }
        padding.setAccessibilityIdentifier("mimic.padding")

        let help = NSTextField(wrappingLabelWithString: "The server must also use Mimic. Leave interface, TUN device, and MTU blank to use automatic or default settings.")
        help.textColor = .secondaryLabelColor
        help.font = .systemFont(ofSize: 12)
        return makeSection("Mimic", rows: [
            enabled,
            help,
            makeFormRow("Interface", control: interface, help: "Physical outbound interface, for example en0. Automatic uses the route to the server."),
            makeFormRow("TUN Device", control: tunName, help: "A dedicated Mimic TUN device. Leave blank to choose an unused device automatically."),
            makeFormRow("MTU", control: mtu, help: "1280–9000 bytes. Default: 1500."),
            makeFormRow("Padding", control: padding, help: "Must match the server: 0–16 bytes, or Random."),
            error,
        ])
    }

    private func addServer() {
        let name = promptText(window: view.window, title: "Add Server", message: "Enter a unique server name")
        guard let name, !name.isEmpty else { return }
        let server = ProxyServer(name: name, addr: "127.0.0.1:1080", protocol: .http)
        service.addServer(server)
        onChange()
        table.reloadData()
        if let row = service.allServers.firstIndex(where: { $0.id == server.id }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
    }

    private func deleteServer() {
        guard let selectedID,
              let index = service.configuration.servers.firstIndex(where: { $0.id == selectedID }) else { return }
        service.removeServer(at: index)
        onChange()
        self.selectedID = nil
        table.reloadData()
        table.deselectAll(nil)
        showPlaceholder()
    }

    private func refreshRemote() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.service.refreshRemoteServers()
            self.table.reloadData()
        }
    }
}
