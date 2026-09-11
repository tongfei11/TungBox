import XCTest
@testable import TungBox

/// 覆盖 DNSConfig 的纯函数逻辑：URL 解析、字典生成、hosts 合并、UserDefaults 往返。
/// UI 行为（toast / 防抖 / reconcileRuntime 触发）不在这里测，得跑应用手动验。
///
/// 注意：每个测试在 setUp/tearDown 调 `DNSConfig.resetAll()` 清掉 UserDefaults，
/// 避免污染本地 prefs（也避免相邻测试互相影响）。
final class DNSConfigTests: XCTestCase {

    override func setUp() {
        super.setUp()
        DNSConfig.resetAll()
    }

    override func tearDown() {
        DNSConfig.resetAll()
        super.tearDown()
    }

    // MARK: - URL 解析

    func testParseBareIPv4() {
        let s = DNSConfig.parseServerURL("223.5.5.5", tag: "x", detour: nil)
        XCTAssertEqual(s?["type"] as? String, "udp")
        XCTAssertEqual(s?["server"] as? String, "223.5.5.5")
        XCTAssertEqual(s?["server_port"] as? Int, 53)
        XCTAssertEqual(s?["tag"] as? String, "x")
        XCTAssertNil(s?["detour"])
    }

    func testParseBareHostWithPort() {
        let s = DNSConfig.parseServerURL("dns.alidns.com:5353", tag: "x", detour: nil)
        XCTAssertEqual(s?["type"] as? String, "udp")
        XCTAssertEqual(s?["server"] as? String, "dns.alidns.com")
        XCTAssertEqual(s?["server_port"] as? Int, 5353)
    }

    func testParseDoHWithDefaultPath() {
        let s = DNSConfig.parseServerURL("https://1.1.1.1/dns-query", tag: "p", detour: "节点选择")
        XCTAssertEqual(s?["type"] as? String, "https")
        XCTAssertEqual(s?["server"] as? String, "1.1.1.1")
        XCTAssertEqual(s?["detour"] as? String, "节点选择")
        // /dns-query 是默认 path，不写进 dict
        XCTAssertNil(s?["path"])
    }

    func testParseDoHWithCustomPath() {
        let s = DNSConfig.parseServerURL("https://doh.example.com/resolve", tag: "p", detour: nil)
        XCTAssertEqual(s?["type"] as? String, "https")
        XCTAssertEqual(s?["server"] as? String, "doh.example.com")
        XCTAssertEqual(s?["path"] as? String, "/resolve")
    }

    func testParseDoHWithExplicitPort() {
        let s = DNSConfig.parseServerURL("https://doh.example.com:8443/dns-query", tag: "p", detour: nil)
        XCTAssertEqual(s?["type"] as? String, "https")
        XCTAssertEqual(s?["server"] as? String, "doh.example.com")
        XCTAssertEqual(s?["server_port"] as? Int, 8443)
    }

    func testParseDoT() {
        let s = DNSConfig.parseServerURL("tls://1.1.1.1", tag: "p", detour: nil)
        XCTAssertEqual(s?["type"] as? String, "tls")
        XCTAssertEqual(s?["server"] as? String, "1.1.1.1")
        XCTAssertNil(s?["server_port"])
    }

    func testParseDoTWithPort() {
        let s = DNSConfig.parseServerURL("tls://1.1.1.1:8853", tag: "p", detour: nil)
        XCTAssertEqual(s?["server_port"] as? Int, 8853)
    }

    func testParseDoQ() {
        let s = DNSConfig.parseServerURL("quic://dns.adguard.com", tag: "p", detour: nil)
        XCTAssertEqual(s?["type"] as? String, "quic")
        XCTAssertEqual(s?["server"] as? String, "dns.adguard.com")
    }

    func testParseDoH3() {
        let s = DNSConfig.parseServerURL("h3://1.1.1.1/dns-query", tag: "p", detour: nil)
        XCTAssertEqual(s?["type"] as? String, "h3")
        XCTAssertEqual(s?["server"] as? String, "1.1.1.1")
        XCTAssertNil(s?["path"])
    }

    func testParseExplicitUDP() {
        let s = DNSConfig.parseServerURL("udp://119.29.29.29", tag: "p", detour: nil)
        XCTAssertEqual(s?["type"] as? String, "udp")
        XCTAssertEqual(s?["server"] as? String, "119.29.29.29")
        XCTAssertEqual(s?["server_port"] as? Int, 53)
    }

    func testParseEmptyReturnsNil() {
        XCTAssertNil(DNSConfig.parseServerURL("", tag: "x", detour: nil))
        XCTAssertNil(DNSConfig.parseServerURL("   ", tag: "x", detour: nil))
    }

    func testParseUnknownSchemeReturnsNil() {
        XCTAssertNil(DNSConfig.parseServerURL("ftp://example.com", tag: "x", detour: nil))
    }

    func testSplitIPv6Bracketed() {
        let (host, port, _) = DNSConfig.splitHostPortPath("[2001:4860:4860::8888]:53")
        XCTAssertEqual(host, "2001:4860:4860::8888")
        XCTAssertEqual(port, 53)
    }

