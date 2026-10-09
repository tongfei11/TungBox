import Foundation
import XCTest
@testable import TungBox

/// 只验证配置展示数据，不创建控制器，不读取本地规则集或执行系统操作。
final class ConfigInspectionTests: XCTestCase {
    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(ConfigCodec.parseObject(from: text))
    }
    private func rows(_ text: String, context: ConfigInspection.RuleContext = .init()) throws -> [RuleInfo] {
        ConfigInspection.ruleRows(in: try object(text), context: context)
    }
    private func records(_ rows: [RuleInfo]) -> [[String]] {
        rows.filter { !$0.isSection }.map { [$0.id, $0.type, $0.value, $0.strategy, $0.note, $0.count, $0.enabled ? "on" : "off"] }
    }
    private func customRule(_ type: String = "DOMAIN", value: String = "custom.test", strategy: String = "Proxy", enabled: Bool = true, note: String = "") -> CustomRule {
        .init(id: UUID(), subscriptionID: UUID(), type: type, value: value, strategy: strategy,
              note: note, enabled: enabled, createdAt: Date(timeIntervalSince1970: 0))
    }
    private func ruleSet(_ name: String, outbound: String = "DIRECT", enabled: Bool = true, rules: [RuleSetEntry] = []) -> CustomRuleSet {
        .init(id: UUID(), subscriptionID: UUID(), name: name, outbound: outbound, rules: rules,
              enabled: enabled, createdAt: Date(timeIntervalSince1970: 0))
    }

    func testNodesPreserveOrderFallbackTypesAndDisplayFields() {
        let text = #"""
        {"outbounds":[{"type":"DIRECT","tag":"hide"},{"type":"block"},{"type":"dns"},
          {"type":"selector"},{"type":"URLTEST"},{"type":"url-test"},
          {"type":"trojan","tag":"节点二","server":"host.test","server_port":443,"transport":{"type":"ws"},"network":"TCP","tls":{"enabled":true}},
          {"type":"HYSTERIA2","tag":"节点一","server":"2001:db8::1","server_port":"8443","network":"tcp"},
          {"type":"fallback","tag":"兼容分组"},{"server":123},{"type":"custom","tag":"","network":"udp"}]}
        """#
        let nodes = ConfigInspection.parseNodes(from: text)
        XCTAssertEqual(nodes.map(\.tag), ["节点二", "节点一", "兼容分组", "unknown", ""])
        XCTAssertEqual(nodes.map(\.type), ["trojan", "HYSTERIA2", "fallback", "unknown", "custom"])
        XCTAssertEqual(nodes.map(\.server), ["host.test:443", "2001:db8::1:8443", "", "123", ""])
        XCTAssertEqual(nodes.map(\.delay), Array(repeating: "未测试", count: 5))
        XCTAssertEqual(nodes.map(\.transport), ["ws", "", "", "", ""])
        XCTAssertEqual(nodes.map(\.supportsUDP), [false, true, true, true, true])
        XCTAssertEqual(nodes.map(\.tls), [true, false, false, false, false])
    }

    func testGroupsPreserveMembersDefaultsAndMissingTagPolicy() {
        let text = #"""
        {"outbounds":[{"type":"selector","tag":"manual","outbounds":["b","a","b"],"default":"missing"},
          {"type":"URL-TEST","tag":"auto","outbounds":["a","b"]},
          {"type":"fallback","tag":"fallback","outbounds":["direct"]},
          {"type":"urltest","tag":"empty"},{"type":"selector","outbounds":["a"]},
          {"type":"trojan","tag":"a"},{"type":"trojan","tag":"b"}]}
        """#
        let groups = ConfigInspection.parseNodeGroups(from: text)
        XCTAssertEqual(groups.map(\.tag), ["manual", "auto", "fallback", "empty"])
        XCTAssertEqual(groups.map(\.type), ["selector", "url-test", "fallback", "urltest"])
        XCTAssertEqual(groups.map(\.members), [["b", "a", "b"], ["a", "b"], ["direct"], []])
        XCTAssertEqual(groups.map(\.current), ["missing", "a", "direct", ""])
        let synthetic = ConfigInspection.parseNodeGroups(from: #"{"outbounds":[{"type":"trojan","tag":"b"},{"type":"vmess","tag":"a"}]}"#)
        XCTAssertEqual(synthetic.map(\.tag), ["节点选择"])
        XCTAssertEqual(synthetic.first?.members, ["b", "a"])
        XCTAssertEqual(synthetic.first?.current, "b")
        XCTAssertTrue(ConfigInspection.parseNodeGroups(from: #"{"outbounds":[{"type":"direct"}]}"#).isEmpty)
    }

    func testUnreadableAndMalformedContainersKeepEmptyOrSectionFallbacks() {
        for text in ["invalid", "[]", "null", "{}", #"{"outbounds":"bad"}"#, #"{"outbounds":[{} , 1]}"#] {
            XCTAssertTrue(ConfigInspection.parseNodes(from: text).isEmpty, text)
            XCTAssertTrue(ConfigInspection.parseNodeGroups(from: text).isEmpty, text)
        }
        let invalid = ConfigInspection.ruleRows(in: nil)
        XCTAssertEqual(invalid.count, 1)
        XCTAssertEqual(invalid[0].value, "# 当前配置不是可读取的 JSON")
        XCTAssertTrue(invalid[0].isSection)
        XCTAssertFalse(invalid[0].enabled)
        XCTAssertEqual(ConfigInspection.buildRulesSummary(from: "invalid"), "当前配置不是可读取的 JSON。")
    }

    func testSummaryPreservesExactModeGroupRouteAndDNSDescriptions() {
        let text = #"""
        {"experimental":{"clash_api":{"default_mode":"Global"}},
         "outbounds":[{"tag":"自动选择","type":"urltest","outbounds":["b","a"],"interval":"3m","tolerance":50,"idle_timeout":"10m","interrupt_exist_connections":true},
          {"tag":"节点选择","type":"selector","outbounds":["自动选择","b"],"default":"b"},
          {"type":"direct","tag":"direct"},{"type":"trojan","tag":"b","server":"host.test","server_port":443}],
         "route":{"rule_set":[{"tag":"geo","format":"binary","update_interval":"1d","download_detour":"direct"}],
           "rules":[{"action":"sniff"},{"protocol":"dns","action":"hijack-dns"},{"clash_mode":"direct","outbound":"direct"},
                    {"rule_set":["geo","other"],"outbound":"b"},{"ip_cidr":"10.0.0.0/8","outbound":"direct"}],"final":"b"},
         "dns":{"rules":[{"clash_mode":"Global","server":"remote"},{"rule_set":"geo","server":"local"}],"final":"remote"}}
        """#
        let expected = """
        当前模式
          全局

        节点分组
          自动选择
            类型: urltest
            节点数: 2
            检测间隔: 3m
            容差: 50 ms
            空闲超时: 10m
            断线切换: 开启
            成员: b, a
          节点选择
            默认: b
            可选: 自动选择, b
          直连: direct
          订阅节点: 1 个
            - b  [trojan] host.test:443

        规则集
          - geo  binary, 更新 1d, 下载出站 direct

        分流规则
          1. sniff
          2. dns -> hijack-dns
          3. 模式 直连 -> direct
          4. 规则集 geo, other -> b
          5. IP 段 10.0.0.0/8 -> direct
          final -> b

        DNS 规则
          1. 模式 全局 -> remote
          2. 规则集 geo -> local
          final -> remote
        """
        XCTAssertEqual(ConfigInspection.buildRulesSummary(from: text), expected)
        XCTAssertEqual(ConfigInspection.modeDisplayName("unknown"), "规则")
        XCTAssertEqual(ConfigInspection.modeDisplayName("DIRECT"), "直连")
    }

    func testEmptyConfigSectionsAndDNSFinalWithoutRulesRemainUnchanged() throws {
        let empty = try rows(#"{"dns":{"final":"local"}}"#)
        XCTAssertEqual(empty.filter(\.isSection).map(\.value), ["# 自定义规则", "# 当前配置规则"])
        XCTAssertEqual(records(empty), [["1", "CUSTOM", "当前订阅还没有自定义规则", "未设置", "通过上方输入框添加", "0", "off"]])
        let summary = ConfigInspection.buildRulesSummary(from: "{}")
        XCTAssertTrue(summary.contains("未找到 自动选择 urltest 分组"))
        XCTAssertTrue(summary.contains("当前配置没有 route.rules"))
        XCTAssertTrue(summary.contains("当前配置没有 dns.rules"))
        XCTAssertTrue(summary.hasSuffix("  final -> 未设置"))
    }

    func testCustomRulesKeepIdentityDisabledStateAndHideExactGeneratedDuplicates() throws {
        let custom = customRule(enabled: false)
        let set = ruleSet("分流方案", rules: [.init(type: "DOMAIN-SUFFIX", value: "set.test")])
        let generated = RuleRouting.customRouteRule(type: custom.type, value: custom.value, strategy: custom.strategy)
        let generatedSet = RuleRouting.customRouteRule(type: "DOMAIN-SUFFIX", value: "set.test", strategy: "DIRECT")
        var extra = generated
        extra["future"] = true
        let context = ConfigInspection.RuleContext(customRules: [custom], ruleSets: [.init(ruleSet: set, referenceError: nil)], ruleSetApplyStatus: "已应用")
        let rows = ConfigInspection.ruleRows(in: ["outbounds": [["tag": TungBoxConfig.tagManual]], "route": ["rules": [generated, generatedSet, extra]]], context: context)
        let actual = rows.filter { !$0.isSection }
        XCTAssertEqual(actual.count, 3)
        XCTAssertEqual(actual[0].customRuleID, custom.id)
        XCTAssertFalse(actual[0].enabled)
        XCTAssertEqual(actual[0].strategy, "Proxy")
        XCTAssertEqual(actual[0].note, "自定义规则")
        XCTAssertEqual(actual[1].ruleSetID, set.id)
        XCTAssertEqual(actual[2].type, "ACTION")
        XCTAssertEqual(actual[2].strategy, "ROUTE")
        XCTAssertEqual(actual.map(\.id), ["1", "2", "3"])
    }

    func testMissingNodePreservesEnablePreferenceAndReportsCustomRuleError() throws {
        let config: [String: Any] = ["outbounds": [["tag": "新节点", "type": "trojan"]]]
        let custom = customRule(strategy: "旧节点")
        let set = ruleSet("节点已改名", outbound: "旧节点")
        let error = try XCTUnwrap(RuleRouting.referenceError(type: "LAN", value: "", strategy: set.outbound, config: config))
        let context = ConfigInspection.RuleContext(customRules: [custom], ruleSets: [.init(ruleSet: set, referenceError: error)])
        let rows = ConfigInspection.ruleRows(in: config, context: context)
        let customRow = try XCTUnwrap(rows.first { $0.customRuleID == custom.id })
        let setRow = try XCTUnwrap(rows.first { $0.ruleSetID == set.id })
        XCTAssertEqual(customRow.note, error)
        XCTAssertTrue(customRow.enabled)
        XCTAssertTrue(setRow.enabled, "引用失效不能伪装成用户已停用")
        for row in [customRow, setRow] {
            XCTAssertEqual(row.referenceError, error)
            XCTAssertEqual(row.strategyReferenceError, error)
            XCTAssertEqual(row.strategy, "旧节点")
        }

        let restoredConfig: [String: Any] = ["outbounds": [["tag": "旧节点", "type": "trojan"]]]
        let restored = ConfigInspection.ruleRows(in: restoredConfig, context: .init(
            customRules: [custom], ruleSets: [.init(ruleSet: set, referenceError: nil)]))
        for row in restored.filter({ $0.customRuleID != nil || $0.ruleSetID != nil }) {
            XCTAssertTrue(row.enabled)
            XCTAssertNil(row.referenceError)
            XCTAssertNil(row.strategyReferenceError)
        }
    }

    func testMissingReferencesWarnForDisabledRulesWithoutChangingPreference() {
        let custom = customRule(strategy: "已删除节点", enabled: false)
        let set = ruleSet("已停用规则集", outbound: "已删除节点", enabled: false)
        let rows = ConfigInspection.ruleRows(in: [:], context: .init(
            customRules: [custom], ruleSets: [.init(ruleSet: set, referenceError: nil)]))
        for row in rows.filter({ $0.customRuleID != nil || $0.ruleSetID != nil }) {
            XCTAssertFalse(row.enabled)
            XCTAssertNotNil(row.referenceError)
            XCTAssertNotNil(row.strategyReferenceError)
        }
    }

    func testMissingRuleSetReferenceDoesNotMarkValidOutboundAsInvalid() {
        let custom = customRule("RULE-SET", value: "removed", strategy: "有效节点")
        let config: [String: Any] = ["outbounds": [["tag": "有效节点"]]]
        let error = RuleRouting.referenceError(type: custom.type, value: custom.value, strategy: custom.strategy, config: config)
        let set = ruleSet("丢失规则集引用", outbound: custom.strategy)
        let rows = ConfigInspection.ruleRows(in: config, context: .init(
            customRules: [custom], ruleSets: [.init(ruleSet: set, referenceError: error)]))
        for row in rows.filter({ $0.customRuleID != nil || $0.ruleSetID != nil }) {
            XCTAssertTrue(row.enabled)
            XCTAssertEqual(row.referenceError, "规则集引用不存在：removed")
            XCTAssertNil(row.strategyReferenceError)
        }
    }

    func testBuiltInStrategiesValidateMappedOutboundTags() {
        let config: [String: Any] = ["outbounds": [["tag": TungBoxConfig.tagManual], ["tag": TungBoxConfig.tagAuto]]]
        for strategy in ["DIRECT", "REJECT", "AUTO", "Proxy"] {
            let custom = customRule(strategy: strategy)
            let rows = ConfigInspection.ruleRows(in: config, context: .init(customRules: [custom]))
            let row = rows.first { $0.customRuleID == custom.id }
            XCTAssertNotNil(row)
            XCTAssertNil(row?.referenceError)
            XCTAssertNil(row?.strategyReferenceError)
        }
    }

    func testRuleSetStatusesPreservePerOccurrenceErrorsAndInvalidFileIdentity() throws {
        let sharedID = UUID()
        var good = ruleSet("正常")
        var failed = ruleSet("错误")
        good.id = sharedID; failed.id = sharedID
        let disabled = ruleSet("停用", enabled: false)
        let invalid = InvalidRuleSet(fileURL: URL(fileURLWithPath: "/fixture/invalid.yaml"), name: "损坏", reason: "格式错误")
        let context = ConfigInspection.RuleContext(
            ruleSets: [.init(ruleSet: good, referenceError: nil), .init(ruleSet: failed, referenceError: "出站不存在"),
                       .init(ruleSet: disabled, referenceError: nil)],
            invalidRuleSets: [invalid], ruleSetApplyStatus: "正在应用")
        let rows = ConfigInspection.ruleRows(in: [:], context: context)
        let sets = rows.filter { $0.type == "规则集" }
        XCTAssertEqual(sets.map(\.value), ["正常", "错误", "停用", "损坏"])
        XCTAssertEqual(sets.map(\.enabled), [true, true, false, false])
        XCTAssertEqual(sets.map(\.referenceError), [nil, "出站不存在", nil, nil])
        XCTAssertEqual(sets.map(\.note), ["正在应用", "出站不存在", "已停用", "⚠️ 格式错误"])
        XCTAssertEqual(sets.map(\.count), ["0 条", "0 条", "0 条", "!"])
        XCTAssertEqual(sets[0].ruleSetID, sharedID)
        XCTAssertEqual(sets[1].ruleSetID, sharedID)
        XCTAssertEqual(sets[3].ruleSetInvalidURL, invalid.fileURL)
    }

    func testRouteRowsExpandInOriginalFieldOrderAndActionTakesPriority() throws {
        let rows = try rows(#"""
        {"route":{"rules":[{"action":"resolve","protocol":"dns","domain":"ignored.test"},
          {"outbound":"direct","clash_mode":"Global","ip_cidr":["10.0.0.0/8","::1/128"],"ip_is_private":true,
           "domain":["b.test","a.test"],"domain_suffix":"suffix.test","domain_keyword":"key","domain_regex":"^x$",
           "source_ip_cidr":"192.0.2.0/24","process_name":"app","process_path":"/app","port":[80,443],"network":"tcp"}],"final":"block"}}
        """#)
        let actual = rows.filter { !$0.isSection }
        XCTAssertEqual(actual.map(\.type), ["CUSTOM", "ACTION", "MODE", "IP-CIDR", "LAN", "DOMAIN", "DOMAIN", "DOMAIN-SUFFIX",
                                           "DOMAIN-KEYWORD", "DOMAIN-REGEX", "SRC-IP", "PROCESS-NAME", "PROCESS-PATH", "DEST-PORT", "NETWORK", "FINAL"])
        XCTAssertEqual(actual.map(\.id), (1...16).map(String.init))
        XCTAssertEqual(actual[1].value, "dns")
        XCTAssertEqual(actual[1].strategy, "RESOLVE")
        XCTAssertEqual(actual[2].value, "全局")
        XCTAssertEqual(actual[3].value, "10.0.0.0/8, ::1/128")
        XCTAssertEqual(actual[5].value, "b.test")
        XCTAssertEqual(actual[6].value, "a.test")
        XCTAssertEqual(actual[13].value, "[80,443]")
        XCTAssertEqual(actual.last?.strategy, "REJECT")
    }

    func testCachedRuleSetRowsKeepRepeatedExpansionsDownloadTextAndDNSPrefix() throws {
        let context = ConfigInspection.RuleContext(cachedRuleSetEntries: ["cached": [.init(type: "DOMAIN", value: "a.test"), .init(type: "IP-CIDR", value: "192.0.2.0/24")]], downloadingRuleSets: ["loading"])
        let rows = try rows(#"""
        {"route":{"rules":[{"rule_set":["cached","cached","loading","missing"],"outbound":"自动选择"}]},
         "dns":{"rules":[{"rule_set":"cached","clash_mode":"Direct","server":"local"}],"final":"remote"}}
        """#, context: context)
        XCTAssertEqual(rows.filter(\.isSection).map(\.value), ["# 自定义规则", "# 当前配置规则", "# 规则集内容：cached", "# 规则集内容：cached", "# DNS 规则", "# DNS内容：cached"])
        let actual = rows.filter { !$0.isSection }
        XCTAssertEqual(actual.map(\.id), (1...11).map(String.init))
        XCTAssertEqual(actual[1].strategy, "AUTO")
        XCTAssertEqual(actual[5].value, "loading")
        XCTAssertEqual(actual[5].note, "下载中")
        XCTAssertEqual(actual[6].note, "等待下载")
        XCTAssertEqual(actual[7].type, "DNS-MODE")
        XCTAssertEqual(actual[8].strategy, "local")
        XCTAssertEqual(actual[8].note, "cached")
        XCTAssertEqual(actual.last?.type, "DNS-FINAL")
        XCTAssertEqual(actual.last?.strategy, "remote")
    }

    func testRuleSetJSONDecodingKeepsSupportedKeyAndValueOrder() {
        let text = #"""
        {"rules":[{"domain":["b.test","a.test"],"domain_suffix":"suffix.test","domain_keyword":"key","domain_regex":"^x$",
          "ip_cidr":["192.0.2.0/24","2001:db8::/32"],"source_ip_cidr":"10.0.0.0/8","process_name":"app","process_path":"ignored","port":443},
          {"domain":7,"process_name":["second","third"]}]}
        """#
        let entries = ConfigInspection.ruleSetEntries(from: Data(text.utf8))
        XCTAssertEqual(entries.map(\.type), ["DOMAIN", "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX", "IP-CIDR", "IP-CIDR", "SRC-IP", "PROCESS-NAME", "PROCESS-NAME", "PROCESS-NAME"])
        XCTAssertEqual(entries.map(\.value), ["b.test", "a.test", "suffix.test", "key", "^x$", "192.0.2.0/24", "2001:db8::/32", "10.0.0.0/8", "app", "second", "third"])
        for text in ["invalid", "[]", "{}", #"{"rules":"bad"}"#, #"{"rules":[1]}"#] {
            XCTAssertTrue(ConfigInspection.ruleSetEntries(from: Data(text.utf8)).isEmpty)
        }
    }

    func testReferencedCacheTagsSkipRouteActionsAndDeduplicateOnlySnapshotReads() throws {
        let config = try object(#"""
        {"route":{"rules":[{"action":"route","rule_set":"hidden"},{"rule_set":["b","a","b"]},{"rule_set":3},{"rule_set":"c"}]},
         "dns":{"rules":[{"action":"route","rule_set":["a","dns"]},{"rule_set":"b"}]}}
        """#)
        XCTAssertEqual(ConfigInspection.referencedRuleSetTags(in: config), ["b", "a", "c", "dns"])
    }
}
