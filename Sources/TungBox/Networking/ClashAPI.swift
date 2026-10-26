import Foundation

enum ClashAPI {
    /// A restarted Core can restore its cached mode over default_mode. Leave a
    /// matching mode and its connections intact; repair only an actual mismatch.
    static func reconcileMode(_ mode: String, port: Int, session: URLSession = .shared) async throws {
        if let config = try await requestJSON(path: "/configs", port: port, session: session) as? [String: Any],
           let actualMode = config["mode"] as? String,
           actualMode.caseInsensitiveCompare(mode) == .orderedSame { return }
        try await setModeAndCloseConnections(mode, port: port, session: session)
    }

    static func setModeAndCloseConnections(_ mode: String, port: Int, session: URLSession = .shared) async throws {
        _ = try await requestJSON(path: "/configs", method: "PATCH", body: ["mode": mode], port: port, session: session)
        guard let config = try await requestJSON(path: "/configs", port: port, session: session) as? [String: Any],
              let actualMode = config["mode"] as? String,
              actualMode.caseInsensitiveCompare(mode) == .orderedSame else {
            throw NSError.user("Core 未应用请求的出站模式")
        }
        // Existing connections retain their previous route after a mode switch.
        _ = try? await closeConnections(port: port, session: session)
    }

    static func proxies(port: Int? = nil) async throws -> [String: Any] {
        try await requestJSON(path: "/proxies", port: port) as? [String: Any] ?? [:]
    }

    static func proxyInfo(_ tag: String) async throws -> [String: Any] {
        let escaped = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        return try await requestJSON(path: "/proxies/\(escaped)") as? [String: Any] ?? [:]
    }

    static func selectProxy(group: String, node: String, port: Int? = nil, session: URLSession = .shared) async throws {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let escaped = group.addingPercentEncoding(withAllowedCharacters: unreserved) ?? group
        let path = "/proxies/\(escaped)"
        _ = try await requestJSON(path: path, method: "PUT", body: ["name": node], port: port, session: session)
        guard let info = try await requestJSON(path: path, port: port, session: session) as? [String: Any],
              let actualNode = info["now"] as? String, actualNode == node else {
            throw NSError.user("Core 未应用请求的节点选择：\(group) → \(node)")
        }
    }

    /// Selector changes affect only new connections in sing-box. Close the old
    /// connection pool after a successful switch so browsers cannot keep using
    /// the previous node through HTTP/2 or other persistent sessions.
    static func selectProxyAndCloseConnections(
        group: String,
        node: String,
        port: Int? = nil,
        session: URLSession = .shared
    ) async throws {
        try await selectProxy(group: group, node: node, port: port, session: session)
        // Selection is already committed at this point. Connection cleanup is
        // best-effort and must not turn a successful instant switch into a slow
        // full process restart when the DELETE endpoint is temporarily busy.
        _ = try? await closeConnections(port: port, session: session)
    }

    static func delay(node: String, url: String, port: Int? = nil) async throws -> Int {
        guard let object = try await requestJSON(path: delayPath(kind: "proxies", tag: node, url: url), port: port) as? [String: Any],
              let delay = object["delay"] as? Int else {
            throw NSError.user("测速接口响应无效")
        }
        return delay
    }

    /// sing-box Meta API calls URLTestGroup.URLTest and performs its selection update.
    /// /proxies/{tag}/delay only probes the selected outbound; PUT supports selectors only.
    static func testGroup(_ tag: String, url: String, port: Int? = nil) async throws {
        // sing-box returns a single {"delay": ms} value for group URLTest.
        // The important side effect is the group's selected outbound; the
        // subsequent /proxies refresh is the source of truth for the UI.
        guard try await requestJSON(path: delayPath(kind: "group", tag: tag, url: url), port: port, timeout: 35) is [String: Any] else {
            throw NSError.user("分组测速接口响应无效")
        }
    }

