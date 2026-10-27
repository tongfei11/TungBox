import XCTest
@testable import TungBox

final class TUNSettingsUpdateTests: XCTestCase {
    @MainActor
    func testBusySwitchOrTransactionDefersWithoutReloading() async {
        var calls = 0
        let result = await TUNSettingsUpdate.apply(isCurrent: { true }, isBusy: { true }, tunEnabled: { true }, reload: { calls += 1; return true })
        XCTAssertEqual(result, .deferred)
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testDisabledTunOnlySavesSettings() async {
        var calls = 0
        let result = await TUNSettingsUpdate.apply(isCurrent: { true }, isBusy: { false }, tunEnabled: { false }, reload: { calls += 1; return true })
        XCTAssertEqual(result, .saved)
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testEnabledTunUsesReloadAndReportsRequest() async {
        var calls = 0
        let result = await TUNSettingsUpdate.apply(isCurrent: { true }, isBusy: { false }, tunEnabled: { true }, reload: { calls += 1; return true })
        XCTAssertEqual(result, .reloadRequested)
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testNewSwitchIntentDuringReloadDiscardsLateResult() async {
        var generation = 1
        let result = await TUNSettingsUpdate.apply(isCurrent: { generation == 1 }, isBusy: { false }, tunEnabled: { true }, reload: { generation = 2; return true })
        XCTAssertEqual(result, .superseded)
    }

    @MainActor
    func testFailedReloadIsNotReportedAsApplied() async {
        let result = await TUNSettingsUpdate.apply(isCurrent: { true }, isBusy: { false }, tunEnabled: { true }, reload: { false })
        XCTAssertEqual(result, .failed)
    }
}
