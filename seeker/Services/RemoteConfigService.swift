import Foundation
import Yams

/// Service for fetching and parsing remote Clash/SS subscription configs
@MainActor
@Observable
class RemoteConfigService {
    var remoteServers: [ProxyServer] = []
    var isLoading = false
    var lastError: String?
    var lastFetchTime: Date?

    private let urlSession: URLSession
    private let cacheDir: URL

    // Track cache info per URL
    private var cacheInfo: [String: Date] = [:] // URL -> lastFetchTime

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.urlSession = URLSession(configuration: config)

        // Setup cache directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.cacheDir = appSupport.appendingPathComponent("seeker/remote_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Cache Management

    /// Wrapper to include source in JSON cache (since ProxyServer's CodingKeys excludes it)
    private struct CachedServer: Codable {
        let server: ProxyServer
        let source: ServerSource

        init(from server: ProxyServer) {
            self.server = server
            self.source = server.source
        }

        func toProxyServer() -> ProxyServer {
            var s = server
            s.source = source
            return s
        }
    }

    private struct CacheData: Codable {
        let url: String
        let servers: [CachedServer]
        let fetchTime: Date
    }

    /// Generate cache filename from URL (using hash)
    private func cacheFileName(for url: String) -> String {
        let hash = url.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .prefix(32)
        return "cache_\(hash).json"
    }

    private func cacheURL(for urlString: String) -> URL {
        cacheDir.appendingPathComponent(cacheFileName(for: urlString))
    }

    /// Load cached servers for specific URLs
    func loadCache(for urls: [String]) {
        var allServers: [ProxyServer] = []
        var oldestFetchTime: Date?

        for urlString in urls {
            let fileURL = cacheURL(for: urlString)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            do {
                let data = try Data(contentsOf: fileURL)
                let cache = try JSONDecoder().decode(CacheData.self, from: data)
                let servers = cache.servers.map { $0.toProxyServer() }
                allServers.append(contentsOf: servers)
                cacheInfo[urlString] = cache.fetchTime

                if oldestFetchTime == nil || cache.fetchTime < oldestFetchTime! {
                    oldestFetchTime = cache.fetchTime
                }
                print("[RemoteConfig] Loaded \(servers.count) servers from cache for \(urlString)")
            } catch {
                print("[RemoteConfig] Failed to load cache for \(urlString): \(error)")
            }
        }

        remoteServers = allServers
        lastFetchTime = oldestFetchTime
    }

