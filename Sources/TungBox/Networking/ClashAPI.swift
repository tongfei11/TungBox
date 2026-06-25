import Foundation

enum ClashAPI {
    static func proxies() async throws -> [String: Any] {
        try await requestJSON(path: "/proxies") as? [String: Any] ?? [:]
    }

    static func proxyInfo(_ tag: String) async throws -> [String: Any] {
        let escaped = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        return try await requestJSON(path: "/proxies/\(escaped)") as? [String: Any] ?? [:]
    }

    static func selectProxy(group: String, node: String) async throws {
        let escaped = group.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? group
        try await requestJSON(path: "/proxies/\(escaped)", method: "PUT", body: ["name": node])
    }

    static func delay(node: String, url: String) async throws -> Int {
        let escapedNode = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
        let escapedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let path = "/proxies/\(escapedNode)/delay?url=\(escapedURL)&timeout=5000"
        
        guard let object = try await requestJSON(path: path) as? [String: Any],
              let delay = object["delay"] as? Int else {
            throw NSError.user("测速接口响应无效")
        }
        return delay
    }

    static func connections() async throws -> [ConnectionInfo] {
        try await parseConnections(from: requestJSON(path: "/connections"))
    }

    /// 同时拉用户代理(9090) 和 TUN 守护进程(9091) 的 connections，合并返回。
    /// 解耦架构后两个 sing-box 进程各自维护连接表，流量统计必须把两边都算上，
    /// 否则 TUN-only 模式（用户代理不跑）下流量永远为 0。
    /// 用 ConnectionInfo.id 前缀加上端口区分，防止两个进程内部 id 碰撞。
    static func connectionsFromAll(extraPorts: [Int]) async throws -> [ConnectionInfo] {
        var results: [ConnectionInfo] = []
        // 主端口（9090）
        do {
            let primary = try await connections()
            results.append(contentsOf: primary)
        } catch {
            // 主端口拉不到不算致命，可能用户代理未启动。继续拉次端口。
        }
        for port in extraPorts {
            do {
                let raw = try await requestJSON(path: "/connections", port: port)
                let extra = try await parseConnections(from: raw)
                // 加端口前缀防止两个进程的 id 碰撞
                let prefixed = extra.map { conn -> ConnectionInfo in
                    var c = conn
                    c.id = "p\(port):\(conn.id)"
                    return c
                }
                results.append(contentsOf: prefixed)
            } catch {
                continue
            }
        }
        return results
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
    static func closeConnections() async throws -> Any {
        try await requestJSON(path: "/connections", method: "DELETE")
    }

    @discardableResult
    static func closeConnection(id: String) async throws -> Any {
        try await requestJSON(path: "/connections/\(id)", method: "DELETE")
    }

    static func traffic() async throws -> (up: Int, down: Int) {
        guard let object = try await requestJSON(path: "/traffic") as? [String: Any] else { return (0, 0) }
        return ((object["up"] as? Int) ?? 0, (object["down"] as? Int) ?? 0)
    }

    /// 拉 `/connections` 顶层的 `uploadTotal` / `downloadTotal` —— 这是 sing-box
    /// 进程级累计字节数（从启动起算），**包含 TCP + UDP + IPv6 + 已关闭的短连接**。
    /// per-connection 的 upload/download 在连接关闭后会从列表移除，按 id 算 delta
    /// 会丢掉短连接的字节（典型例子：YouTube 的 QUIC 短流，几秒钟传完就关）。
    /// 用 totals 算 delta 可避免这种漏算。
    /// 同时支持多端口（用户代理 + TUN 守护进程），返回 [port: (upload, download)]。
    static func trafficTotals(ports: [Int]) async throws -> [Int: (upload: Int64, download: Int64)] {
        var out: [Int: (upload: Int64, download: Int64)] = [:]
        for port in ports {
            guard let obj = try? await requestJSON(path: "/connections", port: port) as? [String: Any] else { continue }
            // 不同版本 sing-box 字段类型可能是 Int 或 NSNumber，统一转 Int64
            let up: Int64
            let down: Int64
            if let v = obj["uploadTotal"] as? Int64 { up = v }
            else if let v = obj["uploadTotal"] as? Int { up = Int64(v) }
            else if let v = obj["uploadTotal"] as? NSNumber { up = v.int64Value }
            else { up = 0 }
            if let v = obj["downloadTotal"] as? Int64 { down = v }
            else if let v = obj["downloadTotal"] as? Int { down = Int64(v) }
            else if let v = obj["downloadTotal"] as? NSNumber { down = v.int64Value }
            else { down = 0 }
            out[port] = (up, down)
        }
        return out
    }

    @discardableResult
    private static func requestJSON(path: String, method: String = "GET", body: [String: Any]? = nil, port: Int? = nil) async throws -> Any {
        let base: String
        if let port = port {
            base = "http://127.0.0.1:\(port)"
        } else {
            base = TungBoxConfig.clashAPIURL
        }
        guard let url = URL(string: base + path) else {
            throw NSError.user("Clash API 地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 5
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError.user(message)
        }
        if data.isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }
}
