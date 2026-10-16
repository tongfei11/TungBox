import Foundation

/// Fetches and caches the external (public) IP address asynchronously.
actor ExternalIPService {
    static let shared = ExternalIPService()

    private(set) var cachedIP: String?
    private var lastFetchTime: Date?
    private var isFetching = false
    private let cacheDuration: TimeInterval = 300 // 5 minutes

    func getExternalIP(force: Bool = false) async -> String? {
        if !force, let cached = cachedIP, let last = lastFetchTime, Date().timeIntervalSince(last) < cacheDuration {
            return cached
        }
        if isFetching { return cachedIP }
        isFetching = true
        defer { isFetching = false }

        let endpoints = [
            "https://api.ipify.org",
            "https://ifconfig.me/ip",
            "https://icanhazip.com"
        ]

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 6.0
        let session = URLSession(configuration: config)

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    let ip = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    if isValidIP(ip) {
                        cachedIP = ip
                        lastFetchTime = Date()
                        return ip
                    }
                }
            } catch {
                continue
            }
        }
        return cachedIP
    }

    private func isValidIP(_ str: String) -> Bool {
        guard !str.isEmpty, str.count <= 45 else { return false }
        // Simple check for either IPv4 (contains .) or IPv6 (contains :)
        return str.contains(".") || str.contains(":")
    }
}
