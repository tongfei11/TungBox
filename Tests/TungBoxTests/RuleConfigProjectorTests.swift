import Foundation
import XCTest
@testable import TungBox

final class RuleConfigProjectorTests: XCTestCase {
    private let subscriptionID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let otherID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!

    func testProjectionKeepsStableCustomOrderThenSetOrderThenSubscriptionBase() throws {
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let custom = [rule("tie-b.invalid", id: b, time: 2), rule("foreign.invalid", subscription: otherID),
                      rule("disabled.invalid", enabled: false), rule("tie-a.invalid", id: a, time: 2),
                      rule("earlier.invalid", time: 1)]
        let sets = [set("second.invalid"), set("disabled-set.invalid", enabled: false),
                    set("foreign-set.invalid", subscription: otherID), set("first.invalid")]
        let result = try project(custom, sets: sets)
        XCTAssertEqual(domains(result.routeRules), ["earlier.invalid", "tie-a.invalid", "tie-b.invalid",
                                                   "second.invalid", "first.invalid", "base.invalid"])
        XCTAssertEqual(result.routeRules.prefix(2).compactMap { $0["action"] as? String }, ["sniff", "hijack-dns"])
        XCTAssertTrue(NSArray(array: result.routeRules).isEqual(to: (result.config["route"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []))
    }

    func testProjectionSkipsMissingNodeAndWholeSetWithMissingDependency() throws {
        let missingNode = rule("old-node.invalid", strategy: "renamed-node")
        let missingSet = set("valid-member.invalid", entries: [
            RuleSetEntry(type: "DOMAIN", value: "valid-member.invalid"),
            RuleSetEntry(type: "RULE-SET", value: "missing-set")
        ])
        let result = try project([missingNode, rule("valid.invalid")], sets: [missingSet, set("old-set-node.invalid", strategy: "renamed-node")])
        XCTAssertEqual(domains(result.routeRules), ["valid.invalid", "base.invalid"])
        XCTAssertTrue(missingNode.enabled)
        XCTAssertTrue(missingSet.enabled, "失效引用只从投影排除，不改变用户保存的启用偏好")
        XCTAssertNotNil(RuleRouting.enableError(for: missingNode, config: config()))
        XCTAssertNotNil(RuleRouting.enableError(for: missingSet, config: config()))
    }

    func testDisableEditAndDeletePreserveIdenticalIndependentBaseRule() throws {
        let identical = RuleRouting.customRouteRule(type: "DOMAIN", value: "duplicate.invalid", strategy: "DIRECT")
        let baseline = [identical]
        var custom = rule("duplicate.invalid")
        let enabled = try project([custom], base: baseline)
        XCTAssertEqual(domains(enabled.routeRules), ["duplicate.invalid", "duplicate.invalid"])
        custom.enabled = false
        XCTAssertEqual(domains(try project([custom], base: baseline).routeRules), ["duplicate.invalid"])
        custom.enabled = true
        custom.value = "edited.invalid"
        custom.strategy = "test-node"
        let edited = try project([custom], base: baseline)
        XCTAssertEqual(domains(edited.routeRules), ["edited.invalid", "duplicate.invalid"])
        XCTAssertEqual(edited.routeRules.first { $0["domain"] as? String == "edited.invalid" }?["outbound"] as? String, "test-node")
        XCTAssertEqual(domains(try project([], base: baseline).routeRules), ["duplicate.invalid"])
    }

    func testReprojectionIsIdempotentAndPreservesModeUnknownFieldsAndDNS() throws {
        let input = config(mode: "Global")
        let custom = [rule("custom.invalid", strategy: "AUTO")]
        let first = try project(custom, configuration: input)
        let second = try project(custom, configuration: first.config)
        XCTAssertEqual(try ConfigCodec.render(first.config), try ConfigCodec.render(second.config))
        XCTAssertEqual(ProxyModeConfig.readMode(from: second.config), "Global")
        XCTAssertEqual(second.routeRules.first { $0["clash_mode"] as? String == "global" }?["outbound"] as? String, TungBoxConfig.tagGlobal)
        XCTAssertEqual((second.config["route"] as? [String: Any])?["final"] as? String, TungBoxConfig.tagManual)
        XCTAssertTrue(NSDictionary(dictionary: second.config["dns"] as? [String: Any] ?? [:]).isEqual(to: input["dns"] as? [String: Any] ?? [:]))
        XCTAssertTrue(NSDictionary(dictionary: second.config["vendor"] as? [String: Any] ?? [:]).isEqual(to: input["vendor"] as? [String: Any] ?? [:]))
        XCTAssertEqual((second.config["route"] as? [String: Any])?["vendor_route"] as? Bool, true)
    }

    func testRejectActionDoesNotCreateBlockOutboundAndInvalidValueStillThrows() throws {
        let result = try project([rule("rejected.invalid", strategy: "REJECT")])
        let rejected = try XCTUnwrap(result.routeRules.first { $0["domain"] as? String == "rejected.invalid" })
        XCTAssertEqual(rejected["action"] as? String, "reject")
        XCTAssertNil(rejected["outbound"])
        XCTAssertFalse((result.config["outbounds"] as? [[String: Any]] ?? []).contains { $0["tag"] as? String == TungBoxConfig.tagBlock })
        var invalid = rule("sctp")
        invalid.type = "NETWORK"
        XCTAssertThrowsError(try project([invalid])) { error in
            XCTAssertTrue(error is RuleSetFormat.FormatError)
        }
    }

    func testLegacyMigrationRemovesOnlyExactKnownSetProjections() throws {
        let known = set("known.invalid", enabled: false)
        let generated = RuleRouting.customRouteRule(type: "DOMAIN", value: "known.invalid", strategy: "DIRECT")
        var decorated = generated
        decorated["vendor_rule"] = "preserve"
        var original = config()
        var route = original["route"] as! [String: Any]
        let retained: [[String: Any]] = [["action": "sniff"], decorated, ["domain": "manual.invalid", "outbound": "direct"]]
        route["rules"] = [retained[0], generated, retained[1], retained[2]]
        original["route"] = route
        let migrated = RuleConfigProjector.legacyBase(in: original, ruleSets: [known])
        XCTAssertTrue(NSArray(array: (migrated["route"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []).isEqual(to: retained))
        XCTAssertTrue(NSDictionary(dictionary: migrated["vendor"] as? [String: Any] ?? [:]).isEqual(to: original["vendor"] as? [String: Any] ?? [:]))
        XCTAssertEqual(try ConfigCodec.render(RuleConfigProjector.legacyBase(in: migrated, ruleSets: [known])), try ConfigCodec.render(migrated))
    }

    func testProjectionUsesIsolatedStoreSnapshotsAndKeepsSavedBaseAndManualEditGuard() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tungbox-projector-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(baseURL: directory)
        let input = config()
        try store.saveRuleBase(ConfigCodec.render(input), for: subscriptionID)
        try store.saveRuleBase(ConfigCodec.render(config()), for: otherID)
        store.saveCustomRules([rule("mine.invalid"), rule("foreign.invalid", subscription: otherID)])
        try store.saveRuleSet(set("mine-set.invalid"))
        try store.saveRuleSet(set("foreign-set.invalid", subscription: otherID))
        let savedBase = try Data(contentsOf: store.ruleBaseURL(for: subscriptionID))
        let result = try RuleConfigProjector.project(config: input, subscriptionID: subscriptionID,
                                                    base: store.baseRouteRules(for: subscriptionID),
                                                    customRules: store.loadCustomRules(),
                                                    ruleSets: store.loadRuleSets(for: subscriptionID).valid,
                                                    fallbackProxyTag: "test-node")
        XCTAssertEqual(domains(result.routeRules), ["mine.invalid", "mine-set.invalid", "base.invalid"])
        XCTAssertEqual(try Data(contentsOf: store.ruleBaseURL(for: subscriptionID)), savedBase)
        try store.saveRuleProjection(ConfigCodec.render(result.config), for: subscriptionID)
        try store.verifyRuleProjection(result.routeRules, for: subscriptionID)
        XCTAssertThrowsError(try store.verifyRuleProjection(result.routeRules + [["domain": "manual.invalid"]], for: subscriptionID))
        XCTAssertEqual(store.loadCustomRules().count, 2)
        XCTAssertEqual(store.loadRuleSets(for: otherID).valid.first?.name, "foreign-set.invalid")
    }

    private func config(mode: String = "Rule") -> [String: Any] {
        ["outbounds": [["type": "selector", "tag": TungBoxConfig.tagManual, "outbounds": [TungBoxConfig.tagAuto, "test-node"]],
                       ["type": "urltest", "tag": TungBoxConfig.tagAuto, "outbounds": ["test-node"]],
                       ["type": "trojan", "tag": "test-node", "server": "node.invalid"], ["type": "direct", "tag": "direct"]],
         "experimental": ["clash_api": ["default_mode": mode]],
         "route": ["final": TungBoxConfig.tagManual, "rules": [["domain": "base.invalid", "outbound": "direct"]], "vendor_route": true],
         "dns": ["servers": [["type": "udp", "tag": "dns", "server": "192.0.2.1"]]],
         "vendor": ["preserve": ["opaque", "fields"]]]
    }

    private func project(_ rules: [CustomRule], sets: [CustomRuleSet] = [], base: [[String: Any]]? = nil,
                         configuration: [String: Any]? = nil) throws -> RuleConfigProjector.Projection {
        try RuleConfigProjector.project(config: configuration ?? config(), subscriptionID: subscriptionID,
                                       base: base ?? [["domain": "base.invalid", "outbound": "direct"]],
                                       customRules: rules, ruleSets: sets, fallbackProxyTag: "test-node")
    }

    private func domains(_ rules: [[String: Any]]) -> [String] { rules.compactMap { $0["domain"] as? String } }

    private func rule(_ value: String, strategy: String = "DIRECT", subscription: UUID? = nil,
                      enabled: Bool = true, id: UUID = UUID(), time: TimeInterval = 0) -> CustomRule {
        CustomRule(id: id, subscriptionID: subscription ?? subscriptionID, type: "DOMAIN", value: value,
                   strategy: strategy, note: "fixture", enabled: enabled, createdAt: Date(timeIntervalSince1970: time))
    }

    private func set(_ name: String, strategy: String = "DIRECT", subscription: UUID? = nil,
                     enabled: Bool = true, entries: [RuleSetEntry]? = nil) -> CustomRuleSet {
        CustomRuleSet(id: UUID(), subscriptionID: subscription ?? subscriptionID, name: name, outbound: strategy,
                      rules: entries ?? [RuleSetEntry(type: "DOMAIN", value: name)], enabled: enabled,
                      createdAt: Date(timeIntervalSince1970: 0))
    }
}
