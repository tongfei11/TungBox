import Foundation
import XCTest
@testable import TungBox

final class HostsConfigTests: XCTestCase {
    private func config(_ hosts: [String: [String]], rules: [[String: Any]] = []) -> [String: Any] {
        ["dns": ["servers": [["tag": "dns-hosts", "type": "hosts", "predefined": hosts]], "strategy": "prefer_ipv4"],
         "route": ["rules": rules], "outbounds": [["type": "direct", "tag": "direct"]]]
    }

    private func apply(_ value: [String: Any]) -> [String: Any] {
        ProxyModeConfig.ensureModeSupport(in: value, mode: "Rule", fallbackProxyTag: "direct")
    }

    func testHostsParsingUsesSnapshotAndCustomOverrides() {
        let result = DNSConfig.parseHostsEntries(systemHosts: "1.2.3.4 EXAMPLE.test alias.test # comment\n1.2.3.4 alias.test\ninvalid bad.test\n::1 localhost\n", customHosts: "EXAMPLE.test=::1;127.0.0.2,invalid\ncustom.test=192.0.2.1")
        XCTAssertEqual(result["example.test"], ["::1", "127.0.0.2"])
        XCTAssertEqual(result["alias.test"], ["1.2.3.4"])
        XCTAssertNil(result["localhost"])
        XCTAssertNil(result["bad.test"])
        XCTAssertNil(DNSConfig.parseHostsEntries(systemHosts: nil, customHosts: "custom.test=192.0.2.1")["alias.test"])
    }

    func testDNSHostsSourceUsesOnlyMergedSnapshot() throws {
        let dns = DNSConfig.buildSingBoxDNS(hostsEntries: ["snapshot.test": ["127.0.0.1"]])
        let servers = try XCTUnwrap(dns["servers"] as? [[String: Any]])
        let hosts = try XCTUnwrap(servers.first { $0["tag"] as? String == "dns-hosts" })
        XCTAssertEqual(hosts["path"] as? [String], ["/dev/null"])
        XCTAssertEqual(hosts["predefined"] as? [String: [String]], ["snapshot.test": ["127.0.0.1"]])
        let empty = DNSConfig.buildSingBoxDNS(hostsEntries: [:])
        XCTAssertFalse((empty["servers"] as? [[String: Any]] ?? []).contains { $0["tag"] as? String == "dns-hosts" })
    }

    func testHostsAddressSelectionRespectsStrategy() {
        let addresses = ["invalid", "::1", "127.0.0.1"]
        XCTAssertEqual(ProxyModeConfig.preferredHostsAddress(addresses, strategy: "prefer_ipv4"), "127.0.0.1")
        XCTAssertEqual(ProxyModeConfig.preferredHostsAddress(addresses, strategy: "prefer_ipv6"), "::1")
        XCTAssertNil(ProxyModeConfig.preferredHostsAddress(["::1"], strategy: "ipv4_only"))
        XCTAssertNil(ProxyModeConfig.preferredHostsAddress(["127.0.0.1"], strategy: "ipv6_only"))
    }

    func testModeRebuildPreservesUserResolveAndRoutingPriority() throws {
        let user: [String: Any] = ["action": "resolve", "domain": ["user.test"], "server": "custom"]
        let route: [String: Any] = ["domain": ["mapped.test"], "outbound": "direct"]
        let first = apply(config(["mapped.test": ["127.0.0.1"]], rules: [user, route]))
        let second = apply(first)
        XCTAssertTrue(NSDictionary(dictionary: first).isEqual(to: second))
        let rules = try XCTUnwrap((second["route"] as? [String: Any])?["rules"] as? [[String: Any]])
        XCTAssertEqual(rules[2]["override_address"] as? String, "127.0.0.1")
        XCTAssertEqual(rules[2]["ip_version"] as? Int, 4)
        XCTAssertEqual(rules[3]["ip_version"] as? Int, 6)
        XCTAssertEqual(rules[4]["action"] as? String, "resolve")
        XCTAssertEqual(rules[4]["server"] as? String, "dns-hosts")
        XCTAssertTrue(NSDictionary(dictionary: rules[rules.count - 2]).isEqual(to: user))
        XCTAssertTrue(NSDictionary(dictionary: rules.last!).isEqual(to: route))
    }

    func testSystemHostsMappingWinsOverEnabledOrDisabledDomainProxyRuleInEveryMode() throws {
        let entries = DNSConfig.parseHostsEntries(systemHosts: "124.113.85.3 ops-test.zdxlz.com", customHosts: "")
        let proxyRule: [String: Any] = ["domain_suffix": "zdxlz.com", "action": "route", "outbound": "proxy"]
        for mode in ["Rule", "Global", "Direct"] {
            for domainRules in [[proxyRule], []] {
                var source = config(entries, rules: domainRules)
                source["outbounds"] = [["type": "direct", "tag": "direct"], ["type": "direct", "tag": "proxy"]]
                let result = ProxyModeConfig.ensureModeSupport(in: source, mode: mode, fallbackProxyTag: "proxy")
                let rules = try XCTUnwrap((result["route"] as? [String: Any])?["rules"] as? [[String: Any]])
                XCTAssertEqual(rules[2]["override_address"] as? String, "124.113.85.3")
                let firstTerminal = try XCTUnwrap(rules.first { $0["outbound"] != nil })
                XCTAssertEqual(firstTerminal["domain"] as? [String], ["ops-test.zdxlz.com"])
                XCTAssertEqual(firstTerminal["outbound"] as? String, "direct")
                let rebuilt = ProxyModeConfig.ensureModeSupport(in: result, mode: mode, fallbackProxyTag: "proxy")
                XCTAssertTrue(NSDictionary(dictionary: result).isEqual(to: rebuilt))
                let disabled = ProxyModeConfig.ensureModeSupport(in: DNSConfig.replacingDNS(in: result, with: ["servers": []]), mode: mode, fallbackProxyTag: "proxy")
                let remaining = (disabled["route"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
                XCTAssertFalse(remaining.contains { $0["domain"] as? [String] == ["ops-test.zdxlz.com"] })
            }
        }
    }

    func testReplacingHostsRemovesOldOverridesAndMigratesLegacyRule() throws {
        let old = config(["old.test": ["127.0.0.1"]], rules: [["action": "resolve", "domain": ["old.test"]], ["action": "resolve", "domain": ["user.test"]]])
        let newDNS: [String: Any] = ["servers": [["tag": "dns-hosts", "predefined": ["new.test": ["127.0.0.2"]]]]]
        let updated = apply(DNSConfig.replacingDNS(in: apply(old), with: newDNS))
        let rules = try XCTUnwrap((updated["route"] as? [String: Any])?["rules"] as? [[String: Any]])
        XCTAssertFalse(rules.contains { ($0["domain"] as? [String]) == ["old.test"] })
        XCTAssertTrue(rules.contains { ($0["domain"] as? [String]) == ["user.test"] })
        XCTAssertTrue(rules.contains { $0["override_address"] as? String == "127.0.0.2" })
        let disabled = apply(DNSConfig.replacingDNS(in: updated, with: ["servers": []]))
        let disabledRules = try XCTUnwrap((disabled["route"] as? [String: Any])?["rules"] as? [[String: Any]])
        XCTAssertFalse(disabledRules.contains { $0["override_address"] != nil })
    }
}
