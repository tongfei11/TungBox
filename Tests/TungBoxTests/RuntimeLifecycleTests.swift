import XCTest
@testable import TungBox

final class RuntimeLifecycleTests: XCTestCase {
    @MainActor
    func testDelayedCallbackRunsOnlyForItsOriginalGeneration() async {
        for delay: TimeInterval in [2, 3] {
            let coordinator = RuntimeCoordinator()
            var calls = 0
            let task = coordinator.schedule(after: delay, sleep: { seconds in XCTAssertEqual(seconds, delay) }) { calls += 1 }
            await task.value
            XCTAssertEqual(calls, 1)
        }
    }

    @MainActor
    func testNewSwitchCancelsWakeAndSelectorRestoreCallbacks() async {
        for delay: TimeInterval in [2, 3] {
            let coordinator = RuntimeCoordinator()
            let (started, signal) = AsyncStream<Void>.makeStream()
            let (release, resume) = AsyncStream<Void>.makeStream()
            var called = false
            let task = coordinator.schedule(after: delay, sleep: { _ in
                signal.yield(()); signal.finish()
                var iterator = release.makeAsyncIterator()
                _ = await iterator.next()
            }) { called = true }
            var iterator = started.makeAsyncIterator()
            _ = await iterator.next()
            _ = coordinator.begin(Self.input(tun: false))
            resume.yield(()); resume.finish()
            await task.value
            XCTAssertFalse(called)
        }
    }

    @MainActor
    func testShutdownIsTerminalAndRepeatedCallsDoNotRepeatCleanup() async {
        let f = LifecycleFixture()
        let old = f.coordinator.begin(Self.input(tun: true))
        let first = f.stop()
        let duplicate = f.stop()
        XCTAssertFalse(f.coordinator.isCurrent(old))
        XCTAssertTrue(f.coordinator.state.isTerminating)
        let rejected = f.coordinator.begin(Self.input(tun: true))
        XCTAssertFalse(f.coordinator.isCurrent(rejected))
        await first.value
        await duplicate.value
        await f.stop().value
        XCTAssertEqual(f.trace.get(), ["cancel", "disable", "disable", "stop", "clear"])
        XCTAssertEqual(f.events.filter { $0 == "finished:false" }.count, 1)
        XCTAssertFalse(f.trace.get().contains { $0.hasPrefix("wait:") }, "退出不能等待 TUN 网卡回收")
    }

    @MainActor
    func testShutdownDoesNotTouchUnownedServices() async {
        let f = LifecycleFixture()
        await f.stop(disableTun: false, stopProxy: false, clearProxy: false).value
        XCTAssertEqual(f.trace.get(), ["cancel"])
        XCTAssertEqual(f.events, ["finished:false"])
    }

