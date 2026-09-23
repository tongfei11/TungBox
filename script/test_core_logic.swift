import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum CoreLogicTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundled = root.appendingPathComponent("bundled")
        let installed = root.appendingPathComponent("installed")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("bundled-private".utf8).write(to: bundled.appendingPathComponent("geosite-private.srs"))
        try Data("bundled-cn".utf8).write(to: bundled.appendingPathComponent("geosite-cn.srs"))
        try Data("updated-private".utf8).write(to: installed.appendingPathComponent("geosite-private.srs"))
        try RuleSetRuntime.installBundledRuleSets(from: bundled, to: installed)
        let installedPrivate = try Data(contentsOf: installed.appendingPathComponent("geosite-private.srs"))
        let installedCN = try Data(contentsOf: installed.appendingPathComponent("geosite-cn.srs"))
        expect(
            installedPrivate == Data("updated-private".utf8),
            "内置规则不能覆盖已更新的本地规则"
        )
        expect(
            installedCN == Data("bundled-cn".utf8),
            "缺失规则应从内置资源补齐"
        )

        let config: [String: Any] = [
            "route": [
                "rule_set": [
                    ["type": "remote", "tag": "geosite-private", "format": "binary", "url": "https://example.com/private.srs", "download_detour": "direct", "update_interval": "7d"],
                    ["type": "remote", "tag": "third-party", "format": "binary", "url": "https://example.com/third-party.srs"]
                ]
            ]
        ]
        let localized = RuleSetRuntime.localizeBuiltInRuleSets(in: config, ruleSetDirectory: installed)
        let route = localized.config["route"] as! [String: Any]
        let sets = route["rule_set"] as! [[String: Any]]
        expect(localized.didChange, "内置远程规则应切换为本地规则")
        expect(sets[0]["type"] as? String == "local", "内置规则类型应为 local")
        expect(sets[0]["url"] == nil, "运行配置不应保留远程 URL")
        expect(localized.remoteSources["geosite-private"]?.absoluteString == "https://example.com/private.srs", "应保留后台更新源")
        expect(sets[1]["type"] as? String == "remote", "第三方规则不应被改写")

        let now = Date(timeIntervalSince1970: 2_000_000)
        let privateFile = installed.appendingPathComponent("geosite-private.srs")
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-8 * 86_400)], ofItemAtPath: privateFile.path)
        expect(RuleSetRuntime.needsRefresh(tag: "geosite-private", fileURL: privateFile, now: now), "超过七天的 private 规则应更新")
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-6 * 86_400)], ofItemAtPath: privateFile.path)
        expect(!RuleSetRuntime.needsRefresh(tag: "geosite-private", fileURL: privateFile, now: now), "七天内的 private 规则不应重复下载")
        expect(RuleSetRuntime.needsRefresh(tag: "geoip-cn", fileURL: installed.appendingPathComponent("missing.srs"), now: now), "缺失规则应立即更新")

        expect(RuleSearch.matches(type: "DOMAIN", value: "example.com", strategy: "代理", note: "示例", isSection: false, query: "example"), "搜索应匹配规则值")
        expect(!RuleSearch.matches(type: "IP-CIDR", value: "192.0.2.0/24", strategy: "直连", note: "测试", isSection: false, query: "example"), "搜索应排除不匹配规则")
        expect(RuleSearch.matches(type: "", value: "# 当前配置规则", strategy: "", note: "", isSection: true, query: "example"), "筛选结果应保留分组标题")

        var connectionGate = FirstConnectionGate()
        expect(!connectionGate.hasConnected, "首次启动前不应视为网络已就绪")
        expect(connectionGate.markConnected(), "首次连接成功后应触发延后网络任务")
        expect(connectionGate.hasConnected, "连接成功后应记录已就绪")
        expect(!connectionGate.markConnected(), "同一进程后续连接不应重复触发自动检查")

        expect(StartupNetworkPolicy.systemProxyConfigured(in: ["HTTPEnable": 1]), "应识别 HTTP 系统代理")
        expect(StartupNetworkPolicy.systemProxyConfigured(in: ["ProxyAutoConfigEnable": 1]), "应识别 PAC 系统代理")
        expect(!StartupNetworkPolicy.systemProxyConfigured(in: [:]), "没有启用项时不应误判为系统代理")
        expect(StartupNetworkPolicy.subscriptionRoutes(systemProxyConfigured: true) == [.systemProxy, .direct], "存在其他系统代理时应优先使用，失败后再直连")
        expect(StartupNetworkPolicy.subscriptionRoutes(systemProxyConfigured: false) == [.systemProxy], "没有系统代理时不应重复发起直连请求")
        let directProxyPolicy = StartupNetworkPolicy.proxyDictionary(for: .direct)
        expect(directProxyPolicy?["HTTPEnable"] as? Int == 0, "直连兜底必须禁用 HTTP 系统代理")
        expect(directProxyPolicy?["HTTPSEnable"] as? Int == 0, "直连兜底必须禁用 HTTPS 系统代理")
        expect(directProxyPolicy?["SOCKSEnable"] as? Int == 0, "直连兜底必须禁用 SOCKS 系统代理")
        expect(StartupNetworkPolicy.proxyDictionary(for: .systemProxy) == nil, "系统代理路径必须继承 macOS 代理设置")
        let connectedProxyPolicy = StartupNetworkPolicy.postConnectionProxyDictionary(proxyPort: 7890)
        expect(connectedProxyPolicy["HTTPEnable"] as? Int == 1, "连接后后台请求应启用本地 HTTP 代理")
        expect(connectedProxyPolicy["HTTPPort"] as? Int == 7890, "连接后后台请求应使用已就绪的代理端口")
        let tunProxyPolicy = StartupNetworkPolicy.postConnectionProxyDictionary(proxyPort: nil)
        expect(tunProxyPolicy["HTTPEnable"] as? Int == 0, "仅 TUN 模式应绕过残留系统代理")
        expect(RuleSetRuntime.cachePreparationAction(hasLocalSRS: true, hasConnected: false) == .decompileLocal, "连接前应直接解包内置规则")
        expect(RuleSetRuntime.cachePreparationAction(hasLocalSRS: false, hasConnected: false) == .waitForConnection, "连接前缺失规则时不得访问远程资源")
        expect(RuleSetRuntime.cachePreparationAction(hasLocalSRS: false, hasConnected: true) == .download, "连接后才允许下载缺失规则")

        print("PASS: core logic tests")
    }
}