    private func saveCache(servers: [ProxyServer], for urlString: String) {
        let cachedServers = servers.map { CachedServer(from: $0) }
        let cache = CacheData(url: urlString, servers: cachedServers, fetchTime: Date())

        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL(for: urlString))
            cacheInfo[urlString] = Date()
            print("[RemoteConfig] Saved \(servers.count) servers to cache for \(urlString)")
        } catch {
            print("[RemoteConfig] Failed to save cache for \(urlString): \(error)")
        }
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        remoteServers = []
        lastFetchTime = nil
        cacheInfo = [:]
    }

    /// Check if any URL needs refresh (cache older than specified interval)
    func needsRefresh(for urls: [String] = [], olderThan interval: TimeInterval = 3600) -> Bool {
        if urls.isEmpty {
            guard let lastFetch = lastFetchTime else { return true }
            return Date().timeIntervalSince(lastFetch) > interval
        }

        for url in urls {
            guard let fetchTime = cacheInfo[url] else { return true }
            if Date().timeIntervalSince(fetchTime) > interval {
                return true
            }
        }
        return false
    }

    /// Fetch servers from all remote config URLs
    func fetchRemoteServers(from urls: [String]) async {
        guard !urls.isEmpty else {
            remoteServers = []
            clearCache()
            return
        }

        isLoading = true
        lastError = nil

        var allServers: [ProxyServer] = []
        var errors: [String] = []

        for urlString in urls {
            do {
                let servers = try await fetchServers(from: urlString)
                allServers.append(contentsOf: servers)
                // Save cache for this URL
                saveCache(servers: servers, for: urlString)
            } catch {
                print("[RemoteConfig] Failed to fetch from \(urlString): \(error)")
                errors.append("\(urlString): \(error.localizedDescription)")
                // Load from cache if fetch failed
                if let cachedServers = loadCachedServers(for: urlString) {
                    allServers.append(contentsOf: cachedServers)
                    print("[RemoteConfig] Using cached servers for \(urlString)")
                }
            }
        }

        remoteServers = allServers
        lastFetchTime = Date()
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        isLoading = false
    }

    /// Load cached servers for a single URL (used when fetch fails)
    private func loadCachedServers(for urlString: String) -> [ProxyServer]? {
        let fileURL = cacheURL(for: urlString)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let cache = try JSONDecoder().decode(CacheData.self, from: data)
            return cache.servers.map { $0.toProxyServer() }
        } catch {
            return nil
        }
    }

    /// Fetch and parse servers from a single URL
    private func fetchServers(from urlString: String) async throws -> [ProxyServer] {
        guard let url = URL(string: urlString) else {
            throw RemoteConfigError.invalidURL(urlString)
        }

        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw RemoteConfigError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        // Try to parse as different formats
        if let servers = try? parseAsBase64SSSubscription(data: data, sourceURL: urlString) {
            return servers
        }

        if let servers = try? parseAsClashYAML(data: data, sourceURL: urlString) {
            return servers
        }

        // Try plain text SS URLs
        if let servers = try? parseAsPlainSSURLs(data: data, sourceURL: urlString) {
            return servers
        }

        throw RemoteConfigError.unsupportedFormat
    }

    // MARK: - Parsing Methods

    /// Parse Base64-encoded SS subscription format
    private func parseAsBase64SSSubscription(data: Data, sourceURL: String) throws -> [ProxyServer] {
        guard let base64String = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw RemoteConfigError.invalidData
        }

        // Handle URL-safe Base64
        let paddedBase64 = base64String
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .padding(toLength: ((base64String.count + 3) / 4) * 4, withPad: "=", startingAt: 0)

        guard let decodedData = Data(base64Encoded: paddedBase64),
              let decodedString = String(data: decodedData, encoding: .utf8) else {
            throw RemoteConfigError.base64DecodeFailed
        }

        return parseSSURLLines(decodedString, sourceURL: sourceURL)
    }

    /// Parse plain text SS URLs (one per line)
    private func parseAsPlainSSURLs(data: Data, sourceURL: String) throws -> [ProxyServer] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw RemoteConfigError.invalidData
        }

        let servers = parseSSURLLines(content, sourceURL: sourceURL)
        guard !servers.isEmpty else {
            throw RemoteConfigError.noServersFound
        }
        return servers
    }

    /// Parse lines containing SS URLs
    private func parseSSURLLines(_ content: String, sourceURL: String) -> [ProxyServer] {
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { parseSSURL($0, sourceURL: sourceURL) }
    }

    /// Parse a single SS URL into a ProxyServer
    /// Format: ss://BASE64(method:password)@host:port#name
    /// Or: ss://BASE64(method:password@host:port)#name
    private func parseSSURL(_ urlString: String, sourceURL: String) -> ProxyServer? {
        guard urlString.lowercased().hasPrefix("ss://") else { return nil }

        var url = String(urlString.dropFirst(5)) // Remove "ss://"

        // Extract name from fragment
        var name = ""
        if let hashIndex = url.lastIndex(of: "#") {
            let fragment = String(url[url.index(after: hashIndex)...])
            name = fragment.removingPercentEncoding ?? fragment
            url = String(url[..<hashIndex])
        }

        // Try format: BASE64(method:password)@host:port
        if let atIndex = url.lastIndex(of: "@") {
            let userInfoPart = String(url[..<atIndex])
            let hostPortPart = String(url[url.index(after: atIndex)...])

            // Decode userInfo
            if let decodedUserInfo = decodeBase64(userInfoPart),
               let colonIndex = decodedUserInfo.firstIndex(of: ":") {
                let method = String(decodedUserInfo[..<colonIndex])
                let password = String(decodedUserInfo[decodedUserInfo.index(after: colonIndex)...])

                // Parse host:port
                if let (host, port) = parseHostPort(hostPortPart) {
                    return ProxyServer(
                        name: name.isEmpty ? "\(host):\(port)" : name,
                        addr: "\(host):\(port)",
                        password: password,
                        protocol: .shadowsocks,
                        method: method,
                        source: .remote(url: sourceURL)
                    )
                }
            }
        }

        // Try format: BASE64(method:password@host:port)
        if let decoded = decodeBase64(url.components(separatedBy: "?").first ?? url) {
            // Parse method:password@host:port
            if let atIndex = decoded.lastIndex(of: "@") {
                let userInfoPart = String(decoded[..<atIndex])
                let hostPortPart = String(decoded[decoded.index(after: atIndex)...])

                if let colonIndex = userInfoPart.firstIndex(of: ":") {
                    let method = String(userInfoPart[..<colonIndex])
                    let password = String(userInfoPart[userInfoPart.index(after: colonIndex)...])

                    if let (host, port) = parseHostPort(hostPortPart) {
                        return ProxyServer(
                            name: name.isEmpty ? "\(host):\(port)" : name,
                            addr: "\(host):\(port)",
                            password: password,
                            protocol: .shadowsocks,
                            method: method,
                            source: .remote(url: sourceURL)
                        )
                    }
                }
            }
        }

        return nil
    }

    /// Parse Clash YAML format with proxies array
    private func parseAsClashYAML(data: Data, sourceURL: String) throws -> [ProxyServer] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw RemoteConfigError.invalidData
        }

        // Check if it looks like YAML
        guard content.contains("proxies:") || content.contains("Proxy:") else {
            throw RemoteConfigError.notClashFormat
        }

        struct ClashConfig: Decodable {
            var proxies: [ProxyServer]?
            var Proxy: [ProxyServer]?  // Some configs use uppercase
        }

        let decoder = YAMLDecoder()
        let config = try decoder.decode(ClashConfig.self, from: content)

        var servers = config.proxies ?? config.Proxy ?? []

        // Mark all servers as remote
        for i in servers.indices {
            servers[i].source = .remote(url: sourceURL)
        }

        guard !servers.isEmpty else {
            throw RemoteConfigError.noServersFound
        }

        return servers
    }

    // MARK: - Helpers

    private func decodeBase64(_ string: String) -> String? {
        let padded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .padding(toLength: ((string.count + 3) / 4) * 4, withPad: "=", startingAt: 0)

        guard let data = Data(base64Encoded: padded),
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return decoded
    }

    private func parseHostPort(_ string: String) -> (String, Int)? {
        // Handle IPv6: [host]:port
        if string.hasPrefix("[") {
            if let bracketEnd = string.lastIndex(of: "]") {
                let host = String(string[string.index(after: string.startIndex)..<bracketEnd])
                let remaining = String(string[string.index(after: bracketEnd)...])
                if remaining.hasPrefix(":"), let port = Int(remaining.dropFirst()) {
                    return (host, port)
                }
            }
        } else {
            // IPv4 or hostname: host:port
            let parts = string.split(separator: ":", maxSplits: 1)
            if parts.count == 2, let port = Int(parts[1]) {
                return (String(parts[0]), port)
            }
        }
        return nil
    }
}

// MARK: - Errors

enum RemoteConfigError: LocalizedError {
    case invalidURL(String)
    case httpError(Int)
    case invalidData
    case base64DecodeFailed
    case unsupportedFormat
    case noServersFound
    case notClashFormat

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .httpError(let code): return "HTTP error: \(code)"
        case .invalidData: return "Invalid data received"
        case .base64DecodeFailed: return "Failed to decode Base64 data"
        case .unsupportedFormat: return "Unsupported config format"
        case .noServersFound: return "No servers found in config"
        case .notClashFormat: return "Not a Clash format config"
        }
    }
}
