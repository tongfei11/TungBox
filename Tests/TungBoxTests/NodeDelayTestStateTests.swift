import AppKit
import XCTest
@testable import TungBox

final class NodeDelayTestStateTests: XCTestCase {
    func testRepeatedStartCannotReplaceAnActiveTest() {
        let id = UUID()
        var state = NodeDelayTestState()
        state.begin(id: id, tags: ["first", "second"])
        state.receivedResult(id: id, tag: "first")
        XCTAssertFalse(state.begin(id: UUID(), tags: ["replacement"]))
        XCTAssertEqual(state.requestID, id)
        XCTAssertEqual(state.completed, 1)
        XCTAssertEqual(state.total, 2)
        state.refreshSelection(id: id)
        XCTAssertFalse(state.begin(id: UUID(), tags: ["replacement"]))
        XCTAssertEqual(state.requestID, id)
        XCTAssertEqual(state.phase, .refreshingSelection)
    }

    func testResultsArePresentedBeforeAutomaticSelectionRefreshCompletes() {
        let id = UUID()
        var state = NodeDelayTestState()
        state.begin(id: id, tags: ["first", "second"])
        state.receivedResult(id: id, tag: "first")
        XCTAssertEqual(state.statusText, "节点 URLTest：测试中，1/2 个节点")
        state.receivedResult(id: id, tag: "second")
        state.refreshSelection(id: id)
        XCTAssertEqual(state.completed, 2)
        XCTAssertEqual(state.statusText, "节点 URLTest：节点测试已完成，正在刷新自动选择")
        XCTAssertTrue(state.finish(id: id, succeeded: true))
        XCTAssertEqual(state.statusText, "节点 URLTest：已完成，2 个节点")
    }

    func testCancellationClearsOwnershipAndCannotBeOverwrittenByLateCompletion() {
        let id = UUID()
        var state = NodeDelayTestState()
        state.begin(id: id, tags: ["first", "second"])
        state.receivedResult(id: id, tag: "first")
        XCTAssertTrue(state.finish(id: id, succeeded: false))
        XCTAssertNil(state.requestID)
        XCTAssertEqual(state.statusText, "节点 URLTest：已取消")
        XCTAssertFalse(state.finish(id: id, succeeded: true))
        XCTAssertEqual(state.phase, .cancelled)
    }

    func testOlderResultsAndCleanupCannotTouchNewerTest() {
        let old = UUID(), current = UUID()
        var state = NodeDelayTestState()
        state.begin(id: old, tags: ["old"])
        XCTAssertTrue(state.finish(id: old, succeeded: false))
        XCTAssertTrue(state.begin(id: current, tags: ["first", "second"]))
        state.receivedResult(id: old, tag: "first")
        state.refreshSelection(id: old)
        XCTAssertFalse(state.finish(id: old, succeeded: false))
        XCTAssertEqual(state.completed, 0)
        XCTAssertEqual(state.requestID, current)
        XCTAssertEqual(state.phase, .testing)
        state.receivedResult(id: current, tag: "first")
        XCTAssertEqual(state.completed, 1)
    }

    func testInterruptedTestResetsOnlyPendingNodeDelays() {
        var nodes = ["测试中", "20 ms", "失败", "超时", "未测试"].enumerated().map { index, delay in
            NodeInfo(tag: "node-\(index)", type: "trojan", server: "", delay: delay)
        }
        NodeDelayTestState.clearPendingDelays(in: &nodes)
        XCTAssertEqual(nodes.map(\.delay), ["未测试", "20 ms", "失败", "超时", "未测试"])
    }

    func testGroupAndTrayHistoryCannotOverwriteManualResultsDuringOrAfterTest() {
        let id = UUID()
        var state = NodeDelayTestState()
        var nodes = makeNodes(["20 ms", "测试中", "未测试"])
        state.begin(id: id, tags: ["node-0", "node-1"])
        state.receivedResult(id: id, tag: "node-0")
        let history = makeHistory([80, 90, 100])
        XCTAssertTrue(state.syncBackgroundDelays(proxies: history, in: &nodes))
        XCTAssertEqual(nodes.map(\.delay), ["20 ms", "测试中", "100 ms"])
        nodes[1].delay = "失败"
        state.receivedResult(id: id, tag: "node-1")
        state.refreshSelection(id: id)
        XCTAssertFalse(state.syncBackgroundDelays(proxies: history, in: &nodes))
        XCTAssertEqual(nodes.map(\.delay), ["20 ms", "失败", "100 ms"])
        state.finish(id: id, succeeded: true)
        XCTAssertFalse(state.syncBackgroundDelays(proxies: history, in: &nodes))
        XCTAssertEqual(nodes.map(\.delay), ["20 ms", "失败", "100 ms"])
        state.clearResultProtection()
        XCTAssertTrue(state.syncBackgroundDelays(proxies: history, in: &nodes))
        XCTAssertEqual(nodes.map(\.delay), ["80 ms", "90 ms", "100 ms"])
    }

    func testCancellationProtectsOnlyReturnedResultsAndAllowsNextStart() {
        let id = UUID()
        var state = NodeDelayTestState()
        var nodes = makeNodes(["20 ms", "测试中"])
        state.begin(id: id, tags: ["node-0", "node-1"])
        state.receivedResult(id: id, tag: "node-0")
        state.finish(id: id, succeeded: false)
        NodeDelayTestState.clearPendingDelays(in: &nodes)
        XCTAssertFalse(state.isActive)
        XCTAssertTrue(state.syncBackgroundDelays(proxies: makeHistory([80, 90]), in: &nodes))
        XCTAssertEqual(nodes.map(\.delay), ["20 ms", "90 ms"])
        XCTAssertTrue(state.begin(id: UUID(), tags: ["node-1"]))
        XCTAssertTrue(state.syncBackgroundDelays(proxies: makeHistory([80, 100]), in: &nodes))
        XCTAssertEqual(nodes.map(\.delay), ["80 ms", "90 ms"])
    }

    func testBackgroundHistoryUsesLatestDelayAndPreservesMissingResults() {
        var state = NodeDelayTestState()
        var nodes = makeNodes(["未测试", "未测试", "30 ms"])
        let history: [String: Any] = [
            "node-0": ["history": [["delay": 10], ["delay": 20]]],
            "node-1": ["history": [["delay": 0]]],
            "node-2": ["history": []]
        ]
        XCTAssertTrue(state.syncBackgroundDelays(proxies: history, in: &nodes))
        XCTAssertEqual(nodes.map(\.delay), ["20 ms", "超时", "30 ms"])
        XCTAssertFalse(state.begin(id: UUID(), tags: []))
        XCTAssertFalse(state.isActive)
        XCTAssertTrue(state.begin(id: UUID(), tags: ["node-0", "node-0"]))
        XCTAssertEqual(state.total, 1)
    }

    func testDuplicateAndUnknownResultsDoNotAdvanceProgress() {
        let id = UUID()
        var state = NodeDelayTestState()
        state.begin(id: id, tags: ["first", "second"])
        state.receivedResult(id: id, tag: "first")
        state.receivedResult(id: id, tag: "first")
        state.receivedResult(id: id, tag: "unknown")
        XCTAssertEqual(state.completed, 1)
    }

    private func makeNodes(_ delays: [String]) -> [NodeInfo] {
        delays.enumerated().map { NodeInfo(tag: "node-\($0.offset)", type: "trojan", server: "", delay: $0.element) }
    }

    private func makeHistory(_ delays: [Int]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: delays.enumerated().map { ("node-\($0.offset)", ["history": [["delay": $0.element]]]) })
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
