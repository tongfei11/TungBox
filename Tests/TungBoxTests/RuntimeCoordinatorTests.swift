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

extension RuntimeCoordinatorTests {
    @MainActor
    func testProxyOnlyStartupKeepsDisableStartAuthenticateApplyOrder() async {
        let f = RuntimeFlowFixture()
        await f.run(f.request(systemProxy: true, tun: false))
        XCTAssertEqual(f.calls, ["heartbeat:stop", "disableTun", "tun:stopped", "startUser", "verifyUser", "apply:true", "proxy:ready", "restore", "finish:true"])
    }

    @MainActor
    func testTunOnlyStartupKeepsDiscoveryBeforeEnableAndClearsUserProxy() async {
        let f = RuntimeFlowFixture()
        await f.run(f.request(systemProxy: false, tun: true))
        XCTAssertEqual(f.calls, ["status", "network", "prepare", "enableTun", "heartbeat:new", "verifyTun", "proxy:closing", "stopAndClear", "restore", "finish:true"])
    }

    @MainActor
    func testBothSwitchesStartIndependentCoresInExistingOrder() async {
        let f = RuntimeFlowFixture()
        await f.run(f.request(systemProxy: true, tun: true))
        XCTAssertEqual(f.calls, ["status", "network", "prepare", "enableTun", "heartbeat:new", "verifyTun", "startUser", "verifyUser", "apply:true", "proxy:ready", "restore", "finish:true"])
    }

    @MainActor
    func testBothOffCompletesWithoutStartupOrOptionalDelayRefresh() async {
        let f = RuntimeFlowFixture()
        await f.run(f.request(systemProxy: false, tun: false, refresh: false))
        XCTAssertEqual(f.calls, ["heartbeat:stop", "disableTun", "tun:stopped", "proxy:closing", "stopAndClear", "restore", "finish:false"])
        XCTAssertFalse(f.coordinator.state.isTransitioning)
    }

    @MainActor
    func testExistingTunRequestResumesHeartbeatWithoutRebuild() async {
        let f = RuntimeFlowFixture()
        await f.run(f.request(systemProxy: true, tun: true), needsTun: false)
        XCTAssertEqual(f.calls, ["heartbeat:resume", "verifyTun", "startUser", "verifyUser", "apply:true", "proxy:ready", "restore", "finish:true"])
    }

    @MainActor
    func testRunningUserProxyOnlyRestartsForExplicitForce() async {
        for force in [false, true] {
            let f = RuntimeFlowFixture()
            f.userRunning = true
            await f.run(f.request(systemProxy: true, tun: false, force: force))
            XCTAssertEqual(f.calls.filter { ["stopUser", "startUser", "verifyUser", "apply:true"].contains($0) }, force ? ["stopUser", "startUser", "verifyUser", "apply:true"] : ["verifyUser", "apply:true"])
        }
    }

    @MainActor
    func testTunFailureDoesNotStopIndependentProxyOrStartDelayRefresh() async {
        let f = RuntimeFlowFixture()
        var services = f.services()
        services.tunStatus = { f.calls.append("status"); return .notInstalled }
        await f.run(f.request(systemProxy: true, tun: true), services: services)
        XCTAssertEqual(f.calls, ["status", "tun:failed", "startUser", "verifyUser", "apply:true", "proxy:ready", "restore", "finish:false"])
        XCTAssertFalse(f.switches.tunEnabled)
        XCTAssertTrue(f.switches.systemProxyEnabled)
        XCTAssertTrue(f.logs.joined().contains("TUN 服务不可用：未安装"))
    }

    @MainActor
    func testProxyAuthenticationFailureKeepsTunAndPerformsExistingCleanup() async {
        let f = RuntimeFlowFixture()
        var services = f.services()
        services.verifyUserAPI = { f.calls.append("verifyUser"); throw MockFailure.failed }
        await f.run(f.request(systemProxy: true, tun: true), needsTun: false, services: services)
        XCTAssertEqual(f.calls, ["heartbeat:resume", "verifyTun", "startUser", "verifyUser", "proxy:failed", "stopUser", "apply:false", "reportError", "restore", "finish:false"])
        XCTAssertTrue(f.switches.tunEnabled)
        XCTAssertFalse(f.switches.systemProxyEnabled)
    }

    @MainActor
    func testProxyShutdownFailureStopsCompletionAndClearsTransitionState() async {
        let f = RuntimeFlowFixture()
        var services = f.services()
        services.stopUserProxyAndClearSystemProxy = { f.calls.append("stopAndClear"); throw MockFailure.failed }
        await f.run(f.request(systemProxy: false, tun: false), services: services)
        XCTAssertEqual(f.calls, ["heartbeat:stop", "disableTun", "tun:stopped", "proxy:closing", "stopAndClear", "shutdownError"])
        XCTAssertFalse(f.coordinator.state.isTransitioning)
    }

