import Foundation

// MARK: - Main Configuration Model

struct SeekerConfiguration: Codable, Equatable {
    // Basic settings
    var verbose: Bool = false
    var dnsStartIp: String = "11.0.0.10"
    var dnsServers: [String] = []
    var dnsTimeout: String = "1s"
    var dnsListens: [String] = []

    // TUN Device
    var tunName: String = "utun4"
    var tunIp: String = "11.0.0.1"
    var tunCidr: String = "11.0.0.0/16"
    var tunBypassDirect: Bool = true

    // Mode settings
    var gatewayMode: Bool = false
    var redirMode: Bool = false

    // Performance settings
    var queueNumber: Int = 2
    var threadsPerQueue: Int = 3
    var probeTimeout: String = "200ms"
    var pingTimeout: String = "2s"
    var connectTimeout: String = "2s"
    var readTimeout: String = "300s"
    var writeTimeout: String = "300s"
    var maxConnectErrors: Int = 2

    // Paths
    var dbPath: String = "seeker.sqlite"
    var geoIp: String = ""

    // Ping URLs
    var pingUrls: [PingUrl] = []

    // Remote config URLs
    var remoteConfigUrls: [String] = []

    // Servers, proxy groups, and rules
    var servers: [ProxyServer] = []
    var proxyGroups: [ProxyGroup] = []
    var rules: [String] = []

    // Additional fields that may exist in config
    var idleTimeout: String = "300s"

    enum CodingKeys: String, CodingKey {
        case verbose
        case dnsStartIp = "dns_start_ip"
        case dnsServers = "dns_servers"
        case dnsTimeout = "dns_timeout"
        case dnsListens = "dns_listens"
        case dnsListen = "dns_listen"  // Alternative singular form
        case tunName = "tun_name"
        case tunIp = "tun_ip"
        case tunCidr = "tun_cidr"
        case tunBypassDirect = "tun_bypass_direct"
        case gatewayMode = "gateway_mode"
        case redirMode = "redir_mode"
        case queueNumber = "queue_number"
        case threadsPerQueue = "threads_per_queue"
        case probeTimeout = "probe_timeout"
        case pingTimeout = "ping_timeout"
        case connectTimeout = "connect_timeout"
        case readTimeout = "read_timeout"
        case writeTimeout = "write_timeout"
        case idleTimeout = "idle_timeout"
        case maxConnectErrors = "max_connect_errors"
        case dbPath = "db_path"
        case geoIp = "geo_ip"
        case pingUrls = "ping_urls"
        case remoteConfigUrls = "remote_config_urls"
        case servers
        case proxyGroups = "proxy_groups"
        case rules
    }

    init() {}

