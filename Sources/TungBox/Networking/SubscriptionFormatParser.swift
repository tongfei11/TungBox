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
        // Preferred path: a real (zero-dependency) YAML parse that preserves nested
        // structures — tls/reality-opts/ws-opts/grpc-opts/smux/ech-opts/alpn arrays —
        // so protocol options aren't mangled by line-based heuristics.
        if let doc = parseYAMLDocument(text) as? [String: Any],
           let rawProxies = (doc["proxies"] as? [Any]) ?? (doc["Proxy"] as? [Any]) {
            let proxies = rawProxies.compactMap { ($0 as? [String: Any]).flatMap(clashProxyToSingBox) }
            if !proxies.isEmpty { return proxies }
        }

        // Legacy fallback: line-based parser (kept for odd inputs the YAML parse misses).
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

            if inProxies && currentIndent <= indentLevel && !trimmed.hasPrefix("- ") && !trimmed.hasPrefix("-{") && trimmed != "-" && currentIndent > 0 {
                if !current.isEmpty { proxies.append(current) }
                inProxies = false
                continue
            }

            guard inProxies else { continue }

            // New proxy entry starting with a hyphen on a line by itself
            if trimmed == "-" {
                if !current.isEmpty { proxies.append(current) }
                current = [:]
                continue
            }

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
        // YAML path gives raw `name`; legacy path maps name→tag.
        let tag = clash["name"] as? String ?? clash["tag"] as? String ?? "\(type)-node"
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
            if let flow = clash["flow"] as? String, !flow.isEmpty { node["flow"] = flow }
            // UDP 封装：xudp 提供全锥 UDP（游戏/语音更稳）。订阅没给就默认 xudp。
            let vlessPE = (clash["packet-encoding"] as? String ?? clash["packet_encoding"] as? String) ?? ""
            node["packet_encoding"] = vlessPE.isEmpty ? "xudp" : vlessPE
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
            if let obfsType = clash["obfs"] as? String {
                node["obfs"] = [
                    "type": obfsType,
                    "password": clash["obfs-password"] as? String ?? ""
                ]
            }
            if let up = clash["up"] as? String ?? clash["up_mbps"] as? String {
                if let upVal = parseMbps(up) { node["up_mbps"] = upVal }
            } else if let upInt = clash["up"] as? Int ?? clash["up_mbps"] as? Int {
                node["up_mbps"] = upInt
            }
            if let down = clash["down"] as? String ?? clash["down_mbps"] as? String {
                if let downVal = parseMbps(down) { node["down_mbps"] = downVal }
            } else if let downInt = clash["down"] as? Int ?? clash["down_mbps"] as? Int {
                node["down_mbps"] = downInt
            }
        case "hysteria":
            // Hysteria v1（与 hy2 不同：auth_str + 字符串 obfs + 整数 mbps）
            node["type"] = "hysteria"
            if let authStr = clash["auth-str"] as? String ?? clash["auth_str"] as? String ?? clash["password"] as? String, !authStr.isEmpty {
                node["auth_str"] = authStr
            }
            if let obfs = clash["obfs"] as? String, !obfs.isEmpty { node["obfs"] = obfs }
            if let up = clash["up"] as? String ?? clash["up_mbps"] as? String {
                if let v = parseMbps(up) { node["up_mbps"] = v }
            } else if let upInt = clash["up"] as? Int ?? clash["up_mbps"] as? Int {
                node["up_mbps"] = upInt
            }
            if let down = clash["down"] as? String ?? clash["down_mbps"] as? String {
                if let v = parseMbps(down) { node["down_mbps"] = v }
            } else if let downInt = clash["down"] as? Int ?? clash["down_mbps"] as? Int {
                node["down_mbps"] = downInt
            }
        case "tuic":
            node["type"] = "tuic"
            node["uuid"] = clash["uuid"] as? String ?? ""
            node["password"] = clash["password"] as? String ?? ""
            if let cc = clash["congestion-controller"] as? String ?? clash["congestion_control"] as? String, !cc.isEmpty {
                node["congestion_control"] = cc
            }
            if let urm = clash["udp-relay-mode"] as? String ?? clash["udp_relay_mode"] as? String, !urm.isEmpty {
                node["udp_relay_mode"] = urm
            }
            if (clash["reduce-rtt"] as? Bool) == true || (clash["zero-rtt-handshake"] as? Bool) == true {
                node["zero_rtt_handshake"] = true
            }
        case "anytls":
            node["type"] = "anytls"
            node["password"] = clash["password"] as? String ?? ""
        case "naive":
            node["type"] = "naive"
            node["username"] = clash["username"] as? String ?? ""
            node["password"] = clash["password"] as? String ?? ""
        case "http", "socks", "socks5":
            node["type"] = (type == "socks5") ? "socks" : type
            node["username"] = clash["username"] as? String ?? ""
            node["password"] = clash["password"] as? String ?? ""
        default:
            return nil
        }

        // TLS —— tuic/hy2/hy1/anytls/naive 协议本身强制 TLS，即使订阅没写 tls 字段也要建。
        let tlsMandatory: Set<String> = ["tuic", "hysteria2", "hysteria", "anytls", "naive"]
        let tls: Bool = {
            if tlsMandatory.contains(node["type"] as? String ?? "") { return true }
            if let b = clash["tls"] as? Bool { return b }
            if let s = clash["tls"] as? String { return s.lowercased() == "true" }
            return false
        }()
        if tls {
            let sni = clash["servername"] as? String ?? clash["sni"] as? String ?? clash["peer"] as? String ?? server
            var tlsConfig: [String: Any] = ["enabled": true, "server_name": sni]
            if (clash["skip-cert-verify"] as? Bool) == true || (clash["insecure"] as? Bool) == true {
                tlsConfig["insecure"] = true
            }

            // ALPN（数组 / 逗号串 / 带括号字符串都兼容；tuic 默认 h3）
            if let alpn = parseAlpn(clash["alpn"]), !alpn.isEmpty {
                tlsConfig["alpn"] = alpn
            } else if (node["type"] as? String) == "tuic" {
                tlsConfig["alpn"] = ["h3"]   // tuic 不带 alpn 基本握手失败
            }

            // uTLS 指纹（client-fingerprint 是 Clash 顶层字段）
            if let fingerprint = clash["client-fingerprint"] as? String ?? clash["client_fingerprint"] as? String ?? clash["fingerprint"] as? String, !fingerprint.isEmpty {
                tlsConfig["utls"] = ["enabled": true, "fingerprint": fingerprint]
            }

            // Reality（Clash.Meta 用 reality-opts 嵌套；也兼容顶层 public-key）
            let realityOpts = clash["reality-opts"] as? [String: Any] ?? [:]
            let publicKey = (realityOpts["public-key"] as? String ?? realityOpts["public_key"] as? String
                ?? clash["public-key"] as? String ?? clash["public_key"] as? String) ?? ""
            if !publicKey.isEmpty {
                var reality: [String: Any] = ["enabled": true, "public_key": publicKey]
                if let shortId = realityOpts["short-id"] as? String ?? realityOpts["short_id"] as? String
                    ?? clash["short-id"] as? String ?? clash["short_id"] as? String {
                    reality["short_id"] = shortId
                }
                tlsConfig["reality"] = reality
            }

            // ECH（ech-opts.enable + 可选 config）→ 加密 ClientHello
            if let ech = clash["ech-opts"] as? [String: Any],
               (ech["enable"] as? Bool) == true || (ech["enabled"] as? Bool) == true {
                var echCfg: [String: Any] = ["enabled": true]
                if let cfg = ech["config"] as? String, !cfg.isEmpty { echCfg["config"] = [cfg] }
                else if let cfgArr = ech["config"] as? [Any] {
                    let arr = cfgArr.compactMap { $0 as? String }
                    if !arr.isEmpty { echCfg["config"] = arr }
                }
                tlsConfig["ech"] = echCfg
            }

            node["tls"] = tlsConfig
        }

        // Network / transport（支持 ws / grpc / http(h2) / httpupgrade，嵌套 *-opts）
        let network = (clash["network"] as? String ?? "tcp").lowercased()
        switch network {
        case "ws":
            let opts = clash["ws-opts"] as? [String: Any] ?? [:]
            var transport: [String: Any] = ["type": "ws"]
            transport["path"] = opts["path"] as? String ?? clash["ws-path"] as? String ?? clash["path"] as? String ?? "/"
            if let host = wsHost(opts: opts, clash: clash) { transport["headers"] = ["Host": host] }
            if let maxEarly = opts["max-early-data"] as? Int { transport["max_early_data"] = maxEarly }
            if let edh = opts["early-data-header-name"] as? String, !edh.isEmpty { transport["early_data_header_name"] = edh }
            node["transport"] = transport
        case "httpupgrade":
            let opts = clash["httpupgrade-opts"] as? [String: Any] ?? clash["ws-opts"] as? [String: Any] ?? [:]
            var transport: [String: Any] = ["type": "httpupgrade"]
            transport["path"] = opts["path"] as? String ?? clash["path"] as? String ?? "/"
            if let host = wsHost(opts: opts, clash: clash) { transport["host"] = host }
            node["transport"] = transport
        case "h2", "http":
            let opts = clash["h2-opts"] as? [String: Any] ?? clash["http-opts"] as? [String: Any] ?? [:]
            var transport: [String: Any] = ["type": "http"]
            if let hosts = opts["host"] as? [Any] {
                let arr = hosts.compactMap { $0 as? String }
                if !arr.isEmpty { transport["host"] = arr }
            } else if let host = opts["host"] as? String ?? clash["host"] as? String, !host.isEmpty {
                transport["host"] = [host]
            }
            if let path = opts["path"] as? String, !path.isEmpty { transport["path"] = path }
            node["transport"] = transport
        case "grpc":
            let opts = clash["grpc-opts"] as? [String: Any] ?? [:]
            let svc = opts["grpc-service-name"] as? String ?? clash["grpc-service-name"] as? String ?? clash["grpc-service"] as? String ?? ""
            node["transport"] = ["type": "grpc", "service_name": svc]
        default: break
        }

        // Multiplex（smux）—— 只对流式(TCP)协议；hy2/tuic 是 QUIC 原生复用，不加。
        let muxCapable: Set<String> = ["vmess", "vless", "trojan", "shadowsocks"]
        if muxCapable.contains(node["type"] as? String ?? ""),
           let smux = clash["smux"] as? [String: Any],
           (smux["enabled"] as? Bool) == true {
            var mux: [String: Any] = ["enabled": true]
            if let proto = smux["protocol"] as? String, !proto.isEmpty { mux["protocol"] = proto }
            if let v = smux["max-connections"] as? Int ?? smux["max_connections"] as? Int { mux["max_connections"] = v }
            if let v = smux["min-streams"] as? Int ?? smux["min_streams"] as? Int { mux["min_streams"] = v }
            if let v = smux["max-streams"] as? Int ?? smux["max_streams"] as? Int { mux["max_streams"] = v }
            if (smux["padding"] as? Bool) == true { mux["padding"] = true }
            if let brutal = smux["brutal-opts"] as? [String: Any] ?? smux["brutal"] as? [String: Any],
               (brutal["enabled"] as? Bool) == true {
                var b: [String: Any] = ["enabled": true]
                if let up = brutal["up"] as? Int { b["up_mbps"] = up } else if let up = brutal["up"] as? String, let v = parseMbps(up) { b["up_mbps"] = v }
                if let down = brutal["down"] as? Int { b["down_mbps"] = down } else if let down = brutal["down"] as? String, let v = parseMbps(down) { b["down_mbps"] = v }
                mux["brutal"] = b
            }
            node["multiplex"] = mux
        }

        return node
    }

    // MARK: - Minimal YAML parser (Clash subset)

    /// Parse a YAML document into nested [String:Any] / [Any] / scalars. Handles the
    /// Clash subset we care about: block mappings, block sequences (incl. compact
    /// `- key: val`), flow mappings `{a: b}`, flow sequences `[a, b]`, and quoted /
    /// unquoted scalars. Zero-dependency (no Yams) so the build never needs network.
    static func parseYAMLDocument(_ text: String) -> Any? {
        var lines: [(indent: Int, content: String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let noComment = stripYAMLComment(raw)
            if noComment.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let indent = noComment.prefix { $0 == " " }.count
            lines.append((indent, String(noComment.drop { $0 == " " })))
        }
        guard !lines.isEmpty else { return nil }
        var i = 0
        return parseYAMLBlock(lines, &i, parentIndent: -1)
    }

    private static func stripYAMLComment(_ line: String) -> String {
        var inS = false, inD = false
        var out = ""
        var prev: Character = " "
        for ch in line {
            if ch == "'" && !inD { inS.toggle() }
            else if ch == "\"" && !inS { inD.toggle() }
            else if ch == "#" && !inS && !inD && (prev == " " || out.isEmpty) { break }
            out.append(ch)
            prev = ch
        }
        return out
    }

    private static func parseYAMLBlock(_ lines: [(indent: Int, content: String)], _ i: inout Int, parentIndent: Int) -> Any {
        guard i < lines.count, lines[i].indent > parentIndent else { return [String: Any]() }
        let base = lines[i].indent
        let first = lines[i].content

        // A whole node that is a flow value.
        if first.hasPrefix("{") || first.hasPrefix("[") {
            let v = parseFlow(first); i += 1; return v
        }

        // Sequence
        if first == "-" || first.hasPrefix("- ") {
            var arr: [Any] = []
            while i < lines.count, lines[i].indent == base,
                  (lines[i].content == "-" || lines[i].content.hasPrefix("- ")) {
                let head = lines[i].content == "-" ? "" : String(lines[i].content.dropFirst(2))
                // Collect this item's sub-lines: the head (at virtual indent base+2)
                // plus all following deeper lines, then recurse.
                var sub: [(indent: Int, content: String)] = []
                if !head.isEmpty { sub.append((base + 2, head)) }
                i += 1
                while i < lines.count, lines[i].indent > base {
                    sub.append(lines[i]); i += 1
                }
                if sub.isEmpty {
                    arr.append("")
                } else {
                    var j = 0
                    arr.append(parseYAMLBlock(sub, &j, parentIndent: base + 1))
                }
            }
            return arr
        }

        // Mapping
        var map: [String: Any] = [:]
        while i < lines.count, lines[i].indent == base {
            let line = lines[i].content
            guard let colon = topLevelColonIndex(line) else { i += 1; continue }
            let key = unquoteYAML(String(line[..<colon]).trimmingCharacters(in: .whitespaces))
            let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            i += 1
            if rest.isEmpty {
                if i < lines.count, lines[i].indent > base {
                    map[key] = parseYAMLBlock(lines, &i, parentIndent: base)
                } else {
                    map[key] = ""
                }
            } else if rest.hasPrefix("{") || rest.hasPrefix("[") {
                map[key] = parseFlow(rest)
            } else {
                map[key] = parseScalar(rest)
            }
        }
        return map
    }

    /// Index of the first top-level `:` (followed by space or EOL), ignoring colons
    /// inside quotes or `{}`/`[]`.
    private static func topLevelColonIndex(_ s: String) -> String.Index? {
        var inS = false, inD = false, depth = 0
        var idx = s.startIndex
        while idx < s.endIndex {
            let ch = s[idx]
            if ch == "'" && !inD { inS.toggle() }
            else if ch == "\"" && !inS { inD.toggle() }
            else if !inS && !inD {
                if ch == "{" || ch == "[" { depth += 1 }
                else if ch == "}" || ch == "]" { depth -= 1 }
                else if ch == ":" && depth == 0 {
                    let next = s.index(after: idx)
                    if next == s.endIndex || s[next] == " " { return idx }
                }
            }
            idx = s.index(after: idx)
        }
        return nil
    }

    /// Parse a flow scalar/sequence/mapping (`{...}` / `[...]` / bare scalar).
    private static func parseFlow(_ raw: String) -> Any {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("{") && s.hasSuffix("}") {
            var map: [String: Any] = [:]
            for part in splitTopLevel(String(s.dropFirst().dropLast())) {
                guard let colon = topLevelColonIndex(part) ?? part.firstIndex(of: ":") else { continue }
                let key = unquoteYAML(String(part[..<colon]).trimmingCharacters(in: .whitespaces))
                let val = String(part[part.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if key.isEmpty { continue }
                map[key] = (val.hasPrefix("{") || val.hasPrefix("[")) ? parseFlow(val) : parseScalar(val)
            }
            return map
        }
        if s.hasPrefix("[") && s.hasSuffix("]") {
            return splitTopLevel(String(s.dropFirst().dropLast())).map { p -> Any in
                let t = p.trimmingCharacters(in: .whitespaces)
                return (t.hasPrefix("{") || t.hasPrefix("[")) ? parseFlow(t) : parseScalar(t)
            }
        }
        return parseScalar(s)
    }

    /// Split a flow body on top-level commas (ignoring nested brackets/quotes).
    private static func splitTopLevel(_ s: String) -> [String] {
        var parts: [String] = []
        var cur = ""
        var inS = false, inD = false, depth = 0
        for ch in s {
            if ch == "'" && !inD { inS.toggle(); cur.append(ch) }
            else if ch == "\"" && !inS { inD.toggle(); cur.append(ch) }
            else if !inS && !inD && (ch == "{" || ch == "[") { depth += 1; cur.append(ch) }
            else if !inS && !inD && (ch == "}" || ch == "]") { depth -= 1; cur.append(ch) }
            else if ch == "," && !inS && !inD && depth == 0 {
                parts.append(cur); cur = ""
            } else { cur.append(ch) }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(cur) }
        return parts
    }

    private static func parseScalar(_ raw: String) -> Any {
        let s = unquoteYAML(raw.trimmingCharacters(in: .whitespaces))
        let lower = s.lowercased()
        if lower == "true" { return true }
        if lower == "false" { return false }
        if lower == "null" || lower == "~" { return "" }
        if let n = Int(s) { return n }
        return s
    }

    private static func unquoteYAML(_ s: String) -> String {
        if s.count >= 2 {
            if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
                return String(s.dropFirst().dropLast())
            }
        }
        return s
    }

    // MARK: - Helpers

    private static func decodeBase64(_ text: String) -> String? {
        var s = text.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = s.count % 4
        if padding > 0 {
            s += String(repeating: "=", count: 4 - padding)
        }
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Normalize an ALPN value (array, comma string, or bracketed string) to [String].
    private static func parseAlpn(_ value: Any?) -> [String]? {
        if let arr = value as? [Any] {
            let s = arr.compactMap { $0 as? String }.filter { !$0.isEmpty }
            return s.isEmpty ? nil : s
        }
        if let str = value as? String, !str.isEmpty {
            let cleaned = str.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            let parts = cleaned.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
                .filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts
        }
        return nil
    }

    /// Resolve the ws/httpupgrade Host header from nested or flat Clash fields.
    private static func wsHost(opts: [String: Any], clash: [String: Any]) -> String? {
        if let headers = opts["headers"] as? [String: Any],
           let h = (headers["Host"] as? String ?? headers["host"] as? String), !h.isEmpty { return h }
        if let headers = clash["ws-headers"] as? [String: Any],
           let h = (headers["Host"] as? String ?? headers["host"] as? String), !h.isEmpty { return h }
        if let host = clash["host"] as? String, !host.isEmpty { return host }
        if let headersStr = clash["headers"] as? String, let h = extractHostFromInlineMap(headersStr) { return h }
        return nil
    }

    private static func extractHostFromInlineMap(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "{} "))
        let pairs = trimmed.components(separatedBy: ",")
        for pair in pairs {
            let kv = pair.components(separatedBy: ":")
            if kv.count >= 2 {
                let key = kv[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
                if key.lowercased() == "host" {
                    return kv[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
                }
            }
        }
        return nil
    }

    private static func parseMbps(_ text: String) -> Int? {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "mbps", with: "")
            .replacingOccurrences(of: "m", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Int(cleaned)
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
