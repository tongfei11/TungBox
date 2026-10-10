import Foundation
import XCTest
@testable import TungBox

final class RuleSetRuntimeTests: XCTestCase {
    func testRuleProjectionDoesNotUndoCurrentModeRulesOrInvalidateNodeTests() throws {
        let base: [[String: Any]] = [
            ["action": "sniff"], ["protocol": "dns", "action": "hijack-dns"],
            ["clash_mode": "direct", "outbound": "direct"],
            ["clash_mode": "global", "outbound": TungBoxConfig.tagManual],
            ["ip_is_private": true, "outbound": "direct"]
        ]
        let generated = [RuleRouting.customRouteRule(type: "DOMAIN", value: "example.invalid", strategy: "DIRECT")]
        let original: [String: Any] = [
            "route": ["rules": RuleRouting.rebuild(base: base, generated: generated), "final": TungBoxConfig.tagManual],
            "outbounds": [
                ["type": "selector", "tag": TungBoxConfig.tagManual, "outbounds": ["node"]],
                ["type": "trojan", "tag": "node", "server": "node.invalid"]
            ]
        ]
        for mode in ["Direct", "Global", "Rule"] {
            let running = ProxyModeConfig.ensureModeSupport(in: original, mode: mode, fallbackProxyTag: "node")
            let projected = RuleRouting.rebuildingRules(in: running, base: base, generated: generated, fallbackProxyTag: "node")
            XCTAssertEqual(try ConfigCodec.render(projected), try ConfigCodec.render(running), "规则来源中的旧全局出站不能触发配置变化和 TUN 重载")
            XCTAssertEqual(NodeDelayTestPolicy.configurationIdentity(try ConfigCodec.render(projected)), NodeDelayTestPolicy.configurationIdentity(try ConfigCodec.render(running)))
        }
    }

    func testRuleProjectionStillAppliesRealRuleChangesAndPreservesOtherFields() throws {
        let source = ProxyModeConfig.ensureModeSupport(in: [
            "route": ["future": true, "rules": []],
            "outbounds": [["type": "trojan", "tag": "node", "server": "node.invalid"]],
            "future": ["keep": [2, 1]]
        ], mode: "Global", fallbackProxyTag: "node")
        let added = RuleRouting.customRouteRule(type: "DOMAIN", value: "added.invalid", strategy: "DIRECT")
        let projected = RuleRouting.rebuildingRules(in: source, base: [], generated: [added], fallbackProxyTag: "node")
        let route = try XCTUnwrap(projected["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        XCTAssertTrue(rules.contains { NSDictionary(dictionary: $0).isEqual(to: added) })
        XCTAssertEqual(route["future"] as? Bool, true)
        XCTAssertTrue(NSDictionary(dictionary: projected["future"] as? [String: Any] ?? [:]).isEqual(to: source["future"] as? [String: Any] ?? [:]))
        XCTAssertEqual(ProxyModeConfig.readMode(from: projected), "Global")
        XCTAssertNotEqual(NodeDelayTestPolicy.configurationIdentity(try ConfigCodec.render(projected)), NodeDelayTestPolicy.configurationIdentity(try ConfigCodec.render(source)))
    }

    func testInstallBundledRuleSetsCopiesMissingFilesWithoutOverwritingUpdates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundled = root.appendingPathComponent("bundled")
        let installed = root.appendingPathComponent("installed")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("bundled-private".utf8).write(to: bundled.appendingPathComponent("geosite-private.srs"))
        try Data("bundled-cn".utf8).write(to: bundled.appendingPathComponent("geosite-cn.srs"))
        try Data("updated-private".utf8).write(to: installed.appendingPathComponent("geosite-private.srs"))

        try RuleSetRuntime.installBundledRuleSets(from: bundled, to: installed)

        XCTAssertEqual(
            try Data(contentsOf: installed.appendingPathComponent("geosite-private.srs")),
            Data("updated-private".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: installed.appendingPathComponent("geosite-cn.srs")),
            Data("bundled-cn".utf8)
        )
    }

    func testLocalizeBuiltInRuleSetsRemovesNetworkDependencyButPreservesRemoteSourceMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let localFile = root.appendingPathComponent("geosite-private.srs")
        try Data("rule-set".utf8).write(to: localFile)

        let config: [String: Any] = [
            "route": [
                "rule_set": [
                    [
                        "type": "remote",
                        "tag": "geosite-private",
                        "format": "binary",
                        "url": "https://example.com/private.srs",
                        "download_detour": "direct",
                        "update_interval": "7d"
                    ],
                    [
                        "type": "remote",
                        "tag": "third-party",
                        "format": "binary",
                        "url": "https://example.com/third-party.srs"
                    ]
                ]
            ]
        ]

        let result = RuleSetRuntime.localizeBuiltInRuleSets(in: config, ruleSetDirectory: root)
        let route = try XCTUnwrap(result.config["route"] as? [String: Any])
        let sets = try XCTUnwrap(route["rule_set"] as? [[String: Any]])

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(sets[0]["type"] as? String, "local")
        XCTAssertEqual(sets[0]["path"] as? String, localFile.path)
        XCTAssertNil(sets[0]["url"])
        XCTAssertNil(sets[0]["download_detour"])
        XCTAssertNil(sets[0]["update_interval"])
        XCTAssertEqual(result.remoteSources["geosite-private"]?.absoluteString, "https://example.com/private.srs")
        XCTAssertEqual(sets[1]["type"] as? String, "remote")
        XCTAssertEqual(sets[1]["url"] as? String, "https://example.com/third-party.srs")
    }

