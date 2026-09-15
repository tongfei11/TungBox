import XCTest
@testable import TungBox

final class NodeDelayTests: XCTestCase {
    func testStoreCleansOnlyObsoleteGeneratedConfigs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let obsolete = [
            "test_node_profile.json",
            "before-refresh-legacy.json",
            "tun-config-debug.json",
            "tun-request-debug.json"
        ]
        let retained = ["profile.json", "run_profile.json", "tun-request.json"]
        for name in obsolete + retained {
            try Data("{}".utf8).write(to: directory.appendingPathComponent(name))
        }

        _ = Store(baseURL: directory)

        for name in obsolete {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
        }
        for name in retained {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
        }
    }

    func testCompatibilityRepairRestoresMissingTrojanTLS() throws {
        let config: [String: Any] = [
            "outbounds": [
                ["type": "trojan", "tag": "legacy", "server": "example.com", "server_port": 443, "password": "secret"],
                ["type": "trojan", "tag": "custom", "server": "example.net", "server_port": 443, "password": "secret", "tls": ["enabled": true, "server_name": "sni.example"]],
                ["type": "trojan", "tag": "plain", "server": "plain.example", "server_port": 80, "password": "secret", "tls": ["enabled": false]],
                ["type": "hysteria2", "tag": "hy2", "server": "example.org", "server_port": 443, "password": "secret"]
            ]
        ]

        let repaired = ConfigCompatibilityChecker.autoFix(config: config)
        let outbounds = try XCTUnwrap(repaired.config["outbounds"] as? [[String: Any]])
        XCTAssertEqual((outbounds[0]["tls"] as? [String: Any])?["enabled"] as? Bool, true)
        XCTAssertEqual((outbounds[1]["tls"] as? [String: Any])?["server_name"] as? String, "sni.example")
        XCTAssertEqual((outbounds[2]["tls"] as? [String: Any])?["enabled"] as? Bool, false)
        XCTAssertNil(outbounds[3]["tls"])
        XCTAssertTrue(repaired.fixed.contains { $0.contains("补充 Trojan 必需的 TLS") })
    }

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
