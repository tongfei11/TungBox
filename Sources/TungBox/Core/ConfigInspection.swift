import Foundation

/// 配置展示数据解析。只处理输入配置与订阅/规则集快照，不读取窗口、偏好或文件。
enum ConfigInspection {
    struct RuleSetSnapshot {
        let ruleSet: CustomRuleSet
        let referenceError: String?
    }

    struct RuleContext {
        var customRules: [CustomRule] = []
        var ruleSets: [RuleSetSnapshot] = []
        var invalidRuleSets: [InvalidRuleSet] = []
        var ruleSetApplyStatus: String = ""
        var cachedRuleSetEntries: [String: [RuleSetEntry]] = [:]
        var downloadingRuleSets: Set<String> = []
    }

    /// 只读取会展开的引用，保留首次出现顺序；action 规则不展开。
    static func referencedRuleSetTags(in config: [String: Any]) -> [String] {
        let route = config["route"] as? [String: Any] ?? [:]
        let dns = config["dns"] as? [String: Any] ?? [:]
        let routeRules = (route["rules"] as? [[String: Any]] ?? []).filter { !($0["action"] is String) }
        let dnsRules = dns["rules"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        return (routeRules + dnsRules).flatMap { rule -> [String] in
            if let tags = rule["rule_set"] as? [String] { return tags }
            if let tag = rule["rule_set"] as? String { return [tag] }
            return []
        }.filter { seen.insert($0).inserted }
    }

    static func parseNodes(from text: String) -> [NodeInfo] {
        guard let object = ConfigCodec.parseObject(from: text),
              let outbounds = object["outbounds"] as? [[String: Any]] else { return [] }
        let hiddenTypes = Set(["direct", "block", "dns", "selector", "urltest", "url-test"])
        return outbounds.compactMap { outbound in
            let type = (outbound["type"] as? String) ?? "unknown"
            guard !hiddenTypes.contains(type.lowercased()) else { return nil }
            let tag = (outbound["tag"] as? String) ?? type
            let server = outbound["server"].map { "\($0)" } ?? ""
            let port = outbound["server_port"].map { ":\($0)" } ?? ""
            let transport = (outbound["transport"] as? [String: Any])?["type"] as? String ?? ""
            let network = (outbound["network"] as? String)?.lowercased() ?? ""
            // QUIC-based protocols are inherently UDP; others relay UDP unless the
            // outbound restricts `network` to tcp only.
            let quicTypes = Set(["hysteria", "hysteria2", "tuic"])
            let supportsUDP = quicTypes.contains(type.lowercased()) || network != "tcp"
            let tls = (outbound["tls"] as? [String: Any])?["enabled"] as? Bool ?? false
            return NodeInfo(tag: tag, type: type, server: server + port, delay: "未测试",
                            transport: transport, supportsUDP: supportsUDP, tls: tls)
        }
    }

    static func parseNodeGroups(from text: String) -> [NodeGroupInfo] {
        guard let object = ConfigCodec.parseObject(from: text),
              let outbounds = object["outbounds"] as? [[String: Any]] else { return [] }

        let nodeTags = parseNodes(from: text).map(\.tag)
        var groups: [NodeGroupInfo] = []
        for outbound in outbounds {
            let type = ((outbound["type"] as? String) ?? "").lowercased()
            guard ["selector", "urltest", "url-test", "fallback"].contains(type),
                  let tag = outbound["tag"] as? String else { continue }
            let members = outbound["outbounds"] as? [String] ?? []
            let current = (outbound["default"] as? String) ?? members.first ?? ""
            groups.append(NodeGroupInfo(tag: tag, type: type, members: members, current: current))
        }

        if groups.isEmpty, !nodeTags.isEmpty {
            groups.append(NodeGroupInfo(tag: TungBoxConfig.tagManual, type: "selector", members: nodeTags, current: nodeTags.first ?? ""))
        }
        return groups
    }

    static func buildRulesSummary(from text: String) -> String {
        guard let config = ConfigCodec.parseObject(from: text) else {
            return "当前配置不是可读取的 JSON。"
        }

        var lines: [String] = []
        let mode = ProxyModeConfig.readMode(from: config)
        lines.append("当前模式")
        lines.append("  \(modeDisplayName(mode))")
        lines.append("")

        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let nodeOutbounds = outbounds.filter { outbound in
            let type = ((outbound["type"] as? String) ?? "").lowercased()
            return !["direct", "block", "dns", "selector", "urltest", "url-test"].contains(type)
        }

        lines.append("节点分组")
        if let auto = firstOutbound(in: outbounds, tag: TungBoxConfig.tagAuto) {
            let autoNodes = auto["outbounds"] as? [String] ?? []
            lines.append("  自动选择")
            lines.append("    类型: \(auto["type"] ?? "urltest")")
            lines.append("    节点数: \(autoNodes.count)")
            lines.append("    检测间隔: \(auto["interval"] ?? "未设置")")
            lines.append("    容差: \(auto["tolerance"] ?? "未设置") ms")
            lines.append("    空闲超时: \(auto["idle_timeout"] ?? "未设置")")
            lines.append("    断线切换: \(boolText(auto["interrupt_exist_connections"]))")
            lines.append("    成员: \(joined(autoNodes))")
        } else {
            lines.append("  未找到 自动选择 urltest 分组")
        }

        if let manual = firstOutbound(in: outbounds, tag: TungBoxConfig.tagManual) {
            let manualNodes = manual["outbounds"] as? [String] ?? []
            lines.append("  节点选择")
            lines.append("    默认: \((manual["default"] as? String) ?? "未设置")")
            lines.append("    可选: \(joined(manualNodes))")
        } else {
            lines.append("  未找到 节点选择 selector 分组")
        }
        lines.append("  直连: direct")
        lines.append("  订阅节点: \(nodeOutbounds.count) 个")
        for outbound in nodeOutbounds {
            let tag = (outbound["tag"] as? String) ?? "未命名"
            let type = (outbound["type"] as? String) ?? "unknown"
            let server = outbound["server"].map { "\($0)" } ?? ""
            let port = outbound["server_port"].map { ":\($0)" } ?? ""
            lines.append("    - \(tag)  [\(type)] \(server)\(port)")
        }
        lines.append("")

        let route = config["route"] as? [String: Any] ?? [:]
        let ruleSets = route["rule_set"] as? [[String: Any]] ?? []
        lines.append("规则集")
        if ruleSets.isEmpty {
            lines.append("  当前配置没有 route.rule_set")
        } else {
            for ruleSet in ruleSets {
                let tag = (ruleSet["tag"] as? String) ?? "未命名"
                let format = (ruleSet["format"] as? String) ?? "unknown"
                let interval = (ruleSet["update_interval"] as? String) ?? "未设置"
                let detour = (ruleSet["download_detour"] as? String) ?? "默认"
                lines.append("  - \(tag)  \(format), 更新 \(interval), 下载出站 \(detour)")
            }
        }
        lines.append("")

        let rules = route["rules"] as? [[String: Any]] ?? []
        lines.append("分流规则")
        if rules.isEmpty {
            lines.append("  当前配置没有 route.rules")
        } else {
            for (index, rule) in rules.enumerated() {
                lines.append("  \(index + 1). \(describeRouteRule(rule))")
            }
        }
        lines.append("  final -> \((route["final"] as? String) ?? "未设置")")
        lines.append("")

        let dns = config["dns"] as? [String: Any] ?? [:]
        let dnsRules = dns["rules"] as? [[String: Any]] ?? []
        lines.append("DNS 规则")
        if dnsRules.isEmpty {
            lines.append("  当前配置没有 dns.rules")
        } else {
            for (index, rule) in dnsRules.enumerated() {
                lines.append("  \(index + 1). \(describeDNSRule(rule))")
            }
        }
        lines.append("  final -> \((dns["final"] as? String) ?? "未设置")")

        return lines.joined(separator: "\n")
    }

    private static func firstOutbound(in outbounds: [[String: Any]], tag: String) -> [String: Any]? {
        outbounds.first { ($0["tag"] as? String) == tag }
    }

    static func modeDisplayName(_ mode: String) -> String {
        switch mode.lowercased() {
        case "global": return "全局"
        case "direct": return "直连"
        default: return "规则"
        }
    }

    private static func boolText(_ value: Any?) -> String {
        guard let value = value as? Bool else { return "未设置" }
        return value ? "开启" : "关闭"
    }

    private static func joined(_ values: [String]) -> String {
        values.isEmpty ? "无" : values.joined(separator: ", ")
    }

    private static func describeRouteRule(_ rule: [String: Any]) -> String {
        if let action = rule["action"] as? String {
            if let protocolValue = rule["protocol"] as? String {
                return "\(protocolValue) -> \(action)"
            }
            return action
        }
        let outbound = (rule["outbound"] as? String) ?? "未设置出站"
        if let clashMode = rule["clash_mode"] as? String {
            return "模式 \(modeDisplayName(clashMode)) -> \(outbound)"
        }
        if let ruleSet = rule["rule_set"] {
            return "规则集 \(compactDescription(ruleSet)) -> \(outbound)"
        }
        if let cidr = rule["ip_cidr"] {
            return "IP 段 \(compactDescription(cidr)) -> \(outbound)"
        }
        return "\(compactDescription(rule)) -> \(outbound)"
    }

    private static func describeDNSRule(_ rule: [String: Any]) -> String {
        let server = (rule["server"] as? String) ?? "未设置 DNS"
        if let clashMode = rule["clash_mode"] as? String {
            return "模式 \(modeDisplayName(clashMode)) -> \(server)"
        }
        if let ruleSet = rule["rule_set"] {
            return "规则集 \(compactDescription(ruleSet)) -> \(server)"
        }
        return "\(compactDescription(rule)) -> \(server)"
    }

    private static func compactDescription(_ value: Any) -> String {
        if let values = value as? [String] {
            return values.joined(separator: ", ")
        }
        if let value = value as? String {
            return value
        }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "\(value)"
    }

    static func ruleRows(in config: [String: Any]?, context: RuleContext = .init()) -> [RuleInfo] {
        guard let config else {
            return [sectionRule("当前配置不是可读取的 JSON")]
        }

        var rows: [RuleInfo] = []
        var nextID = 1

        func append(_ type: String, _ value: String, _ strategy: String, _ note: String = "", enabled: Bool = true, count: String = "0") {
            rows.append(RuleInfo(
                customRuleID: nil,
                enabled: enabled,
                id: "\(nextID)",
                type: type,
                value: value,
                strategy: strategy,
                count: count,
                note: note,
                isSection: false
            ))
            nextID += 1
        }

        func appendCustom(_ rule: CustomRule) {
            rows.append(RuleInfo(
                customRuleID: rule.id,
                enabled: rule.enabled,
                id: "\(nextID)",
                type: rule.type,
                value: rule.value,
                strategy: displayStrategy(RuleRouting.outboundForStrategy(rule.strategy)),
                count: "0",
                note: rule.note.isEmpty ? "自定义规则" : rule.note,
                isSection: false
            ))
            nextID += 1
        }

        let currentCustomRules = context.customRules
        rows.append(sectionRule("自定义规则"))
        if currentCustomRules.isEmpty {
            append("CUSTOM", "当前订阅还没有自定义规则", "未设置", "通过上方输入框添加", enabled: false)
        } else {
            for rule in currentCustomRules {
                appendCustom(rule)
            }
        }

        // 规则集（分流方案）
        let sets = context.ruleSets.map(\.ruleSet)
        if !sets.isEmpty || !context.invalidRuleSets.isEmpty {
            rows.append(sectionRule("规则集"))
            for snapshot in context.ruleSets {
                let set = snapshot.ruleSet
                rows.append(RuleInfo(
                    customRuleID: nil,
                    enabled: set.enabled && snapshot.referenceError == nil,
                    id: "\(nextID)",
                    type: "规则集",
                    value: set.name,
                    strategy: displayStrategy(RuleRouting.outboundForStrategy(set.outbound)),
                    count: "\(set.rules.count) 条",
                    note: snapshot.referenceError ?? (set.enabled ? context.ruleSetApplyStatus : "已停用"),
                    isSection: false,
                    ruleSetID: set.id
                ))
                nextID += 1
            }
            for invalid in context.invalidRuleSets {
                rows.append(RuleInfo(
                    customRuleID: nil,
                    enabled: false,
                    id: "\(nextID)",
                    type: "规则集",
                    value: invalid.name,
                    strategy: "—",
                    count: "!",
                    note: "⚠️ \(invalid.reason)",
                    isSection: false,
                    ruleSetInvalidURL: invalid.fileURL
                ))
                nextID += 1
            }
        }

        // Route rules injected by enabled rule sets — hidden from "当前配置规则" so they
        // don't duplicate the rule-set section above.
        let ruleSetGenerated: [[String: Any]] = sets.filter { $0.enabled }.flatMap { set in
            set.rules.map { RuleRouting.customRouteRule(type: $0.type, value: $0.value, strategy: set.outbound) }
        }

        let route = config["route"] as? [String: Any] ?? [:]
        let rules = route["rules"] as? [[String: Any]] ?? []
        rows.append(sectionRule("当前配置规则"))
        for rule in rules {
            if currentCustomRules.contains(where: { customRuleMatches($0, rule) }) {
                continue
            }
            if ruleSetGenerated.contains(where: { NSDictionary(dictionary: $0).isEqual(to: rule) }) {
                continue
            }
            if let action = rule["action"] as? String {
                let protocolValue = (rule["protocol"] as? String) ?? "ALL"
                append("ACTION", protocolValue, action.uppercased(), "sing-box action")
                continue
            }
            let strategy = displayStrategy((rule["outbound"] as? String) ?? (rule["server"] as? String) ?? "")
            if let clashMode = rule["clash_mode"] as? String {
                append("MODE", modeDisplayName(clashMode), strategy, "模式规则")
            }
            if let ruleSet = rule["rule_set"] {
                appendExpandedRuleSetRows(ruleSet, strategy: strategy, rows: &rows, nextID: &nextID, context: context)
            }
            if let cidr = rule["ip_cidr"] {
                append("IP-CIDR", compactDescription(cidr), strategy, "IP 段")
            }
            if let priv = rule["ip_is_private"] as? Bool, priv {
                append("LAN", "内网 / 私有地址", strategy, "内网")
            }
            if let domains = rule["domain"] {
                appendEachRuleValue(type: "DOMAIN", values: domains, strategy: strategy, note: "显式域名", append: append)
            }
            if let suffixes = rule["domain_suffix"] {
                appendEachRuleValue(type: "DOMAIN-SUFFIX", values: suffixes, strategy: strategy, note: "域名后缀", append: append)
            }
            if let keywords = rule["domain_keyword"] {
                appendEachRuleValue(type: "DOMAIN-KEYWORD", values: keywords, strategy: strategy, note: "域名关键字", append: append)
            }
            if let regexes = rule["domain_regex"] {
                appendEachRuleValue(type: "DOMAIN-REGEX", values: regexes, strategy: strategy, note: "域名正则", append: append)
            }
            if let sourceCIDR = rule["source_ip_cidr"] {
                appendEachRuleValue(type: "SRC-IP", values: sourceCIDR, strategy: strategy, note: "源 IP", append: append)
            }
            if let processName = rule["process_name"] {
                appendEachRuleValue(type: "PROCESS-NAME", values: processName, strategy: strategy, note: "进程", append: append)
            }
            if let processPath = rule["process_path"] {
                appendEachRuleValue(type: "PROCESS-PATH", values: processPath, strategy: strategy, note: "进程路径", append: append)
            }
            if let port = rule["port"] {
                appendEachRuleValue(type: "DEST-PORT", values: port, strategy: strategy, note: "端口", append: append)
            }
            if let network = rule["network"] {
                appendEachRuleValue(type: "NETWORK", values: network, strategy: strategy, note: "网络类型", append: append)
            }
        }

        if let final = route["final"] as? String {
            append("FINAL", "未命中以上规则", displayStrategy(final), "默认策略")
        }

        let dns = config["dns"] as? [String: Any] ?? [:]
        let dnsRules = dns["rules"] as? [[String: Any]] ?? []
        if !dnsRules.isEmpty {
            rows.append(sectionRule("DNS 规则"))
            for rule in dnsRules {
                let server = (rule["server"] as? String) ?? "未设置"
                if let clashMode = rule["clash_mode"] as? String {
                    append("DNS-MODE", modeDisplayName(clashMode), server, "DNS 模式规则")
                }
                if let ruleSet = rule["rule_set"] {
                    appendExpandedRuleSetRows(ruleSet, strategy: server, rows: &rows, nextID: &nextID, context: context, notePrefix: "DNS")
                }
            }
            if let final = dns["final"] as? String {
                append("DNS-FINAL", "未命中以上 DNS 规则", final, "默认 DNS")
            }
        }

        return rows
    }

    private static func sectionRule(_ title: String) -> RuleInfo {
        RuleInfo(customRuleID: nil, enabled: false, id: "", type: "", value: "# \(title)", strategy: "", count: "", note: "", isSection: true)
    }

    private static func appendExpandedRuleSetRows(
        _ ruleSetValue: Any,
        strategy: String,
        rows: inout [RuleInfo],
        nextID: inout Int,
        context: RuleContext,
        notePrefix: String = "规则集"
    ) {
        let tags: [String]
        if let values = ruleSetValue as? [String] {
            tags = values
        } else if let value = ruleSetValue as? String {
            tags = [value]
        } else {
            tags = []
        }

        for tag in tags {
            let entries = context.cachedRuleSetEntries[tag] ?? []
            if entries.isEmpty {
                rows.append(RuleInfo(
                    customRuleID: nil,
                    enabled: true,
                    id: "\(nextID)",
                    type: "RULE-SET",
                    value: tag,
                    strategy: strategy,
                    count: "0",
                    note: context.downloadingRuleSets.contains(tag) ? "下载中" : "等待下载",
                    isSection: false
                ))
                nextID += 1
            } else {
                rows.append(sectionRule("\(notePrefix)内容：\(tag)"))
                for entry in entries {
                    rows.append(RuleInfo(
                        customRuleID: nil,
                        enabled: true,
                        id: "\(nextID)",
                        type: entry.type,
                        value: entry.value,
                        strategy: strategy,
                        count: "0",
                        note: tag,
                        isSection: false
                    ))
                    nextID += 1
                }
            }
        }
    }

    private static func appendRuleSetValues(type: String, key: String, from rule: [String: Any], to entries: inout [RuleSetEntry]) {
        if let values = rule[key] as? [String] {
            for value in values {
                entries.append(RuleSetEntry(type: type, value: value))
            }
        } else if let value = rule[key] as? String {
            entries.append(RuleSetEntry(type: type, value: value))
        }
    }

    private static func displayStrategy(_ strategy: String) -> String {
        switch strategy {
        case TungBoxConfig.tagDirect: return "DIRECT"
        case TungBoxConfig.tagBlock: return "REJECT"
        case TungBoxConfig.tagManual: return "Proxy"
        case TungBoxConfig.tagAuto: return "AUTO"
        default: return strategy.isEmpty ? "未设置" : strategy
        }
    }

    private static func appendEachRuleValue(
        type: String,
        values: Any,
        strategy: String,
        note: String,
        append: (String, String, String, String, Bool, String) -> Void
    ) {
        if let list = values as? [String] {
            for value in list {
                append(type, value, strategy, note, true, "0")
            }
        } else if let value = values as? String {
            append(type, value, strategy, note, true, "0")
        } else {
            append(type, compactDescription(values), strategy, note, true, "0")
        }
    }

    private static func customRuleMatches(_ customRule: CustomRule, _ routeRule: [String: Any]) -> Bool {
        let expected = RuleRouting.customRouteRule(type: customRule.type, value: customRule.value, strategy: customRule.strategy)
        return NSDictionary(dictionary: expected).isEqual(to: routeRule)
    }

    static func ruleSetEntries(from data: Data) -> [RuleSetEntry] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = object["rules"] as? [[String: Any]] else { return [] }

        var entries: [RuleSetEntry] = []
        for rule in rules {
            appendRuleSetValues(type: "DOMAIN", key: "domain", from: rule, to: &entries)
            appendRuleSetValues(type: "DOMAIN-SUFFIX", key: "domain_suffix", from: rule, to: &entries)
            appendRuleSetValues(type: "DOMAIN-KEYWORD", key: "domain_keyword", from: rule, to: &entries)
            appendRuleSetValues(type: "DOMAIN-REGEX", key: "domain_regex", from: rule, to: &entries)
            appendRuleSetValues(type: "IP-CIDR", key: "ip_cidr", from: rule, to: &entries)
            appendRuleSetValues(type: "SRC-IP", key: "source_ip_cidr", from: rule, to: &entries)
            appendRuleSetValues(type: "PROCESS-NAME", key: "process_name", from: rule, to: &entries)
        }
        return entries
    }
}