    /// Creates a default configuration with sensible defaults
    static func defaultConfiguration() -> SeekerConfiguration {
        var config = SeekerConfiguration()
        config.dnsServers = ["223.5.5.5:53", "114.114.114.114:53"]
        config.dnsListens = ["0.0.0.0:53"]
        config.pingUrls = [
            PingUrl(host: "www.google.com", port: 80, path: "/"),
            PingUrl(host: "www.youtube.com", port: 80, path: "/")
        ]
        return config
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        verbose = try container.decodeIfPresent(Bool.self, forKey: .verbose) ?? false
        dnsStartIp = try container.decodeIfPresent(String.self, forKey: .dnsStartIp) ?? "11.0.0.10"
        dnsServers = try container.decodeIfPresent([String].self, forKey: .dnsServers) ?? []
        dnsTimeout = try container.decodeIfPresent(String.self, forKey: .dnsTimeout) ?? "1s"

        // Handle both dns_listens (array) and dns_listen (single string)
        if let listens = try container.decodeIfPresent([String].self, forKey: .dnsListens) {
            dnsListens = listens
        } else if let listen = try container.decodeIfPresent(String.self, forKey: .dnsListen) {
            dnsListens = [listen]
        } else {
            dnsListens = []
        }

        tunName = try container.decodeIfPresent(String.self, forKey: .tunName) ?? "utun4"
        tunIp = try container.decodeIfPresent(String.self, forKey: .tunIp) ?? "11.0.0.1"
        tunCidr = try container.decodeIfPresent(String.self, forKey: .tunCidr) ?? "11.0.0.0/16"
        tunBypassDirect = try container.decodeIfPresent(Bool.self, forKey: .tunBypassDirect) ?? true

        gatewayMode = try container.decodeIfPresent(Bool.self, forKey: .gatewayMode) ?? false
        redirMode = try container.decodeIfPresent(Bool.self, forKey: .redirMode) ?? false

        queueNumber = try container.decodeIfPresent(Int.self, forKey: .queueNumber) ?? 2
        threadsPerQueue = try container.decodeIfPresent(Int.self, forKey: .threadsPerQueue) ?? 3
        probeTimeout = try container.decodeIfPresent(String.self, forKey: .probeTimeout) ?? "200ms"
        pingTimeout = try container.decodeIfPresent(String.self, forKey: .pingTimeout) ?? "2s"
        connectTimeout = try container.decodeIfPresent(String.self, forKey: .connectTimeout) ?? "2s"
        readTimeout = try container.decodeIfPresent(String.self, forKey: .readTimeout) ?? "300s"
        writeTimeout = try container.decodeIfPresent(String.self, forKey: .writeTimeout) ?? "300s"
        idleTimeout = try container.decodeIfPresent(String.self, forKey: .idleTimeout) ?? "300s"
        maxConnectErrors = try container.decodeIfPresent(Int.self, forKey: .maxConnectErrors) ?? 2

        dbPath = try container.decodeIfPresent(String.self, forKey: .dbPath) ?? "seeker.sqlite"
        geoIp = try container.decodeIfPresent(String.self, forKey: .geoIp) ?? ""

        pingUrls = try container.decodeIfPresent([PingUrl].self, forKey: .pingUrls) ?? []
        remoteConfigUrls = try container.decodeIfPresent([String].self, forKey: .remoteConfigUrls) ?? []

        servers = try container.decodeIfPresent([ProxyServer].self, forKey: .servers) ?? []
        proxyGroups = try container.decodeIfPresent([ProxyGroup].self, forKey: .proxyGroups) ?? []
        rules = try container.decodeIfPresent([String].self, forKey: .rules) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(verbose, forKey: .verbose)
        try container.encode(dnsStartIp, forKey: .dnsStartIp)
        try container.encode(dnsServers, forKey: .dnsServers)
        try container.encode(dnsTimeout, forKey: .dnsTimeout)
        try container.encode(dnsListens, forKey: .dnsListens)

        try container.encode(tunName, forKey: .tunName)
        try container.encode(tunIp, forKey: .tunIp)
        try container.encode(tunCidr, forKey: .tunCidr)
        try container.encode(tunBypassDirect, forKey: .tunBypassDirect)

        try container.encode(gatewayMode, forKey: .gatewayMode)
        try container.encode(redirMode, forKey: .redirMode)

        try container.encode(queueNumber, forKey: .queueNumber)
        try container.encode(threadsPerQueue, forKey: .threadsPerQueue)
        try container.encode(probeTimeout, forKey: .probeTimeout)
        try container.encode(pingTimeout, forKey: .pingTimeout)
        try container.encode(connectTimeout, forKey: .connectTimeout)
        try container.encode(readTimeout, forKey: .readTimeout)
        try container.encode(writeTimeout, forKey: .writeTimeout)
        try container.encode(idleTimeout, forKey: .idleTimeout)
        try container.encode(maxConnectErrors, forKey: .maxConnectErrors)

        try container.encode(dbPath, forKey: .dbPath)
        try container.encode(geoIp, forKey: .geoIp)

        try container.encode(pingUrls, forKey: .pingUrls)
        try container.encode(remoteConfigUrls, forKey: .remoteConfigUrls)

        try container.encode(servers, forKey: .servers)
        try container.encode(proxyGroups, forKey: .proxyGroups)
        try container.encode(rules, forKey: .rules)
    }
}

// MARK: - Ping URL

struct PingUrl: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var host: String = ""
    var port: Int = 80
    var path: String = "/"

    enum CodingKeys: String, CodingKey {
        case host, port, path
    }

    /// Display string for UI (e.g., "example.com:80/path")
    var displayString: String {
        let portPart = port == 80 ? "" : ":\(port)"
        return "\(host)\(portPart)\(path)"
    }

    init(host: String = "", port: Int = 80, path: String = "/") {
        self.host = host
        self.port = port
        self.path = path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        path = try container.decode(String.self, forKey: .path)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(path, forKey: .path)
    }
}

// MARK: - Server Source

enum ServerSource: Equatable, Hashable, Codable {
    case local
    case remote(url: String)

    var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }
}

// MARK: - Proxy Server

