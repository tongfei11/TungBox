import XCTest
@testable import TungBox

final class TUNIPv6EgressTests: XCTestCase {
    func testOrdinaryProxyUsesPhysicalIPv4WithoutChangingRemoteExitOrSavedConfig() throws {
        let source: [String: Any] = [
            "inbounds": [["type": "mixed", "listen": "127.0.0.1", "listen_port": 17890]],
            "dns": ["strategy": "prefer_ipv4", "servers": [["type": "local", "tag": "dns-local"]]],
            "route": ["default_domain_resolver": "dns-local"],
            "outbounds": [
                ["type": "trojan", "tag": "dual-stack", "server": "node.example", "server_port": 443],
                ["type": "trojan", "tag": "ipv6-explicit", "server": "2001:db8::1", "server_port": 443,
                 "domain_resolver": ["server": "dns-local", "strategy": "ipv6_only"]]
            ]
        ]
        let before = try ConfigCodec.render(source)
        let runtime = TUNIPv6Egress.applying(to: source, supportsIPv6: false)
        let resolver = (runtime["route"] as? [String: Any])?["default_domain_resolver"] as? [String: String]
        XCTAssertEqual(resolver, ["server": "dns-local", "strategy": "ipv4_only"])
        XCTAssertEqual(try ConfigCodec.render(["outbounds": runtime["outbounds"]!]),
                       try ConfigCodec.render(["outbounds": source["outbounds"]!]))
        XCTAssertEqual((runtime["inbounds"] as? [[String: Any]])?.first?["type"] as? String, "mixed")
        XCTAssertEqual((runtime["dns"] as? [String: Any])?["strategy"] as? String, "prefer_ipv4")
        XCTAssertEqual(try ConfigCodec.render(source), before)
    }