    @MainActor
    func testShutdownDrainsInFlightStartupAndRemovesLateTunRequest() async throws {
        let f = LifecycleFixture()
        let old = f.coordinator.begin(Self.input(tun: true))
        let (started, signal) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let startup = Task {
            try await f.coordinator.performBlocking(for: old) { [trace = f.trace, request = f.requestFile] in
                signal.yield(()); signal.finish()
                guard release.wait(timeout: .now() + 2) == .success else { throw LifecycleFailure.timedOut }
                request.set(true)
                trace.mutate { $0.append("late enable") }
            }
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        let cleanup = f.stop()
        XCTAssertTrue(f.coordinator.state.isTerminating, "主线程立即接受退出，不等待旧操作")
        XCTAssertFalse(f.events.contains("finished:false"))
        release.signal()
        try await startup.value
        await cleanup.value
        XCTAssertFalse(f.requestFile.get(), "排队收尾后必须再次删除迟到的启动请求")
        XCTAssertEqual(f.trace.get(), ["cancel", "disable", "late enable", "disable", "stop", "clear"])
    }

    @MainActor
    func testOperationsAndDelayedCallbacksCannotStartAfterTermination() async {
        let f = LifecycleFixture()
        await f.stop().value
        let request = f.coordinator.begin(Self.input(tun: true))
        do {
            try await f.coordinator.performBlocking(for: request) { XCTFail("退出后不得执行新的系统操作") }
            XCTFail("应拒绝退出后的操作")
        } catch { XCTAssertTrue(error is RuntimeCoordinator.OperationError) }
        let task = f.coordinator.schedule(after: 2, sleep: { _ in XCTFail("退出后不应再安排等待") }) {
            XCTFail("退出后不应执行回调")
        }
        await task.value
    }

    @MainActor
    func testNewIntentSupersedesNonterminalStopCleanup() async {
        let f = LifecycleFixture()
        let cleanup = f.stop(terminating: false)
        let latest = f.coordinator.begin(Self.input(tun: true))
        await cleanup.value
        XCTAssertTrue(f.coordinator.isCurrent(latest))
        XCTAssertEqual(f.trace.get(), ["cancel", "disable"])
        XCTAssertFalse(f.events.contains { $0.hasPrefix("finished:") })
    }

    @MainActor
    func testSynchronousStopWaitsOffMainAndReportsExistingTimeout() async {
        let f = LifecycleFixture()
        await f.stop(terminating: false, synchronous: true).value
        XCTAssertEqual(f.trace.get(), ["cancel", "disable", "disable", "wait:8.0", "stop", "clear"])
        XCTAssertTrue(f.events.contains("warning"))
        XCTAssertEqual(f.events.last, "finished:true")
        XCTAssertFalse(f.coordinator.state.isTerminating)
    }

    @MainActor
    func testBackgroundStopWaitUsesSixSecondsWithoutBlockingCompletion() async {
        let f = LifecycleFixture()
        let (warnings, signal) = AsyncStream<Void>.makeStream()
        f.onWarning = { signal.yield(()); signal.finish() }
        await f.stop(terminating: false, synchronous: false).value
        XCTAssertTrue(f.events.contains("finished:true"))
        var iterator = warnings.makeAsyncIterator()
        _ = await iterator.next()
        XCTAssertTrue(f.trace.get().contains("wait:6.0"))
    }

    @MainActor
    func testOwnershipIncludesPendingRequestsAfterSwitchIsTurnedOff() {
        let coordinator = RuntimeCoordinator()
        _ = coordinator.begin(Self.input(tun: true))
        _ = coordinator.begin(Self.input(tun: false))
        XCTAssertTrue(coordinator.state.hasRequestedTun)
        XCTAssertFalse(coordinator.state.hasRequestedProxy)
    }

    @MainActor
    func testReloadUsesDiscoveryPrepareWriteOrderAndReportsSuccess() async {
        let f = LifecycleFixture()
        let success = await f.reload("node change")
        XCTAssertTrue(success)
        XCTAssertEqual(f.trace.get(), ["discover:node change", "prepare:node change", "write:node change"])
        XCTAssertTrue(f.events.contains("reloaded"))
    }

    @MainActor
    func testReloadFailureKeepsRuntimeAndDoesNotPublishSuccess() async {
        let f = LifecycleFixture()
        var services = f.reloadServices()
        services = .init(discover: services.discover, prepare: services.prepare,
                         write: { _ in throw LifecycleFailure.failed }, tunEnabled: services.tunEnabled)
        let success = await f.reload("mock", services: services)
        XCTAssertFalse(success)
        XCTAssertFalse(f.events.contains("reloaded"))
        XCTAssertTrue(f.events.contains { $0.contains("保持当前运行不变") })
        XCTAssertFalse(f.trace.get().contains("stop"))
    }

    @MainActor
    func testNewSwitchDropsSlowReloadBeforeWritingConfig() async {
        let f = LifecycleFixture()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        let original = f.reloadServices()
        let services = RuntimeCoordinator.ReloadServices(discover: { _ in
            signal.yield(()); signal.finish()
            var iterator = release.makeAsyncIterator()
            _ = await iterator.next()
            return .init(physicalInterface: nil, resolvedAddressesByHost: [:])
        }, prepare: original.prepare, write: original.write, tunEnabled: original.tunEnabled)
        let task = Task { await f.reload("old", services: services) }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        _ = f.coordinator.begin(Self.input(tun: false))
        resume.yield(()); resume.finish()
        let success = await task.value
        XCTAssertFalse(success)
        XCTAssertTrue(f.trace.get().isEmpty)
        XCTAssertFalse(f.events.contains("reloaded"))
    }

    @MainActor
    func testNewestReloadWinsWhenEarlierDiscoveryReturnsLate() async {
        let f = LifecycleFixture()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        let original = f.reloadServices()
        let services = RuntimeCoordinator.ReloadServices(discover: { _ in
            signal.yield(()); signal.finish()
            var iterator = release.makeAsyncIterator()
            _ = await iterator.next()
            return .init(physicalInterface: nil, resolvedAddressesByHost: [:])
        }, prepare: original.prepare, write: original.write, tunEnabled: original.tunEnabled)
        let first = Task { await f.reload("first", services: services) }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        let latest = await f.reload("latest")
        XCTAssertTrue(latest)
        resume.yield(()); resume.finish()
        let old = await first.value
        XCTAssertFalse(old)
        XCTAssertEqual(f.trace.get(), ["discover:latest", "prepare:latest", "write:latest"])
    }

    @MainActor
    func testTerminatingPreventsReloadAndCancelsPendingCallbacks() async {
        let f = LifecycleFixture()
        var called = false
        let delayed = f.coordinator.schedule(after: 3, sleep: { _ in }) { called = true }
        await f.stop().value
        await delayed.value
        let reloaded = await f.reload("after exit")
        XCTAssertFalse(reloaded)
        XCTAssertFalse(called)
        XCTAssertFalse(f.trace.get().contains { $0.hasPrefix("discover:") })
    }

    @MainActor
    func testSupersededQueuedReloadIsSkippedAtWriteBoundary() async throws {
        let f = LifecycleFixture()
        let (blocked, signalBlocked) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let blocker = Task {
            try await f.coordinator.performBlocking {
                signalBlocked.yield(()); signalBlocked.finish()
                guard release.wait(timeout: .now() + 2) == .success else { throw LifecycleFailure.timedOut }
            }
        }
        var blockedIterator = blocked.makeAsyncIterator()
        _ = await blockedIterator.next()
        let (prepared, signalPrepared) = AsyncStream<String>.makeStream()
        let original = f.reloadServices()
        let services = RuntimeCoordinator.ReloadServices(discover: original.discover, prepare: { source, network in
            signalPrepared.yield(source)
            return try original.prepare(source, network)
        }, write: original.write, tunEnabled: original.tunEnabled)
        let first = Task { await f.reload("first", services: services) }
        var iterator = prepared.makeAsyncIterator()
        let firstPrepared = await iterator.next()
        XCTAssertEqual(firstPrepared, "first")
        let latest = Task { await f.reload("latest", services: services) }
        let latestPrepared = await iterator.next()
        XCTAssertEqual(latestPrepared, "latest")
        release.signal()
        try await blocker.value
        let oldResult = await first.value
        let latestResult = await latest.value
        XCTAssertFalse(oldResult)
        XCTAssertTrue(latestResult)
        XCTAssertEqual(f.trace.get().filter { $0.hasPrefix("write:") }, ["write:latest"])
        signalPrepared.finish()
    }

    private static func input(tun: Bool) -> RuntimeCoordinator.Input {
        .init(systemProxyEnabled: false, tunEnabled: tun, mixedProxyPort: 7890,
              reason: "mock", forceRestart: false, refreshNodeDelays: false)
    }
}

private enum LifecycleFailure: Error { case failed, timedOut }

@MainActor
private final class LifecycleFixture {
    let coordinator = RuntimeCoordinator()
    let trace = LockedValue<[String]>([])
    let requestFile = LockedValue(false)
    var events: [String] = []
    var onWarning: (() -> Void)?