    func testSplitIPv6Unbracketed() {
        // 裸 IPv6 没有方括号时不能切端口（否则会把最后一段当端口）
        let (host, port, _) = DNSConfig.splitHostPortPath("2001:4860:4860::8888")
        XCTAssertEqual(host, "2001:4860:4860::8888")
        XCTAssertNil(port)
    }

    // MARK: - UserDefaults 默认值往返

    func testDefaultsRoundtrip() {
        // 没设过任何值时取出的应该都是默认
        XCTAssertEqual(DNSConfig.localServer, DNSConfig.defaultLocalServer)
        XCTAssertEqual(DNSConfig.proxyServer, DNSConfig.defaultProxyServer)
        XCTAssertEqual(DNSConfig.strategy, DNSConfig.defaultStrategy)
        XCTAssertEqual(DNSConfig.fakeIPEnabled, DNSConfig.defaultFakeIPEnabled)
        XCTAssertEqual(DNSConfig.fakeIPRange, DNSConfig.defaultFakeIPRange)
        XCTAssertEqual(DNSConfig.fakeIPExcludes, DNSConfig.defaultFakeIPExcludes)
        XCTAssertEqual(DNSConfig.readSystemHosts, DNSConfig.defaultReadSystemHosts)
        XCTAssertEqual(DNSConfig.customHosts, DNSConfig.defaultCustomHosts)
    }

    func testSetThenReadCustomValues() {
        DNSConfig.localServer = "tls://1.1.1.1"
        DNSConfig.proxyServer = "https://dns.google/dns-query"
        DNSConfig.strategy = .ipv6Only
        DNSConfig.fakeIPEnabled = false
        DNSConfig.fakeIPRange = "100.64.0.0/10"
        DNSConfig.fakeIPExcludes = ["lan", "test.local"]
        DNSConfig.readSystemHosts = true
        DNSConfig.customHosts = "api.local=10.0.0.5"

        XCTAssertEqual(DNSConfig.localServer, "tls://1.1.1.1")
        XCTAssertEqual(DNSConfig.proxyServer, "https://dns.google/dns-query")
        XCTAssertEqual(DNSConfig.strategy, .ipv6Only)
        XCTAssertFalse(DNSConfig.fakeIPEnabled)
        XCTAssertEqual(DNSConfig.fakeIPRange, "100.64.0.0/10")
        XCTAssertEqual(DNSConfig.fakeIPExcludes, ["lan", "test.local"])
        XCTAssertTrue(DNSConfig.readSystemHosts)
        XCTAssertEqual(DNSConfig.customHosts, "api.local=10.0.0.5")
    }