    @MainActor
    func testLateAuthenticationCannotReenableProxyAfterNewOffIntent() async {
        let f = RuntimeFlowFixture()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        var services = f.services()
        services.verifyUserAPI = {
            f.calls.append("verifyUser")
            signal.yield(()); signal.finish()
            var iterator = release.makeAsyncIterator()
            _ = await iterator.next()
        }
        let old = f.request(systemProxy: true, tun: false)
        let task = Task { [services] in await f.run(old, services: services) }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        let current = f.request(systemProxy: false, tun: false)
        resume.yield(()); resume.finish()
        await task.value
        XCTAssertFalse(f.calls.contains("apply:true"))
        XCTAssertFalse(f.calls.contains("proxy:ready"))
        XCTAssertFalse(f.calls.contains { $0.hasPrefix("finish:") })
        XCTAssertTrue(f.coordinator.isCurrent(current))
        XCTAssertEqual(f.coordinator.state.systemProxyTransition, .stopping)
    }

    @MainActor
    func testLateFailureCleanupCannotClearNewOnIntent() async {
        let f = RuntimeFlowFixture()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        var services = f.services()
        services.verifyUserAPI = { throw MockFailure.failed }
        services.stopUserProxy = {
            f.calls.append("stopUser")
            signal.yield(()); signal.finish()
            var iterator = release.makeAsyncIterator()
            _ = await iterator.next()
        }
        let old = f.request(systemProxy: true, tun: false)
        let task = Task { [services] in await f.run(old, services: services) }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        let current = f.request(systemProxy: true, tun: true)
        resume.yield(()); resume.finish()
        await task.value
        XCTAssertFalse(f.calls.contains("apply:false"))
        XCTAssertFalse(f.calls.contains("reportError"))
        XCTAssertTrue(f.coordinator.isCurrent(current))
        XCTAssertTrue(f.switches.systemProxyEnabled)
    }

    @MainActor
    func testLateTunEnableCannotPublishStartedOrFailureForNewRequest() async {
        for shouldFail in [false, true] {
            let f = RuntimeFlowFixture()
            let (started, signal) = AsyncStream<Void>.makeStream()
            let (release, resume) = AsyncStream<Void>.makeStream()
            var services = f.services()
            services.enableTun = { _ in
                f.calls.append("enableTun")
                signal.yield(()); signal.finish()
                var iterator = release.makeAsyncIterator()
                _ = await iterator.next()
                if shouldFail { throw MockFailure.failed }
            }
            let old = f.request(systemProxy: false, tun: true)
            let task = Task { [services] in await f.run(old, services: services) }
            var iterator = started.makeAsyncIterator()
            _ = await iterator.next()
            let current = f.request(systemProxy: true, tun: false)
            resume.yield(()); resume.finish()
            await task.value
            XCTAssertFalse(f.calls.contains("heartbeat:new"))
            XCTAssertFalse(f.calls.contains("tun:failed"))
            XCTAssertFalse(f.calls.contains("verifyTun"))
            XCTAssertTrue(f.coordinator.isCurrent(current))
            XCTAssertTrue(f.switches.systemProxyEnabled)
            XCTAssertFalse(f.switches.tunEnabled)
        }
    }

    @MainActor
    func testTunReadinessIsAwaitedAndFailedReadinessDoesNotStartDelayRefresh() async {
        let f = RuntimeFlowFixture()
        let (ready, signal) = AsyncStream<Bool>.makeStream()
        let startup = Task {
            var iterator = ready.makeAsyncIterator()
            return await iterator.next() ?? false
        }
        var services = f.services()
        services.verifyTunStartup = { f.calls.append("verifyTun"); return startup }
        let request = f.request(systemProxy: false, tun: true)
        let task = Task { [services] in await f.run(request, services: services) }
        // A yield gives the main-actor flow a chance to reach the readiness await.
        await Task.yield()
        XCTAssertFalse(f.calls.contains { $0.hasPrefix("finish:") })
        signal.yield(false); signal.finish()
        await task.value
        XCTAssertEqual(f.calls.last, "finish:false")
    }

    @MainActor
    func testTunShutdownWaitDoesNotDelayUserProxyOrSwitchIntent() async {
        let f = RuntimeFlowFixture()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        var services = f.services()
        services.waitForTunStop = {
            signal.yield(()); signal.finish()
            _ = release.wait(timeout: .now() + 2)
        }
        await f.run(f.request(systemProxy: true, tun: false), services: services)
        XCTAssertEqual(f.calls.last, "finish:true", "不等待 TUN 回收才启动独立用户代理")
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        let current = f.request(systemProxy: false, tun: true)
        XCTAssertTrue(f.coordinator.isCurrent(current))
        release.signal()
    }

