import XCTest
@testable import TungBox

final class TUNDNSAddressPlanTests: XCTestCase {
    func testGeneratedCoreAutomaticDNSMatchesInstalledServiceTarget() throws {
        let builder = TUNRuntimeConfigBuilder(settings: .init(),
            device: .init(ipv4Address: TunServiceManager.tunIPv4Address, interfaceName: "utun29"),
            fallbackProxyTag: "direct", cachePath: "/fixture/cache.db",
            clashAPIPort: 9091, clashAPISecret: "fixture-secret")
        let config = builder.prepare(["dns": ["servers": [["type": "fakeip", "tag": "fake",
            "inet4_range": "198.18.0.0/15", "inet6_range": "2001:2::/48"]]]]).config
        let inbound = try XCTUnwrap((config["inbounds"] as? [[String: Any]])?.first { $0["type"] as? String == "tun" })
        let prefix = try XCTUnwrap((inbound["address"] as? [String])?.first)
        let address = String(prefix.split(separator: "/")[0])
        XCTAssertEqual(TUNAddressPlan.dnsAddress(after: address), TunServiceManager.tunDNSIPv4Address)
        XCTAssertEqual(TunServiceManager.tunDNSIPv4Address, "198.19.0.2")
        XCTAssertNotEqual(TunServiceManager.tunDNSIPv4Address, "198.18.0.2")
        XCTAssertEqual(inbound["auto_route"] as? Bool, true)
        // In Core 1.14, leaving dns_address unset enables its early DNS protocol
        // classification, before the Fake-IP lookup and ordinary hijack-dns rule.
        XCTAssertNil(inbound["dns_address"])
        XCTAssertNotEqual(inbound["dns_mode"] as? String, "disabled")
    }

    func testDNSAddressDerivationStaysInSubnetAndRejectsInvalidAddress() {
        XCTAssertEqual(TUNAddressPlan.dnsAddress(after: "198.19.2.1"), "198.19.2.2")
        XCTAssertNil(TUNAddressPlan.dnsAddress(after: "198.19.0.255"))
        XCTAssertNil(TUNAddressPlan.dnsAddress(after: "999.19.0.1"))
        XCTAssertNil(TUNAddressPlan.dnsAddress(after: "198.19.0"))
    }
}