    static func delayPath(kind: String, tag: String, url: String) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let escapedTag = tag.addingPercentEncoding(withAllowedCharacters: unreserved) ?? tag
        let escapedURL = url.addingPercentEncoding(withAllowedCharacters: unreserved) ?? url
        return "/\(kind)/\(escapedTag)/delay?url=\(escapedURL)&timeout=\(kind == "group" ? 30000 : 5000)"
    }

    struct ConnectionSnapshot {
        var connections: [ConnectionInfo] = []
        var totals: [Int: (upload: Int64, download: Int64)] = [:]
    }

    /// Read each Core's connection list and lifetime traffic totals from the same
    /// response. Polling these separately doubles the full JSON allocation.
    static func connectionSnapshot(ports: [Int], session: URLSession = .shared) async throws -> ConnectionSnapshot {
        var snapshot = ConnectionSnapshot()
        var visited = Set<Int>()
        var lastError: Error = NSError.user("无法读取连接统计")
        for port in ports where visited.insert(port).inserted {
            try Task.checkCancellation()
            do {
                guard let object = try await requestJSON(path: "/connections", port: port, session: session) as? [String: Any] else {
                    throw NSError.user("连接统计接口响应无效")
                }
                let connections = try await parseConnections(from: object)
                snapshot.connections.append(contentsOf: connections.map { conn in
                    var connection = conn
                    if port != 9090 { connection.id = "p\(port):\(conn.id)" }
                    return connection
                })
                // Lifetime totals include UDP, IPv6 and already closed connections.
                snapshot.totals[port] = (
                    (object["uploadTotal"] as? NSNumber)?.int64Value ?? 0,
                    (object["downloadTotal"] as? NSNumber)?.int64Value ?? 0
                )
            } catch {
                try Task.checkCancellation()
                // A stopped user Core must not discard a running TUN Core.
                lastError = error
            }
        }
        guard !snapshot.totals.isEmpty else { throw lastError }
        return snapshot
    }

    private static func parseConnections(from raw: Any) async throws -> [ConnectionInfo] {
        guard let object = raw as? [String: Any],
              let connections = object["connections"] as? [[String: Any]] else { return [] }
        return connections.map { item in
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            let chains = item["chains"] as? [String] ?? []
            let destinationHost = (metadata["host"] as? String) ?? (metadata["destinationIP"] as? String) ?? ""
            let destinationPort = metadata["destinationPort"].map { "\($0)" } ?? ""
            let sourceIP = (metadata["sourceIP"] as? String) ?? ""
            return ConnectionInfo(
                id: (item["id"] as? String) ?? UUID().uuidString,
                network: (metadata["network"] as? String) ?? "",
                status: connectionStatus(from: item, chains: chains, destinationHost: destinationHost),
                source: sourceIP,
                destination: destinationPort.isEmpty ? destinationHost : "\(destinationHost):\(destinationPort)",
                rule: (item["rule"] as? String) ?? "",
                outbound: chains.first ?? "",
                upload: (item["upload"] as? Int) ?? 0,
                download: (item["download"] as? Int) ?? 0
            )
        }
    }

    private static func connectionStatus(from item: [String: Any], chains: [String], destinationHost: String) -> String {
        let rawStatus = [
            item["status"],
            item["state"],
            item["connectionStatus"]
        ].compactMap { $0 as? String }.first?.lowercased()

        if let rawStatus {
            if ["reject", "rejected", "blocked", "closed", "failed", "failure"].contains(rawStatus) {
                return "拒绝"
            }
            if ["pending", "connecting", "dialing", "resolving", "opening"].contains(rawStatus) {
                return "pending"
            }
            if ["connected", "established", "open", "active", "ok", "success"].contains(rawStatus) {
                return "成功"
            }
        }

        let rule = ((item["rule"] as? String) ?? "").lowercased()
        let outboundText = chains.joined(separator: " ").lowercased()
        if rule.contains("reject") || outboundText.contains("reject") {
            return "拒绝"
        }
        if destinationHost.isEmpty || chains.isEmpty {
            return "pending"
        }
        return "成功"
    }

    @discardableResult
    static func closeConnections(port: Int? = nil, session: URLSession = .shared) async throws -> Any {
        try await requestJSON(path: "/connections", method: "DELETE", port: port, session: session)
    }

    @discardableResult
    static func closeConnection(id: String, port: Int? = nil) async throws -> Any {
        try await requestJSON(path: "/connections/\(id)", method: "DELETE", port: port)
    }

    static func traffic() async throws -> (up: Int, down: Int) {
        guard let object = try await requestJSON(path: "/traffic") as? [String: Any] else { return (0, 0) }
        return ((object["up"] as? Int) ?? 0, (object["down"] as? Int) ?? 0)
    }

    @discardableResult
    static func makeRequest(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        port: Int? = nil,
        secret: String? = nil
    ) throws -> URLRequest {
        guard let url = endpointURL(path: path, port: port) else {
            throw NSError.user("Clash API 地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        let effectivePort = port ?? 9090
        request.setValue("Bearer \(secret ?? TungBoxConfig.clashAPISecret(for: effectivePort))", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    static func verifyAuthentication(
        port: Int,
        secret: String? = nil,
        session: URLSession = .shared
    ) async throws {
        guard let url = endpointURL(path: "/proxies", port: port) else {
            throw NSError.user("Clash API 地址无效")
        }

        var unauthenticated = URLRequest(url: url)
        unauthenticated.timeoutInterval = 3
        let (_, unauthenticatedResponse) = try await session.data(for: unauthenticated)
        guard (unauthenticatedResponse as? HTTPURLResponse)?.statusCode == 401 else {
            throw NSError.user("本地控制接口未拒绝无认证请求")
        }

        var authenticated = try makeRequest(path: "/proxies", port: port, secret: secret)
        authenticated.timeoutInterval = 3
        let (_, authenticatedResponse) = try await session.data(for: authenticated)
        guard let status = (authenticatedResponse as? HTTPURLResponse)?.statusCode,
              (200..<300).contains(status) else {
            throw NSError.user("本地控制接口认证校验失败")
        }
    }

    private static func requestJSON(path: String, method: String = "GET", body: [String: Any]? = nil, port: Int? = nil, timeout: TimeInterval = 7, session: URLSession = .shared) async throws -> Any {
        var request = try makeRequest(path: path, method: method, body: body, port: port)
        request.timeoutInterval = timeout

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError.user(message)
        }
        if data.isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }

    static func endpointURL(path: String, port: Int? = nil) -> URL? {
        let base: String
        if let port = port {
            base = "http://127.0.0.1:\(port)"
        } else {
            base = TungBoxConfig.clashAPIURL
        }
        return URL(string: base + path)
    }
}
