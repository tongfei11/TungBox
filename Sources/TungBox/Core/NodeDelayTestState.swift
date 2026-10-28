import Foundation

/// Owns presentation of one test so cancelled/older tasks cannot finish a newer one.
struct NodeDelayTestState: Sendable {
    enum Phase: Sendable { case idle, testing, refreshingSelection, completed, cancelled }
    private(set) var requestID: UUID?
    private(set) var total = 0
    private(set) var completed = 0
    private(set) var phase: Phase = .idle
    private var requestedTags = Set<String>()
    private var resultTags = Set<String>()

    var isActive: Bool { requestID != nil }

    func covers(_ tags: [String]) -> Bool {
        isActive && Set(tags).isSubset(of: requestedTags)
    }

    @discardableResult
    mutating func begin(id: UUID, tags: [String]) -> Bool {
        guard !isActive, !tags.isEmpty else { return false }
        requestID = id
        requestedTags = Set(tags)
        resultTags.removeAll()
        total = requestedTags.count
        completed = 0
        phase = .testing
        return true
    }

    mutating func receivedResult(id: UUID, tag: String) {
        guard requestID == id, phase == .testing, requestedTags.contains(tag) else { return }
        resultTags.insert(tag)
        completed = resultTags.count
    }

    mutating func refreshSelection(id: UUID) {
        guard requestID == id else { return }
        phase = .refreshingSelection
    }

    @discardableResult
    mutating func finish(id: UUID, succeeded: Bool) -> Bool {
        guard requestID == id else { return false }
        requestID = nil
        requestedTags.removeAll()
        phase = succeeded ? .completed : .cancelled
        return true
    }

    /// A group retest and tray refresh must not replace explicit manual results.
    /// Keep returned results until the next test or runtime/profile change.
    mutating func clearResultProtection() {
        resultTags.removeAll()
    }

    @discardableResult
    func syncBackgroundDelays(proxies: [String: Any], in nodes: inout [NodeInfo]) -> Bool {
        var updated = false
        for index in nodes.indices {
            let tag = nodes[index].tag
            guard !requestedTags.contains(tag), !resultTags.contains(tag),
                  nodes[index].delay != "测试中",
                  let proxy = proxies[tag] as? [String: Any],
                  let history = proxy["history"] as? [[String: Any]],
                  let delay = history.last?["delay"] as? Int else { continue }
            let value = delay > 0 ? "\(delay) ms" : "超时"
            if nodes[index].delay != value {
                nodes[index].delay = value
                updated = true
            }
        }
        return updated
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