struct ProxyServer: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var addr: String = ""
    var username: String?
    var password: String?
    var `protocol`: ProxyProtocol = .http
    var method: String?
    var obfs: ObfsConfig?

    // Source tracking (not persisted to YAML)
    var source: ServerSource = .local

    enum CodingKeys: String, CodingKey {
        case name, addr, username, password
        case `protocol` = "protocol"
        case method, obfs
        // Clash format alternatives
        case type, server, port, cipher
        // Note: source is not included - it's runtime only
    }

    init(
        name: String = "", addr: String = "", username: String? = nil,
        password: String? = nil, protocol: ProxyProtocol = .http,
        method: String? = nil, obfs: ObfsConfig? = nil,
        source: ServerSource = .local
    ) {
        self.name = name
        self.addr = addr
        self.username = username
        self.password = password
        self.protocol = `protocol`
        self.method = method
        self.obfs = obfs
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)

        // Handle both Seeker format (addr) and Clash format (server:port or server + port)
        if let addrValue = try container.decodeIfPresent(String.self, forKey: .addr) {
            addr = addrValue
        } else if let server = try container.decodeIfPresent(String.self, forKey: .server) {
            // Clash format: server might already contain port, or port is separate
            if server.contains(":") {
                addr = server
            } else if let port = try container.decodeIfPresent(Int.self, forKey: .port) {
                addr = "\(server):\(port)"
            } else {
                addr = server
            }
        } else {
            addr = ""
        }

        username = try container.decodeIfPresent(String.self, forKey: .username)
        password = try container.decodeIfPresent(String.self, forKey: .password)

        // Handle both "protocol" and "type" keys
        if let proto = try container.decodeIfPresent(ProxyProtocol.self, forKey: .protocol) {
            `protocol` = proto
        } else if let typeStr = try container.decodeIfPresent(String.self, forKey: .type) {
            `protocol` = ProxyProtocol(fromClashType: typeStr)
        } else {
            `protocol` = .http
        }

        // Handle both "method" and "cipher" keys
        if let m = try container.decodeIfPresent(String.self, forKey: .method) {
            method = m
        } else if let c = try container.decodeIfPresent(String.self, forKey: .cipher) {
            method = c
        } else {
            method = nil
        }

        obfs = try container.decodeIfPresent(ObfsConfig.self, forKey: .obfs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(addr, forKey: .addr)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(password, forKey: .password)
        try container.encode(`protocol`, forKey: .protocol)
        try container.encodeIfPresent(method, forKey: .method)
        try container.encodeIfPresent(obfs, forKey: .obfs)
    }
}

enum ProxyProtocol: String, Codable, CaseIterable, Hashable {
    case http = "Http"
    case https = "Https"
    case socks5 = "Socks5"
    case shadowsocks = "Shadowsocks"

    var displayName: String {
        switch self {
        case .http: return "HTTP"
        case .https: return "HTTPS"
        case .socks5: return "SOCKS5"
        case .shadowsocks: return "Shadowsocks"
        }
    }

    /// Initialize from Clash-style type string (e.g., "ss", "socks5", "http")
    init(fromClashType type: String) {
        switch type.lowercased() {
        case "ss", "shadowsocks":
            self = .shadowsocks
        case "socks5", "socks":
            self = .socks5
        case "https":
            self = .https
        case "http":
            self = .http
        default:
            self = .http
        }
    }
}

enum ShadowsocksMethod: String, CaseIterable {
    case chacha20IetfPoly1305 = "chacha20-ietf-poly1305"
    case aes256Gcm = "aes-256-gcm"
    case aes128Gcm = "aes-128-gcm"
    case chacha20Ietf = "chacha20-ietf"
    case aes256Cfb = "aes-256-cfb"
    case aes128Cfb = "aes-128-cfb"
    case rc4Md5 = "rc4-md5"
    case plain = "plain"

    var displayName: String { rawValue }

    init?(from string: String?) {
        guard let string = string else { return nil }
        if let method = ShadowsocksMethod(rawValue: string) {
            self = method
        } else {
            return nil
        }
    }
}

struct ObfsConfig: Codable, Equatable, Hashable {
    var mode: String = "Http"
    var host: String = ""
}

// MARK: - Proxy Group

