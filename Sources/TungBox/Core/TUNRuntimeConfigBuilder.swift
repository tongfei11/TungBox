import Foundation

/// 只转换传入的配置和快照；设置读取、网络探测、规则集定位与日志展示由调用方负责。
struct TUNRuntimeConfigBuilder {
    struct Transformation {
        let config: [String: Any]
        let diagnostics: [String]
    }

    let tunInbound: [String: Any]
    let fallbackProxyTag: String
    let cachePath: String
    let clashAPIPort: Int
    let clashAPISecret: String

    /// 分阶段返回诊断，保留调用层在接口探测、DNS 查询及最终校验前的日志顺序。
    func prepare(_ source: [String: Any]) -> Transformation {
        var config = source
        var diagnostics: [String] = []
        var outbounds = config["outbounds"] as? [[String: Any]] ?? []
        if !outbounds.contains(where: { ($0["tag"] as? String) == "direct" }) {
            outbounds.append(["type": "direct", "tag": "direct"])
            config["outbounds"] = outbounds
            diagnostics.append("[TUN] 原始配置缺少 direct outbound，已添加\n")
        } else {
            diagnostics.append("[TUN] 原始配置已有 direct outbound\n")
        }
        let mode = ProxyModeConfig.readMode(from: config)
        config = Self.setTunEnabled(
            true, in: config, tunInbound: tunInbound,
            fallbackProxyTag: fallbackProxyTag, cachePath: cachePath
        )
        config = ProxyModeConfig.ensureModeSupport(in: config, mode: mode, fallbackProxyTag: fallbackProxyTag)
        config = stripLocalListenersForTunDaemon(in: config, diagnostics: &diagnostics)
        config = applyTunAutomaticEgressRouting(in: config, diagnostics: &diagnostics)
        return Transformation(config: config, diagnostics: diagnostics)
    }

    func bindPhysicalInterface(_ interface: String?, in source: [String: Any]) -> Transformation {
        var diagnostics: [String] = []
        let config = applyTunPhysicalEgressBinding(in: source, interface: interface, diagnostics: &diagnostics)
        return Transformation(config: config, diagnostics: diagnostics)
    }

    func applyRouteExclusions(_ resolvedAddresses: [String: [String]], in source: [String: Any]) -> Transformation {
        var diagnostics: [String] = []
        var config = applyTunRuntimeRouteExclusions(in: source, resolvedByHost: resolvedAddresses, diagnostics: &diagnostics)
        config = Self.setTunCacheFile(enabled: true, in: config, cachePath: cachePath)
        return Transformation(config: config, diagnostics: diagnostics)
    }

    static func finalDiagnostics(in config: [String: Any]) -> [String] {
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let hasDirect = outbounds.contains { ($0["tag"] as? String) == "direct" }
        let tags = outbounds.compactMap { $0["tag"] as? String }
        return [
            "[TUN] 最终配置 direct outbound 状态: \(hasDirect ? "存在" : "缺失")\n",
            "[TUN] 最终配置中的所有 outbound tags: \(tags.joined(separator: ", "))\n"
        ]
    }

    static func upstreamHosts(in text: String) -> [String] {
        let config = ConfigCodec.parseObject(from: text) ?? [:]
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        return Array(outbounds.compactMap { $0["server"] as? String }
            .filter { !$0.isEmpty && routeExcludeCIDR(for: $0) == nil && seen.insert($0).inserted }.prefix(16))
    }

    /// 与即时生成路径一致：跳过虚拟出站，并最多解析 16 个非字面量上游。
    static func hostsNeedingResolution(in config: [String: Any]) -> [String] {
        let virtualTypes: Set<String> = ["selector", "urltest", "url-test", "direct", "block", "dns"]
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        var hostsToResolve: [String] = []
        var seenHosts = Set<String>()
        for outbound in outbounds {
            let type = (outbound["type"] as? String ?? "").lowercased()
            guard !virtualTypes.contains(type),
                  let server = outbound["server"] as? String,
                  !server.isEmpty else {
                continue
            }
            if Self.routeExcludeCIDR(for: server) != nil {
                continue
            }
            if seenHosts.insert(server).inserted {
                hostsToResolve.append(server)
            }
        }
        return Array(hostsToResolve.prefix(16))
    }

