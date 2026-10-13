import Foundation

/// Owns runtime requests, transition presentation and blocking-operation dispatch.
/// Core/TUN/proxy startup and failure handling are still performed by the caller.
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

    init(operations: Operations = Operations()) { self.operations = operations }

    /// New intents never await the operation queue or reject a request because a
    /// previous request is in flight. Its generation immediately becomes stale.
    func begin(_ input: Input) -> Request {
        generation += 1
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
}
