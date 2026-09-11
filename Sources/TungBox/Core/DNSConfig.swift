import Foundation

/// 用户可配置的 DNS 设置。基础项（国内/国外上游、策略、Fake-IP 开关）覆盖 95% 场景；
/// 高级项（Fake-IP 网段、跳过列表）默认隐藏，进阶用户才会动。
///
/// 设计原则：跟 Surge 一样克制，不暴露 sing-box `dns.servers` 全部字段。bootstrap /
/// 节点域名 DNS / 直连域名 DNS / nameserver-policy 都隐式跟着国内/国外上游走，
/// fallback-filter 不做（rule_set 分流足够）。
enum DNSConfig {

    enum Strategy: String, CaseIterable {
        case ipv4Only = "ipv4_only"
        case ipv6Only = "ipv6_only"
        case preferIPv4 = "prefer_ipv4"
        case preferIPv6 = "prefer_ipv6"

        var displayName: String {
            switch self {
            case .ipv4Only:   return "仅 IPv4"
            case .ipv6Only:   return "仅 IPv6"
            case .preferIPv4: return "偏好 IPv4"
            case .preferIPv6: return "偏好 IPv6"
            }
        }
    }

    // MARK: - 默认值

    static let defaultLocalServer = "223.5.5.5"
    static let defaultProxyServer = "https://1.1.1.1/dns-query"
    static let defaultStrategy: Strategy = .ipv4Only
    static let defaultFakeIPEnabled = true
    static let defaultFakeIPRange = "198.18.0.0/15"
    /// Fake-IP 跳过列表。这些域名走真实 DNS 而不是 fakeip：
    /// - `lan` / `local` / `arpa`: 本地名解析
    /// - `ntp.*`: NTP 校时需要真实 IP
    /// - `msftncsi.com` / `msftconnecttest.com`: Windows 网络连通性探针，模板里照搬给 macOS 影响不大但加上无害
    /// - `localhost.ptlogin2.qq.com`: QQ 登录回环
    static let defaultFakeIPExcludes: [String] = [
        "lan", "local", "arpa",
        "ntp.org",
        "msftncsi.com", "msftconnecttest.com",
        "localhost.ptlogin2.qq.com"
    ]
    static let defaultReadSystemHosts = false
    static let defaultCustomHosts = ""

    // MARK: - UserDefaults 存取

    private static let kLocal = "dnsLocalServer"
    private static let kProxy = "dnsProxyServer"
    private static let kStrategy = "dnsStrategy"
    private static let kFakeIPEnabled = "dnsFakeIPEnabled"
    private static let kFakeIPRange = "dnsFakeIPRange"
    private static let kFakeIPExcludes = "dnsFakeIPExcludes"
    private static let kReadSystemHosts = "dnsReadSystemHosts"
    private static let kCustomHosts = "dnsCustomHosts"

    static var localServer: String {
        get {
            let s = UserDefaults.standard.string(forKey: kLocal)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return s.isEmpty ? defaultLocalServer : s
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == defaultLocalServer {
                UserDefaults.standard.removeObject(forKey: kLocal)
            } else {
                UserDefaults.standard.set(trimmed, forKey: kLocal)
            }
        }
    }

    static var proxyServer: String {
        get {
            let s = UserDefaults.standard.string(forKey: kProxy)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return s.isEmpty ? defaultProxyServer : s
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == defaultProxyServer {
                UserDefaults.standard.removeObject(forKey: kProxy)
            } else {
                UserDefaults.standard.set(trimmed, forKey: kProxy)
            }
        }
    }

    static var strategy: Strategy {
        get {
            if let raw = UserDefaults.standard.string(forKey: kStrategy),
               let s = Strategy(rawValue: raw) {
                return s
            }
            return defaultStrategy
        }
        set {
            if newValue == defaultStrategy {
                UserDefaults.standard.removeObject(forKey: kStrategy)
            } else {
                UserDefaults.standard.set(newValue.rawValue, forKey: kStrategy)
            }
        }
    }

    static var fakeIPEnabled: Bool {
        get {
            if let v = UserDefaults.standard.object(forKey: kFakeIPEnabled) as? Bool {
                return v
            }
            return defaultFakeIPEnabled
        }
        set {
            if newValue == defaultFakeIPEnabled {
                UserDefaults.standard.removeObject(forKey: kFakeIPEnabled)
            } else {
                UserDefaults.standard.set(newValue, forKey: kFakeIPEnabled)
            }
        }
    }

    static var fakeIPRange: String {
        get {
            let s = UserDefaults.standard.string(forKey: kFakeIPRange)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return s.isEmpty ? defaultFakeIPRange : s
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == defaultFakeIPRange {
                UserDefaults.standard.removeObject(forKey: kFakeIPRange)
            } else {
                UserDefaults.standard.set(trimmed, forKey: kFakeIPRange)
            }
        }
    }

