import Foundation
import XCTest
@testable import TungBox

final class ConfigTransformationTests: XCTestCase {
    func testCodecPreservesUnknownFieldsAndOrderedValues() throws {
        let source = #"""
        {
          "outbounds": [
            {"tag": "节点二", "type": "custom", "future_option": true},
            {"tag": "节点一", "type": "direct"}
          ],
          "future_section": {
            "label": "中文 😀",
            "values": [null, false, 9223372036854775807, 1.25],
            "url": "https://example.com/a/b?q=测试"
          }
        }
        """#
        let config = try XCTUnwrap(ConfigCodec.parseObject(from: source))
        let rendered = try ConfigCodec.render(config)
        let reparsed = try XCTUnwrap(ConfigCodec.parseObject(from: rendered))

        XCTAssertTrue(NSDictionary(dictionary: config).isEqual(to: reparsed))
        let outbounds = try XCTUnwrap(reparsed["outbounds"] as? [[String: Any]])
        XCTAssertEqual(outbounds.compactMap { $0["tag"] as? String }, ["节点二", "节点一"])
        XCTAssertEqual(outbounds[0]["future_option"] as? Bool, true)
        let section = try XCTUnwrap(reparsed["future_section"] as? [String: Any])
        XCTAssertEqual(section["label"] as? String, "中文 😀")
        let values = try XCTUnwrap(section["values"] as? [Any])
        XCTAssertTrue(values[0] is NSNull)
        XCTAssertEqual((values[2] as? NSNumber)?.int64Value, Int64.max)
    }

    func testCodecRejectsMalformedAndNonObjectJSON() {
        for source in ["", "{", #"{"route":}"#, "[]", "[{}]", "null", "true", "42", #""text""#] {
            XCTAssertNil(ConfigCodec.parseObject(from: source), "应拒绝：\(source)")
        }
        XCTAssertNotNil(ConfigCodec.parseObject(from: "{}"))
        XCTAssertNotNil(ConfigCodec.parseObject(from: " \n {\"route\": {}} \t"))
    }

    func testCodecRetainsPrettyPrintedSortedOutput() throws {
        let config: [String: Any] = ["z": [3, 1, 2], "a": ["y": true, "b": "value"]]
        let expected = """
        {
          "a" : {
            "b" : "value",
            "y" : true
          },
          "z" : [
            3,
            1,
            2
          ]
        }
        """

        XCTAssertEqual(try ConfigCodec.render(config), expected)
        XCTAssertEqual(try ConfigCodec.render([:]), "{\n\n}")
    }

    func testCodecRepeatedRoundTripsDoNotChangeOutput() throws {
        var text = #"{"route":{"rules":[{"outbound":"b"},{"outbound":"a"}]},"unknown":{"enabled":false}}"#
        text = try ConfigCodec.render(XCTUnwrap(ConfigCodec.parseObject(from: text)))
        let firstRender = text

        for _ in 0..<3 {
            text = try ConfigCodec.render(XCTUnwrap(ConfigCodec.parseObject(from: text)))
            XCTAssertEqual(text, firstRender)
        }
    }

    func testModeConversionsPreserveCustomRulesAndUnknownFields() throws {
        let source = try XCTUnwrap(ConfigCodec.parseObject(from: #"""
        {
          "unknown": {"keep": [2, 1]},
          "experimental": {"future": true, "clash_api": {
            "secret": "must-remove", "external_controller": "127.0.0.1:9091", "future": 7
          }},
          "outbounds": [
            {"type": "selector", "tag": "节点选择", "outbounds": ["node"]},
            {"type": "trojan", "tag": "node", "server": "example.com"},
            {"type": "direct", "tag": "direct", "future": true}
          ],
          "route": {"final": "节点选择", "future": "keep", "rules": [
            {"action": "SNIFF", "future": 1},
            {"protocol": "DNS", "action": "HIJACK-DNS"},
            {"clash_mode": "Direct", "outbound": "old"},
            {"clash_mode": "GLOBAL", "outbound": "old"},
            {"action": "resolve", "server": "local"},
            {"domain": ["example.com"], "outbound": "node", "future": true},
            {"protocol": "tcp", "action": "hijack-dns"},
            {"clash_mode": "Rule", "outbound": "节点选择"}
          ]}
        }
        """#))
        let expectedRules = try XCTUnwrap(ConfigCodec.parseObject(from: #"""
        {"rules": [
          {"action": "sniff"},
          {"protocol": "dns", "action": "hijack-dns"},
          {"clash_mode": "direct", "outbound": "direct"},
          {"clash_mode": "global", "outbound": "全局"},
          {"action": "resolve", "server": "local"},
          {"domain": ["example.com"], "outbound": "node", "future": true},
          {"protocol": "tcp", "action": "hijack-dns"},
          {"clash_mode": "Rule", "outbound": "节点选择"}
        ]}
        """#))

        for mode in ["Direct", "Global", "Rule"] {
            let result = ProxyModeConfig.ensureModeSupport(in: source, mode: mode, fallbackProxyTag: "unused")
            XCTAssertEqual(ProxyModeConfig.readMode(from: result), mode)
            let experimental = try XCTUnwrap(result["experimental"] as? [String: Any])
            let api = try XCTUnwrap(experimental["clash_api"] as? [String: Any])
            XCTAssertNil(api["secret"])
            XCTAssertEqual(api["external_controller"] as? String, "127.0.0.1:9091")
            XCTAssertEqual(api["future"] as? Int, 7)
            XCTAssertEqual(experimental["future"] as? Bool, true)
            let route = try XCTUnwrap(result["route"] as? [String: Any])
            let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
            XCTAssertTrue(NSDictionary(dictionary: ["rules": rules]).isEqual(to: expectedRules))
            XCTAssertEqual(route["final"] as? String, "节点选择")
            XCTAssertEqual(route["future"] as? String, "keep")
            let unknown = try XCTUnwrap(result["unknown"] as? [String: Any])
            XCTAssertTrue(NSDictionary(dictionary: unknown).isEqual(to: ["keep": [2, 1]]))
            let outbounds = try XCTUnwrap(result["outbounds"] as? [[String: Any]])
            XCTAssertEqual(outbounds.compactMap { $0["tag"] as? String }, ["节点选择", "node", "direct", "全局"])
            XCTAssertEqual(outbounds[2]["future"] as? Bool, true)
        }
    }

    func testRepeatedModeSwitchesDoNotAccumulateRulesOrSelectors() throws {
        let source: [String: Any] = ["outbounds": [["type": "trojan", "tag": "node"]]]
        var result = source
        for mode in ["Direct", "Global", "Rule", "Global", "Direct", "Rule"] {
            result = ProxyModeConfig.ensureModeSupport(in: result, mode: mode, fallbackProxyTag: "direct")
            let expected = ProxyModeConfig.ensureModeSupport(in: source, mode: mode, fallbackProxyTag: "direct")
            XCTAssertEqual(try ConfigCodec.render(result), try ConfigCodec.render(expected))
        }
    }

    func testGlobalSelectorRefreshPreservesManualPickAndGroupOrder() throws {
        let outbounds: [[String: Any]] = [
            ["type": "selector", "tag": "节点选择"],
            ["type": "url-test", "tag": "自动选择"],
            ["type": "selector", "tag": "全局", "outbounds": ["old"], "default": "b", "future": true],
            ["type": "trojan", "tag": "a"],
            ["type": "vmess", "tag": "b"],
            ["type": "fallback", "tag": "fallback-group"],
            ["type": "DNS", "tag": "dns-out"],
            ["type": "block", "tag": "block"]
        ]
        let result = ProxyModeConfig.ensureModeSupport(in: ["outbounds": outbounds], mode: "Global", fallbackProxyTag: "direct")
        let updated = try XCTUnwrap(result["outbounds"] as? [[String: Any]])
        XCTAssertEqual(updated.compactMap { $0["tag"] as? String }, outbounds.compactMap { $0["tag"] as? String } + ["direct"])
        XCTAssertEqual(updated[2]["outbounds"] as? [String], ["自动选择", "a", "b"])
        XCTAssertEqual(updated[2]["default"] as? String, "b")
        XCTAssertEqual(updated[2]["future"] as? Bool, true)

        let refreshed = ProxyModeConfig.ensureModeSupport(in: ["outbounds": outbounds.filter { $0["tag"] as? String != "b" }], mode: "Global", fallbackProxyTag: "direct")
        let refreshedOutbounds = try XCTUnwrap(refreshed["outbounds"] as? [[String: Any]])
        XCTAssertEqual(refreshedOutbounds[2]["default"] as? String, "自动选择")
    }

    func testGlobalSelectorDefaultsWithoutAutoAndDoesNotInventNodes() throws {
        let result = ProxyModeConfig.ensureModeSupport(in: ["outbounds": [["type": "trojan", "tag": "b"], ["type": "vmess", "tag": "a"]]], mode: "Global", fallbackProxyTag: "unused")
        let outbounds = try XCTUnwrap(result["outbounds"] as? [[String: Any]])
        let global = try XCTUnwrap(outbounds.first { $0["tag"] as? String == "全局" })
        XCTAssertEqual(global["outbounds"] as? [String], ["b", "a"])
        XCTAssertEqual(global["default"] as? String, "b")

        let empty = ProxyModeConfig.ensureModeSupport(in: [:], mode: "Global", fallbackProxyTag: "snapshot-node")
        let emptyOutbounds = try XCTUnwrap(empty["outbounds"] as? [[String: Any]])
        XCTAssertEqual(emptyOutbounds.count, 1)
        XCTAssertEqual(emptyOutbounds[0]["tag"] as? String, "direct")
        let rules = try XCTUnwrap((empty["route"] as? [String: Any])?["rules"] as? [[String: Any]])
        XCTAssertEqual(rules[3]["outbound"] as? String, "snapshot-node")
        XCTAssertEqual(((empty["experimental"] as? [String: Any])?["clash_api"] as? [String: Any])?["external_controller"] as? String, "127.0.0.1:9090")
    }

    func testPreferredProxyTagRetainsSelectorURLTestAndSnapshotPriority() {
        let outbounds: [[String: Any]] = [
            ["type": "url-test", "tag": "auto"],
            ["type": "SELECTOR", "tag": "manual"],
            ["type": "selector", "tag": "second"]
        ]
        XCTAssertEqual(ProxyModeConfig.preferredProxyTag(from: outbounds, fallback: "snapshot"), "manual")
        XCTAssertEqual(ProxyModeConfig.preferredProxyTag(from: [outbounds[0]], fallback: "snapshot"), "auto")
        XCTAssertEqual(ProxyModeConfig.preferredProxyTag(from: [], fallback: "snapshot"), "snapshot")
        // 原实现只检查首个 selector；无 tag 时继续尝试 URLTest。
        XCTAssertEqual(ProxyModeConfig.preferredProxyTag(from: [["type": "selector"]] + outbounds, fallback: "snapshot"), "auto")
    }

    func testModeReadKeepsOriginalValueAndDefaultPolicy() {
        XCTAssertEqual(ProxyModeConfig.readMode(from: [:]), "Rule")
        for value: Any in ["", 1, NSNull()] {
            XCTAssertEqual(ProxyModeConfig.readMode(from: ["experimental": ["clash_api": ["default_mode": value]]]), "Rule")
        }
        for value in ["direct", "Global", "Rule", "unknown", " "] {
            XCTAssertEqual(ProxyModeConfig.readMode(from: ["experimental": ["clash_api": ["default_mode": value]]]), value)
        }
    }

    func testLoadRepairOnlyReplacesDanglingResolvers() throws {
        for resolver: Any in ["gone", ["server": "gone", "strategy": "prefer_ipv4"]] {
            let config: [String: Any] = ["dns": ["servers": [["tag": "first"], ["tag": "second"]]], "route": ["default_domain_resolver": resolver, "future": true]]
            let repairedText = try XCTUnwrap(ProxyModeConfig.repairDefaultDomainResolver(inConfigText: ConfigCodec.render(config)))
            let repaired = try XCTUnwrap(ConfigCodec.parseObject(from: repairedText))
            let route = try XCTUnwrap(repaired["route"] as? [String: Any])
            XCTAssertEqual(route["default_domain_resolver"] as? String, "first")
            XCTAssertEqual(route["future"] as? Bool, true)
            XCTAssertNil(ProxyModeConfig.repairDefaultDomainResolver(inConfigText: repairedText))
        }
        for source in [
            "invalid",
            #"{"dns":{"servers":[{"tag":"first"}]},"route":{}}"#,
            #"{"dns":{"servers":[]},"route":{"default_domain_resolver":"gone"}}"#,
            #"{"dns":{"servers":[{}, {"tag":"second"}]},"route":{"default_domain_resolver":"gone"}}"#,
            #"{"dns":{"servers":[{"tag":"first"}]},"route":{"default_domain_resolver":{"server":"first","strategy":"ipv4_only"}}}"#
        ] {
            XCTAssertNil(ProxyModeConfig.repairDefaultDomainResolver(inConfigText: source))
        }
    }

    func testModeConversionFillsMissingResolverAndPreservesValidObject() throws {
        let dns: [String: Any] = ["servers": [["tag": "first"], ["tag": "second"]]]
        for route: [String: Any] in [[:], ["default_domain_resolver": "gone"], ["default_domain_resolver": ["server": "gone"]]] {
            let result = ProxyModeConfig.ensureModeSupport(in: ["dns": dns, "route": route], mode: "Rule", fallbackProxyTag: "direct")
            XCTAssertEqual((result["route"] as? [String: Any])?["default_domain_resolver"] as? String, "first")
        }
        let resolver: [String: Any] = ["server": "second", "strategy": "prefer_ipv4", "future": true]
        let result = ProxyModeConfig.ensureModeSupport(in: ["dns": dns, "route": ["default_domain_resolver": resolver]], mode: "Rule", fallbackProxyTag: "direct")
        let actual = try XCTUnwrap((result["route"] as? [String: Any])?["default_domain_resolver"] as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: actual).isEqual(to: resolver))
    }
}
