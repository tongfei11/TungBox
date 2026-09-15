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

    func testStoreMigratesSubscriptionFilesIntoOneFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let profileID = UUID()
        let subscriptionID = UUID()
        let legacyName = "legacy.json"
        let profile = ConfigProfile(id: profileID, name: "订阅", fileName: legacyName, updatedAt: Date())
        let subscription = Subscription(id: subscriptionID, name: "订阅", url: "https://example.com", profileID: profileID, updatedAt: nil)
        try JSONEncoder().encode([profile]).write(to: directory.appendingPathComponent("profiles.json"))
        try JSONEncoder().encode([subscription]).write(to: directory.appendingPathComponent("subscriptions.json"))
        try Data("{}".utf8).write(to: directory.appendingPathComponent(legacyName))
        try Data("{}".utf8).write(to: directory.appendingPathComponent("rule-base-\(subscriptionID.uuidString).json"))
        try Data("[]".utf8).write(to: directory.appendingPathComponent("rule-projection-\(subscriptionID.uuidString).json"))
        let customRule = CustomRule(
            id: UUID(),
            subscriptionID: subscriptionID,
            type: "DOMAIN",
            value: "example.com",
            strategy: "direct",
            note: "",
            enabled: true,
            createdAt: Date()
        )
        try JSONEncoder().encode([customRule]).write(to: directory.appendingPathComponent("custom-rules.json"))
        let oldRuleSets = directory.appendingPathComponent("custom-rulesets/\(subscriptionID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: oldRuleSets, withIntermediateDirectories: true)
        try Data("name: custom".utf8).write(to: oldRuleSets.appendingPathComponent("rule.yml"))

        let store = Store(baseURL: directory)
        let migrated = try XCTUnwrap(store.loadProfiles().first)
        let folder = directory.appendingPathComponent("subscriptions/\(subscriptionID.uuidString)", isDirectory: true)
        XCTAssertEqual(store.configURL(for: migrated), folder.appendingPathComponent("config.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("config.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("rule-base.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("rule-projection.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("custom-rules.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("custom-rulesets/rule.yml").path))
        XCTAssertEqual(store.loadCustomRules(), [customRule])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("custom-rules.json").path))
    }

    func testStorePrunesProfilesWhoseConfigWasDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let missingID = UUID()
        let subscriptionID = UUID()
        let profiles = [
            ConfigProfile(id: missingID, name: "已删除", fileName: "missing.json", updatedAt: Date())
        ]
        let subscription = Subscription(id: subscriptionID, name: "失效订阅", url: "https://example.com", profileID: missingID, updatedAt: nil)
        try JSONEncoder().encode(profiles).write(to: directory.appendingPathComponent("profiles.json"))
        try JSONEncoder().encode([subscription]).write(to: directory.appendingPathComponent("subscriptions.json"))

        let store = Store(baseURL: directory)

        XCTAssertTrue(store.loadProfiles().isEmpty)
        XCTAssertNil(store.loadSubscriptions().first?.profileID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("profiles").path))
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
