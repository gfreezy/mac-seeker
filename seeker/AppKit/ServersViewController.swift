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
                self?.mutateLocal(id: id) { $0.protocol = protocols[index] }
                self?.table.reloadData()
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
