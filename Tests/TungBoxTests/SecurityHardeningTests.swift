import Foundation
import XCTest
@testable import TungBox

final class SecurityHardeningTests: XCTestCase {
    func testSubscriptionUserInfoRejectsNegativeAndUnreasonableTrafficValues() {
        let valid = SubscriptionImporter.parseSubscriptionUserInfo("upload=10; download=20; total=40; expire=1893456000")
        XCTAssertEqual(valid.upload, 10)
        XCTAssertEqual(valid.download, 20)
        XCTAssertEqual(valid.total, 40)
        XCTAssertNotNil(valid.expiresAt)

        let invalid = SubscriptionImporter.parseSubscriptionUserInfo(
            "upload=-1; download=\(SecurityLimits.subscriptionTrafficMax + 1); total=9223372036854775807; expire=99999999999"
        )
        XCTAssertNil(invalid.upload)
        XCTAssertNil(invalid.download)
        XCTAssertNil(invalid.total)
        XCTAssertNil(invalid.expiresAt)

        let malformed = SubscriptionImporter.parseSubscriptionUserInfo(
            "upload=; download=not-a-number; total=999999999999999999999999999999"
        )
        XCTAssertNil(malformed.upload)
        XCTAssertNil(malformed.download)
        XCTAssertNil(malformed.total)
    }

    func testSaturatingTrafficAdditionCannotTrap() {
        XCTAssertEqual(SaturatingArithmetic.add(Int64.max, 1), Int64.max)
        XCTAssertEqual(SaturatingArithmetic.add(12, 30), 42)
        XCTAssertEqual(SaturatingArithmetic.add(Int.max, 1), Int.max)
        XCTAssertEqual(SubscriptionTraffic.used(upload: Int64.max, download: Int64.max), Int64.max)
        XCTAssertEqual(SubscriptionTraffic.used(upload: -1, download: 20), 20)
        XCTAssertTrue(SubscriptionTraffic.isInconsistent(used: 30, total: 20))
        XCTAssertFalse(SubscriptionTraffic.isInconsistent(used: 20, total: 30))
    }

    func testTrafficDifferencesAndRatesSaturateForCorruptedCounters() {
        XCTAssertEqual(SaturatingArithmetic.nonnegativeDifference(Int64.max, Int64.min), Int64.max)
        XCTAssertEqual(SaturatingArithmetic.nonnegativeDifference(Int.max, Int.min), Int.max)
        XCTAssertEqual(SaturatingArithmetic.rate(bytes: Int64.max, elapsed: 0.000_001), Int.max)
        XCTAssertEqual(SaturatingArithmetic.rate(bytes: Int.max, elapsed: 0.000_001), Int.max)
        XCTAssertEqual(SaturatingArithmetic.add(Int.min, -1), Int.min)
    }
}
