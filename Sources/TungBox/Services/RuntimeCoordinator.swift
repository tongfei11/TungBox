import Foundation

/// Owns runtime requests, startup/shutdown sequencing and failure handling.
/// Injected services perform OS work; events carry effects back to the UI adapter.
@MainActor
final class RuntimeCoordinator {
    struct Input: Equatable, Sendable {
        let systemProxyEnabled: Bool
        let tunEnabled: Bool
        let mixedProxyPort: Int
        let reason: String
        let forceRestart: Bool
        let refreshNodeDelays: Bool
    }

    struct Request: Equatable, Sendable {
        let generation: Int
        let input: Input
    }

    struct Plan: Sendable {
        let tunNeedsReconcile: Bool
        let userProxyURL: URL?
        let userConfigText: String?
        let startedAt: Date
    }

    struct Switches: Equatable, Sendable {
        let systemProxyEnabled: Bool
        let tunEnabled: Bool
    }

    struct Services {
        var tunStatus: @MainActor () async throws -> TunServiceStatus
        var discoverTunNetwork: @MainActor (String) async throws -> TUNRuntimeConfigBuilder.NetworkSnapshot
        var prepareTunConfig: @MainActor (String, TUNRuntimeConfigBuilder.NetworkSnapshot) throws -> String
        var enableTun: @MainActor (String) async throws -> Void
        var disableTun: @MainActor () throws -> Void
        var waitForTunStop: @Sendable () -> Void
        var verifyTunStartup: @MainActor () -> Task<Bool, Never>
        var userProxyIsRunning: @MainActor () -> Bool
        var stopUserProxy: @MainActor () async throws -> Void
        var startUserProxy: @MainActor (URL) async throws -> Void
        var verifyUserAPI: @MainActor () async throws -> Void
        var applySystemProxy: @MainActor (Bool) async throws -> Void
        var stopUserProxyAndClearSystemProxy: @MainActor () async throws -> Void
        var currentSwitches: @MainActor () -> Switches
    }

    enum Event {
        case log(String)
        case tunResumed, tunStarted, tunWillStop, tunStopped
        case tunFailed(Error), userProxyFailed, reportStartupError(Error)
        case userProxyClosing, shutdownFailed(Error), userProxyReady(Int)
        case restoreSelectors, finished(refreshNodeDelays: Bool)
    }

    enum OperationError: Error { case superseded }

    enum FeatureTransition: Equatable, Sendable { case none, starting, stopping }

    struct State: Equatable, Sendable {
        var request: Request?
        var isTerminating = false
        var hasRequestedTun = false
        var hasRequestedProxy = false
        var systemProxyTransition: FeatureTransition = .none
        var tunTransition: FeatureTransition = .none

        // A switch can already show "off" while its background cleanup is still
        // pending. Keep the operation gate separate from the chip directions.
        var isTransitioning = false
    }

    /// The operation boundary is replaceable without constructing a Runner or
    /// touching the OS. Waiting here suspends the caller; work runs on the queue.
    struct Operations: Sendable {
        private let queue: DispatchQueue

        init(queue: DispatchQueue = DispatchQueue(label: "com.tungbox.runtime")) {
            self.queue = queue
        }

        func perform<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                queue.async {
                    do { continuation.resume(returning: try work()) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }
    }

    private(set) var state = State()
    private(set) var generation = 0
    nonisolated private let operations: Operations
    nonisolated private let operationGeneration = LockedValue(0)
    nonisolated private let terminating = LockedValue(false)
    private var delayedTasks: [UUID: Task<Void, Never>] = [:]
    private var shutdownTask: Task<Void, Never>?
    private var reloadID = UUID()
    nonisolated private let reloadOperationID = LockedValue(UUID())

    init(operations: Operations = Operations()) { self.operations = operations }

