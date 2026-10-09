import AppKit
import XCTest
@testable import TungBox

/// Only constructs individual cells, never a controller or running application.
final class RuleTableCellTests: XCTestCase {
    private func rule(isSet: Bool, enabled: Bool = true, error: String? = nil, strategyError: String? = nil) -> RuleInfo {
        .init(customRuleID: isSet ? nil : UUID(), enabled: enabled, id: "1", type: isSet ? "规则集" : "DOMAIN",
              value: "warning-demo.invalid", strategy: "旧节点", count: "0", note: error ?? "测试", isSection: false,
              ruleSetID: isSet ? UUID() : nil, referenceError: error, strategyReferenceError: strategyError)
    }

    @MainActor
    func testMissingNodeShowsOrangeWarningAndStrategyForBothRuleKinds() throws {
        let error = "出站不存在：旧节点，请重新选择"
        let previousTheme = MD3.isDark
        defer { MD3.isDark = previousTheme }
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            MD3.isDark = appearanceName == .darkAqua
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            appearance.performAsCurrentDrawingAppearance {
                for isSet in [false, true] {
                    for enabled in [false, true] {
                        let row = rule(isSet: isSet, enabled: enabled, error: error, strategyError: error)
                        var configuredCheckbox = false
                        let status = RuleTableCell.make(for: row, columnID: "enabled") { _, _ in configuredCheckbox = true }
                        guard let mark = status.subviews.first as? NSTextField else {
                            XCTFail("警告状态缺少文本标记")
                            return
                        }
                        XCTAssertEqual(mark.stringValue, "⚠")
                        XCTAssertEqual(mark.textColor, MD3.warning)
                        XCTAssertEqual(mark.toolTip, error + (enabled ? "" : "（规则已停用）"))
                        XCTAssertFalse(configuredCheckbox, "警告应独立于复选框")
                        let strategy = RuleTableCell.make(for: row, columnID: "strategy")
                        guard let label = strategy.subviews.first as? NSTextField else {
                            XCTFail("策略单元格缺少节点名称")
                            return
                        }
                        XCTAssertEqual(label.stringValue, "旧节点")
                        XCTAssertEqual(label.textColor, MD3.warning)
                        XCTAssertEqual(label.toolTip, error)
                    }
                }
            }
        }
    }

    @MainActor
    func testRuleSetReferenceWarningLeavesValidStrategyNeutral() throws {
        for isSet in [false, true] {
            let row = rule(isSet: isSet, error: "规则集引用不存在：removed")
            let mark = try XCTUnwrap(RuleTableCell.make(for: row, columnID: "enabled").subviews.first as? NSTextField)
            XCTAssertEqual(mark.stringValue, "⚠")
            XCTAssertEqual(mark.textColor, MD3.warning)
            let strategy = try XCTUnwrap(RuleTableCell.make(for: row, columnID: "strategy").subviews.first as? NSTextField)
            XCTAssertEqual(strategy.textColor, MD3.onSurface)
            XCTAssertNil(strategy.toolTip)
        }
    }

    @MainActor
    func testValidRulesKeepCheckboxActionsAndEnabledDisabledMarks() throws {
        for enabled in [true, false] {
            let custom = rule(isSet: false, enabled: enabled)
            var configuredID: UUID?
            let cell = RuleTableCell.make(for: custom, columnID: "enabled") { button, id in
                configuredID = id
                button.tag = 7
            }
            let checkbox = try XCTUnwrap(cell.subviews.first as? MD3Checkbox)
            XCTAssertEqual(checkbox.state, enabled ? .on : .off)
            XCTAssertTrue(checkbox.isEnabled)
            XCTAssertEqual(checkbox.tag, 7)
            XCTAssertEqual(configuredID, custom.customRuleID)
            let set = rule(isSet: true, enabled: enabled)
            let mark = try XCTUnwrap(RuleTableCell.make(for: set, columnID: "enabled").subviews.first as? NSTextField)
            XCTAssertEqual(mark.stringValue, enabled ? "●" : "○")
            XCTAssertEqual(mark.textColor, enabled ? MD3.primary : MD3.onSurfaceVariant)
        }
    }
}
