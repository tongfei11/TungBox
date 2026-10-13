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

    init(operations: Operations = Operations()) { self.operations = operations }

    /// New intents never await the operation queue or reject a request because a
    /// previous request is in flight. Its generation immediately becomes stale.
    func begin(_ input: Input) -> Request {
        generation += 1
        operationGeneration.set(generation)
        let request = Request(generation: generation, input: input)
        state.request = request
        return request
    }

    func isCurrent(_ request: Request) -> Bool { state.request == request }

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
        try await operations.perform { [operationGeneration] in
            guard operationGeneration.get() == request.generation else { throw OperationError.superseded }
            return try work()
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