    /// New intents never await the operation queue or reject a request because a
    /// previous request is in flight. Its generation immediately becomes stale.
    func begin(_ input: Input) -> Request {
        guard !state.isTerminating else { return Request(generation: generation, input: input) }
        cancelDelayedTasks()
        shutdownTask = nil
        reloadID = UUID()
        generation += 1
        operationGeneration.set(generation)
        let request = Request(generation: generation, input: input)
        state.request = request
        state.hasRequestedTun = state.hasRequestedTun || input.tunEnabled
        state.hasRequestedProxy = state.hasRequestedProxy || input.systemProxyEnabled
        return request
    }

    func isCurrent(_ request: Request) -> Bool { !state.isTerminating && state.request == request }

    func acceptsDeferredResult(generation: Int) -> Bool {
        !state.isTerminating && self.generation == generation
    }

    func beginFeatureTransition(systemProxy: FeatureTransition? = nil, tun: FeatureTransition? = nil) {
        updateFeaturePresentation(systemProxy: systemProxy, tun: tun)
        state.isTransitioning = state.systemProxyTransition != .none || state.tunTransition != .none
    }

    func updateFeaturePresentation(systemProxy: FeatureTransition? = nil, tun: FeatureTransition? = nil) {
        if let systemProxy { state.systemProxyTransition = systemProxy }
        if let tun { state.tunTransition = tun }
    }

    func clearFeatureTransitions() {
        state.systemProxyTransition = .none
        state.tunTransition = .none
        state.isTransitioning = false
    }

    @discardableResult
    func finish(_ request: Request) -> Bool {
        guard isCurrent(request) else { return false }
        clearFeatureTransitions()
        return true
    }

    nonisolated func performBlocking<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await operations.perform(work)
    }

    /// Skip an obsolete operation even if it was already queued behind older work.
    nonisolated func performBlocking<T: Sendable>(for request: Request, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await operations.perform { [operationGeneration, terminating] in
            guard !terminating.get(), operationGeneration.get() == request.generation else { throw OperationError.superseded }
            return try work()
        }
    }

    private func cancelDelayedTasks() {
        delayedTasks.values.forEach { $0.cancel() }
        delayedTasks.removeAll()
    }

    @discardableResult
    func schedule(after seconds: TimeInterval,
                  sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
                  action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        let id = UUID()
        let token = generation
        let task = Task { @MainActor [weak self] in
            defer { self?.delayedTasks.removeValue(forKey: id) }
            guard !Task.isCancelled, self?.acceptsDeferredResult(generation: token) == true else { return }
            do { try await sleep(seconds) } catch { return }
            guard let self, !Task.isCancelled, self.acceptsDeferredResult(generation: token) else { return }
            action()
        }
        if state.isTerminating { task.cancel() }
        else { delayedTasks[id] = task }
        return task
    }

    struct ReloadServices {
        let discover: @MainActor (String) async throws -> TUNRuntimeConfigBuilder.NetworkSnapshot
        let prepare: @MainActor (String, TUNRuntimeConfigBuilder.NetworkSnapshot) throws -> String
        let write: @Sendable (String) throws -> Void
        let tunEnabled: @MainActor () -> Bool
    }

    func reloadTun(source: String, services: ReloadServices, emit: (LifecycleEvent) -> Void) async -> Bool {
        guard !state.isTerminating, services.tunEnabled() else { return false }
        cancelDelayedTasks()
        reloadID = UUID()
        let id = reloadID
        reloadOperationID.set(id)
        let token = generation
        func current() -> Bool {
            !Task.isCancelled && reloadID == id && acceptsDeferredResult(generation: token) && services.tunEnabled()
        }
        do {
            let network = try await services.discover(source)
            guard current() else { return false }
            let prepared = try services.prepare(source, network)
            let write = services.write
            try await operations.perform { [operationGeneration, terminating, reloadOperationID] in
                guard !terminating.get(), operationGeneration.get() == token, reloadOperationID.get() == id else {
                    throw OperationError.superseded
                }
                try write(prepared)
            }
            guard current() else { return false }
            emit(.tunReloaded)
            emit(.log("[节点] 已请求 TUN 热重载新节点配置\n"))
            return true
        } catch {
            guard current() else { return false }
            emit(.log("[节点] TUN 配置热重载失败（保持当前运行不变）：\(error.localizedDescription)\n"))
            return false
        }
    }