    static func validateTunRuntimeRouting(in config: [String: Any]) throws {
        let inbounds = config["inbounds"] as? [[String: Any]] ?? []
        let hasAutoRouteTun = inbounds.contains { inbound in
            (inbound["type"] as? String)?.lowercased() == "tun"
                && (inbound["auto_route"] as? Bool) == true
        }
        guard hasAutoRouteTun else { return }

        let route = config["route"] as? [String: Any] ?? [:]
        let autoDetect = route["auto_detect_interface"] as? Bool == true
        let hasDefaultInterface = (route["default_interface"] as? String)?.isEmpty == false
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let hasBoundOutbound = outbounds.contains { outbound in
            (outbound["bind_interface"] as? String)?.isEmpty == false
                || (outbound["inet4_bind_address"] as? String)?.isEmpty == false
                || (outbound["inet6_bind_address"] as? String)?.isEmpty == false
        }

        guard autoDetect || hasDefaultInterface || hasBoundOutbound else {
            throw NSError.user("TUN 配置缺少出口防回环设置：auto_route=true 时必须启用 auto_detect_interface、default_interface 或 outbound 绑定。")
        }
    }

    private func stripLocalListenersForTunDaemon(in config: [String: Any], diagnostics: inout [String]) -> [String: Any] {
        var config = config

        var inbounds = config["inbounds"] as? [[String: Any]] ?? []
        let localTypes: Set<String> = ["mixed", "http", "socks"]
        let before = inbounds.count
        inbounds = inbounds.filter { inbound in
            guard let type = (inbound["type"] as? String)?.lowercased() else { return true }
            return !localTypes.contains(type)
        }
        config["inbounds"] = inbounds
        if inbounds.count < before {
            diagnostics.append("[TUN] 守护进程不绑定本地代理端口（7890 由用户代理独占）\n")
        }

        // Keep clash_api (the clash_mode route rules depend on it) but on a dedicated
        // port so it never collides with the user runner's 9090.
        var experimental = config["experimental"] as? [String: Any] ?? [:]
        var clashAPI = experimental["clash_api"] as? [String: Any] ?? [:]
        clashAPI["external_controller"] = "127.0.0.1:\(clashAPIPort)"
        clashAPI["secret"] = clashAPISecret
        experimental["clash_api"] = clashAPI
        config["experimental"] = experimental
        return config
    }

    private func applyTunAutomaticEgressRouting(in config: [String: Any], diagnostics: inout [String]) -> [String: Any] {
        var config = config
        var changed = false

        var route = config["route"] as? [String: Any] ?? [:]
        if route.removeValue(forKey: "default_interface") != nil {
            changed = true
        }
        if route["auto_detect_interface"] as? Bool != true {
            route["auto_detect_interface"] = true
            changed = true
        }
        if !route.isEmpty {
            config["route"] = route
        }

        if var outbounds = config["outbounds"] as? [[String: Any]] {
            var outboundsChanged = false
            for index in outbounds.indices {
                if outbounds[index].removeValue(forKey: "bind_interface") != nil {
                    outboundsChanged = true
                }
                if outbounds[index].removeValue(forKey: "inet4_bind_address") != nil {
                    outboundsChanged = true
                }
                if outbounds[index].removeValue(forKey: "inet6_bind_address") != nil {
                    outboundsChanged = true
                }
            }
            if outboundsChanged {
                config["outbounds"] = outbounds
                changed = true
            }
        }

        if var dns = config["dns"] as? [String: Any],
           var servers = dns["servers"] as? [[String: Any]] {
            var dnsChanged = false
            for index in servers.indices where servers[index]["detour"] as? String == "direct" {
                servers[index].removeValue(forKey: "detour")
                dnsChanged = true
            }
            if dnsChanged {
                dns["servers"] = servers
                config["dns"] = dns
                changed = true
            }
        }

        if changed {
            diagnostics.append("[TUN] 已启用 auto_detect_interface，并清理固定出口绑定和 DNS direct detour\n")
        } else {
            diagnostics.append("[TUN] 运行时出口：auto_detect_interface 已启用\n")
        }

        return config
    }

