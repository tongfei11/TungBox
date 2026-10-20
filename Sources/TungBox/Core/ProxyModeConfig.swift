import Foundation

/// 模式配置转换。调用方明确传入模式与节点回退值，不读取窗口或运行状态。
enum ProxyModeConfig {
    /// sing-box only accepts modes declared by startup rules or default_mode.
    /// Add Rule to transient configs when a Global/Direct startup would omit it.
    static func ensuringRuntimeRuleMode(in config: [String: Any]) -> [String: Any] {
        guard readMode(from: config).caseInsensitiveCompare("Rule") != .orderedSame else { return config }
        var route = config["route"] as? [String: Any] ?? [:]
        var rules = route["rules"] as? [[String: Any]] ?? []
        let dns = config["dns"] as? [String: Any] ?? [:]
        guard !containsRuleMode(rules), !containsRuleMode(dns["rules"] as? [[String: Any]] ?? []) else { return config }
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let final = (route["final"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard let fallback = final ?? outbounds.first?["tag"] as? String, !fallback.isEmpty else { return config }
        // This last rule uses the same outbound as the implicit route fallback.
        // Earlier custom rules keep their priority; saved editor configs stay intact.
        rules.append(["clash_mode": "Rule", "outbound": fallback])
        route["rules"] = rules
        var runtime = config
        runtime["route"] = route
        return runtime
    }

    private static func containsRuleMode(_ rules: [[String: Any]]) -> Bool {
        rules.contains { rule in
            (rule["clash_mode"] as? String)?.caseInsensitiveCompare("Rule") == .orderedSame
                || containsRuleMode(rule["rules"] as? [[String: Any]] ?? [])
        }
    }

    static func readMode(from config: [String: Any]) -> String {
        let experimental = config["experimental"] as? [String: Any]
        let clashAPI = experimental?["clash_api"] as? [String: Any]
        return (clashAPI?["default_mode"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Rule"
    }

    /// Repair a dangling `route.default_domain_resolver` that points at a DNS server
    /// tag no longer present in `dns.servers` (a stale reference left over from an
    /// older config, e.g. "dns-cn"). Returns the repaired config text, or nil if no
    /// change was needed.
    static func repairDefaultDomainResolver(inConfigText text: String) -> String? {
        guard var config = ConfigCodec.parseObject(from: text),
              var route = config["route"] as? [String: Any],
              let dns = config["dns"] as? [String: Any],
              let servers = dns["servers"] as? [[String: Any]],
              let firstTag = servers.first?["tag"] as? String else { return nil }
        let definedTags = Set(servers.compactMap { $0["tag"] as? String })
        let resolver = route["default_domain_resolver"]
        let resolverTag = (resolver as? String) ?? (resolver as? [String: Any])?["server"] as? String
        guard let tag = resolverTag, !definedTags.contains(tag) else { return nil }
        route["default_domain_resolver"] = firstTag
        config["route"] = route
        return try? ConfigCodec.render(config)
    }

    static func ensureModeSupport(in config: [String: Any], mode: String, fallbackProxyTag: String) -> [String: Any] {
        var config = config
        var experimental = config["experimental"] as? [String: Any] ?? [:]
        var clashAPI = experimental["clash_api"] as? [String: Any] ?? [:]
        if clashAPI["external_controller"] == nil {
            clashAPI["external_controller"] = "127.0.0.1:9090"
        }
        clashAPI.removeValue(forKey: "secret")
        clashAPI["default_mode"] = mode
        experimental["clash_api"] = clashAPI
        config["experimental"] = experimental

        var outbounds = config["outbounds"] as? [[String: Any]] ?? []
        if !outbounds.contains(where: { ($0["tag"] as? String) == "direct" }) {
            outbounds.append(["type": "direct", "tag": "direct"])
        }
        outbounds = ensureGlobalSelector(in: outbounds)
        config["outbounds"] = outbounds

        let proxyTag = preferredProxyTag(from: outbounds, fallback: fallbackProxyTag)
        // Global clash mode routes through the dedicated 全局 selector (manual node
        // pick) when present; otherwise fall back to the main proxy group.
        let globalTag = outbounds.contains { ($0["tag"] as? String) == TungBoxConfig.tagGlobal }
            ? TungBoxConfig.tagGlobal
            : proxyTag
        var route = config["route"] as? [String: Any] ?? [:]
        var rules = route["rules"] as? [[String: Any]] ?? []
        rules.removeAll { isManagedRuntimeRule($0) }
        let hostsDomains = Array(DNSConfig.collectHostsEntries().keys).sorted()
        var prefixRules: [[String: Any]] = [
            ["action": "sniff"],
            ["protocol": "dns", "action": "hijack-dns"]
        ]
        if !hostsDomains.isEmpty {
            prefixRules.append([
                "domain": hostsDomains,
                "action": "resolve"
            ])
        }
        prefixRules.append(["clash_mode": "direct", "outbound": "direct"])
        prefixRules.append(["clash_mode": "global", "outbound": globalTag])
        rules = prefixRules + rules
        route["rules"] = rules
        // sing-box 1.12+: outbound dials that chain to domain-based routing require a
        // default domain resolver pointing at a *defined* DNS server. A nil value — or
        // a dangling reference (e.g. a stale "dns-cn" no longer present in dns.servers,
        // left over from an older config) — makes sing-box FATAL. Repoint it to the
        // first available server.
        if let dns = config["dns"] as? [String: Any],
           let servers = dns["servers"] as? [[String: Any]],
           let firstTag = servers.first?["tag"] as? String {
            let definedTags = Set(servers.compactMap { $0["tag"] as? String })
            let resolver = route["default_domain_resolver"]
            let resolverTag = (resolver as? String) ?? (resolver as? [String: Any])?["server"] as? String
            if resolverTag == nil || !definedTags.contains(resolverTag!) {
                route["default_domain_resolver"] = firstTag
            }
        }
        config["route"] = route

        return config
    }

    private static func isManagedRuntimeRule(_ rule: [String: Any]) -> Bool {
        if let action = (rule["action"] as? String)?.lowercased() {
            if action == "sniff" { return true }
            if action == "hijack-dns",
               (rule["protocol"] as? String)?.lowercased() == "dns" {
                return true
            }
            if action == "resolve", rule["domain"] != nil {
                return true
            }
        }
        guard let clashMode = (rule["clash_mode"] as? String)?.lowercased() else { return false }
        return clashMode == "direct" || clashMode == "global"
    }

    /// Ensure a dedicated 全局 (Global) selector exists for clash global mode.
    /// Members are [自动选择] + all subscription nodes, defaulting to 自动选择, so the
    /// user can either ride auto-select or manually pin a node for global mode. Kept
    /// in sync (members refreshed) so newly added nodes show up; never reorders the
    /// existing groups, so `preferredProxyTag` still resolves to 节点选择.
    private static func ensureGlobalSelector(in outbounds: [[String: Any]]) -> [[String: Any]] {
        let virtualTypes: Set<String> = ["selector", "urltest", "url-test", "fallback", "direct", "block", "dns"]
        let nodeTags = outbounds.compactMap { outbound -> String? in
            let type = (outbound["type"] as? String ?? "").lowercased()
            guard !virtualTypes.contains(type), let tag = outbound["tag"] as? String else { return nil }
            return tag
        }
        guard !nodeTags.isEmpty else { return outbounds }

        let hasAuto = outbounds.contains { ($0["tag"] as? String) == TungBoxConfig.tagAuto }
        let members = (hasAuto ? [TungBoxConfig.tagAuto] : []) + nodeTags
        let defaultMember = hasAuto ? TungBoxConfig.tagAuto : (nodeTags.first ?? "")

        var outbounds = outbounds
        if let index = outbounds.firstIndex(where: { ($0["tag"] as? String) == TungBoxConfig.tagGlobal }) {
            // Refresh members but preserve the user's current manual pick.
            outbounds[index]["outbounds"] = members
            if let current = outbounds[index]["default"] as? String, members.contains(current) {
                outbounds[index]["default"] = current
            } else {
                outbounds[index]["default"] = defaultMember
            }
        } else {
            outbounds.append([
                "type": "selector",
                "tag": TungBoxConfig.tagGlobal,
                "outbounds": members,
                "default": defaultMember,
                "interrupt_exist_connections": true
            ])
        }
        return outbounds
    }

    /// fallback 沿用调用方当前首个节点；不能改从 outbounds 推断，以免改变已有行为。
    static func preferredProxyTag(from outbounds: [[String: Any]], fallback: String) -> String {
        if let selector = outbounds.first(where: { ($0["type"] as? String)?.lowercased() == "selector" }),
           let tag = selector["tag"] as? String {
            return tag
        }
        if let urltest = outbounds.first(where: { ["urltest", "url-test"].contains((($0["type"] as? String) ?? "").lowercased()) }),
           let tag = urltest["tag"] as? String {
            return tag
        }
        return fallback
    }

    /// Preserves user-configured selector `default` values from an existing configuration
    /// into a newly generated configuration (e.g. from subscription refresh). If a
    /// previously selected node still exists in the new selector members, keep it.
    static func preserveSelectorDefaults(from existingConfigText: String, into newConfigText: String) -> String {
        guard let existingConfig = ConfigCodec.parseObject(from: existingConfigText),
              let existingOutbounds = existingConfig["outbounds"] as? [[String: Any]],
              var newConfig = ConfigCodec.parseObject(from: newConfigText),
              var newOutbounds = newConfig["outbounds"] as? [[String: Any]] else {
            return newConfigText
        }

        var existingDefaults: [String: String] = [:]
        for outbound in existingOutbounds {
            if (outbound["type"] as? String)?.lowercased() == "selector",
               let tag = outbound["tag"] as? String,
               let def = outbound["default"] as? String, !def.isEmpty {
                existingDefaults[tag] = def
            }
        }

        guard !existingDefaults.isEmpty else { return newConfigText }

        var changed = false
        for i in newOutbounds.indices {
            if (newOutbounds[i]["type"] as? String)?.lowercased() == "selector",
               let tag = newOutbounds[i]["tag"] as? String,
               let existingDefault = existingDefaults[tag] {
                let members = newOutbounds[i]["outbounds"] as? [String] ?? []
                if members.contains(existingDefault) {
                    newOutbounds[i]["default"] = existingDefault
                    changed = true
                }
            }
        }

        guard changed else { return newConfigText }
        newConfig["outbounds"] = newOutbounds
        return (try? ConfigCodec.render(newConfig)) ?? newConfigText
    }
}
