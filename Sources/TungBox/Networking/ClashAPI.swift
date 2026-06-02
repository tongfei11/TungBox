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
        guard let object = try await requestJSON(path: "/connections") as? [String: Any],
              let connections = object["connections"] as? [[String: Any]] else { return [] }
        return connections.map { item in
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            let chains = item["chains"] as? [String] ?? []
            let destinationHost = (metadata["host"] as? String) ?? (metadata["destinationIP"] as? String) ?? ""
            let destinationPort = metadata["destinationPort"].map { "\($0)" } ?? ""
            let sourceIP = (metadata["sourceIP"] as? String) ?? ""
            let sourcePort = metadata["sourcePort"].map { "\($0)" } ?? ""
            return ConnectionInfo(
                id: (item["id"] as? String) ?? UUID().uuidString,
                network: (metadata["network"] as? String) ?? "",
                source: sourcePort.isEmpty ? sourceIP : "\(sourceIP):\(sourcePort)",
                destination: destinationPort.isEmpty ? destinationHost : "\(destinationHost):\(destinationPort)",
                rule: (item["rule"] as? String) ?? "",
                outbound: chains.first ?? "",
                upload: (item["upload"] as? Int) ?? 0,
                download: (item["download"] as? Int) ?? 0
            )
        }
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

    @discardableResult
    private static func requestJSON(path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Any {
        guard let url = URL(string: TungBoxConfig.clashAPIURL + path) else {
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
