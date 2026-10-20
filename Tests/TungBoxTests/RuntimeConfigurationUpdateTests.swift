import XCTest
@testable import TungBox

final class RuntimeConfigurationUpdateTests: XCTestCase {
    private enum Failure: Error { case update }

    @MainActor
    func testBothRuntimesReceiveUpdate() async throws {
        var events: [String] = []
        let applied = try await RuntimeConfigurationUpdate.apply(tun: true, proxy: true, services: .init(
            current: { true }, updateTun: { events.append("tun") },
            updateProxy: { events.append("proxy") }, restoreTun: { events.append("restore") }))
        XCTAssertTrue(applied)
        XCTAssertEqual(events, ["tun", "proxy"])
    }

    @MainActor
    func testProxyFailureRestoresTunBeforeReportingFailure() async throws {
        var events: [String] = []
        do {
            _ = try await RuntimeConfigurationUpdate.apply(tun: true, proxy: true, services: .init(
                current: { true }, updateTun: { events.append("tun") },
                updateProxy: { events.append("proxy"); throw Failure.update },
                restoreTun: { events.append("restore") }))
            XCTFail("应报告失败而不是显示已生效")
        } catch Failure.update { }
        XCTAssertEqual(events, ["tun", "proxy", "restore"])
    }

    @MainActor
    func testNewSwitchIntentPreventsLateProxyUpdateAndRestoration() async throws {
        var current = true
        var events: [String] = []
        let applied = try await RuntimeConfigurationUpdate.apply(tun: true, proxy: true, services: .init(
            current: { current }, updateTun: { events.append("tun"); current = false },
            updateProxy: { events.append("proxy") }, restoreTun: { events.append("restore") }))
        XCTAssertFalse(applied)
        XCTAssertEqual(events, ["tun"])
    }
}
