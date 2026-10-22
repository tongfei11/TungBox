import Foundation

/// Fetches and caches the external (public) IP address asynchronously.
actor ExternalIPService {
    static let shared = ExternalIPService()

    private(set) var cachedIP: String?
    private var lastFetchTime: Date?
    private var inFlightTask: Task<String?, Never>?
    private let cacheDuration: TimeInterval = 300 // 5 minutes

    func getExternalIP(force: Bool = false) async -> String? {
        if !force, let cached = cachedIP, let last = lastFetchTime, Date().timeIntervalSince(last) < cacheDuration {
            return cached
        }
        if !force, let inFlight = inFlightTask {
            return await inFlight.value
        }

        let task = Task<String?, Never> {
            await self.performFetch()
        }
        inFlightTask = task
        let result = await task.value
        inFlightTask = nil
        return result
    }

    private func performFetch() async -> String? {
        let endpoints = [
            "https://api.ipify.org",
            "https://api.ip.sb/ip",
            "https://myip.la",
            "https://icanhazip.com",
            "https://ifconfig.me/ip"
        ]

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.0
        config.timeoutIntervalForResource = 5.0
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("curl/7.64.1", forHTTPHeaderField: "User-Agent")
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
