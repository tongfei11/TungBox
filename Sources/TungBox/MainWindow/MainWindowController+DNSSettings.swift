import AppKit
import Foundation

extension MainWindowController: NSTextViewDelegate, NSTextFieldDelegate {

    func makeSettingsDNSPage() -> NSView {
        // -------- 上游 --------
        dnsLocalServerField.stringValue = DNSConfig.localServer
        dnsLocalServerField.placeholderString = DNSConfig.defaultLocalServer
        dnsLocalServerField.translatesAutoresizingMaskIntoConstraints = false
        dnsLocalServerField.heightAnchor.constraint(equalToConstant: 36).isActive = true
        dnsLocalServerField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        dnsLocalServerField.target = self
        dnsLocalServerField.action = #selector(dnsLocalServerCommitted(_:))
        dnsLocalServerField.delegate = self

        dnsProxyServerField.stringValue = DNSConfig.proxyServer
        dnsProxyServerField.placeholderString = DNSConfig.defaultProxyServer
        dnsProxyServerField.translatesAutoresizingMaskIntoConstraints = false
        dnsProxyServerField.heightAnchor.constraint(equalToConstant: 36).isActive = true
        dnsProxyServerField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        dnsProxyServerField.target = self
        dnsProxyServerField.action = #selector(dnsProxyServerCommitted(_:))
        dnsProxyServerField.delegate = self

        dnsStrategyPopup.removeAllItems()
        for strategy in DNSConfig.Strategy.allCases {
            dnsStrategyPopup.addItem(withTitle: strategy.displayName)
        }
        if let idx = DNSConfig.Strategy.allCases.firstIndex(of: DNSConfig.strategy) {
            dnsStrategyPopup.selectItem(at: idx)
        }
        dnsStrategyPopup.target = self
        dnsStrategyPopup.action = #selector(dnsStrategyChanged(_:))
        dnsStrategyPopup.translatesAutoresizingMaskIntoConstraints = false
        dnsStrategyPopup.heightAnchor.constraint(equalToConstant: 36).isActive = true
        dnsStrategyPopup.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let upstreamForm = NSGridView(views: [
            [settingsLabel("国内 DNS"), dnsLocalServerField],
            [settingsLabel("国外 DNS"), dnsProxyServerField],
            [settingsLabel("DNS 策略"), dnsStrategyPopup]
        ])
        upstreamForm.translatesAutoresizingMaskIntoConstraints = false
        upstreamForm.column(at: 0).xPlacement = .trailing
        upstreamForm.column(at: 1).width = 560
        upstreamForm.rowSpacing = 10
        upstreamForm.columnSpacing = 10

        let upstreamHint = dnsHintLabel("支持裸 IP（默认 UDP/53）、tls://(DoT)、https://(DoH)、quic://(DoQ)、h3://(DoH3)。国外 DNS 默认走当前节点出去，防污染。")

        // -------- Fake-IP --------
        dnsFakeIPCheckbox.target = self
        dnsFakeIPCheckbox.action = #selector(dnsFakeIPToggled(_:))
        dnsFakeIPCheckbox.state = DNSConfig.fakeIPEnabled ? .on : .off
        let fakeIPRow = settingsToggleRow(
            title: "启用 Fake-IP",
            hint: "防 DNS 污染 + 省一次解析往返。",
            checkbox: dnsFakeIPCheckbox
        )

        dnsFakeIPRangeField.stringValue = DNSConfig.fakeIPRange
        dnsFakeIPRangeField.placeholderString = DNSConfig.defaultFakeIPRange
        dnsFakeIPRangeField.translatesAutoresizingMaskIntoConstraints = false
        dnsFakeIPRangeField.heightAnchor.constraint(equalToConstant: 36).isActive = true
        dnsFakeIPRangeField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        dnsFakeIPRangeField.target = self
        dnsFakeIPRangeField.action = #selector(dnsFakeIPRangeCommitted(_:))
        dnsFakeIPRangeField.delegate = self

        let rangeRow = NSStackView(views: [settingsLabel("Fake-IP 网段"), dnsFakeIPRangeField])
        rangeRow.orientation = .horizontal
        rangeRow.spacing = 12
        rangeRow.alignment = .centerY
        rangeRow.translatesAutoresizingMaskIntoConstraints = false

        let excludesLabel = settingsLabel("跳过 Fake-IP 的域名（每行一个，使用域名后缀匹配）")
        let excludesScroll = makeMultilineTextHost(textView: dnsFakeIPExcludesTextView,
                                                   initial: DNSConfig.fakeIPExcludes.joined(separator: "\n"),
                                                   height: 120)

        let fakeipFooter = dnsHintLabel("国内域名、私有网段、跳过列表会走真实 DNS；国外域名走 Fake-IP。")

        // -------- Hosts（两个子区独立，互不依赖）--------
        let hostsCustomTitle = settingsLabel("自定义 hosts")
        hostsCustomTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let customHostsLabel = dnsHintLabel("每行一条，格式 `域名=IP`；多 IP 用 ; 分隔。例：`api.local=10.0.0.5`、`dev.example.com=192.168.1.20;192.168.1.21`")
        let customHostsScroll = makeMultilineTextHost(textView: dnsCustomHostsTextView,
                                                      initial: DNSConfig.customHosts,
                                                      height: 110)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 560).isActive = true

