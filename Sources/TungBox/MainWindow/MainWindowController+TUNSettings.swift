import AppKit
import Foundation

extension MainWindowController {

    /// 返回 4 个 TUN 配置 panel + 重置按钮。由 makeSettingsTunPage() 拼接到「服务管理」
    /// panel 后面，共用同一个滚动页面。
    func makeTunConfigPanels() -> [NSView] {
        // -------- 协议栈 --------
        tunStackPopup.removeAllItems()
        for s in TUNConfig.Stack.allCases {
            tunStackPopup.addItem(withTitle: s.displayName)
        }
        if let idx = TUNConfig.Stack.allCases.firstIndex(of: TUNConfig.stack) {
            tunStackPopup.selectItem(at: idx)
        }
        tunStackPopup.target = self
        tunStackPopup.action = #selector(tunStackChanged(_:))
        tunStackPopup.translatesAutoresizingMaskIntoConstraints = false
        tunStackPopup.heightAnchor.constraint(equalToConstant: 36).isActive = true
        tunStackPopup.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let stackRow = NSStackView(views: [settingsLabel("协议栈"), tunStackPopup])
        stackRow.orientation = .horizontal
        stackRow.spacing = 12
        stackRow.alignment = .centerY
        stackRow.translatesAutoresizingMaskIntoConstraints = false

        let stackHint = tunHintLabel("System 最快但兼容性弱；GVisor 兼容最好略慢；Mixed = System TCP + GVisor UDP（默认）。")

        // -------- 网络参数 --------
        tunMTUField.stringValue = String(TUNConfig.mtu)
        tunMTUField.placeholderString = String(TUNConfig.defaultMTU)
        tunMTUField.translatesAutoresizingMaskIntoConstraints = false
        tunMTUField.heightAnchor.constraint(equalToConstant: 36).isActive = true
        tunMTUField.widthAnchor.constraint(equalToConstant: 160).isActive = true
        tunMTUField.target = self
        tunMTUField.action = #selector(tunMTUCommitted(_:))
        tunMTUField.delegate = self

        let mtuRow = NSStackView(views: [settingsLabel("MTU"), tunMTUField])
        mtuRow.orientation = .horizontal
        mtuRow.spacing = 12
        mtuRow.alignment = .centerY
        mtuRow.translatesAutoresizingMaskIntoConstraints = false

        let mtuHint = tunHintLabel("默认 9000（高吞吐）。卡顿 / 部分 PPPoE 或移动热点环境可改 1500。")

        tunStrictRouteCheckbox.target = self
        tunStrictRouteCheckbox.action = #selector(tunStrictRouteToggled(_:))
        tunStrictRouteCheckbox.state = TUNConfig.strictRoute ? .on : .off
        let strictRow = settingsToggleRow(
            title: "严格路由",
            hint: "防泄漏更严格，但会阻止外部访问局域网服务。",
            checkbox: tunStrictRouteCheckbox
        )

        // -------- 路由排除 --------
        let routeExcludeLabel = settingsLabel("排除的 CIDR（每行一条；命中的目标地址绕过 TUN 直连）")
        let routeScroll = makeTunMultilineTextHost(textView: tunRouteExcludeTextView,
                                                   initial: TUNConfig.routeExclude.joined(separator: "\n"),
                                                   height: 130)

        let routeHint = tunHintLabel("默认包含全部私有/链路本地/回环段。需要保留某条 VPN 段或局域网段直连时在这里追加。")

        // -------- 高级 --------
        tunEINCheckbox.target = self
        tunEINCheckbox.action = #selector(tunEINToggled(_:))
        tunEINCheckbox.state = TUNConfig.endpointIndependentNAT ? .on : .off
        let einRow = settingsToggleRow(
            title: "端点独立 NAT",
            hint: "对 P2P / 游戏 / 语音通话更友好，对部分严格 NAT 类型的应用必需。",
            checkbox: tunEINCheckbox
        )

        tunIncludeIfaceField.stringValue = TUNConfig.includeInterface.joined(separator: ", ")
        tunIncludeIfaceField.placeholderString = "留空 = 全部接口；例：en0, en1"
        tunIncludeIfaceField.translatesAutoresizingMaskIntoConstraints = false
        tunIncludeIfaceField.heightAnchor.constraint(equalToConstant: 36).isActive = true
        tunIncludeIfaceField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        tunIncludeIfaceField.target = self
        tunIncludeIfaceField.action = #selector(tunIncludeIfaceCommitted(_:))
        tunIncludeIfaceField.delegate = self

        tunExcludeIfaceField.stringValue = TUNConfig.excludeInterface.joined(separator: ", ")
        tunExcludeIfaceField.placeholderString = "例：awdl0, llw0"
        tunExcludeIfaceField.translatesAutoresizingMaskIntoConstraints = false
        tunExcludeIfaceField.heightAnchor.constraint(equalToConstant: 36).isActive = true
        tunExcludeIfaceField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        tunExcludeIfaceField.target = self
        tunExcludeIfaceField.action = #selector(tunExcludeIfaceCommitted(_:))
        tunExcludeIfaceField.delegate = self

        let advForm = NSGridView(views: [
            [settingsLabel("包含接口"), tunIncludeIfaceField],
            [settingsLabel("排除接口"), tunExcludeIfaceField]
        ])
        advForm.translatesAutoresizingMaskIntoConstraints = false
        advForm.column(at: 0).xPlacement = .trailing
        advForm.column(at: 1).width = 560
        advForm.rowSpacing = 10
        advForm.columnSpacing = 10

        let advHint = tunHintLabel("多网卡场景：只让指定物理网卡的流量进 TUN（包含），或强制某些虚拟接口绕过（排除）。普通用户不用动。")

        let resetButton = settingsButton(title: "重置为默认值", action: #selector(tunSettingsResetClicked), style: .outlined)
        let resetRow = NSStackView(views: [resetButton])
        resetRow.orientation = .horizontal
        resetRow.alignment = .centerY
        resetRow.spacing = 0
        resetRow.translatesAutoresizingMaskIntoConstraints = false

        return [
            settingsPanel(title: "协议栈", views: [stackRow, stackHint]),
            settingsPanel(title: "网络参数", views: [mtuRow, mtuHint, settingsDivider(), strictRow]),
            settingsPanel(title: "路由排除", views: [routeExcludeLabel, routeScroll, routeHint]),
            settingsPanel(title: "高级", views: [einRow, settingsDivider(), advForm, advHint]),
            resetRow
        ]
    }

    // MARK: - 多行文本宿主（跟 DNS 那边一份独立实现，私有命名避免重复）

    private func makeTunMultilineTextHost(textView: NSTextView, initial: String, height: CGFloat) -> NSScrollView {
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
        return scroll
    }

    // MARK: - 控件事件（仅在值真改后保存 + 防抖应用）

    @objc func tunStackChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        let all = TUNConfig.Stack.allCases
        guard idx >= 0 && idx < all.count else { return }
        let v = all[idx]
        guard v != TUNConfig.stack else { return }
        TUNConfig.stack = v
        scheduleTUNApply()
    }