    func testSetToDefaultClearsKey() {
        // 把值设回默认应等价于"未设"，UserDefaults 应该把 key 删掉（用 has-key 测）
        DNSConfig.localServer = "8.8.8.8"
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "dnsLocalServer"))
        DNSConfig.localServer = DNSConfig.defaultLocalServer
        XCTAssertNil(UserDefaults.standard.object(forKey: "dnsLocalServer"))
    }

    func testResetAllClearsAllKeys() {
        DNSConfig.localServer = "1.2.3.4"
        DNSConfig.fakeIPEnabled = false
        DNSConfig.readSystemHosts = true
        DNSConfig.resetAll()
        XCTAssertEqual(DNSConfig.localServer, DNSConfig.defaultLocalServer)
        XCTAssertEqual(DNSConfig.fakeIPEnabled, DNSConfig.defaultFakeIPEnabled)
        XCTAssertEqual(DNSConfig.readSystemHosts, DNSConfig.defaultReadSystemHosts)
    }

    // MARK: - buildSingBoxDNS 结构

    func testBuildWithDefaults() {
        let dns = DNSConfig.buildSingBoxDNS()
        let servers = dns["servers"] as? [[String: Any]] ?? []
        // 默认开 Fake-IP：dns-local + dns-proxy + dns-fakeip
        XCTAssertEqual(servers.count, 3)
        XCTAssertEqual(servers[0]["tag"] as? String, "dns-local")
        XCTAssertEqual(servers[1]["tag"] as? String, "dns-proxy")
        XCTAssertEqual(servers[2]["tag"] as? String, "dns-fakeip")
        XCTAssertEqual(servers[2]["type"] as? String, "fakeip")

        XCTAssertEqual(dns["strategy"] as? String, "ipv4_only")
        XCTAssertEqual(dns["final"] as? String, "dns-proxy")
        XCTAssertNotNil(dns["fakeip"])
        XCTAssertEqual((dns["fakeip"] as? [String: Any])?["enabled"] as? Bool, true)
        XCTAssertEqual(dns["independent_cache"] as? Bool, true)
    }

    func testBuildWithFakeIPDisabled() {
        DNSConfig.fakeIPEnabled = false
        let dns = DNSConfig.buildSingBoxDNS()
        let servers = dns["servers"] as? [[String: Any]] ?? []
        // 关 Fake-IP：只剩 dns-local + dns-proxy
        XCTAssertEqual(servers.count, 2)
        XCTAssertFalse(servers.contains { ($0["tag"] as? String) == "dns-fakeip" })
        XCTAssertNil(dns["fakeip"])
        XCTAssertNil(dns["independent_cache"])
    }

    func testBuildProxyServerHasDetour() {
        let dns = DNSConfig.buildSingBoxDNS()
        let servers = dns["servers"] as? [[String: Any]] ?? []
        let proxy = servers.first { ($0["tag"] as? String) == "dns-proxy" }
        // dns-proxy 必须走代理（detour 非空且不为 direct）
        let detour = proxy?["detour"] as? String
        XCTAssertNotNil(detour)
        XCTAssertNotEqual(detour, "direct")
        // dns-local 不应有 detour
        let local = servers.first { ($0["tag"] as? String) == "dns-local" }
        XCTAssertNil(local?["detour"])
    }

    func testBuildRulesOrder() {
        let dns = DNSConfig.buildSingBoxDNS()
        let rules = dns["rules"] as? [[String: Any]] ?? []
        // 默认顺序：cn+private→local，excludes→local，notcn→fakeip
        XCTAssertEqual(rules.count, 3)
        XCTAssertEqual(rules[0]["server"] as? String, "dns-local")
        XCTAssertEqual(rules[1]["server"] as? String, "dns-local")
        XCTAssertEqual(rules[2]["server"] as? String, "dns-fakeip")
    }

    func testBuildWithHostsAddsServerAndPriorityRule() {
        DNSConfig.customHosts = "api.local=10.0.0.5\ndev.x=1.2.3.4;5.6.7.8"
        let dns = DNSConfig.buildSingBoxDNS()
        let servers = dns["servers"] as? [[String: Any]] ?? []
        // 应该有 dns-hosts server
        let hosts = servers.first { ($0["tag"] as? String) == "dns-hosts" }
        XCTAssertNotNil(hosts)
        XCTAssertEqual(hosts?["type"] as? String, "hosts")
        let predefined = hosts?["predefined"] as? [String: [String]]
        XCTAssertEqual(predefined?["api.local"], ["10.0.0.5"])
        XCTAssertEqual(predefined?["dev.x"], ["1.2.3.4", "5.6.7.8"])

        // 第一条规则必须是 hosts，否则 hosts 不优先生效
        let rules = dns["rules"] as? [[String: Any]] ?? []
        XCTAssertEqual(rules.first?["server"] as? String, "dns-hosts")
        let domains = rules.first?["domain"] as? [String] ?? []
        XCTAssertTrue(domains.contains("api.local"))
        XCTAssertTrue(domains.contains("dev.x"))
    }

    func testBuildInvalidLocalFallsBackToDefault() {
        DNSConfig.localServer = "ftp://nonsense"
        // setter 不校验，但 buildSingBoxDNS 解析失败时应该兜底
        let dns = DNSConfig.buildSingBoxDNS()
        let servers = dns["servers"] as? [[String: Any]] ?? []
        let local = servers.first { ($0["tag"] as? String) == "dns-local" }
        XCTAssertEqual(local?["server"] as? String, "223.5.5.5")
    }

    // MARK: - hosts 解析

    func testCollectHostsEmpty() {
        XCTAssertTrue(DNSConfig.collectHostsEntries().isEmpty)
    }

    func testCollectHostsCustomBasic() {
        DNSConfig.customHosts = "api.local=10.0.0.5"
        let map = DNSConfig.collectHostsEntries()
        XCTAssertEqual(map["api.local"], ["10.0.0.5"])
    }

    func testCollectHostsCustomMultiIP() {
        DNSConfig.customHosts = "x.test=1.2.3.4;5.6.7.8,9.10.11.12"
        let map = DNSConfig.collectHostsEntries()
        XCTAssertEqual(map["x.test"], ["1.2.3.4", "5.6.7.8", "9.10.11.12"])
    }

    func testCollectHostsCustomSkipsCommentsAndBlanks() {
        DNSConfig.customHosts = """
        # 注释行
        api.local=10.0.0.5

        # 另一条注释
        dev.x=1.1.1.1
        """
        let map = DNSConfig.collectHostsEntries()
        XCTAssertEqual(map.count, 2)
    }

    func testCollectHostsCustomSkipsMalformed() {
        DNSConfig.customHosts = """
        api.local=10.0.0.5
        no-equals-sign
        =1.2.3.4
        x=
        """
        let map = DNSConfig.collectHostsEntries()
        XCTAssertEqual(map.count, 1)
        XCTAssertEqual(map["api.local"], ["10.0.0.5"])
    }

    func testCollectHostsCustomOverridesSystem() {
        // 这个测试无法直接 mock /etc/hosts；但能证明 custom 单独工作时优先于 default
        DNSConfig.customHosts = "localhost=10.0.0.1"
        DNSConfig.readSystemHosts = false
        let map = DNSConfig.collectHostsEntries()
        XCTAssertEqual(map["localhost"], ["10.0.0.1"])
    }
}
