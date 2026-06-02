import Foundation

/// Scans sing-box configs for deprecated fields and offers auto-fix where possible.
enum ConfigCompatibilityChecker {

    struct Issue {
        let severity: Severity
        let path: String
        let message: String
        let autoFixed: Bool
    }

    enum Severity: String {
        case error = "ERROR"   // Will break on current Core version
        case warn = "WARN"     // Deprecated, will be removed in future
        case info = "INFO"     // Style / best-practice advice
    }

    // MARK: - Public API

    /// Returns a list of compatibility issues found in the config, with the option to auto-fix.
    static func check(config: [String: Any]) -> [Issue] {
        var issues: [Issue] = []

        // --- 1.12.0: route.default_domain_resolver → deprecated, removed in 1.14 ---
        if let route = config["route"] as? [String: Any], route["default_domain_resolver"] != nil {
            issues.append(Issue(
                severity: .error,
                path: "route.default_domain_resolver",
                message: "已弃用，将在 sing-box 1.14.0 中被移除。请改用各 outbound 的 dial.domain_resolver 字段。",
                autoFixed: true
            ))
        }

        // --- 1.12.0: domain_strategy in dial fields → domain_resolver ---
        if let outbounds = config["outbounds"] as? [[String: Any]] {
            for (i, outbound) in outbounds.enumerated() {
                if let dial = outbound["dial"] as? [String: Any], dial["domain_strategy"] != nil {
                    issues.append(Issue(
                        severity: .warn,
                        path: "outbounds[\(i)].dial.domain_strategy",
                        message: "已弃用。请改用 dial.domain_resolver = { server = \"...\", strategy = \"...\" }。",
                        autoFixed: true
                    ))
                }
            }
        }

        // --- 1.12.0: dns.rules[].outbound → deprecated ---
        if let dnsRules = (config["dns"] as? [String: Any])?["rules"] as? [[String: Any]] {
            for (i, rule) in dnsRules.enumerated() {
                if rule["outbound"] != nil {
                    issues.append(Issue(
                        severity: .error,
                        path: "dns.rules[\(i)].outbound",
                        message: "DNS 规则中的 outbound 字段已于 sing-box 1.12.0 弃用，将在 1.14.0 移除。请在对应 outbound 的 dial 字段中使用 domain_resolver。",
                        autoFixed: false
                    ))
                }
            }
        }

        // --- 1.12.0: dns.servers[].address in URL format → type + server ---
        if let servers = (config["dns"] as? [String: Any])?["servers"] as? [[String: Any]] {
            for (i, server) in servers.enumerated() {
                if let addr = server["address"] as? String, addr.contains("://") {
                    issues.append(Issue(
                        severity: .warn,
                        path: "dns.servers[\(i)].address",
                        message: "DNS 服务器地址 URL 格式 (例如 tcp://1.1.1.1) 已弃用。请改用 type 和 server 字段。",
                        autoFixed: true
                    ))
                }
                if server["strategy"] != nil {
                    issues.append(Issue(
                        severity: .warn,
                        path: "dns.servers[\(i)].strategy",
                        message: "DNS 服务器的 strategy 已弃用。请改用 dns.rules[].strategy 或顶层 dns.strategy。",
                        autoFixed: false
                    ))
                }
                if server["address_resolver"] != nil {
                    issues.append(Issue(
                        severity: .warn,
                        path: "dns.servers[\(i)].address_resolver",
                        message: "address_resolver 已弃用。请改用 domain_resolver。",
                        autoFixed: true
                    ))
                }
                if server["client_subnet"] != nil {
                    issues.append(Issue(
                        severity: .warn,
                        path: "dns.servers[\(i)].client_subnet",
                        message: "DNS 服务器的 client_subnet 已弃用。请改用 dns.rules[].client_subnet。",
                        autoFixed: false
                    ))
                }
            }
        }

        // --- 1.14.0: dns.rules[].ip_cidr / ip_is_private without match_response ---
        if let dnsRules = (config["dns"] as? [String: Any])?["rules"] as? [[String: Any]] {
            for (i, rule) in dnsRules.enumerated() {
                if (rule["ip_cidr"] != nil || rule["ip_is_private"] != nil),
                   rule["match_response"] == nil {
                    issues.append(Issue(
                        severity: .warn,
                        path: "dns.rules[\(i)]",
                        message: "DNS 规则中的 ip_cidr / ip_is_private 缺少 match_response。在 1.14.0 中弃用，请改用 evaluate 规则链。",
                        autoFixed: false
                    ))
                }
            }
        }

        // --- 1.10.0: TUN inet4_address / inet6_address → address array ---
        if let inbounds = config["inbounds"] as? [[String: Any]] {
            for (i, inbound) in inbounds.enumerated() {
                if let type = inbound["type"] as? String, type == "tun" {
                    if inbound["inet4_address"] != nil || inbound["inet6_address"] != nil {
                        issues.append(Issue(
                            severity: .warn,
                            path: "inbounds[\(i)].tun",
                            message: "TUN 的 inet4_address / inet6_address 已在 1.10.0 弃用。请合并为 address 数组。",
                            autoFixed: true
                        ))
                    }
                    if inbound["inet4_route_address"] != nil || inbound["inet6_route_address"] != nil {
                        issues.append(Issue(
                            severity: .warn,
                            path: "inbounds[\(i)].tun",
                            message: "TUN 的 inet4_route_address / inet6_route_address 已弃用。请合并为 route_address 数组。",
                            autoFixed: true
                        ))
                    }
                }
            }
        }

        // --- 1.11.0: type: "block" / type: "dns" outbounds → rule actions ---
        if let outbounds = config["outbounds"] as? [[String: Any]] {
            for (i, outbound) in outbounds.enumerated() {
                let type = (outbound["type"] as? String) ?? ""
                if type == "block", outbound["tag"] != nil {
                    issues.append(Issue(
                        severity: .warn,
                        path: "outbounds[\(i)]",
                        message: "type: block 的 outbound 已弃用。请改用 route.rule action: reject。",
                        autoFixed: false
                    ))
                }
                if type == "dns", outbound["tag"] != nil {
                    issues.append(Issue(
                        severity: .warn,
                        path: "outbounds[\(i)]",
                        message: "type: dns 的 outbound 已弃用。请改用 sniff + hijack-dns 规则。",
                        autoFixed: false
                    ))
                }
            }
        }

        // --- 1.14.0: experimental.cache_file.store_rdrc → store_dns ---
        if let cache = (config["experimental"] as? [String: Any])?["cache_file"] as? [String: Any],
           cache["store_rdrc"] != nil {
            issues.append(Issue(
                severity: .info,
                path: "experimental.cache_file.store_rdrc",
                message: "store_rdrc 已弃用，在 1.14.0 移除。建议改用 store_dns。",
                autoFixed: true
            ))
        }

        return issues
    }

