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
