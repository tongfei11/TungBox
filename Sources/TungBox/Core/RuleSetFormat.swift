import Foundation

/// Parsing, strict validation, and minimal YAML (de)serialization for custom rule
/// sets. Pure and UI-independent so both the Store (file I/O) and the editor
/// (save-time validation) share one source of truth for the rule format.
enum RuleSetFormat {

    struct FormatError: Error { let message: String }

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
        if type == "LAN" { return }   // LAN takes no value
        guard !v.isEmpty else { throw FormatError(message: "缺少匹配值") }
        switch type {
        case "DEST-PORT":
            guard let p = Int(v), (1...65535).contains(p) else {
                throw FormatError(message: "端口需为 1-65535 之间的数字")
            }
        case "IP-CIDR", "IP-CIDR6", "SRC-IP":
            guard v.contains("/") else {
                throw FormatError(message: "需 CIDR 写法，例如 192.168.0.0/16")
            }
        case "GEOIP":
            guard v.range(of: "^[A-Za-z][A-Za-z-]*$", options: .regularExpression) != nil else {
                throw FormatError(message: "国家/地区码示例：cn、us、hk")
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
            if line.hasPrefix("-") {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
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
        var out = ""
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
        var id: UUID?
        var name: String?
        var outbound: String?
        var enabled = true
        var createdAt = Date(timeIntervalSince1970: 0)
        var ruleLines: [String] = []
        var inRules = false

        for raw in yaml.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if inRules {
                if trimmed.hasPrefix("-") {
                    ruleLines.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                    continue
                }
                inRules = false   // a non-list line ends the rules block
            }
            if trimmed == "rules:" { inRules = true; continue }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = unquote(String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
            switch key {
            case "id": id = UUID(uuidString: value)
            case "name": name = value
            case "outbound": outbound = value
            case "enabled": enabled = (value.lowercased() == "true")
            case "createdAt": createdAt = iso.date(from: value) ?? createdAt
            default: break
            }
        }

        guard let name, !name.isEmpty else { return .failure(FormatError(message: "缺少 name 字段")) }
        guard let outbound, !outbound.isEmpty else { return .failure(FormatError(message: "缺少 outbound 字段")) }
        let (entries, errors) = parseRules(ruleLines.joined(separator: "\n"))
        if let first = errors.first {
            return .failure(FormatError(message: "规则「\(first.text)」无效：\(first.reason)"))
        }
        return .success(CustomRuleSet(
            id: id ?? UUID(),
            subscriptionID: subscriptionID,
            name: name,
            outbound: outbound,
            rules: entries,
            enabled: enabled,
            createdAt: createdAt
        ))
    }

    // MARK: - Scalar helpers

    private static var iso: ISO8601DateFormatter { ISO8601DateFormatter() }

    private static func scalar(_ s: String) -> String {
        if s.isEmpty { return "\"\"" }
        let special = Set(":#{}[],&*!|>'\"%@`")
        let needsQuote = s.first == " " || s.last == " " || s.contains { special.contains($0) }
        if needsQuote {
            let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return s
    }

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2, s.first == "\"", s.last == "\"" else { return s }
        let inner = String(s.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