    private func applyTunPhysicalEgressBinding(in config: [String: Any], interface: String?, diagnostics: inout [String]) -> [String: Any] {
        var config = config
        guard let interface else {
            diagnostics.append("[TUN] 未找到可用物理出口接口，保留 auto_detect_interface\n")
            return config
        }

        var route = config["route"] as? [String: Any] ?? [:]
        route["default_interface"] = interface
        route.removeValue(forKey: "auto_detect_interface")
        config["route"] = route

        var outbounds = config["outbounds"] as? [[String: Any]] ?? []
        var changedOutbounds = false
        let virtualTypes: Set<String> = ["selector", "urltest", "url-test", "direct", "block", "dns"]
        for index in outbounds.indices {
            let type = (outbounds[index]["type"] as? String ?? "").lowercased()
            guard !virtualTypes.contains(type) else { continue }
            outbounds[index]["bind_interface"] = interface
            changedOutbounds = true
        }
        if changedOutbounds {
            config["outbounds"] = outbounds
        }

        diagnostics.append("[TUN] 已绑定 direct/节点出站到物理接口 \(interface)，避免 direct 出口无路由\n")
        return config
    }

    private func applyTunRuntimeRouteExclusions(in config: [String: Any], resolvedByHost: [String: [String]], diagnostics: inout [String]) -> [String: Any] {
        var config = config
        var bypassCIDRs: [String] = []
        var seen = Set<String>()

        func add(_ cidr: String) {
            if seen.insert(cidr).inserted {
                bypassCIDRs.append(cidr)
            }
        }

        let alwaysBypass = [
            "1.0.0.1",
            "1.1.1.1",
            "8.8.4.4",
            "8.8.8.8",
            "114.114.114.114",
            "119.29.29.29",
            "120.53.53.53",
            "180.76.76.76",
            "223.5.5.5",
            "223.6.6.6"
        ]
        for ip in alwaysBypass {
            if let cidr = Self.routeExcludeCIDR(for: ip) {
                add(cidr)
            }
        }

        if let dns = config["dns"] as? [String: Any],
           let servers = dns["servers"] as? [[String: Any]] {
            for server in servers {
                if let address = server["server"] as? String,
                   let cidr = Self.routeExcludeCIDR(for: address) {
                    add(cidr)
                }
            }
        }

        let virtualTypes: Set<String> = ["selector", "urltest", "url-test", "direct", "block", "dns"]
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        for outbound in outbounds {
            let type = (outbound["type"] as? String ?? "").lowercased()
            guard !virtualTypes.contains(type),
                  let server = outbound["server"] as? String,
                  !server.isEmpty else { continue }
            if let cidr = Self.routeExcludeCIDR(for: server) {
                add(cidr)
            }
        }
        let cappedHosts = Self.hostsNeedingResolution(in: config)
        for host in cappedHosts {
            for ip in (resolvedByHost[host] ?? []).prefix(4) {
                if let cidr = Self.routeExcludeCIDR(for: ip) {
                    add(cidr)
                }
            }
        }

        guard !bypassCIDRs.isEmpty else {
            return config
        }

        var inbounds = config["inbounds"] as? [[String: Any]] ?? []
        var updatedTun = false
        for index in inbounds.indices {
            guard (inbounds[index]["type"] as? String)?.lowercased() == "tun" else {
                continue
            }
            var excludes = inbounds[index]["route_exclude_address"] as? [String] ?? []
            var excludeSet = Set(excludes)
            var added = 0
            for cidr in bypassCIDRs where excludeSet.insert(cidr).inserted {
                excludes.append(cidr)
                added += 1
            }
            if added > 0 {
                inbounds[index]["route_exclude_address"] = excludes
                updatedTun = true
            }
        }
        if updatedTun {
            config["inbounds"] = inbounds
            diagnostics.append("[TUN] 已排除 DNS/节点上游地址 \(bypassCIDRs.count) 个，避免代理握手被 TUN 捕获\n")
        }

        // 不再硬覆盖 dns.strategy —— 由 DNSConfig 用户设置主导。仅在调试日志里记一笔，
        // 方便排查"明明没 IPv6 路由怎么还在查 AAAA"的问题。
        if let dns = config["dns"] as? [String: Any],
           let strategy = dns["strategy"] as? String {
            diagnostics.append("[TUN] DNS 策略：\(strategy)\n")
        }

        return config
    }

