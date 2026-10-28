import XCTest
@testable import TungBox

final class SelectorSelectionCoordinatorTests: XCTestCase {
    private let profile = UUID()
    private func config(manual: String = "自动选择", global: String = "自动选择", members: [String] = ["自动选择", "日本 03", "香港 11"]) throws -> String {
        try ConfigCodec.render(["outbounds": [
            ["type": "selector", "tag": "节点选择", "outbounds": members, "default": manual],
            ["type": "selector", "tag": "全局", "outbounds": members, "default": global]
        ]])
    }

    @MainActor
    func testLateOldRestoreCannotBecomeFinalSelectionAfterManualClick() async throws {
        let coordinator = SelectorSelectionCoordinator()
        let (started, signal) = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        var epoch = 0
        var actual = "自动选择"
        var writes: [String] = []
        let old = Task {
            try await coordinator.apply(selections: [.init(group: "全局", node: "自动选择")], ports: [9090],
                isCurrent: { epoch == 0 }, write: { selection, _ in
                    signal.yield(()); signal.finish()
                    await withCheckedContinuation { release = $0 }
                    actual = selection.node
                    writes.append(selection.node)
                })
        }
        var iterator = started.makeAsyncIterator()
        await iterator.next()
        epoch = 1
        coordinator.remember(profile: profile, group: "全局", node: "日本 03")
        let targets = coordinator.selections(in: try config(global: "日本 03"), profile: profile)
        let manual = Task {
            try await coordinator.apply(selections: targets, ports: [9090], isCurrent: { epoch == 1 },
                write: { selection, _ in
                    if selection.group == "全局" { actual = selection.node; writes.append(selection.node) }
                })
        }
        await Task.yield()
        XCTAssertTrue(writes.isEmpty, "新选择必须等已经发出的旧 PUT 结束，不能与其竞速")
        release?.resume()
        let oldApplied = try await old.value
        let manualApplied = try await manual.value
        XCTAssertFalse(oldApplied)
        XCTAssertTrue(manualApplied)
        XCTAssertEqual(writes, ["自动选择", "日本 03"])
        XCTAssertEqual(actual, "日本 03")
    }

    @MainActor
    func testObservationCapturedDuringWriteCannotReplaceOptimisticChoice() async throws {
        let coordinator = SelectorSelectionCoordinator()
        let before = coordinator.observationToken
        let (started, signal) = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        let task = Task {
            try await coordinator.apply(selections: [.init(group: "节点选择", node: "日本 03")], ports: [9091],
                isCurrent: { true }, write: { _, _ in
                    signal.yield(()); signal.finish()
                    await withCheckedContinuation { release = $0 }
                })
        }
        var iterator = started.makeAsyncIterator()
        await iterator.next()
        let during = coordinator.observationToken
        XCTAssertNil(during)
        XCTAssertFalse(coordinator.acceptsObservation(before))
        release?.resume()
        _ = try await task.value
        XCTAssertFalse(coordinator.acceptsObservation(during))
        XCTAssertFalse(coordinator.acceptsObservation(before))
        XCTAssertTrue(coordinator.acceptsObservation(coordinator.observationToken))
    }

    @MainActor
    func testNewChoiceOverridesOldRestoreSnapshotAndKeepsIndependentGroups() throws {
        let coordinator = SelectorSelectionCoordinator()
        let oldSnapshot = try config()
        coordinator.remember(profile: profile, group: "节点选择", node: "香港 11")
        coordinator.remember(profile: profile, group: "全局", node: "日本 03")
        let targets = coordinator.selections(in: oldSnapshot, profile: profile)
        XCTAssertEqual(targets, [.init(group: "节点选择", node: "香港 11"), .init(group: "全局", node: "日本 03")])
        XCTAssertEqual(coordinator.selections(in: oldSnapshot, profile: UUID()).map(\.node), ["自动选择", "自动选择"])
        XCTAssertEqual(coordinator.selections(in: try config(members: ["自动选择"]), profile: profile).map(\.node), ["自动选择", "自动选择"])
    }

    @MainActor
    func testFailureDoesNotPoisonQueueOrBlockSwitchOff() async throws {
        enum Failure: Error { case rejected }
        let coordinator = SelectorSelectionCoordinator()
        do {
            _ = try await coordinator.apply(selections: [.init(group: "节点选择", node: "日本 03")], ports: [9090],
                isCurrent: { true }, write: { _, _ in throw Failure.rejected })
            XCTFail("失败必须传播")
        } catch Failure.rejected { }
        XCTAssertTrue(coordinator.acceptsObservation(coordinator.observationToken))
        var writes = 0
        let skipped = try await coordinator.apply(selections: [.init(group: "节点选择", node: "日本 03")], ports: [9090],
            isCurrent: { false }, write: { _, _ in writes += 1 })
        XCTAssertFalse(skipped)
        XCTAssertEqual(writes, 0)
        let recovered = try await coordinator.apply(selections: [.init(group: "节点选择", node: "香港 11")], ports: [9090],
            isCurrent: { true }, write: { _, _ in writes += 1 })
        XCTAssertTrue(recovered)
        XCTAssertEqual(writes, 1)
    }
}