    func stop(disableTun: Bool = true, stopProxy: Bool = true, clearProxy: Bool = true,
              terminating: Bool = true, synchronous: Bool = true) -> Task<Void, Never> {
        let trace = trace
        let requestFile = requestFile
        return coordinator.shutdown(.init(disableTun: disableTun, stopUserProxy: stopProxy, clearSystemProxy: clearProxy,
                                           synchronously: synchronous, isTerminating: terminating), services: .init(
            cancelTasks: { trace.mutate { $0.append("cancel") } },
            disableTun: { requestFile.set(false); trace.mutate { $0.append("disable") } },
            waitForTunStop: { timeout in
                XCTAssertFalse(Thread.isMainThread)
                trace.mutate { $0.append("wait:\(timeout)") }
                return .init(success: false, residue: "mock residue")
            },
            stopUserProxy: { trace.mutate { $0.append("stop") } },
            clearSystemProxy: { trace.mutate { $0.append("clear") } }
        )) { self.record($0) }
    }

    func reloadServices() -> RuntimeCoordinator.ReloadServices {
        let trace = trace
        return .init(discover: { source in
            self.trace.mutate { $0.append("discover:\(source)") }
            return .init(physicalInterface: "mock0", resolvedAddressesByHost: [:])
        }, prepare: { source, _ in
            self.trace.mutate { $0.append("prepare:\(source)") }
            return source
        }, write: { source in trace.mutate { $0.append("write:\(source)") } }, tunEnabled: { true })
    }

    func reload(_ source: String, services: RuntimeCoordinator.ReloadServices? = nil) async -> Bool {
        await coordinator.reloadTun(source: source, services: services ?? reloadServices()) { record($0) }
    }

    func record(_ event: RuntimeCoordinator.LifecycleEvent) {
        switch event {
        case .log(let text): events.append(text)
        case .tunReloaded: events.append("reloaded")
        case .tunStopWarning: events.append("warning"); onWarning?()
        case .shutdownFinished(let refresh): events.append("finished:\(refresh)")
        }
    }
}
