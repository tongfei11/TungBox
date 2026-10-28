import Foundation

enum RuleRouting {
    static func customRouteRule(type: String, value: String, strategy: String) -> [String: Any] {
        let outbound = outboundForStrategy(strategy)
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if strategy == "REJECT" {
            var rule = customRouteRule(type: type, value: value, strategy: "DIRECT")
            rule.removeValue(forKey: "outbound")
            rule["action"] = "reject"
            return rule
        }
        switch type {
        case "DOMAIN":
            return ["domain": normalizedValue, "action": "route", "outbound": outbound]
        case "DOMAIN-SUFFIX":
            return ["domain_suffix": normalizedValue, "action": "route", "outbound": outbound]
        case "DOMAIN-KEYWORD":
            return ["domain_keyword": normalizedValue, "action": "route", "outbound": outbound]
        case "DOMAIN-WILDCARD":
            return ["domain_regex": wildcardRegex(from: normalizedValue), "action": "route", "outbound": outbound]
        case "DOMAIN-REGEX", "URL-REGEX":
            return ["domain_regex": normalizedValue, "action": "route", "outbound": outbound]
        case "RULE-SET":
            return ["rule_set": normalizedValue, "action": "route", "outbound": outbound]
        case "IP-CIDR":
            return ["ip_cidr": normalizedValue, "action": "route", "outbound": outbound]
        case "IP-CIDR6":
            return ["ip_cidr": normalizedValue, "action": "route", "outbound": outbound]
        case "GEOIP":
            return ["rule_set": normalizedValue.hasPrefix("geoip-") ? normalizedValue : "geoip-\(normalizedValue.lowercased())", "action": "route", "outbound": outbound]
        case "LAN":
            return ["ip_is_private": true, "action": "route", "outbound": outbound]
        case "SRC-IP":
            return ["source_ip_cidr": normalizedValue, "action": "route", "outbound": outbound]
        case "PROCESS-NAME":
            return ["process_name": normalizedValue, "action": "route", "outbound": outbound]
        case "PROCESS-PATH":
            return ["process_path": normalizedValue, "action": "route", "outbound": outbound]
        case "DEST-PORT":
            if let port = Int(normalizedValue) {
                return ["port": port, "action": "route", "outbound": outbound]
            }
            return ["port": normalizedValue, "action": "route", "outbound": outbound]
        case "PROTOCOL":
            return ["protocol": normalizedValue.lowercased(), "action": "route", "outbound": outbound]
        case "NETWORK":
            return ["network": normalizedValue.lowercased(), "action": "route", "outbound": outbound]
        default:
            return ["domain": normalizedValue, "action": "route", "outbound": outbound]
        }
    }

    static func outboundForStrategy(_ strategy: String) -> String {
        switch strategy {
        case "DIRECT": return TungBoxConfig.tagDirect
        case "REJECT": return TungBoxConfig.tagBlock
        case "AUTO": return TungBoxConfig.tagAuto
        case "Proxy": return TungBoxConfig.tagManual
        default: return strategy
        }
    }

    private static func wildcardRegex(from value: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: value)
            .replacingOccurrences(of: "\\*", with: ".*")
        return "^\(escaped)$"
    }

    static func ensureOutboundSupport(in config: [String: Any], strategy: String) -> [String: Any] {
        var config = config
        var outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let requiredTag = outboundForStrategy(strategy)
        if !outbounds.contains(where: { ($0["tag"] as? String) == requiredTag }) {
            guard [TungBoxConfig.tagDirect, TungBoxConfig.tagBlock].contains(requiredTag) else {
                return config
            }
            let type = requiredTag == TungBoxConfig.tagBlock ? "block" : "direct"
            outbounds.append(["type": type, "tag": requiredTag])
            config["outbounds"] = outbounds
        }
        return config
    }

    static func customRuleInsertIndex(in rules: [[String: Any]]) -> Int {
        var index = 0
        while index < rules.count {
            let rule = rules[index]
            if rule["clash_mode"] != nil || ["sniff", "hijack-dns", "resolve", "route-options"].contains(rule["action"] as? String ?? "") {
                index += 1
            } else {
                break
            }
        }
        return index
    }


    static func outboundReferenceError(strategy: String, config: [String: Any]) -> String? {
        if !["DIRECT", "REJECT"].contains(strategy) {
            let tag = outboundForStrategy(strategy)
            let tags = (config["outbounds"] as? [[String: Any]] ?? []).compactMap { $0["tag"] as? String }
            if !tags.contains(tag) { return "出站不存在：\(strategy)" }
        }
        return nil
    }

    static func referenceError(type: String, value: String, strategy: String, config: [String: Any]) -> String? {
        if let error = outboundReferenceError(strategy: strategy, config: config) { return error }
        if type == "RULE-SET" || type == "GEOIP" {
            let tag = type == "GEOIP" ? (value.hasPrefix("geoip-") ? value : "geoip-\(value.lowercased())") : value
            let route = config["route"] as? [String: Any] ?? [:]
            let tags = (route["rule_set"] as? [[String: Any]] ?? []).compactMap { $0["tag"] as? String }
            if !tags.contains(tag) { return "规则集引用不存在：\(tag)" }
        }
        return nil
    }

    static func referenceError(for set: CustomRuleSet, config: [String: Any]) -> String? {
        if let error = outboundReferenceError(strategy: set.outbound, config: config) { return error }
        return set.rules.compactMap {
            referenceError(type: $0.type, value: $0.value, strategy: set.outbound, config: config)
        }.first
    }

    // These checks run before any enable-state, file, configuration or runtime mutation.
    static func enableError(for rule: CustomRule, config: [String: Any]?) -> String? {
        guard let config else { return "当前配置不是有效 JSON" }
        return referenceError(type: rule.type, value: rule.value, strategy: rule.strategy, config: config)
    }

    static func enableError(for set: CustomRuleSet, config: [String: Any]?) -> String? {
        guard let config else { return "当前配置不是有效 JSON" }
        return referenceError(for: set, config: config)
    }

    static func rebuild(base: [[String: Any]], generated: [[String: Any]]) -> [[String: Any]] {
        var rules = base
        rules.insert(contentsOf: generated, at: customRuleInsertIndex(in: base))
        return rules
    }

    /// The independent rule source may contain older managed mode rules. Reapply
    /// the current runtime rules so an unchanged source cannot undo startup's
    /// global selector repair and restart TUN during a delay test.
    static func rebuildingRules(in config: [String: Any], base: [[String: Any]], generated: [[String: Any]], fallbackProxyTag: String) -> [String: Any] {
        var config = config
        var route = config["route"] as? [String: Any] ?? [:]
        route["rules"] = rebuild(base: base, generated: generated)
        config["route"] = route
        return ProxyModeConfig.ensureModeSupport(in: config, mode: ProxyModeConfig.readMode(from: config), fallbackProxyTag: fallbackProxyTag)
    }
}
