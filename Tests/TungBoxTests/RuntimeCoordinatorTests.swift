import XCTest
@testable import TungBox

final class RuntimeCoordinatorTests: XCTestCase {
    @MainActor
    func testInputSnapshotKeepsIndependentSwitchesAndOperationOptions() {
        let coordinator = RuntimeCoordinator()
        for systemProxy in [false, true] {
            for tun in [false, true] {
                let input = RuntimeCoordinator.Input(
                    systemProxyEnabled: systemProxy, tunEnabled: tun, mixedProxyPort: 8123,
                    reason: "mock switch", forceRestart: true, refreshNodeDelays: false
                )
                let request = coordinator.begin(input)
                XCTAssertEqual(request.input, input)
                XCTAssertEqual(coordinator.state.request, request)
            }
        }
        XCTAssertEqual(coordinator.generation, 4)
    }

    @MainActor
    func testRapidRequestsInvalidateOlderGenerationEvenWithIdenticalInput() {
        let coordinator = RuntimeCoordinator()
        let first = coordinator.begin(input(systemProxy: true, tun: true))
        let second = coordinator.begin(input(systemProxy: false, tun: true))
        let third = coordinator.begin(input(systemProxy: false, tun: true))
        XCTAssertFalse(coordinator.isCurrent(first))
        XCTAssertFalse(coordinator.isCurrent(second))
        XCTAssertTrue(coordinator.isCurrent(third))
        XCTAssertEqual([first.generation, second.generation, third.generation], [1, 2, 3])
        XCTAssertTrue(first.input.systemProxyEnabled, "旧请求保留自己的不可变快照")
    }

    @MainActor
    func testFeatureTransitionsRemainIndependentAndSetBusyState() {
        let coordinator = RuntimeCoordinator()
        XCTAssertFalse(coordinator.state.isTransitioning)
        coordinator.beginFeatureTransition(systemProxy: .starting)
        coordinator.beginFeatureTransition(tun: .stopping)
        XCTAssertEqual(coordinator.state.systemProxyTransition, .starting)
        XCTAssertEqual(coordinator.state.tunTransition, .stopping)
        coordinator.beginFeatureTransition(systemProxy: RuntimeCoordinator.FeatureTransition.none)
        XCTAssertTrue(coordinator.state.isTransitioning)
        XCTAssertEqual(coordinator.state.tunTransition, .stopping)
        coordinator.beginFeatureTransition(tun: RuntimeCoordinator.FeatureTransition.none)
        XCTAssertFalse(coordinator.state.isTransitioning)
    }

    @MainActor
    func testSwitchOffPresentationDoesNotEndPendingBackgroundCleanup() {
        let coordinator = RuntimeCoordinator()
        let request = coordinator.begin(input(systemProxy: false, tun: false))
        coordinator.beginFeatureTransition(systemProxy: .stopping)
        coordinator.updateFeaturePresentation(systemProxy: RuntimeCoordinator.FeatureTransition.none)
        XCTAssertEqual(coordinator.state.systemProxyTransition, .none)
        XCTAssertTrue(coordinator.state.isTransitioning, "开关已经显示关闭，但收尾完成前不能开始新的测速")
        let newer = coordinator.begin(input(systemProxy: true, tun: false))
        coordinator.beginFeatureTransition(systemProxy: .starting)
        XCTAssertFalse(coordinator.finish(request))
        XCTAssertTrue(coordinator.state.isTransitioning)
        XCTAssertTrue(coordinator.finish(newer))
        XCTAssertFalse(coordinator.state.isTransitioning)
    }

    @MainActor
    func testOnlyLatestCompletionMayClearFeatureTransitions() {
        let coordinator = RuntimeCoordinator()
        let old = coordinator.begin(input(systemProxy: true, tun: false))
        coordinator.beginFeatureTransition(systemProxy: .starting)
        let current = coordinator.begin(input(systemProxy: false, tun: true))
        coordinator.beginFeatureTransition(systemProxy: .stopping, tun: .starting)
        XCTAssertFalse(coordinator.finish(old))
        XCTAssertEqual(coordinator.state.systemProxyTransition, .stopping)
        XCTAssertEqual(coordinator.state.tunTransition, .starting)
        XCTAssertTrue(coordinator.finish(current))
        XCTAssertFalse(coordinator.state.isTransitioning)
        XCTAssertEqual(coordinator.state.request, current)
        XCTAssertTrue(coordinator.isCurrent(current), "完成不另增代次，既有回调仍使用相同运行快照")
    }

