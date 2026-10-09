import AppKit
import XCTest
@testable import TungBox

final class NodeDelayTestStateTests: XCTestCase {
    func testResultsArePresentedBeforeAutomaticSelectionRefreshCompletes() {
        let id = UUID()
        var state = NodeDelayTestState()
        state.begin(id: id, total: 2)
        state.receivedResult(id: id)
        XCTAssertEqual(state.statusText, "节点 URLTest：测试中，1/2 个节点")
        state.receivedResult(id: id)
        state.refreshSelection(id: id)
        XCTAssertEqual(state.completed, 2)
        XCTAssertEqual(state.statusText, "节点 URLTest：节点测试已完成，正在刷新自动选择")
        XCTAssertTrue(state.finish(id: id, succeeded: true))
        XCTAssertEqual(state.statusText, "节点 URLTest：已完成，2 个节点")
    }

    func testCancellationClearsOwnershipAndCannotBeOverwrittenByLateCompletion() {
        let id = UUID()
        var state = NodeDelayTestState()
        state.begin(id: id, total: 2)
        state.receivedResult(id: id)
        XCTAssertTrue(state.finish(id: id, succeeded: false))
        XCTAssertNil(state.requestID)
        XCTAssertEqual(state.statusText, "节点 URLTest：已取消")
        XCTAssertFalse(state.finish(id: id, succeeded: true))
        XCTAssertEqual(state.phase, .cancelled)
    }

    func testOlderResultsAndCleanupCannotTouchNewerTest() {
        let old = UUID(), current = UUID()
        var state = NodeDelayTestState()
        state.begin(id: old, total: 5)
        state.begin(id: current, total: 2)
        state.receivedResult(id: old)
        state.refreshSelection(id: old)
        XCTAssertFalse(state.finish(id: old, succeeded: false))
        XCTAssertEqual(state.completed, 0)
        XCTAssertEqual(state.requestID, current)
        XCTAssertEqual(state.phase, .testing)
        state.receivedResult(id: current)
        XCTAssertEqual(state.completed, 1)
    }

    func testInterruptedTestResetsOnlyPendingNodeDelays() {
        var nodes = ["测试中", "20 ms", "失败", "超时", "未测试"].enumerated().map { index, delay in
            NodeInfo(tag: "node-\(index)", type: "trojan", server: "", delay: delay)
        }
        NodeDelayTestState.clearPendingDelays(in: &nodes)
        XCTAssertEqual(nodes.map(\.delay), ["未测试", "20 ms", "失败", "超时", "未测试"])
    }

    @MainActor
    func testLatencyResultsUpdateExistingTilesWithoutRebuildingLayout() {
        let root = NSStackView()
        let nested = NSStackView()
        let first = MD3NodeTileView(), second = MD3NodeTileView()
        first.nodeTag = "first"; first.delayValue = "测试中"
        second.nodeTag = "second"; second.delayValue = "测试中"
        nested.addArrangedSubview(first)
        nested.addArrangedSubview(second)
        root.addArrangedSubview(nested)
        MD3NodeTileView.refreshDelays(in: root, delays: ["first": "20 ms"])
        XCTAssertEqual(first.delayValue, "20 ms")
        XCTAssertEqual(second.delayValue, "测试中")
        XCTAssertTrue(root.arrangedSubviews.first === nested)
        XCTAssertTrue(nested.arrangedSubviews.first === first)
        XCTAssertTrue(nested.arrangedSubviews.last === second)
        MD3NodeTileView.refreshDelays(in: root, delays: ["second": "失败"])
        XCTAssertEqual(second.delayValue, "失败")
    }
}