    struct ShutdownPlan: Sendable {
        let disableTun: Bool
        let stopUserProxy: Bool
        let clearSystemProxy: Bool
        let synchronously: Bool
        let isTerminating: Bool
    }

    struct TunStopResult: Sendable { let success: Bool; let residue: String }

    struct ShutdownServices: Sendable {
        let cancelTasks: @MainActor @Sendable () -> Void
        let disableTun: @Sendable () throws -> Void
        let waitForTunStop: @Sendable (TimeInterval) -> TunStopResult
        let stopUserProxy: @Sendable () -> Void
        let clearSystemProxy: @Sendable () -> Void
    }

    enum LifecycleEvent {
        case log(String), tunReloaded, tunStopWarning
        case shutdownFinished(refreshStatus: Bool)
    }

    @discardableResult
    func shutdown(_ plan: ShutdownPlan, services: ShutdownServices,
                  emit: @escaping @MainActor (LifecycleEvent) -> Void) -> Task<Void, Never> {
        if let shutdownTask, !plan.isTerminating || state.isTerminating { return shutdownTask }
        generation += 1
        let token = generation
        operationGeneration.set(token)
        state.request = nil
        state.isTerminating = plan.isTerminating
        terminating.set(plan.isTerminating)
        reloadID = UUID()
        cancelDelayedTasks()
        clearFeatureTransitions()
        services.cancelTasks()
        if plan.disableTun {
            try? services.disableTun()
            emit(.log("[TungBox] TUN 标记已关闭\n"))
            if plan.isTerminating { emit(.log("[TungBox] 退出：已交由后台守护进程回收 TUN\n")) }
        }
        let task = Task { @MainActor [self] in
            // Drain already-running startup work, then repeat removal so a late
            // enable cannot recreate the TUN request after shutdown's first delete.
            _ = try? await operations.perform { [operationGeneration] in
                guard operationGeneration.get() == token else { return }
                if plan.disableTun { try? services.disableTun() }
            }
            guard generation == token else { return }
            if plan.disableTun, !plan.isTerminating, plan.synchronously {
                let result = try? await operations.perform { services.waitForTunStop(8) }
                guard generation == token else { return }
                if let result { reportTunStop(result, synchronous: true, emit: emit) }
            }
            _ = try? await operations.perform { [operationGeneration] in
                guard operationGeneration.get() == token else { return }
                if plan.stopUserProxy { services.stopUserProxy() }
                if plan.clearSystemProxy { services.clearSystemProxy() }
            }
            guard generation == token else { return }
            if plan.stopUserProxy { emit(.log("[TungBox] sing-box 已停止\n")) }
            if plan.clearSystemProxy { emit(.log("[TungBox] 系统代理已关闭\n")) }
            if plan.disableTun, !plan.isTerminating, !plan.synchronously {
                emit(.log("[TungBox] 正在后台等待回收 TUN 网卡...\n"))
                Task { @MainActor [weak self] in
                    let result = await Task.detached { services.waitForTunStop(6) }.value
                    guard let self, self.acceptsDeferredResult(generation: token) else { return }
                    self.reportTunStop(result, synchronous: false, emit: emit)
                }
            }
            emit(.shutdownFinished(refreshStatus: !plan.isTerminating))
        }
        shutdownTask = task
        return task
    }

    private func reportTunStop(_ result: TunStopResult, synchronous: Bool, emit: (LifecycleEvent) -> Void) {
        if result.success { emit(.log("[TungBox] TUN 已确认回收\n")) }
        else {
            let timing = synchronous ? "未在 8 秒内确认回收" : "未能在后台确认回收"
            emit(.log("[警告] TUN \(timing)：\(result.residue)。请到设置重新安装 TUN 服务以更新安全停机脚本。\n"))
            emit(.tunStopWarning)
        }
    }