    func testRuleSearchFiltersExistingRowsWithoutRebuildingThem() {
        let rows = [
            RuleInfo(customRuleID: nil, enabled: false, id: "", type: "", value: "# 当前配置规则", strategy: "", count: "", note: "", isSection: true),
            RuleInfo(customRuleID: nil, enabled: true, id: "1", type: "DOMAIN", value: "example.com", strategy: "代理", count: "0", note: "示例", isSection: false),
            RuleInfo(customRuleID: nil, enabled: true, id: "2", type: "IP-CIDR", value: "192.0.2.0/24", strategy: "直连", count: "0", note: "测试网段", isSection: false)
        ]

        let filtered = rows.filter {
            RuleSearch.matches(
                type: $0.type,
                value: $0.value,
                strategy: $0.strategy,
                note: $0.note,
                isSection: $0.isSection,
                query: "example"
            )
        }

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered[0].isSection)
        XCTAssertEqual(filtered[1].value, "example.com")
    }

    func testBuiltInRuleSetRefreshIntervals() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("geosite-private.srs")
        try Data("rule-set".utf8).write(to: file)
        let now = Date(timeIntervalSince1970: 2_000_000)

        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-8 * 86_400)], ofItemAtPath: file.path)
        XCTAssertTrue(RuleSetRuntime.needsRefresh(tag: "geosite-private", fileURL: file, now: now))

        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-6 * 86_400)], ofItemAtPath: file.path)
        XCTAssertFalse(RuleSetRuntime.needsRefresh(tag: "geosite-private", fileURL: file, now: now))
        XCTAssertTrue(RuleSetRuntime.needsRefresh(tag: "geoip-cn", fileURL: root.appendingPathComponent("missing.srs"), now: now))
    }

    func testDeferredNetworkChecksOpenOnlyAfterFirstSuccessfulConnection() {
        var gate = FirstConnectionGate()

        XCTAssertFalse(gate.hasConnected)
        XCTAssertTrue(gate.markConnected())
        XCTAssertTrue(gate.hasConnected)
        XCTAssertFalse(gate.markConnected())
    }

    func testFirstSubscriptionUsesOtherSystemProxyBeforeFallingBackToDirect() {
        XCTAssertTrue(StartupNetworkPolicy.systemProxyConfigured(in: ["HTTPEnable": 1]))
        XCTAssertTrue(StartupNetworkPolicy.systemProxyConfigured(in: ["ProxyAutoConfigEnable": 1]))
        XCTAssertFalse(StartupNetworkPolicy.systemProxyConfigured(in: [:]))
        XCTAssertEqual(
            StartupNetworkPolicy.subscriptionRoutes(systemProxyConfigured: true),
            [.systemProxy, .direct]
        )
        XCTAssertEqual(
            StartupNetworkPolicy.subscriptionRoutes(systemProxyConfigured: false),
            [.systemProxy]
        )

        let directFallback = StartupNetworkPolicy.proxyDictionary(for: .direct)
        XCTAssertEqual(directFallback?["HTTPEnable"] as? Int, 0)
        XCTAssertEqual(directFallback?["HTTPSEnable"] as? Int, 0)
        XCTAssertEqual(directFallback?["SOCKSEnable"] as? Int, 0)
        XCTAssertNil(StartupNetworkPolicy.proxyDictionary(for: .systemProxy))
    }

    func testPostConnectionBackgroundRequestsUseReadyProxyOrTunDirectPath() {
        let proxy = StartupNetworkPolicy.postConnectionProxyDictionary(proxyPort: 7890)
        XCTAssertEqual(proxy["HTTPEnable"] as? Int, 1)
        XCTAssertEqual(proxy["HTTPPort"] as? Int, 7890)

        let tun = StartupNetworkPolicy.postConnectionProxyDictionary(proxyPort: nil)
        XCTAssertEqual(tun["HTTPEnable"] as? Int, 0)
        XCTAssertEqual(tun["HTTPSEnable"] as? Int, 0)
    }

    func testRulePageNeverDownloadsBeforeFirstConnection() {
        XCTAssertEqual(
            RuleSetRuntime.cachePreparationAction(hasLocalSRS: true, hasConnected: false),
            .decompileLocal
        )
        XCTAssertEqual(
            RuleSetRuntime.cachePreparationAction(hasLocalSRS: false, hasConnected: false),
            .waitForConnection
        )
        XCTAssertEqual(
            RuleSetRuntime.cachePreparationAction(hasLocalSRS: false, hasConnected: true),
            .download
        )
    }
}
