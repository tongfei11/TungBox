import Foundation

enum SubscriptionImporter {
    /// 机场后端常按 User-Agent 返回不同格式。同一个订阅 URL，sing-box UA 拿到
    /// 的可能是没有节点的"骨架"，而 Clash UA 拿到完整节点表。fetch 优先用
    /// sing-box UA（原生格式最优），上层若解析到 0 节点会用回退 UA 重试。
    ///
    /// 只列我们实际**能解析**的格式对应的 UA（sing-box JSON / Clash YAML）。
    /// 不列 Surge 或 NekoBox UA：那些 UA 服务端会返回 Surge MANAGED-CONFIG 或
    /// base64 share-link 列表，我们当前不解析这些格式，加进来只会浪费一次请求。
    static let fallbackUserAgents = [
        "sing-box/1.12.0",
        "clash-verge/v2.4.4 mihomo/Meta",
        "ClashMetaForAndroid/2.11.10.Meta",
        "Clash/v1.18.0"
    ]

    /// 解析 HTTP 响应头里的 `subscription-userinfo: upload=X; download=Y; total=Z; expire=T`。
    /// expire 为空或 0 表示无限期。
    struct SubscriptionUserInfo {
        var upload: Int64?
        var download: Int64?
        var total: Int64?
        var expiresAt: Date?
    }

    static func parseSubscriptionUserInfo(_ header: String?) -> SubscriptionUserInfo {
        var info = SubscriptionUserInfo()
        guard let header = header else { return info }
        for part in header.components(separatedBy: ";") {
            let kv = part.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
            let raw = kv[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "upload":   info.upload = Int64(raw)
            case "download": info.download = Int64(raw)
            case "total":    info.total = Int64(raw)
            case "expire":
                if let ts = TimeInterval(raw), ts > 0 {
                    info.expiresAt = Date(timeIntervalSince1970: ts)
                }
            default: break
            }
        }
        return info
    }

    /// Fetch the subscription trying multiple User-Agents until one returns content
    /// that parses to at least one node. Mirrors what NekoBox/Surge users would see
    /// — the same URL returns different formats per UA, and we always want the one
    /// with real nodes (not the "skeleton" some panels return for unrecognized UAs).
    /// Also returns the standard `subscription-userinfo` header so the UI can show
    /// traffic usage / expiry.
    static func fetchBest(urlString: String) throws -> (text: String, userAgent: String, info: SubscriptionUserInfo) {
        var lastError: Error? = nil
        var lastFetched: (text: String, info: SubscriptionUserInfo)? = nil
        for ua in fallbackUserAgents {
            do {
                let (text, header) = try fetchWithHeader(urlString: urlString, userAgent: ua)
                let info = parseSubscriptionUserInfo(header)
                lastFetched = (text, info)
                if let nodes = try? extractNodesFromAnyFormat(text), !nodes.isEmpty {
                    return (text, ua, info)
                }
            } catch {
                lastError = error
            }
        }
        if let f = lastFetched { return (f.text, fallbackUserAgents.last ?? "", f.info) }
        throw lastError ?? NSError.user("订阅下载失败")
    }