struct ProxyGroup: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var proxies: [String] = []
    var pingUrls: [PingUrl]?
    var pingTimeout: String?

    enum CodingKeys: String, CodingKey {
        case name, proxies
        case pingUrls = "ping_urls"
        case pingTimeout = "ping_timeout"
    }

    init(
        name: String = "", proxies: [String] = [],
        pingUrls: [PingUrl]? = nil, pingTimeout: String? = nil
    ) {
        self.name = name
        self.proxies = proxies
        self.pingUrls = pingUrls
        self.pingTimeout = pingTimeout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        proxies = try container.decode([String].self, forKey: .proxies)
        pingUrls = try container.decodeIfPresent([PingUrl].self, forKey: .pingUrls)
        pingTimeout = try container.decodeIfPresent(String.self, forKey: .pingTimeout)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(proxies, forKey: .proxies)
        try container.encodeIfPresent(pingUrls, forKey: .pingUrls)
        try container.encodeIfPresent(pingTimeout, forKey: .pingTimeout)
    }
}

// MARK: - Rule Types

enum RuleType: String, CaseIterable {
    case domain = "DOMAIN"
    case domainSuffix = "DOMAIN-SUFFIX"
    case domainKeyword = "DOMAIN-KEYWORD"
    case ipCidr = "IP-CIDR"
    case geoip = "GEOIP"
    case match = "MATCH"

    var displayName: String {
        switch self {
        case .domain: return "Domain (Exact)"
        case .domainSuffix: return "Domain Suffix"
        case .domainKeyword: return "Domain Keyword"
        case .ipCidr: return "IP CIDR"
        case .geoip: return "GeoIP"
        case .match: return "Default Match"
        }
    }

    var needsValue: Bool { self != .match }

    var placeholder: String {
        switch self {
        case .domain: return "example.com"
        case .domainSuffix: return "example.com"
        case .domainKeyword: return "keyword"
        case .ipCidr: return "192.168.0.0/24"
        case .geoip: return "CN"
        case .match: return ""
        }
    }
}

enum RuleAction: Equatable, Hashable {
    case direct
    case reject
    case proxy(groupName: String)
    case probe(groupName: String)

    init(from string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed == "DIRECT" {
            self = .direct
        } else if trimmed == "REJECT" {
            self = .reject
        } else if trimmed == "PROXY" {
            // PROXY without parentheses = proxy with empty group
            self = .proxy(groupName: "")
        } else if trimmed.hasPrefix("PROXY(") && trimmed.hasSuffix(")") {
            let groupName = String(trimmed.dropFirst(6).dropLast())
            self = .proxy(groupName: groupName)
        } else if trimmed == "PROBE" {
            // PROBE without parentheses = probe with empty group
            self = .probe(groupName: "")
        } else if trimmed.hasPrefix("PROBE(") && trimmed.hasSuffix(")") {
            let groupName = String(trimmed.dropFirst(6).dropLast())
            self = .probe(groupName: groupName)
        } else {
            self = .direct
        }
    }

    func toString() -> String {
        switch self {
        case .direct: return "DIRECT"
        case .reject: return "REJECT"
        case .proxy(let group): return group.isEmpty ? "PROXY" : "PROXY(\(group))"
        case .probe(let group): return group.isEmpty ? "PROBE" : "PROBE(\(group))"
        }
    }

    var displayName: String {
        switch self {
        case .direct: return "Direct"
        case .reject: return "Reject"
        case .proxy(let group): return group.isEmpty ? "Proxy" : "Proxy(\(group))"
        case .probe(let group): return group.isEmpty ? "Probe" : "Probe(\(group))"
        }
    }
}

// MARK: - Parsed Rule

struct ParsedRule: Equatable, Identifiable, Hashable {
    var type: RuleType
    var value: String
    var action: RuleAction

    // Stable ID based on content
    var id: String {
        "\(type.rawValue)|\(value)|\(action.toString())"
    }

    init(type: RuleType = .match, value: String = "", action: RuleAction = .direct) {
        self.type = type
        self.value = value
        self.action = action
    }

    init?(from string: String) {
        let parts = string.split(separator: ",", maxSplits: 2).map(String.init)

        guard parts.count >= 2 else { return nil }

        guard let ruleType = RuleType(rawValue: parts[0]) else { return nil }
        self.type = ruleType

        if parts.count == 3 {
            self.value = parts[1]
            self.action = RuleAction(from: parts[2])
        } else {
            self.value = ""
            self.action = RuleAction(from: parts[1])
        }
    }

    func toString() -> String {
        if type == .match {
            return "\(type.rawValue),\(action.toString())"
        }
        return "\(type.rawValue),\(value),\(action.toString())"
    }
}
