import XCTest
@testable import TungBox

final class NodeDelayTests: XCTestCase {
    func testGroupDelayUsesReselectionEndpointAndPreservesQueryURL() throws {
        let target = "https://example.com/probe?a=1&b=two#fragment"
        let path = ClashAPI.delayPath(kind: "group", tag: "自动/选择?#", url: target)
        XCTAssertTrue(path.hasPrefix("/group/"))
        XCTAssertTrue(path.contains("%2F"))
        XCTAssertFalse(path.contains("/proxies/"))
        let url = try XCTUnwrap(ClashAPI.endpointURL(path: path, port: 9091))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, target)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "timeout" })?.value, "30000")
        XCTAssertEqual(components.port, 9091)
        XCTAssertNil(components.fragment)
    }

    func testSingleDelayKeepsLeafProbeEndpoint() throws {
        let path = ClashAPI.delayPath(kind: "proxies", tag: "node/a", url: "https://example.com")
        XCTAssertTrue(path.hasPrefix("/proxies/node%2Fa/delay?"))
        XCTAssertTrue(path.hasSuffix("timeout=5000"))
    }
}
