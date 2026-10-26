import Network
import XCTest
@testable import TungBox

/// Pure runtime-config transformations; no Core is started and no OS routes change.
final class FakeIPTunCompatibilityTests: XCTestCase {
    private func build(pool: String?, legacy: Bool = false) throws -> [String: Any] {
        var fake: [String: Any] = ["inet4_range": "198.18.0.0/15"]
        if let pool { fake["inet6_range"] = pool }
        let dns: [String: Any]
        if legacy {
            fake["enabled"] = true
            dns = ["fakeip": fake]
        } else {
            fake["type"] = "fakeip"
            fake["tag"] = "dns-fakeip"
            dns = ["servers": [fake]]
        }
        let builder = TUNRuntimeConfigBuilder(settings: .init(),
            device: .init(ipv4Address: "198.19.0.1", interfaceName: "utun29"),
            fallbackProxyTag: "direct", cachePath: "/fixture/tun/cache.db",
            clashAPIPort: 9091, clashAPISecret: "fixture-secret")
        let prepared = builder.prepare(["dns": dns, "outbounds": [["type": "direct", "tag": "direct"]]])
        let bound = builder.bindPhysicalInterface(nil, in: prepared.config)
        let output = builder.finish(bound.config, resolvedAddresses: [:])
        return try XCTUnwrap(ConfigCodec.parseObject(from: output.text.get()))
    }

    private func tun(_ config: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap((config["inbounds"] as? [[String: Any]])?.first { $0["type"] as? String == "tun" })
    }

    func testLegacyFakeIPv6PoolNoLongerOverlapsPrivateExclusionsAndHasIPv6Interface() throws {
        for legacy in [false, true] {
            let config = try build(pool: "fc00::/18", legacy: legacy)
            let dns = try XCTUnwrap(config["dns"] as? [String: Any])
            let pool = legacy ? (dns["fakeip"] as? [String: Any])?["inet6_range"] as? String
                : ((dns["servers"] as? [[String: Any]])?.first)?["inet6_range"] as? String
            XCTAssertEqual(pool, "2001:2::/48")
            let inbound = try tun(config)
            XCTAssertTrue((inbound["address"] as? [String] ?? []).contains { $0.contains(":") })
            let excludes = inbound["route_exclude_address"] as? [String] ?? []
            XCTAssertTrue(excludes.contains("fc00::/7"), "保留真实局域网 IPv6 的旁路")
            XCTAssertFalse(excludes.contains { containsIPv6("2001:2::1", cidr: $0) })
            let cache = (config["experimental"] as? [String: Any])?["cache_file"] as? [String: Any]
            XCTAssertEqual(cache?["store_fakeip"] as? Bool, true)
            XCTAssertEqual(cache?["path"] as? String, "/fixture/tun/cache.db")
        }
    }

    func testCustomNonConflictingIPv6PoolIsPreservedAndDualStackIsEnabled() throws {
        let config = try build(pool: "2001:db8:1234::/48")
        let servers = (config["dns"] as? [String: Any])?["servers"] as? [[String: Any]]
        XCTAssertEqual(servers?.first?["inet6_range"] as? String, "2001:db8:1234::/48")
        XCTAssertEqual((try tun(config)["address"] as? [String])?.count, 2)
    }

    func testIPv4OnlyPoolDoesNotIntroduceIPv6Capture() throws {
        let config = try build(pool: nil)
        XCTAssertEqual(try tun(config)["address"] as? [String], ["198.19.0.1/30"])
        let cache = (config["experimental"] as? [String: Any])?["cache_file"] as? [String: Any]
        XCTAssertEqual(cache?["store_fakeip"] as? Bool, true)
    }

    private func containsIPv6(_ address: String, cidr: String) -> Bool {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let bits = Int(parts[1]), (0...128).contains(bits),
              let prefix = IPv6Address(String(parts[0]))?.rawValue,
              let value = IPv6Address(address)?.rawValue else { return false }
        return (0..<bits).allSatisfy { bit in
            let mask = UInt8(1 << (7 - bit % 8))
            return prefix[bit / 8] & mask == value[bit / 8] & mask
        }
    }
}
