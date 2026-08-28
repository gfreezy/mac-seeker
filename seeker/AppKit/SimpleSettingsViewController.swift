import AppKit

@MainActor
final class SimpleSettingsViewController: NSViewController {
    private let section: ConfigSection
    private let service: ConfigurationService
    private let onChange: () -> Void

    init(section: ConfigSection, service: ConfigurationService, onChange: @escaping () -> Void) {
        self.section = section
        self.service = service
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.addArrangedSubview(makeHeader(section.rawValue))

        switch section {
        case .general: buildGeneral(in: stack)
        case .dns: buildDNS(in: stack)
        case .tun: buildTUN(in: stack)
        case .performance: buildPerformance(in: stack)
        case .servers, .groups, .rules: break
        }
        view = makeFormScrollView(stack: stack)
    }

    private func changed(_ mutation: (inout SeekerConfiguration) -> Void) {
        mutation(&service.configuration)
        onChange()
    }

    private func text(_ value: String, placeholder: String = "", update: @escaping (inout SeekerConfiguration, String) -> Void) -> NSTextField {
        CallbackTextField(value: value, placeholder: placeholder) { [weak self] value in
            self?.changed { update(&$0, value) }
        }
    }

    private func buildGeneral(in stack: NSStackView) {
        let config = service.configuration
        stack.addArrangedSubview(makeSection("Logging", rows: [
            makeCheckbox(title: "Verbose Logging", value: config.verbose) { [weak self] value in
                self?.changed { $0.verbose = value }
            },
        ]))
        stack.addArrangedSubview(makeSection("Mode", rows: [
            makeCheckbox(title: "Gateway Mode", value: config.gatewayMode) { [weak self] value in
                self?.changed { $0.gatewayMode = value }
            },
            makeCheckbox(title: "Redir Mode", value: config.redirMode) { [weak self] value in
                self?.changed { $0.redirMode = value }
            },
        ]))
        stack.addArrangedSubview(makeSection("Paths", rows: [
            makeFormRow("Database Path", control: text(config.dbPath) { $0.dbPath = $1 }),
            makeFormRow("GeoIP Database", control: text(config.geoIp) { $0.geoIp = $1 }),
        ]))
        stack.addArrangedSubview(makeSection("API Server", rows: [
            makeFormRow("API Address", control: text(config.apiAddr, placeholder: "127.0.0.1:7890") { $0.apiAddr = $1 }),
        ]))
        let urls = makeMultilineEditor(text: config.remoteConfigUrls.joined(separator: "\n")) { [weak self] value in
            self?.changed { $0.remoteConfigUrls = nonemptyLines(value) }
        }
        stack.addArrangedSubview(makeSection("Remote Clash Config URLs (one per line)", rows: [urls]))
    }

    private func buildDNS(in stack: NSStackView) {
        let config = service.configuration
        stack.addArrangedSubview(makeSection("DNS Settings", rows: [
            makeFormRow("Start IP", control: text(config.dnsStartIp) { $0.dnsStartIp = $1 }),
            makeFormRow("Timeout", control: text(config.dnsTimeout) { $0.dnsTimeout = $1 }),
        ]))
        let servers = makeMultilineEditor(text: config.dnsServers.joined(separator: "\n")) { [weak self] value in
            self?.changed { $0.dnsServers = nonemptyLines(value) }
        }
        let listens = makeMultilineEditor(text: config.dnsListens.joined(separator: "\n")) { [weak self] value in
            self?.changed { $0.dnsListens = nonemptyLines(value) }
        }
        stack.addArrangedSubview(makeSection("DNS Servers (one per line)", rows: [servers]))
        stack.addArrangedSubview(makeSection("DNS Listen Addresses (one per line)", rows: [listens]))
    }

    private func buildTUN(in stack: NSStackView) {
        let config = service.configuration
        stack.addArrangedSubview(makeSection("TUN Device", rows: [
            makeFormRow(
                "Device Name (Optional)",
                control: text(config.tunName, placeholder: "Automatic") { $0.tunName = $1 }
            ),
            makeFormRow("IP Address", control: text(config.tunIp) { $0.tunIp = $1 }),
            makeFormRow("CIDR", control: text(config.tunCidr) { $0.tunCidr = $1 }),
        ]))
        stack.addArrangedSubview(makeSection("Options", rows: [
            makeCheckbox(title: "Bypass Direct Traffic", value: config.tunBypassDirect) { [weak self] value in
                self?.changed { $0.tunBypassDirect = value }
            },
        ]))
    }

    private func buildPerformance(in stack: NSStackView) {
        let config = service.configuration
        func integerField(_ value: Int, range: ClosedRange<Int>, update: @escaping (inout SeekerConfiguration, Int) -> Void) -> NSTextField {
            CallbackTextField(value: String(value)) { [weak self] string in
                guard let number = Int(string), range.contains(number) else { return }
                self?.changed { update(&$0, number) }
            }
        }

        stack.addArrangedSubview(makeSection("Queue Settings (Linux)", rows: [
            makeFormRow("Queue Number", control: integerField(config.queueNumber, range: 1...16) { $0.queueNumber = $1 }),
            makeFormRow("Threads per Queue", control: integerField(config.threadsPerQueue, range: 1...16) { $0.threadsPerQueue = $1 }),
        ]))
        stack.addArrangedSubview(makeSection("Connection Timeouts", rows: [
            makeFormRow("Probe Timeout", control: text(config.probeTimeout) { $0.probeTimeout = $1 }),
            makeFormRow("Ping Timeout", control: text(config.pingTimeout) { $0.pingTimeout = $1 }),
            makeFormRow("Connect Timeout", control: text(config.connectTimeout) { $0.connectTimeout = $1 }),
        ]))
        stack.addArrangedSubview(makeSection("I/O Timeouts", rows: [
            makeFormRow("Read Timeout", control: text(config.readTimeout) { $0.readTimeout = $1 }),
            makeFormRow("Write Timeout", control: text(config.writeTimeout) { $0.writeTimeout = $1 }),
            makeFormRow("Idle Timeout", control: text(config.idleTimeout) { $0.idleTimeout = $1 }),
        ]))
        stack.addArrangedSubview(makeSection("Error Handling", rows: [
            makeFormRow("Max Connect Errors", control: integerField(config.maxConnectErrors, range: 1...10) { $0.maxConnectErrors = $1 }),
        ]))
        let pings = makeMultilineEditor(text: pingUrlsText(config.pingUrls), height: 120) { [weak self] value in
            self?.changed { $0.pingUrls = parsePingUrls(value) }
        }
        stack.addArrangedSubview(makeSection("Ping URLs (host|port|path)", rows: [pings]))
    }
}