        let hostsSystemTitle = settingsLabel("系统 hosts")
        hostsSystemTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        dnsReadSystemHostsCheckbox.target = self
        dnsReadSystemHostsCheckbox.action = #selector(dnsReadSystemHostsToggled(_:))
        dnsReadSystemHostsCheckbox.state = DNSConfig.readSystemHosts ? .on : .off
        let systemHostsRow = settingsToggleRow(
            title: "读取系统 /etc/hosts",
            hint: "TUN 接管 53 端口后系统 /etc/hosts 默认不生效；启用后由 sing-box 一并读取。与上方「自定义 hosts」相互独立，可单独使用；同名域名以自定义为准。",
            checkbox: dnsReadSystemHostsCheckbox
        )

        // -------- 重置（独立放底部，不进 panel）--------
        let resetButton = settingsButton(title: "重置为默认值", action: #selector(dnsSettingsResetClicked), style: .outlined)
        let resetRow = NSStackView(views: [resetButton])
        resetRow.orientation = .horizontal
        resetRow.alignment = .centerY
        resetRow.spacing = 0
        resetRow.translatesAutoresizingMaskIntoConstraints = false

        return settingsPageStack([
            settingsPanel(title: "DNS 上游", views: [upstreamForm, upstreamHint]),
            settingsPanel(title: "Fake-IP", views: [fakeIPRow, settingsDivider(), rangeRow, excludesLabel, excludesScroll, fakeipFooter]),
            settingsPanel(title: "Hosts", views: [
                hostsCustomTitle, customHostsLabel, customHostsScroll,
                divider,
                hostsSystemTitle, systemHostsRow
            ]),
            resetRow
        ])
    }

    // MARK: - 多行文本编辑器宿主

