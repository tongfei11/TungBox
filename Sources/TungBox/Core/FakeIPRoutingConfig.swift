import Foundation

/// Keep synthetic IPv6 destinations outside the private LAN bypass range.
enum FakeIPRoutingConfig {
    static let ipv6Pool = "2001:2::/48"
    static let interfaceIPv6Prefix = "fd74:756e:6762:6f78::1/126"

    static func migratingLegacyIPv6Pool(in config: [String: Any]) -> [String: Any] {
        guard var dns = config["dns"] as? [String: Any] else { return config }
        var changed = false
        func migrate(_ entry: [String: Any]) -> [String: Any] {
            var entry = entry
            if (entry["inet6_range"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fc00::/18" {
                entry["inet6_range"] = ipv6Pool
                changed = true
            }
            return entry
        }
        if let servers = dns["servers"] as? [[String: Any]] {
            dns["servers"] = servers.map { server in
                (server["type"] as? String)?.lowercased() == "fakeip" ? migrate(server) : server
            }
        }
        if let legacy = dns["fakeip"] as? [String: Any], legacy["enabled"] as? Bool == true {
            dns["fakeip"] = migrate(legacy)
        }
        guard changed else { return config }
        var result = config
        result["dns"] = dns
        return result
    }

    static func hasIPv6Pool(in config: [String: Any]) -> Bool {
        let dns = config["dns"] as? [String: Any] ?? [:]
        func hasPool(_ entry: [String: Any]) -> Bool {
            !(entry["inet6_range"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if (dns["servers"] as? [[String: Any]] ?? []).contains(where: {
            ($0["type"] as? String)?.lowercased() == "fakeip" && hasPool($0)
        }) { return true }
        let legacy = dns["fakeip"] as? [String: Any] ?? [:]
        return legacy["enabled"] as? Bool == true && hasPool(legacy)
    }
}