    @objc func tunMTUCommitted(_ sender: NSTextField) {
        let raw = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            guard TUNConfig.mtu != TUNConfig.defaultMTU else { return }
            TUNConfig.mtu = TUNConfig.defaultMTU
            sender.stringValue = String(TUNConfig.defaultMTU)
            scheduleTUNApply()
            return
        }
        guard let mtu = Int(raw), mtu >= 576, mtu <= 65535 else {
            showToast("MTU 不合法（576-65535）：\(raw)", style: .warning)
            sender.stringValue = String(TUNConfig.mtu)
            return
        }
        guard mtu != TUNConfig.mtu else { return }
        TUNConfig.mtu = mtu
        scheduleTUNApply()
    }

    @objc func tunStrictRouteToggled(_ sender: MD3Checkbox) {
        let on = sender.state == .on
        guard on != TUNConfig.strictRoute else { return }
        TUNConfig.strictRoute = on
        scheduleTUNApply()
    }

    @objc func tunEINToggled(_ sender: MD3Checkbox) {
        let on = sender.state == .on
        guard on != TUNConfig.endpointIndependentNAT else { return }
        TUNConfig.endpointIndependentNAT = on
        scheduleTUNApply()
    }

    @objc func tunIncludeIfaceCommitted(_ sender: NSTextField) {
        let parts = sender.stringValue
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts != TUNConfig.includeInterface else { return }
        TUNConfig.includeInterface = parts
        scheduleTUNApply()
    }

    @objc func tunExcludeIfaceCommitted(_ sender: NSTextField) {
        let parts = sender.stringValue
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts != TUNConfig.excludeInterface else { return }
        TUNConfig.excludeInterface = parts
        scheduleTUNApply()
    }

    @objc func tunSettingsResetClicked() {
        TUNConfig.resetAll()
        if let idx = TUNConfig.Stack.allCases.firstIndex(of: TUNConfig.defaultStack) {
            tunStackPopup.selectItem(at: idx)
        }
        tunMTUField.stringValue = String(TUNConfig.defaultMTU)
        tunStrictRouteCheckbox.state = TUNConfig.defaultStrictRoute ? .on : .off
        tunEINCheckbox.state = TUNConfig.defaultEndpointIndependentNAT ? .on : .off
        tunRouteExcludeTextView.string = TUNConfig.defaultRouteExclude.joined(separator: "\n")
        tunIncludeIfaceField.stringValue = TUNConfig.defaultIncludeInterface.joined(separator: ", ")
        tunExcludeIfaceField.stringValue = TUNConfig.defaultExcludeInterface.joined(separator: ", ")
        appendLog("[TUN] 已重置为默认值\n")
        showToast("TUN 设置已重置为默认值", style: .info)
        scheduleTUNApply()
    }

    // MARK: - 应用变更

    /// 跨文件代理入口：路由排除 textview 写回是由 DNS 文件里的 NSTextViewDelegate
    /// dispatcher 触发的（因为 conformance 在那边），它没法直接调本文件的 private
    /// schedule，于是走这个 internal 方法。
    func tunRouteExcludeChanged() {
        scheduleTUNApply()
    }

    /// 跟 DNS 同样的 500ms 防抖；每个 handler 已经做了"值没变就 return"判断，进到这里
    /// 一定是真变更。
    private func scheduleTUNApply() {
        tunApplyWorkItem?.cancel()
        tunSettingsApplyID = UUID()
        let id = tunSettingsApplyID
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in await self?.applyTUNConfigToActiveProfile(id: id) }
        }
        tunApplyWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func applyTUNConfigToActiveProfile(id: UUID) async {
        let generation = runtimeTransitionID
        let profileID = selectedIndex.flatMap { profiles.indices.contains($0) ? profiles[$0].id : nil }
        let current = { [self] in
            tunSettingsApplyID == id && runtimeTransitionID == generation
                && !runtimeCoordinator.state.isTerminating
                && selectedIndex.flatMap { profiles.indices.contains($0) ? profiles[$0].id : nil } == profileID
        }
        let outcome = await TUNSettingsUpdate.apply(isCurrent: current, isBusy: { [self] in
            runtimeCoordinator.state.isTransitioning || isApplyingRuleSets || isSyncingHosts
        }, tunEnabled: { [self] in isTunEnabled }, reload: { [self] in
            guard parseConfigObject(from: editor.string) != nil else { return false }
            return await reloadTunConfigInPlace(configText: editor.string)
        })
        switch outcome {
        case .deferred:
            // Recheck the latest state after the user's switch/transaction finishes.
            guard tunSettingsApplyID == id else { return }
            scheduleTUNApply()
        case .saved:
            appendLog("[TUN] 设置已保存，下次启用 TUN 时生效\n")
        case .reloadRequested:
            appendLog("[TUN] 已按最新设置写入配置并请求 daemon 热重载\n")
            showToast("TUN 设置已保存，已请求重载", style: .info)
        case .failed:
            appendLog("[TUN] 设置已保存，但本次重载请求失败\n")
            showToast("TUN 设置已保存，重载失败，请查看日志", style: .warning)
        case .superseded:
            break
        }
    }

    private func tunHintLabel(_ text: String) -> NSTextField {
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
