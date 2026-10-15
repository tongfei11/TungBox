import Foundation
import XCTest
@testable import TungBox

final class SubscriptionRefreshBatchTests: XCTestCase {
    func testActiveSubscriptionFinishingFirstKeepsProxyAliveForOtherDownloads() {
        let active = UUID(), second = UUID(), third = UUID(), fourth = UUID()
        var batch = SubscriptionRefreshBatch()
        XCTAssertTrue(batch.begin(subscriptionIDs: [active, second, third, fourth]))
        XCTAssertTrue(batch.deferReload(subscriptionID: active, runtimeGeneration: 7))

        var proxyRunning = true
        var reloadCount = 0
        func complete(_ id: UUID) {
            XCTAssertTrue(proxyRunning, "其他订阅下载期间不能因当前订阅完成而重启代理")
            if batch.finish(subscriptionID: id, currentSubscriptionID: active, runtimeGeneration: 7) == true {
                proxyRunning = false
                reloadCount += 1
            }
        }
        complete(active)
        complete(second)
        complete(third)
        XCTAssertEqual(reloadCount, 0)
        complete(fourth)
        XCTAssertEqual(reloadCount, 1)
        XCTAssertFalse(batch.isActive)
        XCTAssertNil(batch.finish(subscriptionID: fourth, currentSubscriptionID: active, runtimeGeneration: 7))
    }

    func testFailedDeletedOrStaleResponsesStillReleaseTheirBatchSlots() {
        let active = UUID(), failed = UUID(), deleted = UUID()
        var batch = SubscriptionRefreshBatch()
        XCTAssertTrue(batch.begin(subscriptionIDs: [active, failed, deleted]))
        XCTAssertTrue(batch.deferReload(subscriptionID: active, runtimeGeneration: 1))
        XCTAssertNil(batch.finish(subscriptionID: active, currentSubscriptionID: active, runtimeGeneration: 1))
        XCTAssertNil(batch.finish(subscriptionID: failed, currentSubscriptionID: active, runtimeGeneration: 1))
        XCTAssertEqual(batch.finish(subscriptionID: deleted, currentSubscriptionID: active, runtimeGeneration: 1), true)
        XCTAssertTrue(batch.begin(subscriptionIDs: [active]), "失败不得卡住后续自动刷新")
        XCTAssertEqual(batch.finish(subscriptionID: active, currentSubscriptionID: active, runtimeGeneration: 1), false,
                       "当前订阅失败、没有成功更新时不应重启")
    }

    func testNewSwitchIntentSupersedesDeferredAutomaticReload() {
        let active = UUID()
        var batch = SubscriptionRefreshBatch()
        XCTAssertTrue(batch.begin(subscriptionIDs: [active]))
        XCTAssertTrue(batch.deferReload(subscriptionID: active, runtimeGeneration: 4))
        XCTAssertEqual(batch.finish(subscriptionID: active, currentSubscriptionID: active, runtimeGeneration: 5), false,
                       "用户的新开关意图优先，不执行旧自动刷新的重启请求")
    }

    func testSwitchingSubscriptionOrDeletingSelectionDoesNotApplyOldDeferredReload() {
        for current in [UUID(), nil] as [UUID?] {
            let active = UUID()
            var batch = SubscriptionRefreshBatch()
            XCTAssertTrue(batch.begin(subscriptionIDs: [active]))
            XCTAssertTrue(batch.deferReload(subscriptionID: active, runtimeGeneration: 1))
            XCTAssertEqual(batch.finish(subscriptionID: active, currentSubscriptionID: current, runtimeGeneration: 1), false)
        }
    }

    func testManualRefreshDuringAutomaticBatchAlsoDefersItsRestart() {
        let active = UUID(), downloading = UUID()
        var batch = SubscriptionRefreshBatch()
        XCTAssertTrue(batch.begin(subscriptionIDs: [downloading]))
        XCTAssertTrue(batch.deferReload(subscriptionID: active, runtimeGeneration: 3))
        XCTAssertEqual(batch.finish(subscriptionID: downloading, currentSubscriptionID: active, runtimeGeneration: 3), true)
        XCTAssertFalse(batch.deferReload(subscriptionID: active, runtimeGeneration: 3),
                       "没有自动下载时手动刷新仍可立即应用")
    }

    func testOverlappingTimerDoesNotReplacePendingBatchOrLoseItsReload() {
        let active = UUID(), other = UUID()
        var batch = SubscriptionRefreshBatch()
        XCTAssertFalse(batch.begin(subscriptionIDs: []))
        XCTAssertTrue(batch.begin(subscriptionIDs: [active]))
        XCTAssertTrue(batch.deferReload(subscriptionID: active, runtimeGeneration: 2))
        XCTAssertFalse(batch.begin(subscriptionIDs: [other]))
        XCTAssertNil(batch.finish(subscriptionID: other, currentSubscriptionID: active, runtimeGeneration: 2))
        XCTAssertEqual(batch.finish(subscriptionID: active, currentSubscriptionID: active, runtimeGeneration: 2), true)
    }

    func testLatestSuccessfulManualRefreshReplacesOlderDeferredRuntimeGeneration() {
        let active = UUID()
        var batch = SubscriptionRefreshBatch()
        XCTAssertTrue(batch.begin(subscriptionIDs: [active]))
        XCTAssertTrue(batch.deferReload(subscriptionID: active, runtimeGeneration: 2))
        XCTAssertTrue(batch.deferReload(subscriptionID: active, runtimeGeneration: 3))
        XCTAssertEqual(batch.finish(subscriptionID: active, currentSubscriptionID: active, runtimeGeneration: 3), true)
    }
}