    private static func routeExcludeCIDR(for address: String) -> String? {
        let trimmed = address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard isPublicIPv4Address(trimmed) else { return nil }
        return "\(trimmed)/32"
    }

    static func isPublicIPv4Address(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return false
        }
        let first = octets[0]
        let second = octets[1]
        switch first {
        case 0, 10, 127:
            return false
        case 100 where (64...127).contains(second):
            return false
        case 169 where second == 254:
            return false
        case 172 where (16...31).contains(second):
            return false
        case 192 where second == 168:
            return false
        case 198 where second == 18 || second == 19:
            return false
        case 224...255:
            return false
        default:
            return true
        }
    }

    static func setTunEnabled(
        _ enabled: Bool,
        in config: [String: Any],
        tunInbound: [String: Any],
        fallbackProxyTag: String,
        cachePath: String
    ) -> [String: Any] {
        var config = config
        var inbounds = config["inbounds"] as? [[String: Any]] ?? []
        inbounds.removeAll { ($0["type"] as? String)?.lowercased() == "tun" }
        if enabled {
            var log = config["log"] as? [String: Any] ?? [:]
            log["level"] = "warn"
            config["log"] = log

            inbounds.insert(tunInbound, at: 0)

            var outbounds = config["outbounds"] as? [[String: Any]] ?? []

            // 确保 direct outbound 存在
            if !outbounds.contains(where: { ($0["tag"] as? String) == "direct" }) {
                outbounds.append(["type": "direct", "tag": "direct"])
            }

            let proxyTag = ProxyModeConfig.preferredProxyTag(from: outbounds, fallback: fallbackProxyTag)
            var route = config["route"] as? [String: Any] ?? [:]
            if proxyTag != "direct" {
                if (route["final"] as? String).map({ $0 == "direct" }) ?? true {
                    route["final"] = proxyTag
                }
            }
            config["route"] = route
            config["outbounds"] = outbounds
        } else {
            if var route = config["route"] as? [String: Any] {
                route.removeValue(forKey: "default_interface")
                route.removeValue(forKey: "auto_detect_interface")
                if route.isEmpty {
                    config.removeValue(forKey: "route")
                } else {
                    config["route"] = route
                }
            }
        }
        config["inbounds"] = inbounds
        config = setTunCacheFile(enabled: enabled, in: config, cachePath: cachePath)
        return config
    }

    private static func setTunCacheFile(enabled: Bool, in config: [String: Any], cachePath: String) -> [String: Any] {
        var config = config
        var experimental = config["experimental"] as? [String: Any] ?? [:]
        var cacheFile = experimental["cache_file"] as? [String: Any] ?? [:]

        if enabled {
            cacheFile["enabled"] = true
            cacheFile["path"] = cachePath
            experimental["cache_file"] = cacheFile
            config["experimental"] = experimental
            return config
        }

        if cacheFile["path"] as? String == cachePath {
            cacheFile.removeValue(forKey: "path")
            experimental["cache_file"] = cacheFile
            config["experimental"] = experimental
        }
        return config
    }
}
