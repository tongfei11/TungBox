import XCTest
@testable import TungBox

/// 覆盖 TUNConfig 的纯函数逻辑：UserDefaults 往返、applyUserFields 注入 TUN inbound。
/// 实际 daemon 热重载行为不在这里测，得跑 sing-box 看 daemon 日志。
final class TUNConfigTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TUNConfig.resetAll()
    }

    override func tearDown() {
        TUNConfig.resetAll()
        super.tearDown()
    }

    // MARK: - 默认值

    func testDefaultsRoundtrip() {
        XCTAssertEqual(TUNConfig.stack, TUNConfig.defaultStack)
        XCTAssertEqual(TUNConfig.mtu, TUNConfig.defaultMTU)
        XCTAssertEqual(TUNConfig.strictRoute, TUNConfig.defaultStrictRoute)
        XCTAssertEqual(TUNConfig.endpointIndependentNAT, TUNConfig.defaultEndpointIndependentNAT)
        XCTAssertEqual(TUNConfig.routeExclude, TUNConfig.defaultRouteExclude)
        XCTAssertEqual(TUNConfig.includeInterface, TUNConfig.defaultIncludeInterface)
        XCTAssertEqual(TUNConfig.excludeInterface, TUNConfig.defaultExcludeInterface)
    }

    func testSetThenRead() {
        TUNConfig.stack = .system
        TUNConfig.mtu = 1500
        TUNConfig.strictRoute = true
        TUNConfig.endpointIndependentNAT = true
        TUNConfig.routeExclude = ["10.0.0.0/8", "192.168.1.0/24"]
        TUNConfig.includeInterface = ["en0"]
        TUNConfig.excludeInterface = ["awdl0", "llw0"]

        XCTAssertEqual(TUNConfig.stack, .system)
        XCTAssertEqual(TUNConfig.mtu, 1500)
        XCTAssertTrue(TUNConfig.strictRoute)
        XCTAssertTrue(TUNConfig.endpointIndependentNAT)
        XCTAssertEqual(TUNConfig.routeExclude, ["10.0.0.0/8", "192.168.1.0/24"])
        XCTAssertEqual(TUNConfig.includeInterface, ["en0"])
        XCTAssertEqual(TUNConfig.excludeInterface, ["awdl0", "llw0"])
    }

    func testSetToDefaultClearsKey() {
        TUNConfig.stack = .system
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "tunStack"))
        TUNConfig.stack = TUNConfig.defaultStack
        XCTAssertNil(UserDefaults.standard.object(forKey: "tunStack"))

        TUNConfig.mtu = 1500
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "tunMTU"))
        TUNConfig.mtu = TUNConfig.defaultMTU
        XCTAssertNil(UserDefaults.standard.object(forKey: "tunMTU"))
    }

    func testInterfaceListsTrimAndDropEmpty() {
        TUNConfig.includeInterface = ["  en0  ", "", "en1", "   "]
        XCTAssertEqual(TUNConfig.includeInterface, ["en0", "en1"])
    }

    func testResetAll() {
        TUNConfig.stack = .gvisor
        TUNConfig.mtu = 1500
        TUNConfig.endpointIndependentNAT = true
        TUNConfig.includeInterface = ["en0"]
        TUNConfig.resetAll()
        XCTAssertEqual(TUNConfig.stack, TUNConfig.defaultStack)
        XCTAssertEqual(TUNConfig.mtu, TUNConfig.defaultMTU)
        XCTAssertEqual(TUNConfig.endpointIndependentNAT, TUNConfig.defaultEndpointIndependentNAT)
        XCTAssertEqual(TUNConfig.includeInterface, [])
    }

    func testStackEnumCoverage() {
        // 三档都能存进 / 取出
        for s in TUNConfig.Stack.allCases {
            TUNConfig.stack = s
            XCTAssertEqual(TUNConfig.stack, s)
        }
    }

    // MARK: - applyUserFields

    func testApplyDefaultFields() {
        let base: [String: Any] = [
            "type": "tun",
            "tag": "tun-in",
            "auto_route": true
        ]
        let out = TUNConfig.applyUserFields(to: base)
        // 透传 base 字段
        XCTAssertEqual(out["type"] as? String, "tun")
        XCTAssertEqual(out["tag"] as? String, "tun-in")
        XCTAssertEqual(out["auto_route"] as? Bool, true)
        // 默认值注入
        XCTAssertEqual(out["stack"] as? String, "mixed")
        XCTAssertEqual(out["mtu"] as? Int, 9000)
        XCTAssertEqual(out["strict_route"] as? Bool, false)
        XCTAssertEqual(out["endpoint_independent_nat"] as? Bool, false)
        XCTAssertEqual(out["route_exclude_address"] as? [String], TUNConfig.defaultRouteExclude)
        // 默认空列表不应写 include/exclude_interface（让 sing-box 用空集行为）
        XCTAssertNil(out["include_interface"])
        XCTAssertNil(out["exclude_interface"])
    }

    func testApplyCustomStackAndMTU() {
        TUNConfig.stack = .gvisor
        TUNConfig.mtu = 1500
        let out = TUNConfig.applyUserFields(to: [:])
        XCTAssertEqual(out["stack"] as? String, "gvisor")
        XCTAssertEqual(out["mtu"] as? Int, 1500)
    }

    func testApplyInterfaceLists() {
        TUNConfig.includeInterface = ["en0", "en1"]
        TUNConfig.excludeInterface = ["awdl0"]
        let out = TUNConfig.applyUserFields(to: [:])
        XCTAssertEqual(out["include_interface"] as? [String], ["en0", "en1"])
        XCTAssertEqual(out["exclude_interface"] as? [String], ["awdl0"])
    }

    func testApplyOverwritesExistingFields() {
        // base 里如果用户偷塞了 stack/mtu，applyUserFields 也应该覆盖成 TUNConfig 的值
        let base: [String: Any] = [
            "type": "tun",
            "stack": "system",
            "mtu": 1280
        ]
        TUNConfig.stack = .gvisor
        TUNConfig.mtu = 9000
        let out = TUNConfig.applyUserFields(to: base)
        XCTAssertEqual(out["stack"] as? String, "gvisor")
        XCTAssertEqual(out["mtu"] as? Int, 9000)
    }

    func testApplyRemovesStaleInterfaceList() {
        // base 带旧的 include_interface，UserDefaults 此刻为空 → 应该被清掉
        let base: [String: Any] = [
            "include_interface": ["stale_en0"],
            "exclude_interface": ["stale_awdl"]
        ]
        let out = TUNConfig.applyUserFields(to: base)
        XCTAssertNil(out["include_interface"])
        XCTAssertNil(out["exclude_interface"])
    }
}
