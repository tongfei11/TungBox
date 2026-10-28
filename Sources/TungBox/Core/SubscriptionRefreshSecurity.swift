import Foundation

struct SubscriptionRefreshToken: Equatable, Sendable {
    let subscriptionID: UUID
    let url: String
    let generation: UInt64
}

struct SubscriptionRefreshTracker {
    private var generations: [UUID: UInt64] = [:]

    mutating func begin(subscriptionID: UUID, url: String) -> SubscriptionRefreshToken {
        let next = (generations[subscriptionID] ?? 0) &+ 1
        generations[subscriptionID] = next
        return SubscriptionRefreshToken(subscriptionID: subscriptionID, url: url, generation: next)
    }

    mutating func invalidate(subscriptionID: UUID) {
        generations[subscriptionID] = (generations[subscriptionID] ?? 0) &+ 1
    }

    func isCurrent(_ token: SubscriptionRefreshToken, currentURL: String?) -> Bool {
        token.url == currentURL && generations[token.subscriptionID] == token.generation
    }
}

/// Keep the proxy serving a whole automatic download batch. A refreshed active
/// subscription may request one reload once every download has returned, unless
/// a newer switch or subscription selection has superseded that runtime intent.
struct SubscriptionRefreshBatch {
    private var pending: Set<UUID> = []
    private var deferredReloads: [UUID: Int] = [:]

    var isActive: Bool { !pending.isEmpty }

    mutating func begin(subscriptionIDs: [UUID]) -> Bool {
        guard !isActive, !subscriptionIDs.isEmpty else { return false }
        pending = Set(subscriptionIDs)
        deferredReloads = [:]
        return true
    }

    /// Manual refreshes during a batch also leave its download transport intact.
    mutating func deferReload(subscriptionID: UUID, runtimeGeneration: Int) -> Bool {
        guard isActive else { return false }
        deferredReloads[subscriptionID] = runtimeGeneration
        return true
    }

    /// nil means downloads remain. Both successful and failed/stale responses
    /// must finish their slot; only the latest current runtime may be reloaded.
    mutating func finish(subscriptionID: UUID, currentSubscriptionID: UUID?, runtimeGeneration: Int) -> Bool? {
        guard pending.remove(subscriptionID) != nil, pending.isEmpty else { return nil }
        let shouldReload = currentSubscriptionID.flatMap { deferredReloads[$0] } == runtimeGeneration
        deferredReloads = [:]
        return shouldReload
    }
}