    /// fetch 的内部版本，同时返回响应里的 `subscription-userinfo`。
    private static func fetchWithHeader(urlString: String, userAgent: String) throws -> (text: String, header: String?) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw NSError.user("订阅地址必须是 http 或 https URL")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as AnyHashable: 0,
            kCFNetworkProxiesHTTPSEnable as AnyHashable: 0,
            kCFNetworkProxiesSOCKSEnable as AnyHashable: 0
        ]
        let session = URLSession(configuration: config)
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedValue<Result<(Data, URLResponse), Error>?>(nil)
        session.dataTask(with: request) { data, response, error in
            if let error { result.set(.failure(error)) }
            else { result.set(.success((data ?? Data(), response ?? URLResponse()))) }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 30)
        guard let resolved = result.get() else { throw NSError.user("订阅下载超时，请检查网络或订阅地址") }
        let (data, response) = try resolved.get()
        let http = response as? HTTPURLResponse
        if let http, !(200..<300).contains(http.statusCode) {
            throw NSError.user("订阅下载失败：HTTP \(http.statusCode)")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError.user("订阅内容不是 UTF-8 文本")
        }
        // 响应头大小写不敏感；标准 key 是 subscription-userinfo
        let header = http?.value(forHTTPHeaderField: "subscription-userinfo")
            ?? http?.value(forHTTPHeaderField: "Subscription-Userinfo")
        return (text, header)
    }

    static func fetch(urlString: String, userAgent: String = "sing-box/1.12.0") throws -> String {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw NSError.user("订阅地址必须是 http 或 https URL")
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        // 订阅下载必须直连，不能走系统代理。否则代理开着时 URLSession 会读
        // 系统代理设置（指向 127.0.0.1:7890）→ 订阅请求经自家代理 → 该域名若
        // 命中代理规则又被丢回本机，自家代理空转/超时 → 刷新失败 → 触发崩溃路径。
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as AnyHashable: 0,
            kCFNetworkProxiesHTTPSEnable as AnyHashable: 0,
            kCFNetworkProxiesSOCKSEnable as AnyHashable: 0
        ]
        let session = URLSession(configuration: config)

        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedValue<Result<(Data, URLResponse), Error>?>(nil)
        session.dataTask(with: request) { data, response, error in
            if let error {
                result.set(.failure(error))
            } else {
                result.set(.success((data ?? Data(), response ?? URLResponse())))
            }
            semaphore.signal()
        }.resume()
        // 30s timeout guard — prevents hanging if semaphore never signals
        _ = semaphore.wait(timeout: .now() + 30)

        guard let resolved = result.get() else {
            throw NSError.user("订阅下载超时，请检查网络或订阅地址")
        }
        let (data, response) = try resolved.get()
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError.user("订阅下载失败：HTTP \(http.statusCode)")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError.user("订阅内容不是 UTF-8 文本")
        }
        return text
    }

    static func singBoxConfig(from text: String, profileName: String) throws -> String {
        let parsed = try parseSubscription(text)
        let nodes = extractNodes(fromConfig: parsed.config)
        guard !nodes.isEmpty else {
            throw NSError.user("订阅内容里没有可用的 sing-box 节点。请确认 Xboard 模板输出 outbounds。")
        }
        var config = try generateManagedConfig(profileName: profileName, nodes: nodes, subscriptionRuleSetURLs: parsed.ruleSetURLs)

        // Auto-fix deprecated sing-box fields for compatibility with newer Core
        let (fixed, fixLog) = ConfigCompatibilityChecker.autoFix(config: config)
        // Log auto-fixes so user can review
        for msg in fixLog {
            SubscriptionImporter.compatibilityFixLog.append("[兼容性] [AUTO-FIX] \(msg)")
        }
        config = fixed

        return try renderJSON(config)
    }

    /// Collects compatibility fix messages to be logged after import completes.
    nonisolated(unsafe) static var compatibilityFixLog: [String] = []

    static func extractNodes(from text: String) throws -> [[String: Any]] {
        let parsed = try parseSubscription(text)
        return extractNodes(fromConfig: parsed.config)
    }

    private static func parseSubscription(_ text: String) throws -> (config: [String: Any], ruleSetURLs: [String: String]) {
        let format = SubscriptionFormatParser.detectFormat(text)

        // sing-box JSON: use existing logic (config structure + rule sets already present)
        // 给 sing-box JSON 分支做诊断：服务端可能下发了一份"骨架配置"——只有
        // selector/urltest 组但成员是空的，订阅过期/套餐用完时常见。
        var diagnostic: String? = nil
        if format == .singBoxJSON {
            let candidates = [
                text.trimmingCharacters(in: .whitespacesAndNewlines),
                decodeBase64(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            ].filter { !$0.isEmpty }

            for candidate in candidates {
                guard let config = jsonObject(from: candidate) else { continue }
                let nodes = extractNodes(fromConfig: config)
                if !nodes.isEmpty {
                    return (config, extractRuleSetURLs(fromConfig: config))
                }
                // 收集第一份能解析但 0 物理节点的配置作为诊断
                if diagnostic == nil, let obs = config["outbounds"] as? [[String: Any]] {
                    let virtual: Set<String> = ["selector", "urltest", "url-test", "fallback", "direct", "block", "dns"]
                    let virtualCount = obs.filter { virtual.contains(($0["type"] as? String)?.lowercased() ?? "") }.count
                    diagnostic = "下发了 \(obs.count) 个 outbound，其中 \(virtualCount) 个是 selector/urltest/direct 等虚拟节点，0 个真实代理节点"
                }
            }
        }

        // Clash YAML / share links: extract nodes, wrap in minimal config
        let rawNodes: [[String: Any]]
        switch format {
        case .singBoxJSON:
            let detail = diagnostic.map { "\n\n诊断：\($0)。" } ?? ""
            throw NSError.user("订阅内容是合法的 sing-box JSON，但里面没有真实代理节点。\(detail)\n\n常见原因：订阅 token 已过期、套餐已用完/到期、或服务端模板配置错误。请联系订阅服务商核查。")
        case .clashYAML:
            rawNodes = try SubscriptionFormatParser.parseClashProxies(text)
        case .unknown:
            throw NSError.user("无法识别订阅格式。支持：\n• sing-box JSON（Xboard 面板模板输出）\n• Clash YAML（机场通用订阅格式）\n\nTungBox 仅支持订阅链接（http/https）导入，不支持单条节点分享链接（vmess:// / trojan:// 等）。\n\n当前内容预览：\(text.prefix(300))")
        }

        // 过滤"信息伪节点"（剩余流量/套餐到期/官网/客服群 等）—— 这些机场塞进
        // proxies 列表当公告用，连不上代理。默认过滤，不暴露开关。
        let nodes = rawNodes.filter { !isFakeInfoNode($0) }

        guard !nodes.isEmpty else {
            throw NSError.user("解析到 0 个可用节点，请检查订阅内容是否有效。")
        }

        // Wrap extracted nodes in a minimal config with route + DNS
        let nodeTags = nodes.compactMap { $0["tag"] as? String }
        let config: [String: Any] = [
            "outbounds": [[
                "type": "urltest",
                "tag": TungBoxConfig.tagAuto,
                "outbounds": nodeTags,
                "url": TungBoxConfig.urlTestURL,
                "interval": "3m",
                "tolerance": 50,
                "idle_timeout": "10m",
                "interrupt_exist_connections": true
            ], [
                "type": "selector",
                "tag": TungBoxConfig.tagManual,
                "outbounds": [TungBoxConfig.tagAuto] + nodeTags,
                "default": TungBoxConfig.tagAuto,
                "interrupt_exist_connections": true
            ]] + nodes + [
                ["type": "direct", "tag": TungBoxConfig.tagDirect],
                ["type": "block", "tag": TungBoxConfig.tagBlock]
            ],
            "dns": basicDNS(),
            "route": basicRoute(),
            "log": ["level": "info", "timestamp": true],
            "experimental": ["cache_file": ["enabled": true], "clash_api": ["external_controller": TungBoxConfig.clashAPIListen, "default_mode": "Rule"]],
            "inbounds": [["type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": TungBoxConfig.mixedPort]]
        ]
        return (config, [:])
    }

    private static func basicDNS() -> [String: Any] {[
        "servers": [
            ["type": "udp", "tag": "dns-local", "server": "223.5.5.5", "server_port": 53],
            ["type": "udp", "tag": "dns-proxy", "server": "1.1.1.1", "server_port": 53, "detour": TungBoxConfig.tagManual]
        ],
        "rules": [
            ["rule_set": [TungBoxConfig.ruleSetCN, TungBoxConfig.ruleSetPrivate], "server": "dns-local"],
            ["rule_set": TungBoxConfig.ruleSetGeolocationNotCN, "server": "dns-proxy"]
        ],
        "final": "dns-proxy",
        "strategy": "prefer_ipv4"
    ]}

    private static func basicRoute() -> [String: Any] {[
        "rule_set": [
            ["type": "remote", "tag": TungBoxConfig.ruleSetPrivate, "format": "binary", "url": TungBoxConfig.resolvedRuleSetURL(for: TungBoxConfig.ruleSetPrivate, subscriptionURLs: [:]), "download_detour": TungBoxConfig.tagDirect, "update_interval": "7d"],
            ["type": "remote", "tag": TungBoxConfig.ruleSetCN, "format": "binary", "url": TungBoxConfig.resolvedRuleSetURL(for: TungBoxConfig.ruleSetCN, subscriptionURLs: [:]), "download_detour": TungBoxConfig.tagManual, "update_interval": "1d"],
            ["type": "remote", "tag": TungBoxConfig.ruleSetGeolocationNotCN, "format": "binary", "url": TungBoxConfig.resolvedRuleSetURL(for: TungBoxConfig.ruleSetGeolocationNotCN, subscriptionURLs: [:]), "download_detour": TungBoxConfig.tagManual, "update_interval": "1d"],
            ["type": "remote", "tag": TungBoxConfig.ruleSetGeoIPCN, "format": "binary", "url": TungBoxConfig.resolvedRuleSetURL(for: TungBoxConfig.ruleSetGeoIPCN, subscriptionURLs: [:]), "download_detour": TungBoxConfig.tagManual, "update_interval": "1d"]
        ],
        "rules": [
            ["action": "sniff"],
            ["protocol": "dns", "action": "hijack-dns"],
            ["rule_set": TungBoxConfig.ruleSetPrivate, "outbound": TungBoxConfig.tagDirect],
            ["rule_set": [TungBoxConfig.ruleSetCN, TungBoxConfig.ruleSetGeoIPCN], "outbound": TungBoxConfig.tagDirect],
            ["rule_set": TungBoxConfig.ruleSetGeolocationNotCN, "outbound": TungBoxConfig.tagManual],
            ["ip_cidr": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "169.254.0.0/16", "224.0.0.0/4", "fc00::/7", "fe80::/10", "::1/128"], "outbound": TungBoxConfig.tagDirect]
        ],
        "final": TungBoxConfig.tagManual,
        "default_domain_resolver": "dns-local",
        "auto_detect_interface": true
    ]}

    private static func extractRuleSetURLs(fromConfig config: [String: Any]) -> [String: String] {
        guard let route = config["route"] as? [String: Any],
              let ruleSets = route["rule_set"] as? [[String: Any]] else { return [:] }
        var result: [String: String] = [:]
        for ruleSet in ruleSets {
            guard let tag = ruleSet["tag"] as? String,
                  let url = ruleSet["url"] as? String,
                  !tag.isEmpty,
                  !url.isEmpty else { continue }
            result[tag] = url
        }
        return result
    }

    private static func extractNodes(fromConfig config: [String: Any]) -> [[String: Any]] {
        guard let outbounds = config["outbounds"] as? [[String: Any]] else { return [] }
        var outboundByTag: [String: [String: Any]] = [:]
        for outbound in outbounds {
            guard let tag = outbound["tag"] as? String, !tag.isEmpty else { continue }
            outboundByTag[tag] = outbound
        }

        var result: [[String: Any]] = []
        var seen = Set<String>()

        for outbound in outbounds {
            appendNode(outbound, to: &result, seen: &seen)
        }

        for outbound in outbounds {
            guard let refs = outbound["outbounds"] as? [String] else { continue }
            for ref in refs {
                if let node = outboundByTag[ref], !seen.contains(ref) {
                    appendNode(node, to: &result, seen: &seen)
                }
            }
        }

        return result
    }

    private static func appendNode(_ outbound: [String: Any], to result: inout [[String: Any]], seen: inout Set<String>) {
        guard let type = outbound["type"] as? String,
              isNodeOutbound(type),
              isUsableNode(outbound),
              !isFakeInfoNode(outbound) else { return }

        var node = outbound
        let tag = uniqueTag(normalizedTag(node["tag"] as? String, type: type, server: node["server"] as? String, index: result.count), seen: seen)
        node["tag"] = tag
        result.append(node)
        seen.insert(tag)
    }

    /// 机场常把套餐/流量/官网这些"提示信息"塞成伪节点（同一台 server，名字写
    /// "剩余流量：xxx GB" / "套餐到期：2027-..." / "永久官网《xxx》" 等）。这些
    /// 节点连不上代理，留在列表里只会占位 + 让测速一片失败。默认过滤，不暴露开关。
    static func isFakeInfoNode(_ outbound: [String: Any]) -> Bool {
        guard let tag = outbound["tag"] as? String else { return false }
        let lower = tag.lowercased()
        // 中文常见
        let zhKeywords = ["剩余流量", "套餐", "到期", "重置", "官网", "网址", "群组", "telegram", "频道", "续费", "购买", "tg群", "TG群", "客服", "qq群", "QQ群", "公告"]
        for kw in zhKeywords where tag.contains(kw) { return true }
        // 英文常见
        let enKeywords = ["expire", "reset", "traffic", "website", "homepage", "official", "subscribe", "renew", "remaining", "left:"]
        for kw in enKeywords where lower.contains(kw) { return true }
        // 含 URL/域名后缀的多半是导航/官网节点
        if lower.contains("http://") || lower.contains("https://") { return true }
        // 名字里直接带带宽/天数信息（如 "剩余 28 天"、"127.39 GB"）
        if tag.range(of: #"\d+(\.\d+)?\s*(GB|MB|TB|KB|gb|mb|tb)"#, options: .regularExpression) != nil { return true }
        if tag.range(of: #"\d+\s*(天|day|days)"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func isNodeOutbound(_ type: String) -> Bool {
        let nonNodeTypes = Set(["direct", "block", "dns", "selector", "urltest", "url-test"])
        return !nonNodeTypes.contains(type.lowercased())
    }

    private static func isUsableNode(_ outbound: [String: Any]) -> Bool {
        guard let server = outbound["server"] as? String else { return true }
        let invalidServers = Set(["0.0.0.0", "127.0.0.1", "localhost", "::1"])
        return !invalidServers.contains(server.lowercased())
    }

    private static func normalizedTag(_ tag: String?, type: String, server: String?, index: Int) -> String {
        if let tag = tag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
            return tag
        }
        return "\(type)-\(server ?? "node")-\(index + 1)"
    }

    private static func uniqueTag(_ tag: String, seen: Set<String>) -> String {
        let reserved = Set([TungBoxConfig.tagAuto, TungBoxConfig.tagManual, TungBoxConfig.tagDirect, TungBoxConfig.tagBlock])
        guard seen.contains(tag) || reserved.contains(tag) else { return tag }

        var index = 2
        var candidate = "\(tag) \(index)"
        while seen.contains(candidate) || reserved.contains(candidate) {
            index += 1
            candidate = "\(tag) \(index)"
        }
        return candidate
    }

    private static func generateManagedConfig(profileName: String, nodes: [[String: Any]], subscriptionRuleSetURLs: [String: String]) throws -> [String: Any] {
        guard !nodes.isEmpty else {
            throw NSError.user("订阅中没有可用节点")
        }

        let nodeTags = nodes.compactMap { $0["tag"] as? String }
        var outbounds: [[String: Any]] = [
            [
                "type": "urltest",
                "tag": TungBoxConfig.tagAuto,
                "outbounds": nodeTags,
                "url": TungBoxConfig.urlTestURL,
                "interval": "3m",
                "tolerance": 50,
                "idle_timeout": "10m",
                "interrupt_exist_connections": true
            ],
            [
                "type": "selector",
                "tag": TungBoxConfig.tagManual,
                "outbounds": [TungBoxConfig.tagAuto] + nodeTags,
                "default": TungBoxConfig.tagAuto,
                "interrupt_exist_connections": true
            ]
        ]
        outbounds.append(contentsOf: nodes)
        outbounds.append(["type": "direct", "tag": TungBoxConfig.tagDirect])
        outbounds.append(["type": "block", "tag": TungBoxConfig.tagBlock])

        return [
            "log": [
                "level": "info",
                "timestamp": true
            ],
            "experimental": [
                "cache_file": [
                    "enabled": true
                ],
                "clash_api": [
                    "external_controller": TungBoxConfig.clashAPIListen,
                    "default_mode": "Rule"
                ]
            ],
            "dns": makeDNS(),
            "inbounds": [
                [
                    "type": "mixed",
                    "tag": "mixed-in",
                    "listen": "127.0.0.1",
                    "listen_port": TungBoxConfig.mixedPort
                ]
            ],
            "outbounds": outbounds,
            "route": makeRoute(subscriptionRuleSetURLs: subscriptionRuleSetURLs)
        ]
    }

    private static func makeDNS() -> [String: Any] {
        [
            "servers": [
                [
                    "type": "udp",
                    "tag": "dns-cn",
                    "server": "223.5.5.5",
                    "server_port": 53
                ],
                [
                    "type": "udp",
                    "tag": "dns-proxy",
                    "server": "1.1.1.1",
                    "server_port": 53,
                    "detour": TungBoxConfig.tagManual
                ]
            ],
            "rules": [
                [
                    "clash_mode": "direct",
                    "server": "dns-cn"
                ],
                [
                    "clash_mode": "global",
                    "server": "dns-proxy"
                ],
                [
                    "rule_set": [TungBoxConfig.ruleSetPrivate, TungBoxConfig.ruleSetCN],
                    "server": "dns-cn"
                ],
                [
                    "rule_set": TungBoxConfig.ruleSetGeolocationNotCN,
                    "server": "dns-proxy"
                ]
            ],
            "final": "dns-proxy",
            "strategy": "prefer_ipv4"
        ]
    }

    private static func makeRoute(subscriptionRuleSetURLs: [String: String]) -> [String: Any] {
        [
            "rule_set": [
                remoteRuleSet(tag: TungBoxConfig.ruleSetPrivate, url: TungBoxConfig.resolvedRuleSetURL(for: TungBoxConfig.ruleSetPrivate, subscriptionURLs: subscriptionRuleSetURLs), detour: TungBoxConfig.tagDirect, interval: "7d"),
                remoteRuleSet(tag: TungBoxConfig.ruleSetCN, url: TungBoxConfig.resolvedRuleSetURL(for: TungBoxConfig.ruleSetCN, subscriptionURLs: subscriptionRuleSetURLs), detour: TungBoxConfig.tagManual, interval: "1d"),
                remoteRuleSet(tag: TungBoxConfig.ruleSetGeolocationNotCN, url: TungBoxConfig.resolvedRuleSetURL(for: TungBoxConfig.ruleSetGeolocationNotCN, subscriptionURLs: subscriptionRuleSetURLs), detour: TungBoxConfig.tagManual, interval: "1d"),
                remoteRuleSet(tag: TungBoxConfig.ruleSetGeoIPCN, url: TungBoxConfig.resolvedRuleSetURL(for: TungBoxConfig.ruleSetGeoIPCN, subscriptionURLs: subscriptionRuleSetURLs), detour: TungBoxConfig.tagManual, interval: "1d")
            ],
            "rules": [
                [
                    "action": "sniff"
                ],
                [
                    "protocol": "dns",
                    "action": "hijack-dns"
                ],
                [
                    "clash_mode": "direct",
                    "outbound": TungBoxConfig.tagDirect
                ],
                [
                    "clash_mode": "global",
                    "outbound": TungBoxConfig.tagManual
                ],
                [
                    "rule_set": TungBoxConfig.ruleSetPrivate,
                    "outbound": TungBoxConfig.tagDirect
                ],
                [
                    "ip_cidr": [
                        "10.0.0.0/8",
                        "172.16.0.0/12",
                        "192.168.0.0/16",
                        "127.0.0.0/8",
                        "169.254.0.0/16",
                        "224.0.0.0/4",
                        "fc00::/7",
                        "fe80::/10",
                        "::1/128"
                    ],
                    "outbound": TungBoxConfig.tagDirect
                ],
                [
                    "rule_set": [TungBoxConfig.ruleSetCN, TungBoxConfig.ruleSetGeoIPCN],
                    "outbound": TungBoxConfig.tagDirect
                ],
                [
                    "rule_set": TungBoxConfig.ruleSetGeolocationNotCN,
                    "outbound": TungBoxConfig.tagManual
                ]
            ],
            "final": TungBoxConfig.tagManual,
            "default_domain_resolver": "dns-cn",
            "auto_detect_interface": true
        ]
    }

    private static func remoteRuleSet(tag: String, url: String, detour: String, interval: String) -> [String: Any] {
        [
            "type": "remote",
            "tag": tag,
            "format": "binary",
            "url": url,
            "download_detour": detour,
            "update_interval": interval
        ]
    }

    private static func isSingBoxJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["outbounds"] != nil || object["inbounds"] != nil || object["route"] != nil
    }

    private static func jsonObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func prettyJSON(from text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else { return text }
        return result
    }

    private static func renderJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func decodeBase64(_ text: String) -> String? {
        var normalized = text
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = normalized.count % 4
        if padding > 0 {
            normalized += String(repeating: "=", count: 4 - padding)
        }
        guard let data = Data(base64Encoded: normalized) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
