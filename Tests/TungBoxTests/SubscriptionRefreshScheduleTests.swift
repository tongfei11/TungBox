import AppKit
import CoreFoundation
import XCTest
@testable import TungBox

final class SubscriptionRefreshScheduleTests: XCTestCase {
    func testMissingPreferenceEnablesOneHourDefault() throws {
        try withDefaults { defaults in
            XCTAssertEqual(SubscriptionRefreshSchedule.minutes(defaults: defaults), 60)
            XCTAssertEqual(SubscriptionRefreshSchedule.statusText(minutes: SubscriptionRefreshSchedule.minutes(defaults: defaults)), "每 1 小时")
        }
    }

    func testExplicitOffAndEverySupportedIntervalSurviveReload() throws {
        try withDefaults { defaults in
            let reloaded = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
            for option in SubscriptionRefreshSchedule.options {
                defaults.set(option.minutes, forKey: SubscriptionRefreshSchedule.defaultsKey)
                XCTAssertEqual(SubscriptionRefreshSchedule.minutes(defaults: reloaded), option.minutes)
            }
            defaults.set(0, forKey: SubscriptionRefreshSchedule.defaultsKey)
            XCTAssertEqual(SubscriptionRefreshSchedule.statusText(minutes: SubscriptionRefreshSchedule.minutes(defaults: reloaded)), "已关闭")
        }
    }

    func testInvalidSavedIntervalFallsBackToOneHour() throws {
        try withDefaults { defaults in
            for value in [-1, 1, 59, Int.max] {
                defaults.set(value, forKey: SubscriptionRefreshSchedule.defaultsKey)
                XCTAssertEqual(SubscriptionRefreshSchedule.minutes(defaults: defaults), 60)
            }
            defaults.set("invalid", forKey: SubscriptionRefreshSchedule.defaultsKey)
            XCTAssertEqual(SubscriptionRefreshSchedule.minutes(defaults: defaults), 60)
        }
    }

    @MainActor
    func testOffCreatesNoTimerAndEnabledTimerWaitsAFullInterval() throws {
        XCTAssertNil(SubscriptionRefreshSchedule.makeTimer(minutes: 0) { _ in XCTFail("关闭时不应刷新") })
        let started = Date()
        let timer = try XCTUnwrap(SubscriptionRefreshSchedule.makeTimer(minutes: 30) { _ in })
        defer { timer.invalidate() }
        XCTAssertEqual(timer.timeInterval, 1800)
        XCTAssertEqual(timer.fireDate.timeIntervalSince(started), 1800, accuracy: 1)
    }

    @MainActor
    func testTimerAlsoFiresWhileRunLoopTracksUIEvents() throws {
        let fired = DispatchSemaphore(value: 0)
        let mode = RunLoop.Mode("TungBoxSubscriptionRefreshTest-\(UUID().uuidString)")
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(rawValue: mode.rawValue as CFString))
        let timer = try XCTUnwrap(SubscriptionRefreshSchedule.makeTimer(minutes: 30) { timer in
            timer.invalidate()
            fired.signal()
        })
        defer { timer.invalidate() }
        timer.fireDate = Date(timeIntervalSinceNow: 0.01)
        let deadline = Date(timeIntervalSinceNow: 0.5)
        var didFire = false
        // Other UI tests may install common-mode sources that wake the run loop
        // before this timer is due. Keep pumping only the tracking mode.
        repeat {
            RunLoop.main.run(mode: mode, before: deadline)
            didFire = fired.wait(timeout: .now()) == .success
        } while !didFire && Date() < deadline
        XCTAssertTrue(didFire)
    }

    private var defaultsSuiteName = ""

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        defaultsSuiteName = "TungBoxSubscriptionRefreshTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        try body(defaults)
    }
}
