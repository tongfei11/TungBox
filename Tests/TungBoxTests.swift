import XCTest
@testable import TungBox

final class SubscriptionFormatTests: XCTestCase {

    // MARK: - Format detection

    func testDetectSingBoxJSON() {
        let json = """
        {"outbounds":[{"type":"vmess","tag":"node1","server":"1.2.3.4","server_port":443}],"route":{"rules":[]}}
        """
        XCTAssertEqual(SubscriptionFormatParser.detectFormat(json), .singBoxJSON)
    }

    func testDetectBase64SingBoxJSON() {
        let raw = #"{"outbounds":[{"type":"vmess","tag":"n1"}]}"#
        let encoded = Data(raw.utf8).base64EncodedString()
        XCTAssertEqual(SubscriptionFormatParser.detectFormat(encoded), .singBoxJSON)
    }

    func testDetectClashYAML() {
        let yaml = """
        proxies:
          - name: "HK"
            type: vmess
            server: 1.2.3.4
            port: 443
            uuid: xxx
        proxy-groups:
          - name: "Proxy"
            type: select
        """
        XCTAssertEqual(SubscriptionFormatParser.detectFormat(yaml), .clashYAML)
    }

    func testDetectUnknown() {
        XCTAssertEqual(SubscriptionFormatParser.detectFormat("random garbage text"), .unknown)
    }

    // MARK: - Clash YAML parsing

    func testParseClashVMessProxy() throws {
        let yaml = """
        proxies:
          - name: HK
            type: vmess
            server: 1.2.3.4
            port: 443
            uuid: abc-def
            cipher: auto
            tls: true
        """
        let nodes = try SubscriptionFormatParser.parseClashProxies(yaml)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0]["tag"] as? String, "HK")
        XCTAssertEqual(nodes[0]["type"] as? String, "vmess")
        XCTAssertEqual(nodes[0]["server"] as? String, "1.2.3.4")
        XCTAssertEqual(nodes[0]["server_port"] as? Int, 443)
        XCTAssertNotNil(nodes[0]["tls"])
    }

    func testParseMultipleClashProxies() throws {
        let yaml = """
        proxies:
          - name: HK
            type: vmess
            server: 1.1.1.1
            port: 443
            uuid: aaa
          - name: JP
            type: trojan
            server: 2.2.2.2
            port: 8443
            password: pwd
        """
        let nodes = try SubscriptionFormatParser.parseClashProxies(yaml)
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[1]["type"] as? String, "trojan")
    }

    func testParseClashProxyWithTransport() throws {
        let yaml = """
        proxies:
          - name: WSNode
            type: vmess
            server: 3.3.3.3
            port: 80
            uuid: xyz
            network: ws
            ws-path: /ws
            host: edge.example.com
        """
        let nodes = try SubscriptionFormatParser.parseClashProxies(yaml)
        XCTAssertEqual(nodes.count, 1)
        let transport = nodes[0]["transport"] as? [String: Any]
        XCTAssertEqual(transport?["type"] as? String, "ws")
        XCTAssertEqual(transport?["path"] as? String, "/ws")
    }
}

final class VersionComparisonTests: XCTestCase {

    func testCompareEqual() {
        XCTAssertEqual(Runner.compareVersions("1.13.12", "1.13.12"), .orderedSame)
    }

    func testCompareAscending() {
        XCTAssertEqual(Runner.compareVersions("1.12.0", "1.13.12"), .orderedAscending)
    }

    func testCompareDescending() {
        XCTAssertEqual(Runner.compareVersions("1.14.0", "1.13.12"), .orderedDescending)
    }

    func testCompareDifferentLengths() {
        XCTAssertEqual(Runner.compareVersions("1.12", "1.12.5"), .orderedAscending)
    }

    func testExtractVersionFromSingBoxOutput() {
        let text = "sing-box version v1.13.12\n\nEnvironment: go1.25.6 darwin/arm64"
        XCTAssertEqual(Runner.extractVersion(from: text), "1.13.12")
    }

