import Foundation
import Darwin

/// Parsing, strict validation, and minimal YAML (de)serialization for custom rule
/// sets. Pure and UI-independent so both the Store (file I/O) and the editor
/// (save-time validation) share one source of truth for the rule format.
enum RuleSetFormat {

    struct FormatError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// A line in the rules text that failed validation.
    struct LineError: Equatable {
        var line: Int      // 1-based index within the rules text
        var text: String
        var reason: String
    }

    /// Rule types accepted in a rule-set line. Mirrors the type dropdown; keep in
    /// sync with populateRuleTypePopup / ruleTypeMeta.
    static let supportedTypes: Set<String> = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-WILDCARD", "DOMAIN-REGEX",
        "RULE-SET", "LAN", "IP-CIDR", "IP-CIDR6", "GEOIP", "SRC-IP",
        "PROCESS-NAME", "PROCESS-PATH", "URL-REGEX",
        "DEST-PORT", "PROTOCOL", "NETWORK"
    ]

    /// Strictly validate a single `TYPE, VALUE`. Throws a human-readable reason.
    static func validate(type: String, value: String) throws {
        guard supportedTypes.contains(type) else {
            throw FormatError(message: "未知规则类型 \(type)")
        }
        let v = value.trimmingCharacters(in: .whitespaces)
        if type == "LAN" {
            guard v.isEmpty else { throw FormatError(message: "LAN 不接受匹配值或附加参数") }
            return
        }
        if !["DOMAIN-REGEX", "PROCESS-PATH"].contains(type), v.contains(",") {
            throw FormatError(message: "仅支持 TYPE, VALUE；请移除策略和附加参数，并在出站下拉中选择策略")
        }
        guard !v.isEmpty else { throw FormatError(message: "缺少匹配值") }
        switch type {
        case "DEST-PORT":
            guard let p = Int(v), (1...65535).contains(p) else {
                throw FormatError(message: "端口需为 1-65535 之间的数字")
            }
        case "IP-CIDR", "IP-CIDR6", "SRC-IP":
            let parts = v.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, let prefix = Int(parts[1]) else {
                throw FormatError(message: "需合法 CIDR，例如 192.168.0.0/16")
            }
            var ipv4 = in_addr()
            var ipv6 = in6_addr()
            let is4 = String(parts[0]).withCString { inet_pton(AF_INET, $0, &ipv4) == 1 }
            let is6 = String(parts[0]).withCString { inet_pton(AF_INET6, $0, &ipv6) == 1 }
            guard (is4 && (0...32).contains(prefix) && type != "IP-CIDR6") ||
                    (is6 && (0...128).contains(prefix) && type != "IP-CIDR") else {
                throw FormatError(message: "IP 地址、地址族或 CIDR 前缀长度无效")
            }
        case "GEOIP":
            guard v.range(of: "^[A-Za-z][A-Za-z-]*$", options: .regularExpression) != nil else {
                throw FormatError(message: "国家/地区码示例：cn、us、hk")
            }
        case "DOMAIN-REGEX":
            guard (try? NSRegularExpression(pattern: v)) != nil else {
                throw FormatError(message: "域名正则表达式无效")
            }
        case "URL-REGEX":
            throw FormatError(message: "不支持完整 URL 匹配，请使用 DOMAIN-REGEX 匹配域名")
        case "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-WILDCARD":
            guard !v.contains(where: { $0.isWhitespace }), !v.contains("://"), !v.contains("/") else {
                throw FormatError(message: "请输入域名，不要包含 URL、空白或路径")
            }
        case "NETWORK":
            guard ["tcp", "udp"].contains(v.lowercased()) else {
                throw FormatError(message: "网络只能填 tcp 或 udp")
            }
        default:
            break
        }
    }

    /// Parse the multi-line rules text into entries, collecting per-line errors.
    /// Blank lines and `#` comments are skipped; a leading `-` (YAML list marker)
    /// is optional so Clash `rules:` blocks paste cleanly.
    static func parseRules(_ text: String) -> (entries: [RuleSetEntry], errors: [LineError]) {
        var entries: [RuleSetEntry] = []
        var errors: [LineError] = []
        let lines = text.components(separatedBy: .newlines)
        for (index, raw) in lines.enumerated() {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("- ") {
                line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            let parts = line.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let type = (parts.first ?? "").uppercased()
            let value = parts.count > 1 ? parts[1] : ""
            do {
                try validate(type: type, value: value)
                entries.append(RuleSetEntry(type: type, value: value))
            } catch {
                let reason = (error as? FormatError)?.message ?? "格式错误"
                errors.append(LineError(line: index + 1, text: line, reason: reason))
            }
        }
        return (entries, errors)
    }

    /// Turn parsed entries back into the editor's multi-line text form.
    static func rulesText(for entries: [RuleSetEntry]) -> String {
        entries.map { $0.type == "LAN" ? "LAN" : "\($0.type), \($0.value)" }.joined(separator: "\n")
    }

    // MARK: - YAML (fixed schema, hand-rolled — no dependency)

    static func serialize(_ set: CustomRuleSet) -> String {
        var out = "schemaVersion: 1\n"
        out += "id: \(set.id.uuidString)\n"
        out += "name: \(scalar(set.name))\n"
        out += "outbound: \(scalar(set.outbound))\n"
        out += "enabled: \(set.enabled)\n"
        out += "createdAt: \(iso.string(from: set.createdAt))\n"
        out += "rules:\n"
        for entry in set.rules {
            let line = entry.type == "LAN" ? "LAN" : "\(entry.type), \(entry.value)"
            out += "  - \(line)\n"
        }
        return out
    }

    /// Decode a rule-set YAML file. `subscriptionID` comes from the containing
    /// folder, not the file. Strict: any invalid rule line fails the whole file.
    static func deserialize(_ yaml: String, subscriptionID: UUID) -> Result<CustomRuleSet, FormatError> {
        var fields: [String: String] = [:]
        var lines: [String] = []
        var inRules = false
        let allowed: Set<String> = ["id", "name", "outbound", "enabled", "createdAt", "rules", "schemaVersion"]
        for (index, raw) in yaml.components(separatedBy: .newlines).enumerated() {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            if raw.first?.isWhitespace == true {
                guard inRules, t.hasPrefix("- ") else {
                    return .failure(FormatError(message: "第 \(index + 1) 行：无效规则清单结构"))
                }
                lines.append(String(t.dropFirst(2)))
                continue
            }
            guard let colon = t.firstIndex(of: ":") else {
                return .failure(FormatError(message: "第 \(index + 1) 行：无效字段"))
            }
            let key = String(t[..<colon])
            guard allowed.contains(key), fields[key] == nil else {
                return .failure(FormatError(message: "未知或重复字段：\(key)"))
            }
            let value = String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            inRules = key == "rules"
            if inRules {
                guard value.isEmpty || value == "[]" else { return .failure(FormatError(message: "rules 必须为清单")) }
                fields[key] = value
            } else if value.hasPrefix("\"") {
                guard let data = value.data(using: .utf8), let decoded = try? JSONDecoder().decode(String.self, from: data) else {
                    return .failure(FormatError(message: "字段 \(key) 的引号或转义无效"))
                }
                fields[key] = decoded
            } else {
                // This is a documented fixed YAML subset; unsupported quoting is rejected.
                guard !value.hasPrefix("'"), !value.contains(" #") else {
                    return .failure(FormatError(message: "字段 \(key) 请使用双引号包裹特殊字符"))
                }
                fields[key] = value
            }
        }
        for key in ["id", "name", "outbound", "enabled", "rules"] where fields[key] == nil {
            return .failure(FormatError(message: "缺少 \(key) 字段"))
        }
        guard let id = UUID(uuidString: fields["id"] ?? ""),
              let name = fields["name"], !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let outbound = fields["outbound"], !outbound.isEmpty,
              let enabled = fields["enabled"], ["true", "false"].contains(enabled) else {
            return .failure(FormatError(message: "UUID、名称、出站或 enabled 无效"))
        }
        if let version = fields["schemaVersion"], version != "1" {
            return .failure(FormatError(message: "不支持的文件格式版本 \(version)"))
        }
        var createdAt = Date(timeIntervalSince1970: 0)
        if let date = fields["createdAt"] {
            guard let parsed = iso.date(from: date) else { return .failure(FormatError(message: "createdAt 无效")) }
            createdAt = parsed
        }
        let result = parseRules(lines.joined(separator: "\n"))
        if let error = result.errors.first { return .failure(FormatError(message: "规则第 \(error.line) 行：\(error.reason)")) }
        return .success(CustomRuleSet(id: id, subscriptionID: subscriptionID, name: name, outbound: outbound,
                                      rules: result.entries, enabled: enabled == "true", createdAt: createdAt))
    }

    // MARK: - Scalar helpers

    private static var iso: ISO8601DateFormatter { ISO8601DateFormatter() }

    private static func scalar(_ s: String) -> String {
        // JSON string escaping is also valid for YAML double-quoted scalars.
        String(data: try! JSONEncoder().encode(s), encoding: .utf8)!
    }
}
