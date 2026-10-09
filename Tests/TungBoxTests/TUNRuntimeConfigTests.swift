import Foundation
import XCTest
@testable import TungBox

/// 全部使用显式设置与网络快照，不构造窗口、不探测网络、不启停 TUN。
final class TUNRuntimeConfigTests: XCTestCase {
    private let cachePath = "/fixture/tun/cache.db"
    private let secret = "fixture-secret"
    private var inbound: [String: Any] {
        ["type": "tun", "tag": "tun-in", "address": ["198.19.0.1/30"],
         "interface_name": "utun29", "auto_route": true, "stack": "mixed", "mtu": 9000,
         "strict_route": false, "endpoint_independent_nat": false,
         "route_exclude_address": ["10.0.0.0/8", "::1/128", "fc00::/7", "fe80::/10"]]
    }
    private var settingsSnapshot: TUNConfig.Settings {
        .init(routeExclude: ["10.0.0.0/8", "::1/128", "fc00::/7", "fe80::/10"])
    }
    private var device: TUNRuntimeConfigBuilder.Device {
        .init(ipv4Address: "198.19.0.1", interfaceName: "utun29")
    }
    private func builder(settings: TUNConfig.Settings? = nil, fallback: String = "snapshot-node") -> TUNRuntimeConfigBuilder {
        TUNRuntimeConfigBuilder(settings: settings ?? settingsSnapshot, device: device, fallbackProxyTag: fallback,
                                cachePath: cachePath, clashAPIPort: 9091, clashAPISecret: secret)
    }
    private func build(_ source: [String: Any], interface: String? = "en0", addresses: [String: [String]] = [:],
                       using builder: TUNRuntimeConfigBuilder? = nil) throws -> TUNRuntimeConfigBuilder.Transformation {
        let builder = builder ?? self.builder()
        let prepared = builder.prepare(source)
        let bound = builder.bindPhysicalInterface(interface, in: prepared.config)
        let output = builder.finish(bound.config, resolvedAddresses: addresses)
        _ = try output.text.get()
        return .init(config: output.config,
                     diagnostics: prepared.diagnostics + bound.diagnostics + output.diagnostics)
    }
    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(ConfigCodec.parseObject(from: text))
    }
    private func dictionary(_ config: [String: Any], _ key: String) throws -> [String: Any] {
        try XCTUnwrap(config[key] as? [String: Any])
    }
    private func outbounds(_ config: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(config["outbounds"] as? [[String: Any]])
    }
    private func tun(_ config: [String: Any]) throws -> [String: Any] {
        let inbounds = try XCTUnwrap(config["inbounds"] as? [[String: Any]])
        return try XCTUnwrap(inbounds.first { ($0["type"] as? String)?.lowercased() == "tun" })
    }

    func testDaemonSeparatesListenersAndKeepsModesAndUnknownFields() throws {
        let source = try object(#"""
        {"future":{"order":[2,1]},"log":{"level":"debug","future":true},
         "inbounds":[{"type":"mixed","tag":"local"},{"type":"HTTP"},{"type":"socks"},
                     {"type":"TUN","tag":"old"},{"type":"redirect","tag":"keep"},{"tag":"unknown"}],
         "outbounds":[{"type":"trojan","tag":"node","server":"example.test","future":true}],
         "route":{"final":"node","rules":[{"domain":["keep.test"],"outbound":"node"}]},
         "experimental":{"future":7,"clash_api":{"default_mode":"Rule","secret":"old","future":true},
                         "cache_file":{"store_rdrc":true}}}
        """#)
        for mode in ["Direct", "Global", "Rule", "custom"] {
            var input = source
            var experimental = try dictionary(input, "experimental")
            var api = try dictionary(experimental, "clash_api")
            api["default_mode"] = mode
            experimental["clash_api"] = api
            input["experimental"] = experimental
            let result = try build(input)
            XCTAssertEqual(ProxyModeConfig.readMode(from: result.config), mode)
            let inbounds = try XCTUnwrap(result.config["inbounds"] as? [[String: Any]])
            XCTAssertEqual(inbounds.compactMap { $0["tag"] as? String }, ["tun-in", "keep", "unknown"])
            let apiOut = try dictionary(dictionary(result.config, "experimental"), "clash_api")
            XCTAssertEqual(apiOut["external_controller"] as? String, "127.0.0.1:9091")
            XCTAssertEqual(apiOut["secret"] as? String, secret)
            XCTAssertEqual(apiOut["future"] as? Bool, true)
            XCTAssertEqual(try dictionary(result.config, "log")["level"] as? String, "warn")
            XCTAssertEqual(try dictionary(result.config, "log")["future"] as? Bool, true)
            XCTAssertEqual(try dictionary(result.config, "future")["order"] as? [Int], [2, 1])
            let outbound = try outbounds(result.config)
            XCTAssertEqual(outbound.compactMap { $0["tag"] as? String }, ["node", "direct", "全局"])
            XCTAssertEqual(outbound[0]["future"] as? Bool, true)
            let cache = try dictionary(dictionary(result.config, "experimental"), "cache_file")
            XCTAssertEqual(cache["enabled"] as? Bool, true)
            XCTAssertEqual(cache["path"] as? String, cachePath)
            XCTAssertEqual(cache["store_rdrc"] as? Bool, true)
            let rules = try XCTUnwrap(dictionary(result.config, "route")["rules"] as? [[String: Any]])
            XCTAssertEqual(rules.last?["domain"] as? [String], ["keep.test"])
            XCTAssertEqual(try dictionary(result.config, "route")["final"] as? String, "node")
            XCTAssertTrue(result.diagnostics.contains("[TUN] 守护进程不绑定本地代理端口（7890 由用户代理独占）\n"))
            XCTAssertFalse(result.diagnostics.joined().contains(secret))
        }
    }

    func testExplicitUserFieldsAndPathsReplaceOldTunInbound() throws {
        var settings = inbound
        settings["stack"] = "gvisor"
        settings["mtu"] = 1400
        settings["strict_route"] = true
        settings["endpoint_independent_nat"] = true
        settings["include_interface"] = ["en0", "en1"]
        settings["exclude_interface"] = ["utun7"]
        let result = try build(["inbounds": [["type": "tun", "stack": "system", "future": "old"]]],
                               using: builder(settings: .init(
                                   stack: .gvisor, mtu: 1400, strictRoute: true, endpointIndependentNAT: true,
                                   routeExclude: settingsSnapshot.routeExclude,
                                   includeInterface: ["en0", "en1"], excludeInterface: ["utun7"])))
        let resultTun = try tun(result.config)
        for key in ["stack", "mtu", "strict_route", "endpoint_independent_nat", "include_interface", "exclude_interface",
                    "address", "interface_name", "auto_route"] {
            let actual = try XCTUnwrap(resultTun[key])
            let expected = try XCTUnwrap(settings[key])
            XCTAssertTrue(NSDictionary(dictionary: [key: actual]).isEqual(to: [key: expected]), key)
        }
        XCTAssertNil(resultTun["future"])
        let alternate = TUNRuntimeConfigBuilder(settings: .init(stack: .gvisor, mtu: 1400, strictRoute: true,
                                               endpointIndependentNAT: true, routeExclude: settingsSnapshot.routeExclude,
                                               includeInterface: ["en0", "en1"], excludeInterface: ["utun7"]), device: device, fallbackProxyTag: "direct",
                                               cachePath: "/another/cache.db", clashAPIPort: 9991, clashAPISecret: "another-secret")
        let other = try build([:], using: alternate)
        let experimental = try dictionary(other.config, "experimental")
        XCTAssertEqual(try dictionary(experimental, "cache_file")["path"] as? String, "/another/cache.db")
        XCTAssertEqual(try dictionary(experimental, "clash_api")["external_controller"] as? String, "127.0.0.1:9991")
        XCTAssertEqual(try dictionary(experimental, "clash_api")["secret"] as? String, "another-secret")
    }

    func testPhysicalBindingSkipsVirtualOutboundsAndPreservesDNSPolicy() throws {
        let types = ["selector", "urltest", "url-test", "DIRECT", "block", "dns", "trojan", "fallback", "future"]
        let nodes: [[String: Any]] = types.map {
            ["type": $0, "tag": $0, "bind_interface": "old", "inet4_bind_address": "1.2.3.4", "inet6_bind_address": "::1"]
        }
        let result = try build(["outbounds": nodes, "route": ["default_interface": "old", "future": true],
                                "dns": ["strategy": "prefer_ipv6", "servers": [
                                    ["tag": "first", "detour": "direct"], ["tag": "second", "detour": "node"],
                                    ["tag": "third", "detour": "DIRECT"]]]])
        let route = try dictionary(result.config, "route")
        XCTAssertEqual(route["default_interface"] as? String, "en0")
        XCTAssertNil(route["auto_detect_interface"])
        XCTAssertEqual(route["future"] as? Bool, true)
        let nodesOut = try outbounds(result.config)
        for index in types.indices {
            XCTAssertEqual(nodesOut[index]["bind_interface"] as? String, index < 6 ? nil : "en0", types[index])
            XCTAssertNil(nodesOut[index]["inet4_bind_address"])
            XCTAssertNil(nodesOut[index]["inet6_bind_address"])
        }
        let dns = try dictionary(result.config, "dns")
        XCTAssertEqual(dns["strategy"] as? String, "prefer_ipv6")
        let servers = try XCTUnwrap(dns["servers"] as? [[String: Any]])
        XCTAssertNil(servers[0]["detour"])
        XCTAssertEqual(servers[1]["detour"] as? String, "node")
        XCTAssertEqual(servers[2]["detour"] as? String, "DIRECT")
    }

    func testNilInterfaceSnapshotKeepsAutomaticRoutingAndClearsStaleBindings() throws {
        let result = try build(["route": ["default_interface": "stale"],
                                "outbounds": [["type": "trojan", "tag": "node", "bind_interface": "stale"]]], interface: nil)
        let route = try dictionary(result.config, "route")
        XCTAssertEqual(route["auto_detect_interface"] as? Bool, true)
        XCTAssertNil(route["default_interface"])
        XCTAssertNil(try outbounds(result.config)[0]["bind_interface"])
        XCTAssertTrue(result.diagnostics.contains("[TUN] 未找到可用物理出口接口，保留 auto_detect_interface\n"))
        // 空字符串沿用旧校验结果：不能当作可用接口，也不能自动回退成 nil。
        XCTAssertThrowsError(try build([:], interface: ""))
    }

    func testRouteExclusionsPreserveExistingIPv6OrderAndDuplicates() throws {
        let source = try object(#"""
        {"dns":{"strategy":"ipv4_only","servers":[{"server":"9.9.9.9"},{"server":"8.8.8.8"},
                   {"server":"10.1.1.1"},{"server":"2001:4860:4860::8888"}]},
         "outbounds":[{"type":"trojan","tag":"literal","server":" [11.12.13.14] "},
                      {"type":"trojan","tag":"hostname","server":"node.test"},
                      {"type":"direct","tag":"direct","server":"12.12.12.12"}]}
        """#)
        let result = try build(source, addresses: ["node.test": ["13.14.15.16", "10.1.1.1", "2001:db8::1", "13.14.15.16"]],
                               using: builder(settings: .init(routeExclude: ["fc00::/7", "9.9.9.9/32", "fc00::/7", "10.0.0.0/8"])))
        let excludes = try XCTUnwrap(tun(result.config)["route_exclude_address"] as? [String])
        XCTAssertEqual(excludes, ["fc00::/7", "9.9.9.9/32", "fc00::/7", "10.0.0.0/8",
                                  "1.0.0.1/32", "1.1.1.1/32", "8.8.4.4/32", "8.8.8.8/32", "114.114.114.114/32",
                                  "119.29.29.29/32", "120.53.53.53/32", "180.76.76.76/32", "223.5.5.5/32", "223.6.6.6/32",
                                  "11.12.13.14/32", "13.14.15.16/32"])
        // 诊断统计候选地址，包含已存在的 9.9.9.9，沿用旧语义。
        XCTAssertTrue(result.diagnostics.contains("[TUN] 已排除 DNS/节点上游地址 13 个，避免代理握手被 TUN 捕获\n"))
        XCTAssertEqual(try dictionary(result.config, "dns")["strategy"] as? String, "ipv4_only")
    }

    func testResolutionCapsHostsAndAddressesButKeepsLaterLiteralServers() throws {
        var nodes: [[String: Any]] = (0..<18).map {
            ["type": "trojan", "tag": "node\($0)", "server": "node\($0).test"]
        }
        nodes.insert(["type": "trojan", "tag": "duplicate", "server": "node0.test"], at: 1)
        nodes.append(["type": "trojan", "tag": "literal", "server": "19.20.21.22"])
        let hosts = TUNRuntimeConfigBuilder.hostsNeedingResolution(in: ["outbounds": nodes])
        XCTAssertEqual(hosts, (0..<16).map { "node\($0).test" })
        let result = try build(["outbounds": nodes], addresses: [
            "node0.test": ["10.1.1.1", "14.1.1.1", "14.1.1.2", "14.1.1.3", "14.1.1.4"],
            "node15.test": ["15.1.1.1"], "node16.test": ["16.1.1.1"], "unrequested.test": ["17.1.1.1"]])
        let excludes = try XCTUnwrap(tun(result.config)["route_exclude_address"] as? [String])
        for ip in ["14.1.1.1", "14.1.1.2", "14.1.1.3", "15.1.1.1", "19.20.21.22"] {
            XCTAssertTrue(excludes.contains(ip + "/32"), ip)
        }
        for ip in ["10.1.1.1", "14.1.1.4", "16.1.1.1", "17.1.1.1"] {
            XCTAssertFalse(excludes.contains(ip + "/32"), ip)
        }
    }

    func testPrefetchAndImmediateResolutionRetainDifferentHostSelection() throws {
        let source = try object(#"""
        {"outbounds":[{"type":"selector","server":"virtual.test"},{"type":"trojan","server":"node.test"},
                      {"type":"trojan","server":"node.test"},{"server":""},{"server":"[8.8.8.8]"},
                      {"type":"dns","server":"dns.test"},{"type":"fallback","server":"fallback.test"},
                      {"type":"trojan","server":"10.0.0.1"},{"type":"trojan","server":"2001:db8::1"}]}
        """#)
        XCTAssertEqual(TUNRuntimeConfigBuilder.upstreamHosts(in: try ConfigCodec.render(source)),
                       ["virtual.test", "node.test", "dns.test", "fallback.test", "10.0.0.1", "2001:db8::1"])
        XCTAssertEqual(TUNRuntimeConfigBuilder.hostsNeedingResolution(in: source),
                       ["node.test", "fallback.test", "10.0.0.1", "2001:db8::1"])
        XCTAssertEqual(TUNRuntimeConfigBuilder.upstreamHosts(in: "invalid"), [])
        let many: [[String: Any]] = (0..<20).map { ["server": "node\($0).test"] }
        XCTAssertEqual(TUNRuntimeConfigBuilder.upstreamHosts(in: try ConfigCodec.render(["outbounds": many])),
                       (0..<16).map { "node\($0).test" })
    }

    func testIPv4ClassificationPreservesOriginalPolicy() {
        for value in ["1.1.1.1", "223.6.6.6", "100.63.0.1", "100.128.0.1", "172.15.0.1", "172.32.0.1",
                      "192.167.0.1", "198.17.0.1", "198.20.0.1", "192.0.2.1", "198.51.100.1", "203.0.113.1"] {
            XCTAssertTrue(TUNRuntimeConfigBuilder.isPublicIPv4Address(value), value)
        }
        for value in ["", "0.1.1.1", "10.1.1.1", "127.0.0.1", "100.64.0.1", "100.127.0.1", "169.254.0.1",
                      "172.16.0.1", "172.31.0.1", "192.168.0.1", "198.18.0.1", "198.19.0.1", "224.0.0.1",
                      "255.255.255.255", "256.1.1.1", "1.1.1", "1..1.1", "node.test", "[8.8.8.8]", "2001:db8::1"] {
            XCTAssertFalse(TUNRuntimeConfigBuilder.isPublicIPv4Address(value), value)
        }
    }

    func testToggleUsesSnapshotFallbackAndPreservesCustomFinal() throws {
        for final: String? in [nil, "direct", "custom"] {
            let result = TUNRuntimeConfigBuilder.setTunEnabled(true, in: ["route": final.map { ["final": $0] } ?? [:]],
                                                              settings: settingsSnapshot, device: device, fallbackProxyTag: "snapshot-node", cachePath: cachePath)
            XCTAssertEqual(try dictionary(result, "route")["final"] as? String, final == "custom" ? "custom" : "snapshot-node")
        }
        let selector: [[String: Any]] = [["type": "selector", "tag": "selected"]]
        let result = TUNRuntimeConfigBuilder.setTunEnabled(true, in: ["outbounds": selector], settings: settingsSnapshot, device: device,
                                                          fallbackProxyTag: "snapshot-node", cachePath: cachePath)
        XCTAssertEqual(try dictionary(result, "route")["final"] as? String, "selected")
    }

    func testDisableRemovesOnlyTunRoutingAndOwnedCachePath() throws {
        let source = try object(#"""
        {"inbounds":[{"type":"TUN"},{"type":"mixed","tag":"local"}],"log":{"level":"debug"},
         "outbounds":[{"tag":"node","bind_interface":"en0"}],
         "route":{"default_interface":"en0","auto_detect_interface":true,"final":"node","future":true},
         "experimental":{"future":true,"cache_file":{"enabled":true,"path":"/fixture/tun/cache.db","store_rdrc":true}}}
        """#)
        let result = TUNRuntimeConfigBuilder.setTunEnabled(false, in: source, settings: .init(), device: device,
                                                          fallbackProxyTag: "unused", cachePath: cachePath)
        let inbounds = try XCTUnwrap(result["inbounds"] as? [[String: Any]])
        XCTAssertEqual(inbounds.compactMap { $0["tag"] as? String }, ["local"])
        let route = try dictionary(result, "route")
        XCTAssertNil(route["default_interface"])
        XCTAssertNil(route["auto_detect_interface"])
        XCTAssertEqual(route["final"] as? String, "node")
        XCTAssertEqual(route["future"] as? Bool, true)
        XCTAssertEqual(try outbounds(result)[0]["bind_interface"] as? String, "en0")
        XCTAssertEqual(try dictionary(result, "log")["level"] as? String, "debug")
        let cache = try dictionary(dictionary(result, "experimental"), "cache_file")
        XCTAssertNil(cache["path"])
        XCTAssertEqual(cache["enabled"] as? Bool, true)
        XCTAssertEqual(cache["store_rdrc"] as? Bool, true)
        let emptyRoute = TUNRuntimeConfigBuilder.setTunEnabled(false, in: ["route": ["auto_detect_interface": true]],
                                                              settings: .init(), device: device, fallbackProxyTag: "unused", cachePath: cachePath)
        XCTAssertNil(emptyRoute["route"])
        XCTAssertNil(emptyRoute["experimental"])
        for path: String? in ["/foreign/cache.db", nil] {
            let original: [String: Any] = ["experimental": ["cache_file": path.map { ["path": $0] } ?? [:]]]
            let disabled = TUNRuntimeConfigBuilder.setTunEnabled(false, in: original, settings: .init(), device: device,
                                                                fallbackProxyTag: "unused", cachePath: cachePath)
            XCTAssertTrue(NSDictionary(dictionary: try dictionary(disabled, "experimental"))
                .isEqual(to: try dictionary(original, "experimental")))
        }
    }

    func testRoutingValidationRetainsEverySupportedEscapeAndError() {
        let tun: [[String: Any]] = [["type": "TUN", "auto_route": true]]
        for config: [String: Any] in [[:], ["inbounds": [["type": "tun", "auto_route": false]]],
                                     ["inbounds": [["type": "mixed", "auto_route": true]]]] {
            XCTAssertNoThrow(try TUNRuntimeConfigBuilder.validateTunRuntimeRouting(in: config))
        }
        for route: [String: Any] in [["auto_detect_interface": true], ["default_interface": "en0"]] {
            XCTAssertNoThrow(try TUNRuntimeConfigBuilder.validateTunRuntimeRouting(in: ["inbounds": tun, "route": route]))
        }
        for key in ["bind_interface", "inet4_bind_address", "inet6_bind_address"] {
            XCTAssertNoThrow(try TUNRuntimeConfigBuilder.validateTunRuntimeRouting(in: ["inbounds": tun, "outbounds": [[key: "bound"]]]))
        }
        for route: [String: Any] in [[:], ["default_interface": ""], ["auto_detect_interface": false]] {
            XCTAssertThrowsError(try TUNRuntimeConfigBuilder.validateTunRuntimeRouting(in: ["inbounds": tun, "route": route])) { error in
                XCTAssertEqual((error as NSError).domain, "TungBox")
                XCTAssertEqual((error as NSError).code, 1)
                XCTAssertEqual(error.localizedDescription,
                               "TUN 配置缺少出口防回环设置：auto_route=true 时必须启用 auto_detect_interface、default_interface 或 outbound 绑定。")
            }
        }
    }

    func testRepeatedBuildsDoNotAccumulateInboundsRulesOrExclusions() throws {
        let source = try object(#"""
        {"outbounds":[{"type":"trojan","tag":"node","server":"node.test"},{"type":"direct","tag":"direct","future":true}],
         "experimental":{"clash_api":{"default_mode":"Global"}},"dns":{"strategy":"prefer_ipv4"}}
        """#)
        let first = try build(source, addresses: ["node.test": ["18.1.1.1"]])
        let rendered = try ConfigCodec.render(first.config)
        var result = first.config
        for _ in 0..<3 {
            result = try build(result, addresses: ["node.test": ["18.1.1.1"]]).config
            XCTAssertEqual(try ConfigCodec.render(result), rendered)
        }
        XCTAssertEqual(try outbounds(result).filter { $0["tag"] as? String == "direct" }.count, 1)
        XCTAssertEqual(try outbounds(result)[1]["future"] as? Bool, true)
    }

    func testDiagnosticOrderAndUnchangedAutomaticRoutingMessage() throws {
        let result = try build(["route": ["auto_detect_interface": true], "dns": ["strategy": "prefer_ipv4"]], interface: nil)
        XCTAssertEqual(result.diagnostics, [
            "[TUN] 原始配置缺少 direct outbound，已添加\n",
            "[TUN] 运行时出口：auto_detect_interface 已启用\n",
            "[TUN] 未找到可用物理出口接口，保留 auto_detect_interface\n",
            "[TUN] 已排除 DNS/节点上游地址 10 个，避免代理握手被 TUN 捕获\n",
            "[TUN] DNS 策略：prefer_ipv4\n",
            "[TUN] 最终配置 direct outbound 状态: 存在\n",
            "[TUN] 最终配置中的所有 outbound tags: direct\n"
        ])
        let again = try build(result.config, interface: nil)
        XCTAssertEqual(again.diagnostics.first, "[TUN] 原始配置已有 direct outbound\n")
    }

    private func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "TungBoxTests.TUNSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    func testSettingsSnapshotKeepsDefaultsAndInvalidValueFallbacks() throws {
        try withIsolatedDefaults { defaults in
            XCTAssertEqual(TUNConfig.snapshot(from: defaults), .init())
            defaults.set("unknown", forKey: "tunStack")
            defaults.set(-100, forKey: "tunMTU")
            defaults.set("invalid", forKey: "tunStrictRoute")
            defaults.set("invalid", forKey: "tunEndpointIndependentNAT")
            defaults.set([1, 2], forKey: "tunRouteExclude")
            defaults.set("invalid", forKey: "tunIncludeInterface")
            defaults.set([1], forKey: "tunExcludeInterface")
            XCTAssertEqual(TUNConfig.snapshot(from: defaults), .init())
            defaults.set(0, forKey: "tunMTU")
            XCTAssertEqual(TUNConfig.snapshot(from: defaults).mtu, 9000)
        }
    }

    func testSettingsSnapshotPreservesExplicitEmptyAndUncleanedArrays() throws {
        try withIsolatedDefaults { defaults in
            defaults.set("system", forKey: "tunStack")
            defaults.set(1500, forKey: "tunMTU")
            defaults.set(true, forKey: "tunStrictRoute")
            defaults.set(true, forKey: "tunEndpointIndependentNAT")
            defaults.set([], forKey: "tunRouteExclude")
            defaults.set([" en0 ", "en0", ""], forKey: "tunIncludeInterface")
            defaults.set(["utun7", "utun7"], forKey: "tunExcludeInterface")
            let snapshot = TUNConfig.snapshot(from: defaults)
            XCTAssertEqual(snapshot.stack, .system)
            XCTAssertEqual(snapshot.mtu, 1500)
            XCTAssertTrue(snapshot.strictRoute)
            XCTAssertTrue(snapshot.endpointIndependentNAT)
            XCTAssertEqual(snapshot.routeExclude, [])
            XCTAssertEqual(snapshot.includeInterface, [" en0 ", "en0", ""])
            XCTAssertEqual(snapshot.excludeInterface, ["utun7", "utun7"])
        }
    }

    func testCapturedSettingsRemainStableAfterPreferencesChange() throws {
        try withIsolatedDefaults { defaults in
            defaults.set("gvisor", forKey: "tunStack")
            defaults.set(1400, forKey: "tunMTU")
            defaults.set(["fc00::/7"], forKey: "tunRouteExclude")
            let captured = TUNConfig.snapshot(from: defaults)
            let capturedBuilder = builder(settings: captured)
            defaults.set("system", forKey: "tunStack")
            defaults.set(1600, forKey: "tunMTU")
            defaults.set(["10.0.0.0/8"], forKey: "tunRouteExclude")
            let config = try build([:], using: capturedBuilder).config
            let resultTun = try tun(config)
            XCTAssertEqual(resultTun["stack"] as? String, "gvisor")
            XCTAssertEqual(resultTun["mtu"] as? Int, 1400)
            XCTAssertEqual((resultTun["route_exclude_address"] as? [String])?.first, "fc00::/7")
            XCTAssertEqual(captured.stack, .gvisor)
            XCTAssertEqual(TUNConfig.snapshot(from: defaults).stack, .system)
            XCTAssertEqual(TUNConfig.snapshot(from: defaults).mtu, 1600)
        }
    }

    func testSettingsApplicationPreservesUnknownFieldsAndRemovesEmptyInterfaceFilters() throws {
        let base: [String: Any] = ["type": "tun", "future": [2, 1], "stack": "old", "mtu": 1,
                                   "include_interface": ["old"], "exclude_interface": ["old"]]
        let result = TUNConfig.Settings().applying(to: base)
        XCTAssertEqual(result["type"] as? String, "tun")
        XCTAssertEqual(result["future"] as? [Int], [2, 1])
        XCTAssertEqual(result["stack"] as? String, "mixed")
        XCTAssertEqual(result["mtu"] as? Int, 9000)
        XCTAssertEqual(result["route_exclude_address"] as? [String],
                       ["10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12",
                        "192.168.0.0/16", "::1/128", "fc00::/7", "fe80::/10"])
        XCTAssertNil(result["include_interface"])
        XCTAssertNil(result["exclude_interface"])
        let explicitEmpty = TUNConfig.Settings(routeExclude: []).applying(to: base)
        XCTAssertEqual(explicitEmpty["route_exclude_address"] as? [String], [])
    }

    func testCompletedOutputIncludesRenderedConfigAndOrderedDiagnostics() throws {
        let builder = builder()
        let prepared = builder.prepare(["dns": ["strategy": "prefer_ipv4"]])
        let bound = builder.bindPhysicalInterface(nil, in: prepared.config)
        let output = builder.finish(bound.config, resolvedAddresses: [:])
        let text = try output.text.get()
        let reparsed = try object(text)
        XCTAssertTrue(NSDictionary(dictionary: output.config).isEqual(to: reparsed))
        XCTAssertEqual(output.diagnostics, [
            "[TUN] 已排除 DNS/节点上游地址 10 个，避免代理握手被 TUN 捕获\n",
            "[TUN] DNS 策略：prefer_ipv4\n",
            "[TUN] 最终配置 direct outbound 状态: 存在\n",
            "[TUN] 最终配置中的所有 outbound tags: direct\n"
        ])
        XCTAssertFalse(output.diagnostics.joined().contains(secret))
    }

    func testCompletedFailureRetainsPriorDiagnosticsAndOriginalRoutingError() throws {
        let builder = builder()
        let prepared = builder.prepare(["dns": ["strategy": "prefer_ipv6"]])
        let bound = builder.bindPhysicalInterface("", in: prepared.config)
        let output = builder.finish(bound.config, resolvedAddresses: [:])
        XCTAssertThrowsError(try output.text.get()) { error in
            XCTAssertEqual((error as NSError).domain, "TungBox")
            XCTAssertEqual((error as NSError).code, 1)
            XCTAssertEqual(error.localizedDescription,
                           "TUN 配置缺少出口防回环设置：auto_route=true 时必须启用 auto_detect_interface、default_interface 或 outbound 绑定。")
        }
        XCTAssertEqual(output.diagnostics, [
            "[TUN] 已排除 DNS/节点上游地址 10 个，避免代理握手被 TUN 捕获\n",
            "[TUN] DNS 策略：prefer_ipv6\n"
        ])
        XCTAssertFalse(output.diagnostics.joined().contains("最终配置"))
    }

    func testDeviceSnapshotControlsOnlyTunAddressAndInterface() throws {
        let custom = TUNRuntimeConfigBuilder(settings: settingsSnapshot,
                                            device: .init(ipv4Address: "198.19.2.1", interfaceName: "utun99"),
                                            fallbackProxyTag: "direct", cachePath: cachePath,
                                            clashAPIPort: 9091, clashAPISecret: secret)
        let resultTun = try tun(build([:], using: custom).config)
        XCTAssertEqual(resultTun["address"] as? [String], ["198.19.2.1/30"])
        XCTAssertEqual(resultTun["interface_name"] as? String, "utun99")
        XCTAssertEqual(resultTun["auto_route"] as? Bool, true)
    }
}
