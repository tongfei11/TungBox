import XCTest
@testable import TungBox

final class OutboundSelectionTests: XCTestCase {
    private let groups = [
        NodeGroupInfo(tag: "全局", type: "selector", members: ["自动选择", "日本 03"], current: "日本 03"),
        NodeGroupInfo(tag: "节点选择", type: "selector", members: ["自动选择", "日本 03"], current: "自动选择"),
        NodeGroupInfo(tag: "自动选择", type: "urltest", members: ["香港 11", "日本 03"], current: "香港 11")
    ]
    private let runtime: [String: Any] = ["proxies": [
        "全局": ["type": "Selector", "now": "日本 03"],
        "节点选择": ["type": "Selector", "now": "自动选择"],
        "自动选择": ["type": "URLTest", "now": "香港 11"],
        "日本 03": ["type": "Trojan"], "香港 11": ["type": "Trojan"]
    ]]

    func testGlobalManualSelectionDoesNotReadRuleAutoGroup() {
        let global = OutboundSelection.resolve(group: OutboundSelection.group(for: "Global"), proxiesObject: runtime, groups: groups, configText: "{}")
        XCTAssertEqual(global.name, "日本 03")
        XCTAssertFalse(global.isAuto)
        let rule = OutboundSelection.resolve(group: OutboundSelection.group(for: "Rule"), proxiesObject: runtime, groups: groups, configText: "{}")
        XCTAssertEqual(rule.name, "香港 11")
        XCTAssertTrue(rule.isAuto)
    }

    func testSavedGlobalChoiceAlsoResolvesWithoutRunningCore() {
        let global = OutboundSelection.resolve(group: OutboundSelection.group(for: "gLoBaL"), proxiesObject: nil, groups: groups, configText: "{}")
        XCTAssertEqual(global.name, "日本 03")
        XCTAssertFalse(global.isAuto)
        let automatic = OutboundSelection.resolve(group: "自动选择", proxiesObject: nil, groups: groups, configText: "{}")
        XCTAssertEqual(automatic.name, "香港 11")
        XCTAssertTrue(automatic.isAuto)
    }
}
