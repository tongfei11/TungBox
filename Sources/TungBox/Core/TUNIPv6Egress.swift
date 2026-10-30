import Foundation
import Network

/// Physical egress evidence only: a TUN/FakeIP IPv6 address is not an Internet exit.
enum TUNIPv6Egress {
    static func availability(interface: String, ifconfig: String, route: String) -> Bool? {
        guard !ifconfig.isEmpty else { return nil }
        let hasGlobalAddress = ifconfig.components(separatedBy: .newlines).contains { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.first == "inet6", fields.count > 1,
                  !fields.contains("tentative"), !fields.contains("duplicated"),
                  let address = IPv6Address(String(fields[1].split(separator: "%")[0])) else { return false }
            return address.rawValue[0] & 0xe0 == 0x20
        }
        guard hasGlobalAddress else { return false }
        guard !route.isEmpty else { return nil }
        return route.components(separatedBy: .newlines).contains { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.count == 2 && fields[0] == "interface:" && fields[1] == interface
        }
    }

    /// Shared by ordinary proxy and TUN runtime configs. Restrict local DNS only.
    /// Proxy DNS and cached synthetic IPv6 destinations
    /// remain usable through the remote proxy even on an IPv4 physical network.
    static func applying(to source: [String: Any], supportsIPv6: Bool?) -> [String: Any] {
        guard supportsIPv6 == false, var dns = source["dns"] as? [String: Any],
              dns["strategy"] as? String != "ipv6_only" else { return source }
        let originalRules = dns["rules"] as? [[String: Any]] ?? []
        var rules: [[String: Any]] = []
        for rule in originalRules {
            if rule["server"] as? String == "dns-local", rule["strategy"] as? String != "ipv6_only" {
                var condition = rule
                // DNS rule action strategy cannot coexist with query_type rules
                // (including our FakeIP rule) in Core 1.14. Use a NODATA answer.
                for key in ["action", "server", "strategy", "disable_cache", "disable_optimistic_cache",
                            "rewrite_ttl", "timeout", "client_subnet", "remove_client_subnet", "speculative", "race"] {
                    condition.removeValue(forKey: key)
                }
                let filter: [String: Any] = [
                    "type": "logical", "mode": "and",
                    "rules": [condition, ["query_type": "AAAA"]],
                    "action": "predefined", "rcode": "NOERROR"
                ]
                if !originalRules.contains(where: { NSDictionary(dictionary: $0).isEqual(to: filter) }) {
                    rules.append(filter)
                }
            }
            rules.append(rule)
        }
        dns["rules"] = rules
        var result = source
        result["dns"] = dns
        var route = source["route"] as? [String: Any] ?? [:]
        if let resolver = route["default_domain_resolver"] as? String, resolver == "dns-local" {
            route["default_domain_resolver"] = ["server": resolver, "strategy": "ipv4_only"]
        } else if var resolver = route["default_domain_resolver"] as? [String: Any],
                  resolver["server"] as? String == "dns-local", resolver["strategy"] as? String != "ipv6_only" {
            resolver["strategy"] = "ipv4_only"
            route["default_domain_resolver"] = resolver
        }
        result["route"] = route
        return result
    }
}