    // MARK: - Auto-fix

    /// Applies available auto-fixes and returns the fixed config + a list of applied fixes.
    static func autoFix(config: [String: Any]) -> (config: [String: Any], fixed: [String]) {
        var c = config
        var fixed: [String] = []

        // 1. Remove route.default_domain_resolver
        if var route = c["route"] as? [String: Any], route["default_domain_resolver"] != nil {
            let oldValue = route["default_domain_resolver"]
            route.removeValue(forKey: "default_domain_resolver")
            c["route"] = route
            fixed.append("移除 route.default_domain_resolver = \(oldValue ?? "nil")")
        }

        // 2. Migrate domain_strategy → domain_resolver in outbound dial fields
        if let outbounds = c["outbounds"] as? [[String: Any]] {
            var newOutbounds = outbounds
            for i in outbounds.indices {
                if var dial = newOutbounds[i]["dial"] as? [String: Any],
                   let strategy = dial["domain_strategy"] as? String {
                    dial.removeValue(forKey: "domain_strategy")
                    dial["domain_resolver"] = [
                        "server": "dns-proxy",
                        "strategy": strategy
                    ]
                    newOutbounds[i]["dial"] = dial
                    fixed.append("outbounds[\(i)]: domain_strategy → domain_resolver")
                }
            }
            c["outbounds"] = newOutbounds
        }

        // 3. Migrate dns.servers[].address URL → type + server
        if var dns = c["dns"] as? [String: Any],
           let servers = dns["servers"] as? [[String: Any]] {
            var newServers = servers
            for i in servers.indices {
                if let addr = newServers[i]["address"] as? String, addr.contains("://") {
                    let parsed = parseDNSAddress(addr)
                    var updated = newServers[i]
                    updated.removeValue(forKey: "address")
                    updated["type"] = parsed.type
                    updated["server"] = parsed.server
                    if let port = parsed.port { updated["server_port"] = port }
                    newServers[i] = updated
                    fixed.append("dns.servers[\(i)]: \(addr) → type=\(parsed.type), server=\(parsed.server)")
                }
            }
            dns["servers"] = newServers
            c["dns"] = dns
        }

        // 4. Rename address_resolver → domain_resolver
        if var dns = c["dns"] as? [String: Any],
           let servers = dns["servers"] as? [[String: Any]] {
            var newServers = servers
            for i in servers.indices {
                if let resolver = newServers[i]["address_resolver"] {
                    var updated = newServers[i]
                    updated.removeValue(forKey: "address_resolver")
                    updated["domain_resolver"] = resolver
                    newServers[i] = updated
                    fixed.append("dns.servers[\(i)]: address_resolver → domain_resolver")
                }
            }
            dns["servers"] = newServers
            c["dns"] = dns
        }

        // 5. TUN address merge
        if let inbounds = c["inbounds"] as? [[String: Any]] {
            var newInbounds = inbounds
            for i in inbounds.indices {
                if let type = newInbounds[i]["type"] as? String, type == "tun" {
                    var updated = newInbounds[i]
                    var addresses: [String] = []
                    if let v4 = updated.removeValue(forKey: "inet4_address") {
                        addresses.append(contentsOf: asStringArray(v4))
                    }
                    if let v6 = updated.removeValue(forKey: "inet6_address") {
                        addresses.append(contentsOf: asStringArray(v6))
                    }
                    if !addresses.isEmpty {
                        updated["address"] = addresses
                        fixed.append("inbounds[\(i)].tun: inet4/inet6_address → address")
                    }

                    var routes: [String] = []
                    if let v4 = updated.removeValue(forKey: "inet4_route_address") {
                        routes.append(contentsOf: asStringArray(v4))
                    }
                    if let v6 = updated.removeValue(forKey: "inet6_route_address") {
                        routes.append(contentsOf: asStringArray(v6))
                    }
                    if !routes.isEmpty {
                        updated["route_address"] = routes
                        fixed.append("inbounds[\(i)].tun: inet4/inet6_route_address → route_address")
                    }
                    newInbounds[i] = updated
                }
            }
            c["inbounds"] = newInbounds
        }

        // 6. store_rdrc → store_dns
        if var exp = c["experimental"] as? [String: Any],
           var cache = exp["cache_file"] as? [String: Any],
           cache["store_rdrc"] != nil {
            cache.removeValue(forKey: "store_rdrc")
            cache["store_dns"] = true
            exp["cache_file"] = cache
            c["experimental"] = exp
            fixed.append("experimental.cache_file: store_rdrc → store_dns")
        }

        return (c, fixed)
    }

    // MARK: - Helpers

    private static func parseDNSAddress(_ addr: String) -> (type: String, server: String, port: Int?) {
        guard let url = URL(string: addr) else { return ("udp", addr, nil) }
        let type = url.scheme?.lowercased() ?? "udp"
        let host = url.host ?? addr
        let port = url.port
        return (type, host, port)
    }

    private static func asStringArray(_ value: Any) -> [String] {
        if let arr = value as? [String] { return arr }
        if let str = value as? String, !str.isEmpty { return [str] }
        return []
    }
}
