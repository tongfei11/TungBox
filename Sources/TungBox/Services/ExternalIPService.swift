import Foundation

/// Fetches and caches the external (public) IP address asynchronously.
actor ExternalIPService {
    static let shared = ExternalIPService()

    private(set) var cachedIP: String?
    private var lastFetchTime: Date?
    private var lastFailureTime: Date?
    private var inFlightTask: Task<String?, Never>?
    private var requestID: UUID?
    private let cacheDuration: TimeInterval = 300
    private let failureRetryInterval: TimeInterval = 30
    private let fetch: @Sendable () async -> String?
    private let now: @Sendable () -> Date

    init(fetch: @escaping @Sendable () async -> String? = ExternalIPService.fetchIP,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetch = fetch
        self.now = now
    }

    func getExternalIP(force: Bool = false) async -> String? {
        if !force {
            if let task = inFlightTask {
                let id = requestID
                let result = await task.value
                guard !Task.isCancelled, !task.isCancelled, requestID == id else { return nil }
                return result ?? cachedIP
            }
            if let cachedIP, let lastFetchTime, now().timeIntervalSince(lastFetchTime) < cacheDuration {
                return cachedIP
            }
            // Runtime/log refreshes must not retry a failing endpoint chain every few seconds.
            if let lastFailureTime, now().timeIntervalSince(lastFailureTime) < failureRetryInterval {
                return cachedIP
            }
        }

        // A forced refresh follows a new route: cancel the old transport and
        // prevent its late response from replacing the new route's address.
        inFlightTask?.cancel()
        let id = UUID()
        let fetch = fetch
        let task = Task { await fetch() }
        requestID = id
        inFlightTask = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard requestID == id else { return nil }
        inFlightTask = nil
        guard !Task.isCancelled, !task.isCancelled else { return nil }

        if let result {
            cachedIP = result
            lastFetchTime = now()
            lastFailureTime = nil
        } else {
            lastFailureTime = now()
        }
        return result ?? cachedIP
    }

    private static func fetchIP() async -> String? {
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

        return await withTaskCancellationHandler {
            for endpoint in endpoints {
                guard !Task.isCancelled else { return nil }
                guard let url = URL(string: endpoint) else { continue }
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.setValue("curl/7.64.1", forHTTPHeaderField: "User-Agent")
                    let (data, response) = try await session.data(for: request)
                    guard !Task.isCancelled else { return nil }
                    if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                        let ip = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        if isValidIP(ip) { return ip }
                    }
                } catch {
                    if Task.isCancelled { return nil }
                }
            }
            return nil
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    private static func isValidIP(_ str: String) -> Bool {
        guard !str.isEmpty, str.count <= 45 else { return false }
        return str.contains(".") || str.contains(":")
    }
}
