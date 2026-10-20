import Foundation

/// Adapts the editor and profile storage to the pure configuration modules in Core.
/// Network discovery and runtime effects remain in MainWindowController+Runtime.swift.
extension MainWindowController {
    func selectProfile(at index: Int, forceReload: Bool = false) {
        guard profiles.indices.contains(index) else { return }
        if !forceReload && selectedIndex == index {
            return
        }
        selectedIndex = index
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        let url = store.configURL(for: profiles[index])
        let rawConfig = (try? String(contentsOf: url)) ?? ""
        var loaded = normalizeLatencyTestURLs(inConfigText: rawConfig) ?? rawConfig
        // Some subscription generators have briefly returned Trojan outbounds
        // without their TLS block. Heal persisted profiles on load as well as at
        // runtime so an older app-created broken profile does not keep failing.
        if let parsed = parseConfigObject(from: loaded) {
            let containedSecret = LocalAPIConfiguration.containsSecret(in: parsed)
            let sanitized = LocalAPIConfiguration.removingSecret(from: parsed)
            let repaired = ConfigCompatibilityChecker.autoFix(config: sanitized)
            if (containedSecret || !repaired.fixed.isEmpty), let rendered = try? renderConfig(repaired.config) {
                loaded = rendered
                try? loaded.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        // Repair a stale/dangling default_domain_resolver (e.g. an old "dns-cn" no
        // longer defined) so the profile passes sing-box check, and persist the fix.
        if let repaired = repairDefaultDomainResolver(inConfigText: loaded) {
            loaded = repaired
            try? loaded.write(to: url, atomically: true, encoding: .utf8)
        }
        editor.string = loaded
        refreshNodesFromEditor()
        refreshModeFromEditor()
        refreshRulesFromEditor()
        selectCurrentNodeInTable()
    }

    @discardableResult
    func saveCurrent() throws -> URL {
        guard let index = selectedIndex else { throw NSError.user("请先选择一个配置") }
        if let normalized = normalizeLatencyTestURLs(inConfigText: editor.string) {
            editor.string = normalized
        }
        if let parsed = parseConfigObject(from: editor.string),
           LocalAPIConfiguration.containsSecret(in: parsed) {
            editor.string = try renderConfig(LocalAPIConfiguration.removingSecret(from: parsed))
        }
        let data = editor.string.data(using: .utf8) ?? Data()
        _ = try JSONSerialization.jsonObject(with: data)
        profiles[index].updatedAt = Date()
        let url = store.configURL(for: profiles[index])
        try editor.string.write(to: url, atomically: true, encoding: .utf8)
        if let (id, rules) = pendingRuleProjection,
           let obj = parseConfigObject(from: editor.string),
           NSArray(array: (obj["route"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []).isEqual(to: rules) {
            try store.saveRuleProjection(editor.string, for: id)
            pendingRuleProjection = nil
        }
        store.saveProfiles(profiles)
        // Saving the profile does not change the watched rule-set files. Keep the
        // last observed revision; subscription changes reset it in the watcher.
        table.reloadData()
        refreshNodesFromEditor()
        refreshRulesFromEditor()
        return url
    }

    func normalizeLatencyTestURLs(inConfigText text: String) -> String? {
        guard var config = parseConfigObject(from: text),
              var outbounds = config["outbounds"] as? [[String: Any]] else {
            return nil
        }

        var changed = false
        for index in outbounds.indices {
            let type = (outbounds[index]["type"] as? String ?? "").lowercased()
            guard ["urltest", "url-test", "fallback"].contains(type),
                  let url = outbounds[index]["url"] as? String,
                  url == "https://www.google.com/generate_204" else {
                continue
            }
            outbounds[index]["url"] = TungBoxConfig.urlTestURL
            changed = true
        }

        guard changed else { return nil }
        config["outbounds"] = outbounds
        return try? renderConfig(config)
    }
    func tunUpstreamHosts(in text: String) -> [String] {
        TUNRuntimeConfigBuilder.upstreamHosts(in: text)
    }

    func preparedTunConfigText(from configText: String, networkSnapshot: TUNRuntimeConfigBuilder.NetworkSnapshot? = nil) throws -> String {
        guard var config = parseConfigObject(from: configText) else {
            throw NSError.user("当前配置不是有效 JSON")
        }
        config = DNSConfig.applying(to: config)
        config = ConfigCompatibilityChecker.autoFix(config: config).config
        config = RuleSetRuntime.localizeBuiltInRuleSets(
            in: config,
            ruleSetDirectory: store.ruleSetsURL
        ).config

        let builder = TUNRuntimeConfigBuilder(
            settings: TUNConfig.snapshot(),
            device: currentTunDevice(),
            fallbackProxyTag: nodes.first?.tag ?? "direct",
            cachePath: TunServiceManager.cachePath,
            clashAPIPort: TungBoxConfig.tunDaemonClashPort,
            clashAPISecret: TungBoxConfig.tunClashAPISecret
        )
        let prepared = builder.prepare(config)
        prepared.diagnostics.forEach { appendLog($0) }

        // 快照中的 nil 表示已探测但没有物理接口，不能再次探测。
        let interface: String?
        if let networkSnapshot {
            interface = networkSnapshot.physicalInterface
        } else {
            interface = TunServiceManager.defaultNetworkInterface()
        }
        let bound = builder.bindPhysicalInterface(interface, in: prepared.config)
        bound.diagnostics.forEach { appendLog($0) }
        let hosts = TUNRuntimeConfigBuilder.hostsNeedingResolution(in: bound.config)
        let addresses = networkSnapshot?.resolvedAddressesByHost ?? resolvePublicIPv4Addresses(forHosts: hosts)
        let output = builder.finish(bound.config, resolvedAddresses: addresses)
        output.diagnostics.forEach { appendLog($0) }
        return try output.text.get()
    }
    func currentTunDevice() -> TUNRuntimeConfigBuilder.Device {
        .init(ipv4Address: TunServiceManager.tunIPv4Address, interfaceName: TunServiceManager.tunInterfaceName)
    }

    func setTunEnabled(_ enabled: Bool, in config: [String: Any]) -> [String: Any] {
        TUNRuntimeConfigBuilder.setTunEnabled(
            enabled, in: config,
            settings: enabled ? TUNConfig.snapshot() : .init(),
            device: currentTunDevice(),
            fallbackProxyTag: nodes.first?.tag ?? "direct",
            cachePath: TunServiceManager.cachePath
        )
    }
    func readMode(from config: [String: Any]) -> String {
        ProxyModeConfig.readMode(from: config)
    }

    func repairDefaultDomainResolver(inConfigText text: String) -> String? {
        ProxyModeConfig.repairDefaultDomainResolver(inConfigText: text)
    }

    func ensureModeSupport(in config: [String: Any], mode: Mode) -> [String: Any] {
        ProxyModeConfig.ensureModeSupport(
            in: config,
            mode: mode.value,
            fallbackProxyTag: nodes.first?.tag ?? "direct"
        )
    }

    func parseConfigObject(from text: String) -> [String: Any]? {
        ConfigCodec.parseObject(from: text)
    }

    func renderConfig(_ config: [String: Any]) throws -> String {
        try ConfigCodec.render(config)
    }
    func defaultConfig() -> String {
        """
        {
          "log": {
            "level": "info"
          },
          "inbounds": [
            {
              "type": "mixed",
              "tag": "mixed-in",
              "listen": "127.0.0.1",
              "listen_port": 7890
            }
          ],
          "outbounds": [
            {
              "type": "direct",
              "tag": "direct"
            }
          ],
          "route": {
            "final": "direct"
          }
        }
        """
    }
    func getMixedProxyPort() -> Int {
        guard let data = editor.string.data(using: .utf8),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inbounds = config["inbounds"] as? [[String: Any]] else {
            return 7890
        }

        for inbound in inbounds {
            if let type = inbound["type"] as? String, type == "mixed",
               let port = inbound["listen_port"] as? Int {
                return port
            }
        }

        for inbound in inbounds {
            if let type = inbound["type"] as? String, type == "http",
               let port = inbound["listen_port"] as? Int {
                return port
            }
        }

        return 7890
    }
}
