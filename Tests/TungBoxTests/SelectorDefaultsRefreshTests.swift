import Foundation
import XCTest
@testable import TungBox

final class SelectorDefaultsRefreshTests: XCTestCase {
    private func text(nodes: [String], manual: String, global: String? = nil) throws -> String {
        var outbounds: [[String: Any]] = nodes.map { ["type": "trojan", "tag": $0] }
        outbounds += [["type": "urltest", "tag": TungBoxConfig.tagAuto, "outbounds": nodes],
                      ["type": "selector", "tag": TungBoxConfig.tagManual,
                       "outbounds": [TungBoxConfig.tagAuto] + nodes, "default": manual]]
        if let global {
            outbounds.append(["type": "selector", "tag": TungBoxConfig.tagGlobal,
                              "outbounds": [TungBoxConfig.tagAuto] + nodes, "default": global])
        }
        return try ConfigCodec.render(["outbounds": outbounds])
    }

    private func selection(_ tag: String, in text: String) throws -> String {
        let config = try XCTUnwrap(ConfigCodec.parseObject(from: text))
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        return try XCTUnwrap(outbounds.first { $0["tag"] as? String == tag }?["default"] as? String)
    }

    func testRefreshRecreatesMissingGlobalAndPreservesManualChoice() throws {
        let existing = try text(nodes: ["NodeA", "NodeB"], manual: TungBoxConfig.tagAuto, global: "NodeB")
        let incoming = try text(nodes: ["NodeA", "NodeB"], manual: TungBoxConfig.tagAuto)
        let refreshed = ProxyModeConfig.preserveSelectorDefaults(from: existing, into: incoming)
        XCTAssertEqual(try selection(TungBoxConfig.tagGlobal, in: refreshed), "NodeB")
    }

    func testRemovedGlobalNodeFallsBackToAvailableAutomaticGroup() throws {
        let existing = try text(nodes: ["NodeA", "NodeB"], manual: TungBoxConfig.tagAuto, global: "NodeB")
        let incoming = try text(nodes: ["NodeA"], manual: TungBoxConfig.tagAuto)
        let refreshed = ProxyModeConfig.preserveSelectorDefaults(from: existing, into: incoming)
        XCTAssertEqual(try selection(TungBoxConfig.tagGlobal, in: refreshed), TungBoxConfig.tagAuto)
        let outbounds = try XCTUnwrap(ConfigCodec.parseObject(from: refreshed)?["outbounds"] as? [[String: Any]])
        let global = try XCTUnwrap(outbounds.first { $0["tag"] as? String == TungBoxConfig.tagGlobal })
        XCTAssertFalse((global["outbounds"] as? [String] ?? []).contains("NodeB"))
    }

    func testRefreshPreservesRuleModeManualSelectorChoice() throws {
        let existing = try text(nodes: ["NodeA", "NodeB"], manual: "NodeB")
        let incoming = try text(nodes: ["NodeA", "NodeB"], manual: TungBoxConfig.tagAuto)
        let refreshed = ProxyModeConfig.preserveSelectorDefaults(from: existing, into: incoming)
        XCTAssertEqual(try selection(TungBoxConfig.tagManual, in: refreshed), "NodeB")
    }
}
