import Foundation

/// 模式配置转换。调用方明确传入模式与节点回退值，不读取窗口或运行状态。
enum ProxyModeConfig {
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
        rules = [
            ["action": "sniff"],
            ["protocol": "dns", "action": "hijack-dns"],
            ["clash_mode": "direct", "outbound": "direct"],
            ["clash_mode": "global", "outbound": globalTag]
        ] + rules
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
}