    func converge(_ request: Request, plan: Plan, services: Services, emit: (Event) -> Void) async {
        func current() -> Bool { !Task.isCancelled && isCurrent(request) }
        guard current() else { return }
        let input = request.input
        var tunStartup: Task<Bool, Never>?

        // TUN and the user proxy are independent. Preserve TUN-first ordering,
        // but do not rebuild an existing TUN request when only proxy state changes.
        if input.tunEnabled {
            if !plan.tunNeedsReconcile {
                emit(.tunResumed)
                tunStartup = services.verifyTunStartup()
                emit(.log("[TungBox] TUN 已在运行，系统代理切换不重启 TUN\n"))
            } else {
                do {
                    let status = try await services.tunStatus()
                    guard current() else { return }
                    guard status.isUsable else {
                        throw NSError.user("TUN 服务不可用：\(status.displayText)。请到 设置 > TUN 设置处理。")
                    }
                    guard let source = plan.userConfigText else { throw NSError.user("缺少 TUN 启动配置") }
                    let discoveryStarted = Date()
                    let network = try await services.discoverTunNetwork(source)
                    guard current() else { return }
                    emit(.log("[性能] TUN 后台出口探测：\(Int(Date().timeIntervalSince(discoveryStarted) * 1000)) ms\n"))
                    let prepared = try services.prepareTunConfig(source, network)
                    try await services.enableTun(prepared)
                    guard current() else { return }
                    emit(.tunStarted)
                    tunStartup = services.verifyTunStartup()
                    emit(.log("[TungBox] TUN 已启用（\(input.reason)）\n"))
                } catch {
                    guard current() else { return }
                    emit(.log("[TungBox] TUN 启用失败（\(input.reason)）：\(error.localizedDescription)\n"))
                    emit(.tunFailed(error))
                }
            }
        } else {
            emit(.tunWillStop)
            try? services.disableTun()
            emit(.tunStopped)
            emit(.log("[TungBox] TUN 已关闭（守护进程后台回收 utun29 与 DNS）\n"))
            let wait = services.waitForTunStop
            Task.detached { wait() }
        }
        guard current() else { return }

        if input.systemProxyEnabled {
            do {
                if input.forceRestart {
                    try await services.stopUserProxy()
                    guard current() else { return }
                }
                if !services.userProxyIsRunning(), let url = plan.userProxyURL {
                    try await services.startUserProxy(url)
                    guard current() else { return }
                }
                guard current() else { return }
                try await services.verifyUserAPI()
                guard current() else { return }
                try await services.applySystemProxy(true)
                guard current() else { return }
                emit(.userProxyReady(input.mixedProxyPort))
            } catch {
                guard current() else { return }
                emit(.log("[TungBox] 系统代理启动失败（\(input.reason)）：\(error.localizedDescription)\n"))
                emit(.userProxyFailed)
                try? await services.stopUserProxy()
                guard current() else { return }
                try? await services.applySystemProxy(false)
                guard current() else { return }
                emit(.reportStartupError(error))
            }
        } else {
            // Off is visible immediately, even while queued OS cleanup is pending.
            emit(.userProxyClosing)
            do {
                try await services.stopUserProxyAndClearSystemProxy()
                guard current() else { return }
            } catch {
                guard current() else { return }
                emit(.log("[TungBox] 系统代理关闭失败（\(input.reason)）：\(error.localizedDescription)\n"))
                clearFeatureTransitions()
                emit(.shutdownFailed(error))
                return
            }
        }

        let readyForTest = await NodeDelayTestPolicy.runtimeIsReady(tunStartup: tunStartup) {
            let switches = services.currentSwitches()
            return current() && switches.systemProxyEnabled == input.systemProxyEnabled && switches.tunEnabled == input.tunEnabled
        }
        guard current() else { return }
        emit(.log("[性能] 运行状态切换完成（\(input.reason)）：\(Int(Date().timeIntervalSince(plan.startedAt) * 1000)) ms，UI 保持异步\n"))
        emit(.restoreSelectors)
        guard finish(request) else { return }
        emit(.finished(refreshNodeDelays: input.refreshNodeDelays && readyForTest))
    }
}
