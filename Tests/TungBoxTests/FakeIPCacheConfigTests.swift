import Foundation
import XCTest
@testable import TungBox

final class FakeIPCacheConfigTests: XCTestCase {
    func testTypedFakeIPRepairsExplicitlyDisabledCacheAndPreservesUnknownFields() throws {
        let source: [String: Any] = ["dns": ["servers": [["type": "fakeip", "tag": "fake"]]],
            "experimental": ["future": 7, "cache_file": ["enabled": false, "store_fakeip": false,
                "path": "/tmp/user-cache.db", "cache_id": "user", "unknown": "retained"]]]
        let updated = FakeIPCacheConfig.applying(to: source)
        let experimental = try XCTUnwrap(updated["experimental"] as? [String: Any])
        let cache = try XCTUnwrap(experimental["cache_file"] as? [String: Any])
        XCTAssertEqual(cache["enabled"] as? Bool, true)
        XCTAssertEqual(cache["store_fakeip"] as? Bool, true)
        XCTAssertEqual(cache["path"] as? String, "/tmp/user-cache.db")
        XCTAssertEqual(cache["cache_id"] as? String, "user")
        XCTAssertEqual(cache["unknown"] as? String, "retained")
        XCTAssertEqual(experimental["future"] as? Int, 7)
        XCTAssertTrue(NSDictionary(dictionary: updated).isEqual(to: FakeIPCacheConfig.applying(to: updated)))
    }

    func testLegacyEnabledFakeIPGetsPersistentStorage() throws {
        let updated = FakeIPCacheConfig.applying(to: ["dns": ["fakeip": ["enabled": true]]])
        let cache = try XCTUnwrap((updated["experimental"] as? [String: Any])?["cache_file"] as? [String: Any])
        XCTAssertEqual(cache["enabled"] as? Bool, true)
        XCTAssertEqual(cache["store_fakeip"] as? Bool, true)
    }

    func testNoFakeIPLeavesConfigurationUntouched() {
        for source: [String: Any] in [[:], ["dns": ["fakeip": ["enabled": false]]],
            ["dns": ["servers": [["type": "udp", "tag": "local"]]],
             "experimental": ["cache_file": ["enabled": false, "store_fakeip": false]]]] {
            XCTAssertTrue(NSDictionary(dictionary: source).isEqual(to: FakeIPCacheConfig.applying(to: source)))
        }
    }

    func testUserAndTunPathsStayIndependentAndNoSecretsAreAdded() throws {
        for path in ["/tmp/user/cache.db", "/Library/Application Support/TungBox/cache.db"] {
            let source: [String: Any] = ["dns": ["servers": [["type": "fakeip"]]],
                "experimental": ["cache_file": ["path": path, "cache_id": path]]]
            let updated = FakeIPCacheConfig.applying(to: source)
            let experimental = try XCTUnwrap(updated["experimental"] as? [String: Any])
            let cache = try XCTUnwrap(experimental["cache_file"] as? [String: Any])
            XCTAssertEqual(cache["path"] as? String, path)
            XCTAssertEqual(cache["cache_id"] as? String, path)
            XCTAssertEqual(Set(cache.keys), Set(["path", "cache_id", "enabled", "store_fakeip"]))
            XCTAssertNil(experimental["clash_api"])
        }
    }
}
