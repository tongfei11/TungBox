import Foundation

// MARK: - Format detection

enum SubscriptionFormat: String {
    case singBoxJSON = "sing-box JSON"
    case clashYAML = "Clash YAML"
    case unknown = "未知格式"
}

enum SubscriptionFormatParser {

    static func detectFormat(_ text: String) -> SubscriptionFormat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // sing-box JSON
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return .singBoxJSON
            }
        }

        // Try base64 → sing-box JSON
        if let decoded = decodeBase64(trimmed),
           let data = decoded.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return .singBoxJSON
        }

        // Clash YAML
        if isClashYAML(trimmed) {
            return .clashYAML
        }

        return .unknown
    }

    // MARK: - Clash YAML detection & parsing

    private static func isClashYAML(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let markers = ["proxies:", "Proxy:", "proxy-groups:", "rules:", "mixed-port:", "port:", "socks-port:"]
        let lines = trimmed.components(separatedBy: .newlines)
        var score = 0
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            for marker in markers {
                if trimmedLine.hasPrefix(marker) { score += 1 }
            }
            if trimmedLine.hasPrefix("- name:") || trimmedLine.hasPrefix("- {name:") {
                score += 1
            }
        }
        return score >= 2
    }

    static func parseClashProxies(_ text: String) throws -> [[String: Any]] {
        let lines = text.components(separatedBy: .newlines)
        var proxies: [[String: Any]] = []
        var current: [String: Any] = [:]
        var inProxies = false
        var indentLevel = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let currentIndent = (line.prefix { $0 == " " || $0 == "\t" }.count)

            if trimmed.hasPrefix("proxies:") || trimmed.hasPrefix("Proxy:") {
                inProxies = true
                indentLevel = currentIndent
                continue
            }

            if inProxies && currentIndent <= indentLevel && !trimmed.hasPrefix("- ") && !trimmed.hasPrefix("-{") && currentIndent > 0 {
                if !current.isEmpty { proxies.append(current) }
                inProxies = false
                continue
            }

            guard inProxies else { continue }

            // New proxy entry
            if trimmed.hasPrefix("- ") {
                if !current.isEmpty { proxies.append(current) }
                current = [:]
                let entry = String(trimmed.dropFirst(2))
                if entry.hasPrefix("{") {
                    current = parseClashInlineProxy(entry)
                } else if let colonIndex = entry.firstIndex(of: ":") {
                    let key = String(entry[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                    let value = String(entry[entry.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    if !key.isEmpty {
                        current[clashToSingBoxKey(key)] = normalizeClashValue(value)
                    }
                }
                continue
            }
            if trimmed.hasPrefix("-{") {
                if !current.isEmpty { proxies.append(current) }
                current = parseClashInlineProxy(String(trimmed.dropFirst()))
                continue
            }

            // Key-value within a proxy entry
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    current[clashToSingBoxKey(key)] = normalizeClashValue(value)
                }
            }
        }

        if !current.isEmpty { proxies.append(current) }

        guard !proxies.isEmpty else {
            throw NSError.user("Clash YAML 中未找到代理节点（proxies 列表为空）")
        }

        return proxies.compactMap { clashProxyToSingBox($0) }
    }

    private static func parseClashInlineProxy(_ entry: String) -> [String: Any] {
        var trimmed = entry.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        var result: [String: Any] = [:]
        let pairs = trimmed.components(separatedBy: ",")
        for pair in pairs {
            let kv = pair.components(separatedBy: ":")
            if kv.count >= 2 {
                let key = kv[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
                let value = kv[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
                result[clashToSingBoxKey(key)] = normalizeClashValue(value)
            }
        }
        return result
    }

    private static func clashToSingBoxKey(_ key: String) -> String {
        switch key {
        case "name": return "tag"
        case "server": return "server"
        case "port": return "server_port"
        case "cipher": return "method"
        case "username": return "username"
        case "sni": return "sni"
        case "skip-cert-verify": return "insecure"
        default: return key
        }
    }

    private static func normalizeClashValue(_ value: String) -> Any {
        if value.lowercased() == "true" { return true }
        if value.lowercased() == "false" { return false }
        if let num = Int(value) { return num }
        return value
    }

    private static func clashProxyToSingBox(_ clash: [String: Any]) -> [String: Any]? {
        guard let type = (clash["type"] as? String)?.lowercased() else { return nil }
        let tag = clash["tag"] as? String ?? "\(type)-node"
        let server = clash["server"] as? String ?? ""

        var node: [String: Any] = ["tag": tag, "server": server]
        node["server_port"] = clash["server_port"] as? Int ?? (clash["port"] as? Int)
        if let portStr = clash["server_port"] as? String { node["server_port"] = Int(portStr) }
        if let portStr = clash["port"] as? String { node["server_port"] = Int(portStr) }

        switch type {
        case "vmess":
            node["type"] = "vmess"
            node["uuid"] = clash["uuid"] as? String ?? ""
            node["alter_id"] = clash["alterId"] as? Int ?? clash["alter_id"] as? Int ?? 0
            node["security"] = clash["cipher"] as? String ?? "auto"
        case "vless":
            node["type"] = "vless"
            node["uuid"] = clash["uuid"] as? String ?? ""
            if let flow = clash["flow"] as? String { node["flow"] = flow }
        case "trojan":
            node["type"] = "trojan"
            node["password"] = clash["password"] as? String ?? ""
        case "ss", "shadowsocks":
            node["type"] = "shadowsocks"
            node["method"] = clash["cipher"] as? String ?? clash["method"] as? String ?? "aes-256-gcm"
            node["password"] = clash["password"] as? String ?? ""
        case "hysteria2", "hy2":
            node["type"] = "hysteria2"
            node["password"] = clash["password"] as? String ?? clash["auth"] as? String ?? ""
        case "tuic":
            node["type"] = "tuic"
            node["uuid"] = clash["uuid"] as? String ?? ""
            node["password"] = clash["password"] as? String ?? ""
        case "http", "socks", "socks5":
            node["type"] = type
            node["username"] = clash["username"] as? String ?? ""
            node["password"] = clash["password"] as? String ?? ""
        default:
            return nil
        }

        // TLS
        let tls: Bool = {
            if let b = clash["tls"] as? Bool { return b }
            if let s = clash["tls"] as? String { return s.lowercased() == "true" }
            return false
        }()
        if tls {
            let sni = clash["sni"] as? String ?? server
            node["tls"] = ["enabled": true, "server_name": sni]
            if (clash["skip-cert-verify"] as? Bool) == true || (clash["insecure"] as? Bool) == true {
                node["tls"] = (node["tls"] as? [String: Any])?.merging(["insecure": true]) { $1 }
            }
        }

        // Network / transport
        let network = (clash["network"] as? String ?? "tcp").lowercased()
        switch network {
        case "ws":
            var transport: [String: Any] = ["type": "ws"]
            transport["path"] = clash["ws-path"] as? String ?? clash["path"] as? String ?? "/"
            if let host = clash["ws-headers"] as? [String: String], let h = host["Host"] {
                transport["headers"] = ["Host": h]
            } else if let host = clash["host"] as? String {
                transport["headers"] = ["Host": host]
            }
            node["transport"] = transport
        case "h2":
            var transport: [String: Any] = ["type": "http"]
            if let host = clash["host"] as? String {
                transport["host"] = [host]
            }
            node["transport"] = transport
        case "grpc":
            node["transport"] = ["type": "grpc", "service_name": clash["grpc-service"] as? String ?? ""]
        default: break
        }

        return node
    }

    // MARK: - Helpers

    private static func decodeBase64(_ text: String) -> String? {
        var s = text.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = s.count % 4
        if pad > 0 { s += String(repeating: "=", count: 4 - pad) }
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// Extension point in the main subscription parser
extension SubscriptionImporter {
    static func extractNodesFromAnyFormat(_ text: String) throws -> [[String: Any]] {
        let format = SubscriptionFormatParser.detectFormat(text)
        switch format {
        case .singBoxJSON:
            return try extractNodes(from: text)
        case .clashYAML:
            return try SubscriptionFormatParser.parseClashProxies(text)
        case .unknown:
            throw NSError.user("无法识别订阅格式。支持：\n• sing-box JSON（Xboard 面板模板输出）\n• Clash YAML（机场通用订阅格式）\n\n当前内容预览：\(text.prefix(300))")
        }
    }
}
