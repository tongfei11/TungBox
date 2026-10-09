import Foundation

/// Owns presentation of one test so cancelled/older tasks cannot finish a newer one.
struct NodeDelayTestState: Sendable {
    enum Phase: Sendable { case idle, testing, refreshingSelection, completed, cancelled }
    private(set) var requestID: UUID?
    private(set) var total = 0
    private(set) var completed = 0
    private(set) var phase: Phase = .idle

    mutating func begin(id: UUID, total: Int) {
        requestID = id
        self.total = total
        completed = 0
        phase = .testing
    }

    mutating func receivedResult(id: UUID) {
        guard requestID == id, phase == .testing else { return }
        completed = min(completed + 1, total)
    }

    mutating func refreshSelection(id: UUID) {
        guard requestID == id else { return }
        phase = .refreshingSelection
    }

    @discardableResult
    mutating func finish(id: UUID, succeeded: Bool) -> Bool {
        guard requestID == id else { return false }
        requestID = nil
        phase = succeeded ? .completed : .cancelled
        return true
    }

    var statusText: String {
        switch phase {
        case .idle: return "节点 URLTest：尚未测试"
        case .testing: return "节点 URLTest：测试中，\(completed)/\(total) 个节点"
        case .refreshingSelection: return "节点 URLTest：节点测试已完成，正在刷新自动选择"
        case .completed: return "节点 URLTest：已完成，\(total) 个节点"
        case .cancelled: return "节点 URLTest：已取消"
        }
    }

    static func clearPendingDelays(in nodes: inout [NodeInfo]) {
        for index in nodes.indices where nodes[index].delay == "测试中" {
            nodes[index].delay = "未测试"
        }
    }
}
