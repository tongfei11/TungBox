import Foundation
import XCTest
@testable import TungBox

final class RuleSetCacheRequestsTests: XCTestCase {
    @MainActor func testNewRequestAndClearInvalidateOldResults() {
        let state = RuleSetCacheRequests()
        let rows = state.beginRows()
        XCTAssertTrue(state.isCurrentRows(rows))
        _ = state.beginRows()
        XCTAssertFalse(state.isCurrentRows(rows))
        let old = state.begin(tag: "cn")
        let latest = state.begin(tag: "cn")
        XCTAssertFalse(state.finish(tag: "cn", request: old))
        XCTAssertTrue(state.finish(tag: "cn", request: latest))
        let pending = state.begin(tag: "cn")
        let pendingRows = state.beginRows()
        state.invalidate()
        XCTAssertFalse(state.isCurrentRows(pendingRows))
        XCTAssertFalse(state.finish(tag: "cn", request: pending))
    }

    @MainActor func testManualRefreshReportsOnlyCompletedCurrentBatch() {
        let state = RuleSetCacheRequests()
        state.beginManualRefresh()
        let old = UUID()
        state.trackManual(old)
        state.beginManualRefresh()
        let first = UUID(), second = UUID(), stale = UUID()
        for request in [first, second, stale] { state.trackManual(request) }
        XCTAssertNil(state.completeManual(old, succeeded: true))
        XCTAssertNil(state.completeManual(first, succeeded: true))
        XCTAssertNil(state.completeManual(second, succeeded: false))
        XCTAssertEqual(state.completeManual(stale, succeeded: false, discarded: true),
                       .init(succeeded: 1, failed: 1, discarded: 1))
        XCTAssertNil(state.completeManual(first, succeeded: true))
        state.beginManualRefresh()
        state.trackManual(old)
        state.invalidate()
        XCTAssertNil(state.completeManual(old, succeeded: true))
    }

    @MainActor func testPublicationFailureRestoresBothCaches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let srs = root.appendingPathComponent("cn.srs")
        let json = root.appendingPathComponent("cn.json")
        let downloaded = root.appendingPathComponent("new.srs")
        try Data("old-srs".utf8).write(to: srs)
        try Data("old-json".utf8).write(to: json)
        try Data("new-srs".utf8).write(to: downloaded)
        XCTAssertThrowsError(try RuleSetCacheRequests.publish(srs: downloaded, json: root.appendingPathComponent("missing.json"), toSRS: srs, toJSON: json))
        XCTAssertEqual(try Data(contentsOf: srs), Data("old-srs".utf8))
        XCTAssertEqual(try Data(contentsOf: json), Data("old-json".utf8))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".backup-") })
        try Data("new-srs".utf8).write(to: downloaded)
        let extracted = root.appendingPathComponent("new.json")
        try Data("new-json".utf8).write(to: extracted)
        try RuleSetCacheRequests.publish(srs: downloaded, json: extracted, toSRS: srs, toJSON: json)
        XCTAssertEqual(try Data(contentsOf: srs), Data("new-srs".utf8))
        XCTAssertEqual(try Data(contentsOf: json), Data("new-json".utf8))
    }
}
