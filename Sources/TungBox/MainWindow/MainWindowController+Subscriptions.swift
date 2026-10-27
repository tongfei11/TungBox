import AppKit
import Foundation

extension MainWindowController {
    
    func makeSubscriptionsView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        let title = NSTextField(labelWithString: "订阅")
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false
        tightenLabelCell(title)
        registerThemeObserver { [weak title] in
            title?.textColor = MD3.onSurface
        }

        let subtitle = NSTextField(labelWithString: "管理订阅链接，获取并更新节点信息")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = MD3.onSurfaceVariant
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        tightenLabelCell(subtitle)
        registerThemeObserver { [weak subtitle] in
            subtitle?.textColor = MD3.onSurfaceVariant
        }

        let headerStack = NSStackView(views: [title, subtitle])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 3
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let addButton = MD3Button()
        addButton.title = "添加订阅"
        addButton.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: nil)
        addButton.style = .filled
        addButton.target = self
        addButton.action = #selector(addSubscriptionClicked)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.heightAnchor.constraint(equalToConstant: ConsoleControlLayout.actionHeight).isActive = true

        let refreshAllButton = MD3Button()
        refreshAllButton.title = "刷新全部"
        refreshAllButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        refreshAllButton.style = .outlined
        refreshAllButton.target = self
        refreshAllButton.action = #selector(refreshAllSubscriptionsClicked)
        refreshAllButton.translatesAutoresizingMaskIntoConstraints = false
        refreshAllButton.heightAnchor.constraint(equalToConstant: ConsoleControlLayout.actionHeight).isActive = true

        let importFileButton = MD3Button()
        importFileButton.title = "从文件导入"
        importFileButton.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        importFileButton.style = .outlined
        importFileButton.target = self
        importFileButton.action = #selector(importSubscriptionFileClicked)
        importFileButton.translatesAutoresizingMaskIntoConstraints = false
        importFileButton.heightAnchor.constraint(equalToConstant: ConsoleControlLayout.actionHeight).isActive = true

        let importClipboardButton = MD3Button()
        importClipboardButton.title = "从剪贴板"
        importClipboardButton.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        importClipboardButton.style = .outlined
        importClipboardButton.target = self
        importClipboardButton.action = #selector(importSubscriptionFromClipboardClicked)
        importClipboardButton.translatesAutoresizingMaskIntoConstraints = false
        importClipboardButton.heightAnchor.constraint(equalToConstant: ConsoleControlLayout.actionHeight).isActive = true

        let deleteButton = MD3Button()
        deleteButton.title = "删除订阅"
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        deleteButton.style = .destructive
        deleteButton.target = self
        deleteButton.action = #selector(deleteSubscriptionClicked)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.heightAnchor.constraint(equalToConstant: ConsoleControlLayout.actionHeight).isActive = true

        let buttons = NSStackView(views: [addButton, refreshAllButton, importFileButton, importClipboardButton, deleteButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.edgeInsets = NSEdgeInsetsZero
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let scroll = MD3ScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.applyThinOverlayScroller()
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        
        subscriptionTable.backgroundColor = .clear
        subscriptionTable.selectionHighlightStyle = .none
        subscriptionTable.autoresizingMask = [.width]
        if #available(macOS 11.0, *) {
            subscriptionTable.style = .fullWidth
        }
        
        let subColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("subscription"))
        subColumn.resizingMask = .autoresizingMask
        subscriptionTable.addTableColumn(subColumn)
        subscriptionTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        
        subscriptionTable.headerView = nil
        subscriptionTable.delegate = self
        subscriptionTable.dataSource = self
        subscriptionTable.intercellSpacing = NSSize(width: 0, height: 12)
        subscriptionTable.rowHeight = 160
        scroll.documentView = subscriptionTable
        subscriptionTable.sizeLastColumnToFit()

        view.addSubview(headerStack)
        view.addSubview(buttons)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),

            buttons.leadingAnchor.constraint(equalTo: headerStack.leadingAnchor),
            buttons.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 18),
            buttons.heightAnchor.constraint(equalToConstant: 34),

            scroll.leadingAnchor.constraint(equalTo: headerStack.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            scroll.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 16),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24)
        ])

        let emptyLabel = subscriptionZeroStateLabel(panel: scroll)
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: scroll.widthAnchor, constant: -32)
        ])

        refreshSubscriptionEmptyState()
        return view
    }

    func subscriptionZeroStateLabel(panel: NSView) -> NSTextField {
        let label = NSTextField(labelWithString: "暂无订阅\n\n点击「添加订阅」导入机场链接或 sing-box 订阅地址。\n支持 sing-box JSON、Clash YAML 等格式。")
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = MD3.onSurfaceVariant
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak label] in
            label?.textColor = MD3.onSurfaceVariant
        }
        zeroStateView = label
        return label
    }

    func refreshSubscriptionEmptyState() {
        zeroStateView?.isHidden = !subscriptions.isEmpty
        subscriptionTable.isHidden = subscriptions.isEmpty
    }

    @objc func addSubscriptionClicked() {
        let nameField = MD3TextField()
        nameField.placeholderString = "订阅名称 (如: Xboard)"
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 432).isActive = true
        nameField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let urlField = MD3TextField()
        urlField.placeholderString = "https://..."
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.widthAnchor.constraint(equalToConstant: 432).isActive = true
        urlField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let stack = NSStackView(views: [nameField, urlField])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 432),
            container.heightAnchor.constraint(equalToConstant: 84)
        ])

        let dialog = showMD3Dialog(
            title: "添加订阅",
            message: "请输入新订阅的名称和配置 URL。",
            customView: container
        )
        
        dialog.window?.initialFirstResponder = nameField
        
        dialog.onConfirm = { [weak self, weak nameField, weak urlField, weak dialog] in
            guard let self = self else { return }
            let name = nameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = urlField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            guard !name.isEmpty else {
                self.showError(NSError.user("订阅名称不能为空"))
                return
            }
            guard !url.isEmpty else {
                self.showError(NSError.user("订阅 URL 不能为空"))
                return
            }

            let subscription = Subscription(
                id: UUID(),
                name: name,
                url: url,
                profileID: nil,
                updatedAt: nil
            )
            self.subscriptions.append(subscription)
            self.store.saveSubscriptions(self.subscriptions)
            self.selectSubscription(at: self.subscriptions.count - 1)
            self.refreshSubscription(at: self.subscriptions.count - 1)
            dialog?.dismiss()
        }
        
        dialog.onCancel = { [weak dialog] in
            dialog?.dismiss()
        }
    }

    @objc func refreshAllSubscriptionsClicked() {
        guard !subscriptions.isEmpty else {
            showToast("暂无订阅可刷新", style: .info)
            return
        }
        showToast("正在刷新全部 \(subscriptions.count) 个订阅...", style: .info)
        for index in subscriptions.indices {
            refreshSubscription(at: index)
        }
    }

    @objc func updateSubscriptionClicked() {
        guard let index = selectedSubscriptionIndex, subscriptions.indices.contains(index) else {
            showError(NSError.user("请先选择一个订阅"))
            return
        }
        let subscription = subscriptions[index]

        let nameField = MD3TextField()
        nameField.stringValue = subscription.name
        nameField.placeholderString = "订阅名称"
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 432).isActive = true
        nameField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let urlField = MD3TextField()
        urlField.stringValue = subscription.url
        urlField.placeholderString = "https://..."
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.widthAnchor.constraint(equalToConstant: 432).isActive = true
        urlField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let stack = NSStackView(views: [nameField, urlField])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 432),
            container.heightAnchor.constraint(equalToConstant: 84)
        ])

        let dialog = showMD3Dialog(
            title: "编辑订阅",
            message: "请修改订阅的名称或配置 URL。",
            customView: container
        )
        
        dialog.window?.initialFirstResponder = nameField
        
        dialog.onConfirm = { [weak self, weak nameField, weak urlField, weak dialog] in
            guard let self = self else { return }
            let name = nameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = urlField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            guard !name.isEmpty else {
                self.showError(NSError.user("订阅名称不能为空"))
                return
            }
            guard !url.isEmpty else {
                self.showError(NSError.user("订阅 URL 不能为空"))
                return
            }

            self.subscriptionRefreshTracker.invalidate(subscriptionID: subscription.id)
            var updated = subscription
            updated.name = name
            updated.url = url
            updated.lastError = nil
            updated.upload = nil
            updated.download = nil
            updated.total = nil
            updated.expiresAt = nil
            self.subscriptions[index] = updated
            self.store.saveSubscriptions(self.subscriptions)
            self.subscriptionTable.reloadData()
            refreshSubscriptionEmptyState()
            refreshSubscriptionBadge()
            self.refreshSubscription(at: index)
            dialog?.dismiss()
        }
        
        dialog.onCancel = { [weak dialog] in
            dialog?.dismiss()
        }
    }

    @objc func deleteSubscriptionClicked() {
        guard let index = selectedSubscriptionIndex, subscriptions.indices.contains(index) else { return }
        let removed = subscriptions[index]
        subscriptionRefreshTracker.invalidate(subscriptionID: removed.id)
        do {
            if let profileID = removed.profileID,
               let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) {
                profiles[profileIndex] = try store.detachProfile(profiles[profileIndex], from: removed.id)
                store.saveProfiles(profiles)
            } else {
                let folder = store.subscriptionFolder(for: removed.id)
                if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            }
        } catch { showError(error); return }
        customRules.removeAll { $0.subscriptionID == removed.id }
        store.saveCustomRules(customRules)
        let name = subscriptions[index].name
        subscriptions.remove(at: index)
        selectSubscription(at: nil)
        store.saveSubscriptions(subscriptions)
        showToast("订阅「\(name)」已删除", style: .info)
    }

    func selectSubscription(at index: Int?) {
        guard let index = index else {
            selectedSubscriptionIndex = nil
            subscriptionNameField.stringValue = ""
            subscriptionURLField.stringValue = ""
            nodes = []
            nodeTable.reloadData()
            subscriptionTable.reloadData()
            refreshSubscriptionEmptyState()
            refreshSubscriptionBadge()
            return
        }
        guard subscriptions.indices.contains(index) else { return }
        let switchingProfile = subscriptions[index].profileID != currentSubscription()?.profileID
        selectedSubscriptionIndex = index
        let subscription = subscriptions[index]
        subscriptionNameField.stringValue = subscription.name
        subscriptionURLField.stringValue = subscription.url

        // Load associated profile
        if let profileID = subscription.profileID,
           let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) {
            selectProfile(at: profileIndex)
        } else {
            nodes = []
            nodeTable.reloadData()
        }
        subscriptionTable.reloadData()
        refreshSubscriptionEmptyState()
        refreshSubscriptionBadge()

        // 切到不同订阅就给提示 —— 节点列表会换成新订阅的，无论代理是否在跑都
        // 对用户有实际影响。
        if switchingProfile {
            showToast("已切换到订阅「\(subscription.name)」", style: .success)
        }
        // 代理/TUN 在跑：runner 还在跑旧订阅的 sing-box，editor/磁盘已经是新订阅。
        // 必须原子地切换 runner，否则流量仍从旧节点出，而节点表显示新节点
        // （用户看到：切了订阅但实际节点没变）。
        if switchingProfile, isSystemProxyEnabled || isTunEnabled {
            beginFeatureTransition(
                systemProxy: isSystemProxyEnabled ? .starting : nil,
                tun: isTunEnabled ? .starting : nil
            )
            for i in nodes.indices { nodes[i].delay = "未测试" }
            refreshNodeGroupsView()
            Task { _ = try? await ClashAPI.closeConnections(port: delayAPIPort()) }
            reconcileRuntime(reason: "切换订阅", forceRestart: true)
        }
    }

    func createProfile(named name: String, content: String) {
        let id = UUID()
        let profile = ConfigProfile(id: id, name: name, fileName: store.profileFileName(id: id), updatedAt: Date())
        profiles.append(profile)
        try? content.write(to: store.configURL(for: profile), atomically: true, encoding: .utf8)
        store.saveProfiles(profiles)
        table.reloadData()
        selectProfile(at: profiles.count - 1)
    }

    func subscriptionFromFields(existing: Subscription?) throws -> Subscription {
        let name = subscriptionNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = subscriptionURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw NSError.user("请输入订阅名称") }
        guard !url.isEmpty else { throw NSError.user("请输入订阅 URL") }
        return Subscription(
            id: existing?.id ?? UUID(),
            name: name,
            url: url,
            profileID: existing?.profileID,
            updatedAt: existing?.updatedAt
        )
    }

    func refreshSubscription(at index: Int, automatic: Bool = false) {
        guard subscriptions.indices.contains(index) else { return }
        let subscription = subscriptions[index]
        let refreshToken = subscriptionRefreshTracker.begin(subscriptionID: subscription.id, url: subscription.url)
        appendLog("[订阅] 开始刷新 \(subscription.name)\n")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                // 用 UA 回退拉取：sing-box / clash 多个 UA 依次试，挑出第一个能
                // 解析到节点的版本（很多机场后端给不同 UA 返回不同内容）。同时
                // 拿响应头里的 subscription-userinfo（流量/到期）。
                let (content, ua, info) = try SubscriptionImporter.fetchBest(urlString: subscription.url)
                let summary = try SubscriptionImporter.extractWithSummary(content)
                let format = summary.format
                let nodes = summary.nodes
                let skippedTotal = summary.skippedTotal
                let skippedDetail = summary.skippedTypesDescription
                let config = try SubscriptionImporter.singBoxConfig(from: content, profileName: subscription.name)
                let fixLog = SubscriptionImporter.compatibilityFixLog
                SubscriptionImporter.compatibilityFixLog = []
                // Check for manual-fix issues
                var manualIssues: [ConfigCompatibilityChecker.Issue] = []
                if let data = config.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    manualIssues = ConfigCompatibilityChecker.check(config: obj).filter { !$0.autoFixed }
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    defer {
                        if automatic { self.finishAutomaticSubscriptionRefresh(subscriptionID: subscription.id) }
                    }
                    guard let idx = self.subscriptions.firstIndex(where: { $0.id == subscription.id }),
                          self.subscriptionRefreshTracker.isCurrent(refreshToken, currentURL: self.subscriptions[idx].url) else { return }
                    if ua != SubscriptionImporter.fallbackUserAgents.first {
                        self.appendLog("[订阅] 服务端按 UA 返回不同内容，使用「\(ua)」拉取成功\n")
                    }
                    self.subscriptions[idx].upload = info.upload
                    self.subscriptions[idx].download = info.download
                    self.subscriptions[idx].total = info.total
                    self.subscriptions[idx].expiresAt = info.expiresAt
                    self.subscriptions[idx].lastError = nil
                    self.store.saveSubscriptions(self.subscriptions)
                    self.subscriptionTable.reloadData()
                    self.appendLog("[订阅] 检测到 \(format.rawValue) 格式，\(nodes.count) 个节点\n")
                    if skippedTotal > 0 {
                        self.appendLog("[订阅] \(skippedTotal) 个节点协议不支持已跳过（\(skippedDetail)）\n")
                        self.showToast("\(subscription.name): \(skippedTotal) 个节点协议不支持已跳过（\(skippedDetail)）", style: .warning, duration: 5.0)
                    }
                    for fix in fixLog { self.appendLog(fix + "\n") }
                    for issue in manualIssues {
                        self.appendLog("[兼容性] [\(issue.severity.rawValue)] \(issue.path): \(issue.message)\n")
                    }
                    let errorCount = manualIssues.filter({ $0.severity == .error }).count
                    if errorCount > 0 {
                        let dialog = self.showMD3Dialog(
                            title: "配置兼容性警告",
                            message: "订阅包含 \(errorCount) 个已弃用的配置项，在当前 Core 版本上可能无法正常启动。\n\n是否安装兼容旧配置的 sing-box 1.11.10？\n\n（可在 设置 → Core 管理 中随时装回最新版）",
                            customView: nil,
                            confirmTitle: "安装兼容旧版 Core",
                            cancelTitle: "忽略"
                        )
                        dialog.onConfirm = { [weak self, weak dialog] in
                            dialog?.dismiss()
                            Task {
                                await self?.downgradeCoreForCompatibility()
                            }
                        }
                        dialog.onCancel = { [weak dialog] in dialog?.dismiss() }
                    }
                    self.applySubscriptionConfig(config, for: subscription.id, refreshToken: refreshToken)
                }
            } catch {
                let errorMsg = error.localizedDescription
                DispatchQueue.main.async {
                    guard let self else { return }
                    defer {
                        if automatic { self.finishAutomaticSubscriptionRefresh(subscriptionID: subscription.id) }
                    }
                    guard let currentIndex = self.subscriptions.firstIndex(where: { $0.id == subscription.id }),
                          self.subscriptionRefreshTracker.isCurrent(refreshToken, currentURL: self.subscriptions[currentIndex].url) else { return }
                    // Store error on subscription card
                    if var sub = self.subscriptions.first(where: { $0.id == subscription.id }) {
                        sub.lastError = errorMsg
                        if let idx = self.subscriptions.firstIndex(where: { $0.id == sub.id }) {
                            self.subscriptions[idx].lastError = errorMsg
                            self.store.saveSubscriptions(self.subscriptions)
                            self.subscriptionTable.reloadData()
                        }
                    }
                    // 卡片状态与日志已呈现失败，后台刷新不再弹窗或发送系统通知。
                    self.appendLog("[订阅] \(subscription.name) 刷新失败：\(errorMsg)\n")
                }
            }
        }
    }

    func startSubscriptionTimer() {
        subscriptionTimer?.invalidate()
        subscriptionTimer = nil

        let minutes = SubscriptionRefreshSchedule.minutes()

        // If set to "off" (0 minutes), don't start a timer
        guard minutes != 0 else {
            appendLog("[订阅] 自动刷新已关闭\n")
            return
        }

        subscriptionTimer = SubscriptionRefreshSchedule.makeTimer(minutes: minutes) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.subscriptions.isEmpty else { return }
                guard self.subscriptionRefreshBatch.begin(subscriptionIDs: self.subscriptions.map(\.id)) else {
                    self.appendLog("[订阅] 上一批自动刷新尚未结束，本次跳过\n")
                    return
                }
                self.appendLog("[订阅] 自动刷新开始\n")
                self.subscriptionAutoStatusLabel.stringValue = "订阅自动刷新：正在刷新 \(self.subscriptions.count) 个订阅"
                for index in self.subscriptions.indices {
                    self.refreshSubscription(at: index, automatic: true)
                }
            }
        }
        appendLog("[订阅] 自动刷新已开启，间隔：\(SubscriptionRefreshSchedule.statusText(minutes: minutes))\n")
    }

    func finishAutomaticSubscriptionRefresh(subscriptionID: UUID) {
        guard let shouldReload = subscriptionRefreshBatch.finish(
            subscriptionID: subscriptionID, currentSubscriptionID: currentSubscription()?.id,
            runtimeGeneration: runtimeTransitionID
        ) else { return }
        appendLog("[订阅] 本批自动刷新已结束\n")
        let minutes = SubscriptionRefreshSchedule.minutes()
        subscriptionAutoStatusLabel.stringValue = "订阅自动刷新：\(SubscriptionRefreshSchedule.statusText(minutes: minutes))，最近一批已结束"
        if shouldReload { reloadRuntimeAfterSubscriptionRefresh() }
    }

    func applySubscriptionConfig(
        _ config: String,
        for subscriptionID: UUID,
        refreshToken: SubscriptionRefreshToken? = nil
    ) {
        guard let index = subscriptions.firstIndex(where: { $0.id == subscriptionID }) else { return }
        if let refreshToken,
           !subscriptionRefreshTracker.isCurrent(refreshToken, currentURL: subscriptions[index].url) {
            appendLog("[订阅] 已丢弃过期刷新结果\n")
            return
        }
        var subscription = subscriptions[index]
        let profileName = "订阅 - \(subscription.name)"

        let existingIndex = subscription.profileID.flatMap { id in profiles.firstIndex { $0.id == id } }
        let newProfileID = UUID()
        var profile = existingIndex.map { profiles[$0] } ?? ConfigProfile(
            id: newProfileID,
            name: profileName,
            fileName: store.profileFileName(id: newProfileID, subscriptionID: subscription.id),
            updatedAt: Date()
        )
        let configURL = store.configURL(for: profile)
        let baseURL = store.ruleBaseURL(for: subscription.id)
        let projectionURL = store.ruleProjectionURL(for: subscription.id)
        var resolvedConfig = config
        if FileManager.default.fileExists(atPath: configURL.path),
           let existingText = try? String(contentsOf: configURL, encoding: .utf8) {
            resolvedConfig = ProxyModeConfig.preserveSelectorDefaults(from: existingText, into: config)
        }
        var snapshots: [(URL, Data?)] = []
        do {
            for url in [configURL, baseURL, projectionURL] {
                snapshots.append((url, FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil))
            }
            try store.saveRuleBase(resolvedConfig, for: subscription.id)
            let merged = try renderConfig(try applyCustomRules(to: resolvedConfig, subscriptionID: subscription.id))
            try checkRuleSetConfig(merged)
            try Data(merged.utf8).write(to: configURL, options: .atomic)
            try store.saveRuleProjection(merged, for: subscription.id)
        } catch {
            do {
                for (url, data) in snapshots {
                    if let data { try data.write(to: url, options: .atomic) }
                    else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                }
            } catch let restoreError { showError(NSError.user("刷新失败且恢复失败：\(restoreError.localizedDescription)")) }
            pendingRuleProjection = nil
            showError(error)
            return
        }
        pendingRuleProjection = nil
        profile.name = profileName
        profile.updatedAt = Date()
        let updatedProfileIndex: Int
        if let existingIndex {
            profiles[existingIndex] = profile
            updatedProfileIndex = existingIndex
        } else {
            profiles.append(profile)
            updatedProfileIndex = profiles.count - 1
            if selectedIndex == nil { selectedIndex = updatedProfileIndex }
        }
        subscription.profileID = profile.id
        subscription.updatedAt = Date()
        subscriptions[index] = subscription
        store.saveProfiles(profiles)
        store.saveSubscriptions(subscriptions)
        table.reloadData()
        subscriptionTable.reloadData()
        refreshSubscriptionEmptyState()
        refreshSubscriptionBadge()

        // 关键修复：只在被刷新的订阅就是**当前活动 profile** 时才重载 editor /
        // 节点表 / 重启代理。否则刷新订阅 A 会把当前正在用的订阅 B 切走（你看到
        // 的"刷新一下就被切过去"的 bug 就是从这来的）。
        let isCurrent = (selectedIndex == updatedProfileIndex)
        if isCurrent {
            selectProfile(at: updatedProfileIndex, forceReload: true)
            refreshNodesFromEditor()
            refreshHomeFeatureStatus()
        }
        appendLog("[订阅] \(subscription.name) 已刷新并写入配置\n")
        RecentStatusTracker.shared.record("订阅「\(subscription.name)」已更新", level: .success)
        showToast("订阅「\(subscription.name)」已更新", style: .success)

        // runner 重启**只**在当前 profile 被刷新时做。其他订阅的刷新不应该惊动当前
        // 流量。
        if isCurrent, isSystemProxyEnabled || isTunEnabled {
            if subscriptionRefreshBatch.deferReload(subscriptionID: subscriptionID, runtimeGeneration: runtimeTransitionID) {
                appendLog("[订阅] 当前订阅已更新，等待本批下载结束后应用运行配置\n")
            } else {
                reloadRuntimeAfterSubscriptionRefresh()
            }
        }
    }

    func reloadRuntimeAfterSubscriptionRefresh() {
        guard !runtimeCoordinator.state.isTerminating, isSystemProxyEnabled || isTunEnabled else { return }
        beginFeatureTransition(
            systemProxy: isSystemProxyEnabled ? .starting : nil,
            tun: isTunEnabled ? .starting : nil
        )
        for i in nodes.indices { nodes[i].delay = "未测试" }
        refreshNodeGroupsView()
        Task { _ = try? await ClashAPI.closeConnections(port: delayAPIPort()) }
        reconcileRuntime(reason: "订阅刷新", forceRestart: true)
    }

    func currentSubscription() -> Subscription? {
        if let index = selectedSubscriptionIndex, subscriptions.indices.contains(index) {
            return subscriptions[index]
        }
        guard let selectedIndex, profiles.indices.contains(selectedIndex) else { return nil }
        let profileID = profiles[selectedIndex].id
        return subscriptions.first { $0.profileID == profileID }
    }

    // MARK: - File / Clipboard import

    @objc func importSubscriptionFileClicked() {
        let panel = NSOpenPanel()
        panel.title = "导入订阅文件"
        panel.message = "选择本地订阅配置文件（JSON、YAML 或 Base64 文本）"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .yaml, .text, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let summary = try SubscriptionImporter.extractWithSummary(content)
            let config = try SubscriptionImporter.singBoxConfig(from: content, profileName: url.deletingPathExtension().lastPathComponent)
            let newName = url.deletingPathExtension().lastPathComponent
            let subscription = Subscription(id: UUID(), name: newName, url: url.absoluteString, profileID: nil, updatedAt: Date())
            subscriptions.append(subscription)
            store.saveSubscriptions(subscriptions)
            applySubscriptionConfig(config, for: subscription.id)
            subscriptionTable.reloadData()
            refreshSubscriptionBadge()
            appendLog("[订阅] 从文件导入 \(newName)（\(summary.nodes.count) 个节点）\n")
            if summary.skippedTotal > 0 {
                let detail = summary.skippedTypesDescription
                appendLog("[订阅] \(summary.skippedTotal) 个节点协议不支持已跳过（\(detail)）\n")
                showToast("\(newName): \(summary.skippedTotal) 个节点协议不支持已跳过（\(detail)）", style: .warning, duration: 5.0)
            }
        } catch {
            showError(NSError.user("文件导入失败：\(error.localizedDescription)"))
        }
    }

    @objc func importSubscriptionFromClipboardClicked() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            showError(NSError.user("剪贴板为空，请先复制订阅链接或配置内容。"))
            return
        }

        // URL in clipboard → pre-fill add dialog
        if let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()) {
            let nameField = MD3TextField()
            nameField.placeholderString = "订阅名称 (如: 机场名)"
            nameField.translatesAutoresizingMaskIntoConstraints = false
            nameField.widthAnchor.constraint(equalToConstant: 432).isActive = true
            nameField.heightAnchor.constraint(equalToConstant: 36).isActive = true

            let urlField = MD3TextField()
            urlField.stringValue = text
            urlField.translatesAutoresizingMaskIntoConstraints = false
            urlField.widthAnchor.constraint(equalToConstant: 432).isActive = true
            urlField.heightAnchor.constraint(equalToConstant: 36).isActive = true

            let stack = NSStackView(views: [nameField, urlField])
            stack.orientation = .vertical; stack.spacing = 12; stack.alignment = .leading
            stack.translatesAutoresizingMaskIntoConstraints = false
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                stack.topAnchor.constraint(equalTo: container.topAnchor),
                stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                container.widthAnchor.constraint(equalToConstant: 432),
                container.heightAnchor.constraint(equalToConstant: 84)
            ])

            let dialog = showMD3Dialog(title: "从剪贴板添加", message: "检测到剪贴板内容是订阅链接。", customView: container)
            dialog.window?.initialFirstResponder = nameField
            dialog.onConfirm = { [weak self, weak nameField, weak urlField, weak dialog] in
                guard let self, let n = nameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty,
                      let u = urlField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty else { return }
                self.addSubscription(name: n, url: u); dialog?.dismiss()
            }
            dialog.onCancel = { [weak dialog] in dialog?.dismiss() }
            return
        }

        // Config text (JSON/YAML) in clipboard → direct import
        do {
            let summary = try SubscriptionImporter.extractWithSummary(text)
            let config = try SubscriptionImporter.singBoxConfig(from: text, profileName: "剪贴板导入")
            let subscription = Subscription(id: UUID(), name: "剪贴板导入", url: "clipboard://", profileID: nil, updatedAt: Date())
            subscriptions.append(subscription)
            store.saveSubscriptions(subscriptions)
            applySubscriptionConfig(config, for: subscription.id)
            subscriptionTable.reloadData()
            refreshSubscriptionBadge()
            appendLog("[订阅] 从剪贴板导入（\(summary.nodes.count) 个节点）\n")
            if summary.skippedTotal > 0 {
                let detail = summary.skippedTypesDescription
                appendLog("[订阅] \(summary.skippedTotal) 个节点协议不支持已跳过（\(detail)）\n")
                showToast("剪贴板导入: \(summary.skippedTotal) 个节点协议不支持已跳过（\(detail)）", style: .warning, duration: 5.0)
            }
        } catch {
            showError(NSError.user("剪贴板内容无法识别。请复制订阅链接（http/https）或完整的配置内容（JSON / YAML）。"))
        }
    }

    private func addSubscription(name: String, url: String) {
        let subscription = Subscription(id: UUID(), name: name, url: url, profileID: nil, updatedAt: nil)
        subscriptions.append(subscription)
        store.saveSubscriptions(subscriptions)
        subscriptionTable.reloadData()
        refreshSubscriptionBadge()
        appendLog("[订阅] 已添加 \(name)\n")
        refreshSubscription(at: subscriptions.count - 1)
    }
}