    private func makeMultilineTextHost(textView: NSTextView, initial: String, height: CGFloat, placeholder: String? = nil) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 560).isActive = true

        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textColor = MD3.onSurface
        textView.backgroundColor = MD3.surface
        textView.string = initial
        textView.delegate = self
        registerThemeObserver { [weak textView] in
            textView?.textColor = MD3.onSurface
            textView?.backgroundColor = MD3.surface
        }
        scroll.documentView = textView
        // NSTextView 不支持原生 placeholder；占位提示由外面的 hint label 承担。
        _ = placeholder
        return scroll
    }

    // MARK: - 控件事件（即时保存 + 触发应用）

    @objc func dnsLocalServerCommitted(_ sender: NSTextField) {
        let v = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = v.isEmpty ? DNSConfig.defaultLocalServer : v
        if !v.isEmpty, !isPlausibleDNSURL(v) {
            showToast("国内 DNS 格式不识别：\(v)", style: .warning)
            sender.stringValue = DNSConfig.localServer
            return
        }
        guard normalized != DNSConfig.localServer else { return }
        DNSConfig.localServer = v
        scheduleDNSApply()
    }

    @objc func dnsProxyServerCommitted(_ sender: NSTextField) {
        let v = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = v.isEmpty ? DNSConfig.defaultProxyServer : v
        if !v.isEmpty, !isPlausibleDNSURL(v) {
            showToast("国外 DNS 格式不识别：\(v)", style: .warning)
            sender.stringValue = DNSConfig.proxyServer
            return
        }
        guard normalized != DNSConfig.proxyServer else { return }
        DNSConfig.proxyServer = v
        scheduleDNSApply()
    }

    @objc func dnsStrategyChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        let all = DNSConfig.Strategy.allCases
        guard idx >= 0 && idx < all.count else { return }
        let chosen = all[idx]
        guard chosen != DNSConfig.strategy else { return }
        DNSConfig.strategy = chosen
        scheduleDNSApply()
    }

    @objc func dnsFakeIPToggled(_ sender: NSButton) {
        let on = sender.state == .on
        guard on != DNSConfig.fakeIPEnabled else { return }
        DNSConfig.fakeIPEnabled = on
        scheduleDNSApply()
    }

    @objc func dnsFakeIPRangeCommitted(_ sender: NSTextField) {
        let v = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = v.isEmpty ? DNSConfig.defaultFakeIPRange : v
        if !v.isEmpty, !isPlausibleCIDR(v) {
            showToast("Fake-IP 网段不是有效 CIDR：\(v)", style: .warning)
            sender.stringValue = DNSConfig.fakeIPRange
            return
        }
        guard normalized != DNSConfig.fakeIPRange else { return }
        DNSConfig.fakeIPRange = v
        scheduleDNSApply()
    }

    @objc func dnsReadSystemHostsToggled(_ sender: NSButton) {
        let on = sender.state == .on
        guard on != DNSConfig.readSystemHosts else { return }
        DNSConfig.readSystemHosts = on
        scheduleDNSApply()
    }

    @objc func dnsSettingsResetClicked() {
        DNSConfig.resetAll()
        dnsLocalServerField.stringValue = DNSConfig.defaultLocalServer
        dnsProxyServerField.stringValue = DNSConfig.defaultProxyServer
        dnsFakeIPCheckbox.state = DNSConfig.defaultFakeIPEnabled ? .on : .off
        dnsFakeIPRangeField.stringValue = DNSConfig.defaultFakeIPRange
        dnsFakeIPExcludesTextView.string = DNSConfig.defaultFakeIPExcludes.joined(separator: "\n")
        dnsReadSystemHostsCheckbox.state = DNSConfig.defaultReadSystemHosts ? .on : .off
        dnsCustomHostsTextView.string = DNSConfig.defaultCustomHosts
        if let idx = DNSConfig.Strategy.allCases.firstIndex(of: DNSConfig.defaultStrategy) {
            dnsStrategyPopup.selectItem(at: idx)
        }
        appendLog("[DNS] 已重置为默认值\n")
        showToast("DNS 设置已重置为默认值", style: .info)
        scheduleDNSApply()
    }

    // MARK: - NSControlTextEditingDelegate / NSTextFieldDelegate
    // 文本框失焦时触发 action（fire on resign first responder）

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              let action = field.action else { return }
        switch field {
        case dnsLocalServerField, dnsProxyServerField, dnsFakeIPRangeField,
             tunMTUField, tunIncludeIfaceField, tunExcludeIfaceField:
            NSApp.sendAction(action, to: field.target, from: field)
        default: break
        }
    }

    // MARK: - NSTextViewDelegate

    func textDidEndEditing(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        switch tv {
        case dnsFakeIPExcludesTextView:
            let lines = tv.string.components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard lines != DNSConfig.fakeIPExcludes else { return }
            DNSConfig.fakeIPExcludes = lines
            scheduleDNSApply()
        case dnsCustomHostsTextView:
            let v = tv.string
            guard v != DNSConfig.customHosts else { return }
            DNSConfig.customHosts = v
            scheduleDNSApply()
        case tunRouteExcludeTextView:
            let lines = tv.string.components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard lines != TUNConfig.routeExclude else { return }
            TUNConfig.routeExclude = lines
            // 触发 TUN 应用——直接调用 TUN 那边的 schedule 通过 selector 化的中介，避免
            // 跨文件 private 函数访问问题。这里直接重新启动 reconcile（与 schedule 等价）。
            tunRouteExcludeChanged()
        default: break
        }
    }

    // MARK: - 应用变更（debounced + 视情况重启代理）

    /// 防抖：连续修改多个控件时只在最后一次 500ms 后真正写盘 + 重启代理一次。
    /// 每个 handler 自己已经做了"值没变就 return"的判断，所以进到这里的都是真改动。
    private func scheduleDNSApply() {
        dnsApplyWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applyDNSConfigToActiveProfile()
        }
        dnsApplyWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func applyDNSConfigToActiveProfile() {
        let wasRunning = isProxyRuntimeRunning()
        guard let _ = selectedIndex,
              var config = parseConfigObject(from: editor.string) else {
            appendLog("[DNS] 已保存（无活动配置可热更新，下次刷新订阅时生效）\n")
            return
        }

        let newDNS = DNSConfig.buildSingBoxDNS()
        // 比较新旧 dns 段，相等就什么都不做：避免无意义的写盘 / 重启 / 弹 toast
        let oldDNS = config["dns"] as? [String: Any] ?? [:]
        if canonicalJSON(newDNS) == canonicalJSON(oldDNS) {
            return
        }

        config["dns"] = newDNS
        do {
            editor.string = try renderConfig(config)
            _ = try saveCurrent()
        } catch {
            appendLog("[DNS] 写回当前配置失败：\(error.localizedDescription)\n")
            showToast("DNS 写回失败：\(error.localizedDescription)", style: .warning)
            return
        }
        appendLog("[DNS] 已更新当前配置 dns 段\n")
        if wasRunning {
            appendLog("[DNS] 代理运行中，正在重启服务以应用新 DNS 设置\n")
            showToast("DNS 已更新，正在重启代理", style: .info)
            reconcileRuntime(reason: "DNS 设置变更", forceRestart: true)
        } else {
            showToast("DNS 设置已保存", style: .success)
        }
    }

    private func canonicalJSON(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    // MARK: - 校验

    private func isPlausibleDNSURL(_ s: String) -> Bool {
        if let schemeEnd = s.range(of: "://") {
            let scheme = s[s.startIndex..<schemeEnd.lowerBound].lowercased()
            let known: Set<String> = ["udp", "tcp", "tls", "https", "quic", "h3"]
            guard known.contains(String(scheme)) else { return false }
            return schemeEnd.upperBound < s.endIndex
        }
        return !s.contains("://")
    }

    private func isPlausibleCIDR(_ s: String) -> Bool {
        guard let slash = s.firstIndex(of: "/") else { return false }
        let addr = String(s[s.startIndex..<slash])
        let maskStr = String(s[s.index(after: slash)...])
        guard let mask = Int(maskStr), mask >= 0, mask <= 128 else { return false }
        return !addr.isEmpty
    }

    // MARK: - hint

    private func dnsHintLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = MD3.onSurfaceVariant
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.usesSingleLineMode = false
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.preferredMaxLayoutWidth = 560
        registerThemeObserver { [weak label] in
            label?.textColor = MD3.onSurfaceVariant
        }
        return label
    }
}