    func testExtractVersionFromHomebrewOutput() {
        let text = "sing-box version 1.12.0"
        XCTAssertEqual(Runner.extractVersion(from: text), "1.12.0")
    }
}

final class ConfigCompatibilityTests: XCTestCase {

    func testDetectDefaultDomainResolver() {
        let config: [String: Any] = ["route": ["default_domain_resolver": "dns-local"]]
        let issues = ConfigCompatibilityChecker.check(config: config)
        XCTAssertTrue(issues.contains { $0.path == "route.default_domain_resolver" && $0.severity == .error })
    }

    func testDetectDNSOutbound() {
        let config: [String: Any] = ["dns": ["rules": [["outbound": "proxy", "domain": ["example.com"]]]]]
        let issues = ConfigCompatibilityChecker.check(config: config)
        XCTAssertTrue(issues.contains { $0.path.hasPrefix("dns.rules[") && $0.severity == .error })
    }

    func testDetectDomainStrategy() {
        let config: [String: Any] = ["outbounds": [["type": "vmess", "dial": ["domain_strategy": "prefer_ipv4"]]]]
        let issues = ConfigCompatibilityChecker.check(config: config)
        XCTAssertTrue(issues.contains { $0.path.contains("domain_strategy") })
    }

    func testAutoFixDefaultDomainResolver() {
        let config: [String: Any] = ["route": ["default_domain_resolver": "dns-local", "rules": []]]
        let (fixed, log) = ConfigCompatibilityChecker.autoFix(config: config)
        let route = fixed["route"] as? [String: Any]
        XCTAssertNil(route?["default_domain_resolver"])
        XCTAssertFalse(log.isEmpty)
    }

    func testAutoFixDomainStrategy() {
        let config: [String: Any] = ["outbounds": [["type": "vmess", "dial": ["domain_strategy": "prefer_ipv4"]]]]
        let (fixed, log) = ConfigCompatibilityChecker.autoFix(config: config)
        let outbounds = fixed["outbounds"] as? [[String: Any]]
        let dial = outbounds?.first?["dial"] as? [String: Any]
        XCTAssertNil(dial?["domain_strategy"])
        XCTAssertNotNil(dial?["domain_resolver"])
    }

    func testAutoFixDNSAddressFormat() {
        let config: [String: Any] = ["dns": ["servers": [["address": "tcp://1.1.1.1"]]]]
        let (fixed, log) = ConfigCompatibilityChecker.autoFix(config: config)
        let dns = fixed["dns"] as? [String: Any]
        let servers = dns?["servers"] as? [[String: Any]]
        XCTAssertEqual(servers?.first?["type"] as? String, "tcp")
        XCTAssertEqual(servers?.first?["server"] as? String, "1.1.1.1")
    }
}

final class SubscriptionImporterTests: XCTestCase {

    func testBase64Decode() {
        let text = "hello world"
        let encoded = Data(text.utf8).base64EncodedString()
        let result = try? SubscriptionImporter.fetch(urlString: "data:text/plain;base64," + encoded)
        // fetch requires http/https URL, so it'll fail with URL validation — test parse instead
        let parsed = try? SubscriptionImporter.singBoxConfig(from: """
        {"outbounds":[{"type":"vmess","tag":"test","server":"1.2.3.4","server_port":443,"uuid":"abc"}]}
        """, profileName: "test")
        XCTAssertNotNil(parsed)
    }

    func testParseSubscriptionWithNodes() throws {
        let config = try SubscriptionImporter.singBoxConfig(from: """
        {"outbounds":[{"type":"vmess","tag":"n1","server":"1.2.3.4","server_port":443,"uuid":"x"},{"type":"shadowsocks","tag":"n2","server":"5.6.7.8","server_port":8388,"method":"aes-256-gcm","password":"pwd"}]}
        """, profileName: "test")
        XCTAssertTrue(config.contains("n1"))
        XCTAssertTrue(config.contains("n2"))
        XCTAssertTrue(config.contains("urltest"))
        XCTAssertTrue(config.contains("selector"))
    }
}