    @MainActor
    func testClearingTransitionsDoesNotAlterCurrentIntentOrGeneration() {
        let coordinator = RuntimeCoordinator()
        let request = coordinator.begin(input(systemProxy: true, tun: true))
        coordinator.beginFeatureTransition(systemProxy: .starting, tun: .starting)
        coordinator.clearFeatureTransitions()
        coordinator.clearFeatureTransitions()
        XCTAssertEqual(coordinator.state.request, request)
        XCTAssertEqual(coordinator.generation, request.generation)
        XCTAssertFalse(coordinator.state.isTransitioning)
    }

    @MainActor
    func testNewSwitchIntentIsAcceptedWhileOldBlockingOperationIsPending() async throws {
        let coordinator = RuntimeCoordinator()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let old = coordinator.begin(input(systemProxy: true, tun: true))
        coordinator.beginFeatureTransition(systemProxy: .starting, tun: .starting)
        let task = Task {
            try await coordinator.performBlocking {
                XCTAssertFalse(Thread.isMainThread)
                signal.yield(())
                signal.finish()
                guard release.wait(timeout: .now() + 2) == .success else { throw MockFailure.timedOut }
                return "old completed"
            }
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        // A new switch never waits on the serial operation queue.
        let current = coordinator.begin(input(systemProxy: false, tun: false))
        coordinator.beginFeatureTransition(systemProxy: .stopping, tun: .stopping)
        XCTAssertFalse(coordinator.isCurrent(old))
        XCTAssertTrue(coordinator.isCurrent(current))
        release.signal()
        let result = try await task.value
        XCTAssertEqual(result, "old completed")
        XCTAssertFalse(coordinator.finish(old), "旧任务迟到后不能撤销新的开关状态")
        XCTAssertEqual(coordinator.state.request?.input.systemProxyEnabled, false)
        XCTAssertEqual(coordinator.state.tunTransition, .stopping)
    }

    @MainActor
    func testBlockingOperationsKeepSerialOrderAndReturnValues() async throws {
        let coordinator = RuntimeCoordinator()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let trace = LockedValue<[String]>([])
        let first = Task {
            try await coordinator.performBlocking {
                trace.mutate { $0.append("first start") }
                signal.yield(())
                signal.finish()
                guard release.wait(timeout: .now() + 2) == .success else { throw MockFailure.timedOut }
                trace.mutate { $0.append("first end") }
                return 1
            }
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        let second = Task {
            try await coordinator.performBlocking {
                trace.mutate { $0.append("second") }
                return 2
            }
        }
        release.signal()
        let firstResult = try await first.value
        let secondResult = try await second.value
        XCTAssertEqual(firstResult, 1)
        XCTAssertEqual(secondResult, 2)
        XCTAssertEqual(trace.get(), ["first start", "first end", "second"])
    }

    @MainActor
    func testOperationFailurePropagatesWithoutLosingLaterRequest() async {
        let coordinator = RuntimeCoordinator()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let old = coordinator.begin(input(systemProxy: false, tun: true))
        let failure = Task {
            try await coordinator.performBlocking { () throws -> Bool in
                signal.yield(())
                signal.finish()
                guard release.wait(timeout: .now() + 2) == .success else { throw MockFailure.timedOut }
                throw MockFailure.failed
            }
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        let current = coordinator.begin(input(systemProxy: true, tun: false))
        coordinator.beginFeatureTransition(systemProxy: .starting)
        release.signal()
        do {
            _ = try await failure.value
            XCTFail("模拟操作错误必须回传")
        } catch {
            XCTAssertEqual(error as? MockFailure, .failed)
        }
        XCTAssertFalse(coordinator.finish(old))
        XCTAssertTrue(coordinator.isCurrent(current))
        XCTAssertEqual(coordinator.state.systemProxyTransition, .starting)
    }

    private func input(systemProxy: Bool, tun: Bool) -> RuntimeCoordinator.Input {
        .init(systemProxyEnabled: systemProxy, tunEnabled: tun, mixedProxyPort: 7890,
              reason: "mock", forceRestart: false, refreshNodeDelays: true)
    }
}

private enum MockFailure: Error, Equatable { case failed, timedOut }
