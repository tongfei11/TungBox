import Foundation
import XCTest
@testable import TungBox

final class SubscriptionRefreshSecurityTests: XCTestCase {
    func testDeletedSubscriptionRejectsLateResponseAfterArrayMoves() {
        let firstID = UUID()
        let secondID = UUID()
        var subscriptions = [
            (id: firstID, url: "https://example.com/a"),
            (id: secondID, url: "https://example.com/b")
        ]
        var tracker = SubscriptionRefreshTracker()
        let token = tracker.begin(subscriptionID: firstID, url: subscriptions[0].url)

        subscriptions.removeFirst()
        let currentURL = subscriptions.first(where: { $0.id == token.subscriptionID })?.url

        XCTAssertEqual(subscriptions[0].id, secondID)
        XCTAssertFalse(tracker.isCurrent(token, currentURL: currentURL))
    }

    func testReorderingDoesNotInvalidateIdentityBoundResponse() {
        let id = UUID()
        var subscriptions = [
            (id: UUID(), url: "https://example.com/other"),
            (id: id, url: "https://example.com/a")
        ]
        var tracker = SubscriptionRefreshTracker()
        let token = tracker.begin(subscriptionID: id, url: subscriptions[1].url)

        subscriptions.swapAt(0, 1)
        let currentURL = subscriptions.first(where: { $0.id == token.subscriptionID })?.url

        XCTAssertTrue(tracker.isCurrent(token, currentURL: currentURL))
    }

    func testURLChangeAndNewerRefreshRejectOldResponse() {
        let id = UUID()
        var tracker = SubscriptionRefreshTracker()
        let first = tracker.begin(subscriptionID: id, url: "https://example.com/a")

        XCTAssertFalse(tracker.isCurrent(first, currentURL: "https://example.com/b"))

        let second = tracker.begin(subscriptionID: id, url: "https://example.com/b")
        XCTAssertFalse(tracker.isCurrent(first, currentURL: "https://example.com/a"))
        XCTAssertTrue(tracker.isCurrent(second, currentURL: "https://example.com/b"))

        tracker.invalidate(subscriptionID: id)
        XCTAssertFalse(tracker.isCurrent(second, currentURL: "https://example.com/b"))
    }
}