    @MainActor
    func testQueuedObsoleteSystemOperationIsSkippedBeforeSideEffects() async throws {
        let coordinator = RuntimeCoordinator()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let ran = LockedValue(false)
        let blocker = Task {
            try await coordinator.performBlocking {
                signal.yield(()); signal.finish()
                guard release.wait(timeout: .now() + 2) == .success else { throw MockFailure.timedOut }
                return true
            }
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        let old = coordinator.begin(input(systemProxy: false, tun: false))
        let queued = Task { try await coordinator.performBlocking(for: old) { ran.set(true) } }
        _ = coordinator.begin(input(systemProxy: true, tun: false))
        release.signal()
        _ = try await blocker.value
        do { try await queued.value; XCTFail("过时操作必须跳过") }
        catch { XCTAssertTrue(error is RuntimeCoordinator.OperationError) }
        XCTAssertFalse(ran.get())
    }
}

@MainActor
private final class RuntimeFlowFixture {
    let coordinator = RuntimeCoordinator()
    var calls: [String] = []
    var logs: [String] = []
    var userRunning = false
    var switches = RuntimeCoordinator.Switches(systemProxyEnabled: false, tunEnabled: false)

    func request(systemProxy: Bool, tun: Bool, force: Bool = false, refresh: Bool = true) -> RuntimeCoordinator.Request {
        switches = .init(systemProxyEnabled: systemProxy, tunEnabled: tun)
        coordinator.beginFeatureTransition(systemProxy: systemProxy ? .starting : .stopping, tun: tun ? .starting : .stopping)
        return coordinator.begin(.init(systemProxyEnabled: systemProxy, tunEnabled: tun, mixedProxyPort: 8123,
                                       reason: "mock", forceRestart: force, refreshNodeDelays: refresh))
    }

    func services() -> RuntimeCoordinator.Services {
        .init(
            tunStatus: { self.calls.append("status"); return .installedIdle },
            discoverTunNetwork: { _ in self.calls.append("network"); return .init(physicalInterface: "mock0", resolvedAddressesByHost: [:]) },
            prepareTunConfig: { _, _ in self.calls.append("prepare"); return "prepared mock" },
            enableTun: { _ in self.calls.append("enableTun") },
            disableTun: { self.calls.append("disableTun") },
            waitForTunStop: {},
            verifyTunStartup: { self.calls.append("verifyTun"); return Task { true } },
            userProxyIsRunning: { self.userRunning },
            stopUserProxy: { self.calls.append("stopUser"); self.userRunning = false },
            startUserProxy: { _ in self.calls.append("startUser"); self.userRunning = true },
            verifyUserAPI: { self.calls.append("verifyUser") },
            applySystemProxy: { self.calls.append("apply:\($0)") },
            stopUserProxyAndClearSystemProxy: { self.calls.append("stopAndClear"); self.userRunning = false },
            restoreSelectors: { self.calls.append("restore") },
            currentSwitches: { self.switches }
        )
    }

    func run(_ request: RuntimeCoordinator.Request, needsTun: Bool = true, services: RuntimeCoordinator.Services? = nil) async {
        let plan = RuntimeCoordinator.Plan(tunNeedsReconcile: needsTun, userProxyURL: URL(fileURLWithPath: "/mock/config.json"),
                                           userConfigText: "mock config", startedAt: Date())
        await coordinator.converge(request, plan: plan, services: services ?? self.services()) { event in
            switch event {
            case .log(let text): self.logs.append(text)
            case .tunResumed: self.calls.append("heartbeat:resume")
            case .tunStarted: self.calls.append("heartbeat:new")
            case .tunWillStop: self.calls.append("heartbeat:stop")
            case .tunStopped: self.calls.append("tun:stopped")
            case .tunFailed:
                self.calls.append("tun:failed")
                self.switches = .init(systemProxyEnabled: self.switches.systemProxyEnabled, tunEnabled: false)
            case .userProxyFailed:
                self.calls.append("proxy:failed")
                self.switches = .init(systemProxyEnabled: false, tunEnabled: self.switches.tunEnabled)
            case .reportStartupError: self.calls.append("reportError")
            case .userProxyClosing: self.calls.append("proxy:closing")
            case .shutdownFailed: self.calls.append("shutdownError")
            case .userProxyReady: self.calls.append("proxy:ready")
            case .finished(let refresh): self.calls.append("finish:\(refresh)")
            }
        }
    }
}