    static var fakeIPExcludes: [String] {
        get {
            if let arr = UserDefaults.standard.array(forKey: kFakeIPExcludes) as? [String] {
                return arr
            }
            return defaultFakeIPExcludes
        }
        set {
            let cleaned = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if cleaned == defaultFakeIPExcludes {
                UserDefaults.standard.removeObject(forKey: kFakeIPExcludes)
            } else {
                UserDefaults.standard.set(cleaned, forKey: kFakeIPExcludes)
            }
        }
    }

    static var readSystemHosts: Bool {
        get {
            if let v = UserDefaults.standard.object(forKey: kReadSystemHosts) as? Bool {
                return v
            }
            return defaultReadSystemHosts
        }
        set {
            if newValue == defaultReadSystemHosts {
                UserDefaults.standard.removeObject(forKey: kReadSystemHosts)
            } else {
                UserDefaults.standard.set(newValue, forKey: kReadSystemHosts)
            }
        }
    }

    static var customHosts: String {
        get { UserDefaults.standard.string(forKey: kCustomHosts) ?? defaultCustomHosts }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: kCustomHosts)
            } else {
                UserDefaults.standard.set(newValue, forKey: kCustomHosts)
            }
        }
    }

    static func resetAll() {
        let keys = [kLocal, kProxy, kStrategy, kFakeIPEnabled, kFakeIPRange, kFakeIPExcludes, kReadSystemHosts, kCustomHosts]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    // MARK: - hosts 解析

    /// 合并 /etc/hosts（可选）+ 用户自定义 hosts 文本，返回 sing-box hosts server 用的
    /// `predefined` 字典。用户自定义条目覆盖同名的 /etc/hosts 条目。
    /// - /etc/hosts 格式：`ip host1 host2 ...`
    /// - 自定义格式：`domain=ip[;ip2,ip3]`（每行一条）
    static func collectHostsEntries() -> [String: [String]] {
        var result: [String: [String]] = [:]

        if readSystemHosts, let content = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8) {
            for rawLine in content.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                let noComment = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                let parts = noComment
                    .split(whereSeparator: { $0 == " " || $0 == "\t" })
                    .map { String($0) }
                    .filter { !$0.isEmpty }
                guard parts.count >= 2 else { continue }
                let ip = parts[0]
                for host in parts.dropFirst() {
                    // 跳过 localhost 这种系统已有的，避免污染
                    if host == "localhost" || host == "broadcasthost" { continue }
                    result[host, default: []].append(ip)
                }
            }
        }

        for rawLine in customHosts.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let domain = parts[0].trimmingCharacters(in: .whitespaces)
            let ips = parts[1]
                .split(whereSeparator: { $0 == ";" || $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !domain.isEmpty, !ips.isEmpty else { continue }
            // 自定义优先覆盖系统 hosts
            result[domain] = ips
        }
        return result
    }

    // MARK: - sing-box dns 字典生成

    /// 拼出 sing-box 配置里的 `dns` 块。被 SubscriptionImporter.basicDNS() 调用。
    static func buildSingBoxDNS() -> [String: Any] {
        var servers: [[String: Any]] = []

        if let localDict = parseServerURL(localServer, tag: "dns-local", detour: nil) {
            servers.append(localDict)
        } else {
            // 兜底：用户填了无法解析的串，回到默认
            servers.append([
                "type": "udp", "tag": "dns-local",
                "server": defaultLocalServer, "server_port": 53
            ])
        }

        if let proxyDict = parseServerURL(proxyServer, tag: "dns-proxy", detour: TungBoxConfig.tagManual) {
            servers.append(proxyDict)
        } else {
            servers.append([
                "type": "https", "tag": "dns-proxy",
                "server": "1.1.1.1", "detour": TungBoxConfig.tagManual
            ])
        }

        var rules: [[String: Any]] = []
        var finalServer = "dns-proxy"

        // Hosts 优先级最高：放在所有规则前面，仅对配置的域名生效（精确匹配）。
        // 未匹配的域名落到后面的规则，所以不会"吃掉"全部流量。
        let hostsMap = collectHostsEntries()
        if !hostsMap.isEmpty {
            servers.append([
                "type": "hosts",
                "tag": "dns-hosts",
                "predefined": hostsMap
            ])
            rules.append([
                "domain": Array(hostsMap.keys).sorted(),
                "server": "dns-hosts"
            ])
        }

        if fakeIPEnabled {
            servers.append([
                "type": "fakeip",
                "tag": "dns-fakeip",
                "inet4_range": fakeIPRange,
                "inet6_range": "fc00::/18"
            ])

            // 国内域名 + 私有 → 国内 DNS（真实解析）
            rules.append([
                "rule_set": [TungBoxConfig.ruleSetCN, TungBoxConfig.ruleSetPrivate],
                "server": "dns-local"
            ])
            // Fake-IP 跳过列表 → 国内 DNS 真实解析
            let excludes = fakeIPExcludes
            if !excludes.isEmpty {
                rules.append([
                    "domain_suffix": excludes,
                    "server": "dns-local"
                ])
            }
            // 国外域名 → 分配 fakeip
            rules.append([
                "rule_set": TungBoxConfig.ruleSetGeolocationNotCN,
                "server": "dns-fakeip"
            ])
            // 没命中 rule_set 的（小众域名）→ 国外真实 DNS
            finalServer = "dns-proxy"
        } else {
            rules.append([
                "rule_set": [TungBoxConfig.ruleSetCN, TungBoxConfig.ruleSetPrivate],
                "server": "dns-local"
            ])
            rules.append([
                "rule_set": TungBoxConfig.ruleSetGeolocationNotCN,
                "server": "dns-proxy"
            ])
        }

        var dns: [String: Any] = [
            "servers": servers,
            "rules": rules,
            "final": finalServer,
            "strategy": strategy.rawValue
        ]

        if fakeIPEnabled {
            dns["fakeip"] = [
                "enabled": true,
                "inet4_range": fakeIPRange,
                "inet6_range": "fc00::/18"
            ]
            // Fake-IP 拿到的是合成 IP，必须缓存到磁盘才能跨重启复用。否则关掉 sing-box
            // 再开，浏览器里旧连接拿到的 198.18.x.x 地址全成野指针。
            dns["independent_cache"] = true
        }

        return dns
    }

    // MARK: - URL 解析

    /// 把用户输入的上游字符串解析成 sing-box dns server 字典。支持：
    /// - 裸 IP/host：默认 UDP/53
    /// - `udp://host[:port]` / `tcp://host[:port]`
    /// - `tls://host[:port]` (DoT)
    /// - `https://host[:port][/path]` (DoH)
    /// - `quic://host[:port]` (DoQ)
    /// - `h3://host[:port][/path]` (DoH3)
    /// Internal for testing; production code uses it via `buildSingBoxDNS()`.
    static func parseServerURL(_ raw: String, tag: String, detour: String?) -> [String: Any]? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        var out: [String: Any] = ["tag": tag]
        if let detour { out["detour"] = detour }

        if let schemeRange = s.range(of: "://") {
            let scheme = String(s[s.startIndex..<schemeRange.lowerBound]).lowercased()
            let rest = String(s[schemeRange.upperBound...])
            let (host, port, path) = splitHostPortPath(rest)
            guard !host.isEmpty else { return nil }

            switch scheme {
            case "https":
                out["type"] = "https"
                out["server"] = host
                if let port { out["server_port"] = port }
                if let path, path != "/dns-query" { out["path"] = path }
            case "h3":
                out["type"] = "h3"
                out["server"] = host
                if let port { out["server_port"] = port }
                if let path, path != "/dns-query" { out["path"] = path }
            case "tls":
                out["type"] = "tls"
                out["server"] = host
                if let port { out["server_port"] = port }
            case "quic":
                out["type"] = "quic"
                out["server"] = host
                if let port { out["server_port"] = port }
            case "udp":
                out["type"] = "udp"
                out["server"] = host
                out["server_port"] = port ?? 53
            case "tcp":
                out["type"] = "tcp"
                out["server"] = host
                out["server_port"] = port ?? 53
            default:
                return nil
            }
            return out
        }

        // 裸 host / IP / "host:port" → UDP
        let (host, port, _) = splitHostPortPath(s)
        guard !host.isEmpty else { return nil }
        out["type"] = "udp"
        out["server"] = host
        out["server_port"] = port ?? 53
        return out
    }

    static func splitHostPortPath(_ raw: String) -> (host: String, port: Int?, path: String?) {
        var rest = raw
        var path: String? = nil
        if let slash = rest.firstIndex(of: "/") {
            path = String(rest[slash...])
            rest = String(rest[rest.startIndex..<slash])
        }
        if rest.hasPrefix("[") {
            // [::1]:53
            if let end = rest.firstIndex(of: "]") {
                let host = String(rest[rest.index(after: rest.startIndex)..<end])
                let after = rest.index(after: end)
                if after < rest.endIndex, rest[after] == ":" {
                    let portStr = String(rest[rest.index(after: after)...])
                    return (host, Int(portStr), path)
                }
                return (host, nil, path)
            }
            return (rest, nil, path)
        }
        if let colon = rest.lastIndex(of: ":") {
            let before = String(rest[rest.startIndex..<colon])
            // 不含其它冒号才认为是端口（避免裸 IPv6 被切割）
            if !before.contains(":") {
                let portStr = String(rest[rest.index(after: colon)...])
                if let p = Int(portStr) {
                    return (before, p, path)
                }
            }
        }
        return (rest, nil, path)
    }
}
