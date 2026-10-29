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

    /// Restrict local DNS only. Proxy DNS and cached synthetic IPv6 destinations
    /// remain usable through the remote proxy even on an IPv4 physical network.
    static func applying(to source: [String: Any], supportsIPv6: Bool?) -> [String: Any] {
        guard supportsIPv6 == false, var dns = source["dns"] as? [String: Any],
              dns["strategy"] as? String != "ipv6_only" else { return source }
        var rules = dns["rules"] as? [[String: Any]] ?? []
        for index in rules.indices where rules[index]["server"] as? String == "dns-local" {
            if rules[index]["strategy"] as? String != "ipv6_only" {
                rules[index]["strategy"] = "ipv4_only"
            }
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