    func testLocalAAAAFilterCoexistsWithFakeIPQueryRulesInActualCore() throws {
        guard let core = ProcessInfo.processInfo.environment["TUNGBOX_TEST_CORE"] else {
            throw XCTSkip("设置 TUNGBOX_TEST_CORE 可运行隔离的 Core 配置校验")
        }
        let source: [String: Any] = [
            "dns": ["strategy": "prefer_ipv4", "servers": [
                ["type": "udp", "tag": "dns-local", "server": "127.0.0.1", "server_port": 15353],
                ["type": "fakeip", "tag": "dns-fakeip", "inet4_range": "198.18.0.0/15", "inet6_range": "2001:2::/48"]
            ], "rules": [
                ["rule_set": ["geosite-cn", "geosite-private"], "server": "dns-local"],
                ["domain_suffix": "local", "server": "dns-local"],
                ["domain_suffix": "fake.test", "query_type": ["A", "AAAA"], "server": "dns-fakeip"]
            ], "final": "dns-local"],
            "route": ["default_domain_resolver": "dns-local", "rule_set": [
                ["type": "inline", "tag": "geosite-cn", "rules": [["domain_suffix": ["qq.com", "qpic.cn"]]]],
                ["type": "inline", "tag": "geosite-private", "rules": [["domain_suffix": "lan"]]]
            ]],
            "outbounds": [["type": "direct", "tag": "direct"]]
        ]
        let config = TUNIPv6Egress.applying(to: source, supportsIPv6: false)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TungBox-CoreDNS-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        try ConfigCodec.render(config).write(to: url, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: core)
        process.arguments = ["check", "-c", url.path]
        // Do not let deprecated-option escape hatches hide an invalid config.
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("ENABLE_DEPRECATED_") }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: output, as: UTF8.self))
    }

    func testPhysicalIPv6RequiresBothGlobalAddressAndMatchingRoute() {
        let linkLocal = "en5: flags=8863\n\tinet6 fe80::1%en5 prefixlen 64\n\tinet 192.0.2.2 netmask 0xffffff00"
        let global = linkLocal + "\n\tinet6 2001:db8::2 prefixlen 64 autoconf secured"
        let route = "destination: default\ninterface: en5\nflags: <UP,GATEWAY>"
        XCTAssertEqual(TUNIPv6Egress.availability(interface: "en5", ifconfig: linkLocal, route: route), false)
        XCTAssertEqual(TUNIPv6Egress.availability(interface: "en5", ifconfig: global, route: route), true)
        XCTAssertEqual(TUNIPv6Egress.availability(interface: "en5", ifconfig: global, route: "interface: utun29"), false)
        XCTAssertEqual(TUNIPv6Egress.availability(interface: "en5", ifconfig: global + " tentative", route: route), false)
        XCTAssertNil(TUNIPv6Egress.availability(interface: "en5", ifconfig: "", route: route))
        XCTAssertNil(TUNIPv6Egress.availability(interface: "en5", ifconfig: global, route: ""))
    }

    func testIPv4PhysicalNetworkRestrictsLocalDNSButKeepsProxyAndFakeIPv6() throws {
        let source: [String: Any] = [
            "dns": ["strategy": "prefer_ipv4", "rules": [
                ["domain_suffix": ["qq.com", "qpic.cn"], "server": "dns-local"],
                ["query_type": ["A", "AAAA"], "server": "dns-fakeip"],
                ["domain_suffix": "proxy.test", "server": "dns-proxy", "strategy": "prefer_ipv6"]
            ], "servers": [["type": "udp", "tag": "dns-local", "server": "192.0.2.53"],
                            ["type": "https", "tag": "dns-proxy", "server": "192.0.2.54"],
                            ["type": "fakeip", "tag": "dns-fakeip", "inet6_range": "2001:2::/48"]]],
            "route": ["default_domain_resolver": "dns-local", "rules": [["outbound": "direct"]]],
            "outbounds": [["type": "direct", "tag": "direct"]]
        ]
        let original = try ConfigCodec.render(source)
        let builder = TUNRuntimeConfigBuilder(settings: .init(),
            device: .init(ipv4Address: "198.19.0.1", interfaceName: "utun29"),
            fallbackProxyTag: "direct", cachePath: "/fixture/cache.db", clashAPIPort: 9091, clashAPISecret: "fixture")
        let prepared = builder.prepare(source)
        let bound = builder.bindPhysicalInterface("en5", supportsIPv6: false, in: prepared.config)
        let result = builder.finish(bound.config, resolvedAddresses: [:])
        _ = try result.text.get()
        let dns = try XCTUnwrap(result.config["dns"] as? [String: Any])
        let rules = try XCTUnwrap(dns["rules"] as? [[String: Any]])
        XCTAssertEqual(rules[0]["action"] as? String, "predefined")
        XCTAssertEqual(rules[0]["rcode"] as? String, "NOERROR")
        let conditions = try XCTUnwrap(rules[0]["rules"] as? [[String: Any]])
        XCTAssertEqual(conditions[0]["domain_suffix"] as? [String], ["qq.com", "qpic.cn"])
        XCTAssertNil(conditions[0]["server"])
        XCTAssertEqual(conditions[1]["query_type"] as? String, "AAAA")
        XCTAssertEqual(rules[1]["server"] as? String, "dns-local")
        XCTAssertNil(rules[1]["strategy"])
        XCTAssertEqual(rules[2]["server"] as? String, "dns-fakeip")
        XCTAssertEqual(rules[3]["strategy"] as? String, "prefer_ipv6")
        XCTAssertEqual(dns["strategy"] as? String, "prefer_ipv4")
        let route = try XCTUnwrap(result.config["route"] as? [String: Any])
        XCTAssertEqual(route["default_domain_resolver"] as? [String: String], ["server": "dns-local", "strategy": "ipv4_only"])
        let inbound = try XCTUnwrap((result.config["inbounds"] as? [[String: Any]])?.first)
        XCTAssertTrue((inbound["address"] as? [String] ?? []).contains(FakeIPRoutingConfig.interfaceIPv6Prefix))
        XCTAssertEqual(try ConfigCodec.render(source), original)
        XCTAssertEqual(try ConfigCodec.render(TUNIPv6Egress.applying(to: bound.config, supportsIPv6: false)),
                       try ConfigCodec.render(bound.config))
    }

    func testDualStackUnknownAndExplicitIPv6OnlyKeepUserChoice() throws {
        for capability: Bool? in [true, nil] {
            let source: [String: Any] = ["dns": ["strategy": "prefer_ipv6", "rules": [["server": "dns-local"]]]]
            XCTAssertEqual(try ConfigCodec.render(TUNIPv6Egress.applying(to: source, supportsIPv6: capability)),
                           try ConfigCodec.render(source))
        }
        let explicit: [String: Any] = ["dns": ["strategy": "ipv6_only", "rules": [["server": "dns-local"]]]]
        XCTAssertEqual(try ConfigCodec.render(TUNIPv6Egress.applying(to: explicit, supportsIPv6: false)),
                       try ConfigCodec.render(explicit))
        let source: [String: Any] = ["dns": ["rules": [["server": "dns-local", "strategy": "ipv6_only"]]],
            "route": ["default_domain_resolver": ["server": "dns-local", "strategy": "ipv6_only", "timeout": "2s"]]]
        XCTAssertEqual(try ConfigCodec.render(TUNIPv6Egress.applying(to: source, supportsIPv6: false)),
                       try ConfigCodec.render(source))
    }
}
