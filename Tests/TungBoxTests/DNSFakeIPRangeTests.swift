import XCTest
@testable import TungBox

final class DNSFakeIPRangeTests: XCTestCase {
    func testAcceptsIPv4CIDRBoundariesAndExistingDefault() {
        for value in ["0.0.0.0/0", "255.255.255.255/32", "198.18.0.0/15", "192.168.1.42/24", DNSConfig.defaultFakeIPRange] {
            XCTAssertTrue(DNSConfig.isValidIPv4CIDR(value), value)
        }
    }

    func testRejectsMalformedAddressesAndPrefixes() {
        for value in ["abc/24", "1.2.3.4/99", "1.2.3.4/33", "1.2.3.4/-1", "1.2.3.4/+1", "1.2.3.4/", "1.2.3.4/2/4", "1.2.3/24", "256.2.3.4/24", "::1/128", "::/0", "1.2.3.4", "1.2.3.4/ 24"] {
            XCTAssertFalse(DNSConfig.isValidIPv4CIDR(value), value)
        }
    }

    func testLegacyInvalidSavedRangeFallsBackWithoutMutatingStoredValue() throws {
        let suite = "TungBox.DNSFakeIPRangeTests.legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for value in ["abc/24", "198.18.0.0/99", "::/0"] {
            defaults.set(value, forKey: "dnsFakeIPRange")
            XCTAssertEqual(DNSConfig.readFakeIPRange(from: defaults), DNSConfig.defaultFakeIPRange)
            XCTAssertEqual(defaults.string(forKey: "dnsFakeIPRange"), value)
        }
    }

    func testInvalidInputPreservesSavedValueAndEmptyInputRestoresDefault() throws {
        let suite = "TungBox.DNSFakeIPRangeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(DNSConfig.setFakeIPRange(" 192.0.2.0/24 \n", defaults: defaults))
        XCTAssertEqual(DNSConfig.readFakeIPRange(from: defaults), "192.0.2.0/24")
        XCTAssertFalse(DNSConfig.setFakeIPRange("192.0.2.0/99", defaults: defaults))
        let recreated = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(DNSConfig.readFakeIPRange(from: recreated), "192.0.2.0/24")
        XCTAssertTrue(DNSConfig.setFakeIPRange(" \n", defaults: defaults))
        XCTAssertEqual(DNSConfig.readFakeIPRange(from: defaults), DNSConfig.defaultFakeIPRange)
    }
}
