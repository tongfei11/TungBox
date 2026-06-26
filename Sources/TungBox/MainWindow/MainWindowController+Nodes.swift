import AppKit
import Foundation

extension MainWindowController {
    
    func makeNodesView() -> NSView {
        let title = NSTextField(labelWithString: "节点")
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak title] in
            title?.textColor = MD3.onSurface
        }

        nodesModeControl.items = ["直连/绕过代理", "全局代理", "规则判定"]
        nodesModeControl.selectedSegment = 2
        nodesModeControl.target = self
        nodesModeControl.action = #selector(nodesModeChanged)
        nodesModeControl.translatesAutoresizingMaskIntoConstraints = false
        nodesModeControl.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let testButton = MD3Button()
        testButton.title = "延迟测试"
        testButton.style = .tonal
        testButton.target = self
        testButton.action = #selector(testAllNodesClicked)
        testButton.translatesAutoresizingMaskIntoConstraints = false
        testButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        testButton.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let topBar = NSStackView(views: [nodesModeControl, spacer, testButton])
        topBar.orientation = .horizontal
        topBar.spacing = 16
        topBar.alignment = .centerY
        topBar.distribution = .fill
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let scroll = MD3ScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.applyThinOverlayScroller()

        nodeGroupsStack.orientation = .vertical
        nodeGroupsStack.spacing = 16
        nodeGroupsStack.alignment = .leading
        nodeGroupsStack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(nodeGroupsStack)
        // 节点分组 stack 直接贴 document（不再内缩 8pt），卡片左右缘和上方按钮齐
        NSLayoutConstraint.activate([
            nodeGroupsStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            nodeGroupsStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            nodeGroupsStack.topAnchor.constraint(equalTo: document.topAnchor),
            nodeGroupsStack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -8)
        ])
        scroll.documentView = document
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

        // 不再用有底色的 MD3Panel 包裹，scroll 直接贴 view，卡片左缘和标题/工具栏对齐
        let view = NSView()
        view.addSubview(title)
        view.addSubview(topBar)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),

            topBar.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            topBar.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),
            topBar.heightAnchor.constraint(equalToConstant: 42),
            nodesModeControl.widthAnchor.constraint(equalToConstant: 520),

            scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            scroll.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24)
        ])

        refreshNodeGroupsView()
        refreshModeFromEditor()
        return view
    }

    func refreshNodeGroupsView() {
        nodeTileActions.removeAll()
        nextNodeTileTag = 1
        nodeGroupsStack.arrangedSubviews.forEach { view in
            nodeGroupsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        func showGroupsHint(_ text: String) {
            let hint = NSTextField(labelWithString: text)
            hint.textColor = MD3.onSurfaceVariant
            hint.font = .systemFont(ofSize: 13)
            hint.translatesAutoresizingMaskIntoConstraints = false
            nodeGroupsStack.addArrangedSubview(hint)
            hint.leadingAnchor.constraint(equalTo: nodeGroupsStack.leadingAnchor).isActive = true
            hint.trailingAnchor.constraint(equalTo: nodeGroupsStack.trailingAnchor).isActive = true
        }

        guard !nodeGroups.isEmpty else {
            showGroupsHint("当前配置没有代理分组。刷新订阅后会显示 selector / urltest 分组。")
            return
        }

        // Show only the groups relevant to the current outbound mode:
        //   Rule   → 节点选择 + 自动选择   Global → 全局 + 自动选择   Direct → none.
        let modeValue = selectedMode().value.lowercased()
        if modeValue == "direct" {
            showGroupsHint("当前模式不使用代理节点（直连 / 绕过代理）。")
            return
        }
        let isAutoGroup: (NodeGroupInfo) -> Bool = {
            ["urltest", "url-test", "fallback"].contains($0.type.lowercased())
        }
        let visibleGroups = nodeGroups.filter { group in
            if isAutoGroup(group) { return true }
            if modeValue == "global" { return group.tag == TungBoxConfig.tagGlobal }
            return group.tag != TungBoxConfig.tagGlobal
        }
        guard !visibleGroups.isEmpty else {
            showGroupsHint(modeValue == "global"
                ? "全局分组将在启动服务后生成。"
                : "当前模式暂无可显示的分组。")
            return
        }

        let nodeByTag = Dictionary(uniqueKeysWithValues: nodes.map { ($0.tag, $0) })
        let sortedGroups = visibleGroups.sorted { g1, g2 in
            let t1 = g1.type.lowercased()
            let t2 = g2.type.lowercased()
            if t1 == "selector" && t2 != "selector" { return true }
            if t1 != "selector" && t2 == "selector" { return false }
            return g1.tag < g2.tag
        }

        for i in stride(from: 0, to: sortedGroups.count, by: 2) {
            let first = nodeGroupCard(group: sortedGroups[i], nodeByTag: nodeByTag)
            let second: NSView
            if i + 1 < sortedGroups.count {
                second = nodeGroupCard(group: sortedGroups[i + 1], nodeByTag: nodeByTag)
            } else {
                second = NSView()
                second.translatesAutoresizingMaskIntoConstraints = false
            }
            
            let rowStack = NSStackView(views: [first, second])
            rowStack.orientation = .horizontal
            rowStack.spacing = 16
            rowStack.distribution = .fillEqually
            rowStack.alignment = .top
            rowStack.translatesAutoresizingMaskIntoConstraints = false
            
            if i + 1 < sortedGroups.count {
                first.heightAnchor.constraint(equalTo: second.heightAnchor).isActive = true
            }
            
            nodeGroupsStack.addArrangedSubview(rowStack)
            NSLayoutConstraint.activate([
                rowStack.leadingAnchor.constraint(equalTo: nodeGroupsStack.leadingAnchor),
                rowStack.trailingAnchor.constraint(equalTo: nodeGroupsStack.trailingAnchor)
            ])
        }
    }

    func nodeGroupCard(group: NodeGroupInfo, nodeByTag: [String: NodeInfo]) -> NSView {
        let card = MD3Panel()
        card.type = .elevated
        card.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: group.tag)
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = MD3.onSurface
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let metaLabel = NSTextField(labelWithString: "· \(groupDisplayType(group.type)) · \(group.members.count)/\(group.members.count)")
        metaLabel.font = .systemFont(ofSize: 10, weight: .medium)
        metaLabel.textColor = MD3.onSurfaceVariant
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        let currentDelay = groupDelay(group: group, nodeByTag: nodeByTag)
        let delayButton = MD3GroupDelayButton()
        delayButton.translatesAutoresizingMaskIntoConstraints = false
        delayButton.delayValue = currentDelay
        delayButton.onClick = { [weak self] in
            guard let self = self,
                  let group = self.nodeGroups.first(where: { $0.tag == group.tag }) else { return }
            self.testGroupNodes(group)
        }

        let resolved = resolveActiveOutboundForGroup(groupTag: group.tag, proxiesObj: lastProxiesObj)
        // For auto groups (urltest/fallback) the picked node is already shown with a
        // selected highlight in the grid below, so omit the redundant "(自动)" suffix
        // in the header. Selector groups keep it to show they route through auto.
        let isAutoGroup = ["urltest", "url-test", "fallback"].contains(group.type.lowercased())
        let displayNode = (resolved.isAuto && !isAutoGroup) ? "\(resolved.name) (自动)" : resolved.name
        let currentLabel = NSTextField(labelWithString: "➜ \(displayNode)")
        currentLabel.font = .systemFont(ofSize: 12, weight: .medium)
        currentLabel.textColor = MD3.onSurfaceVariant
        currentLabel.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSStackView()
        grid.orientation = .vertical
        grid.spacing = 8
        grid.alignment = .leading
        grid.translatesAutoresizingMaskIntoConstraints = false

        var rowViews: [[NSView]] = []
        let members = group.members.isEmpty ? nodes.map(\.tag) : group.members
        for pair in stride(from: 0, to: members.count, by: 2) {
            let first = nodeTile(group: group, nodeTag: members[pair], node: nodeByTag[members[pair]])
            let second: NSView
            if pair + 1 < members.count {
                second = nodeTile(group: group, nodeTag: members[pair + 1], node: nodeByTag[members[pair + 1]])
            } else {
                second = NSView()
                second.translatesAutoresizingMaskIntoConstraints = false
            }
            rowViews.append([first, second])
        }
        if rowViews.isEmpty {
            rowViews = [[nodeTile(group: group, nodeTag: group.current, node: nodeByTag[group.current]), NSView()]]
        }
        for row in rowViews {
            let rowStack = NSStackView(views: row)
            rowStack.orientation = .horizontal
            rowStack.spacing = 8
            rowStack.distribution = .fillEqually
            rowStack.translatesAutoresizingMaskIntoConstraints = false

            grid.addArrangedSubview(rowStack)
            rowStack.leadingAnchor.constraint(equalTo: grid.leadingAnchor).isActive = true
            rowStack.trailingAnchor.constraint(equalTo: grid.trailingAnchor).isActive = true
            // 硬约束等宽：fillEqually 在 cell 有 intrinsicContentSize 差时会被
            // 内容强度推到不等宽。显式同宽约束确保 2 列宽度永远一致。
            if row.count == 2 {
                row[0].widthAnchor.constraint(equalTo: row[1].widthAnchor).isActive = true
            }
        }

        card.addSubview(titleLabel)
        card.addSubview(metaLabel)
        card.addSubview(delayButton)
        card.addSubview(currentLabel)
        card.addSubview(grid)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),

            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            metaLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            delayButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            delayButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            currentLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            currentLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            currentLabel.trailingAnchor.constraint(lessThanOrEqualTo: delayButton.leadingAnchor, constant: -12),

            grid.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            grid.topAnchor.constraint(equalTo: currentLabel.bottomAnchor, constant: 14),
            grid.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    func nodeTile(group: NodeGroupInfo, nodeTag: String, node: NodeInfo?) -> NSView {
        let isSelected = nodeTag == group.current
        let tile = MD3NodeTileView()
        tile.groupTag = group.tag
        tile.nodeTag = nodeTag
        tile.isSelected = isSelected
        let isSelector = group.type.lowercased() == "selector"
        tile.isInteractive = isSelector
        
        var displayName = nodeTag
        var displayDelay = node?.delay ?? ""
        let displayType = node?.type.lowercased() ?? specialNodeType(nodeTag)
        
        if let autoGroup = nodeGroups.first(where: { $0.tag == nodeTag }),
           ["urltest", "url-test", "fallback"].contains(autoGroup.type.lowercased()) {
            // This member is itself an auto group (e.g. 自动选择). Show its group
            // name, not the currently-resolved node — the resolved node flickers as
            // urltest re-picks. The home page still surfaces the concrete pick.
            displayName = nodeTag
            if let resolvedNodeInfo = nodes.first(where: { $0.tag == autoGroup.current }) {
                displayDelay = resolvedNodeInfo.delay
            }
        }
        
        tile.nameLabel.stringValue = displayName
        tile.subLabel.stringValue = nodeSubLabel(displayType: displayType, node: node)
        tile.delayValue = displayDelay
        
        tile.onClick = { [weak self] in
            guard let self = self else { return }
            if group.type.lowercased() == "selector" {
                self.selectNode(nodeTag, inGroup: group.tag)
            }
        }
        
        tile.onTestClick = { [weak self] in
            guard let self = self else { return }
            self.testSingleNode(tag: nodeTag)
        }
        
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.heightAnchor.constraint(equalToConstant: 42).isActive = true
        
        return tile
    }

    /// Build an accurate node sub-label: protocol · transport/security · UDP|TCP.
    /// Replaces the old hardcoded "type / udp" that mislabeled every node as udp.
    func nodeSubLabel(displayType: String, node: NodeInfo?) -> String {
        guard let node else { return displayType }
        var parts = [displayType]
        if !node.transport.isEmpty {
            parts.append(node.transport)
        } else if node.tls {
            parts.append("tls")
        }
        parts.append(node.supportsUDP ? "TCP+UDP" : "仅TCP")
        return parts.joined(separator: " · ")
    }

    func specialNodeType(_ tag: String) -> String {
        switch tag {
        case TungBoxConfig.tagAuto: return "urltest"
        case TungBoxConfig.tagDirect: return "direct"
        case TungBoxConfig.tagBlock: return "reject"
        default: return "outbound"
        }
    }

    func groupDisplayType(_ type: String) -> String {
        switch type.lowercased() {
        case "urltest", "url-test": return "URLTest"
        case "selector": return "Selector"
        case "fallback": return "Fallback"
        default: return type
        }
    }

    func groupDelay(group: NodeGroupInfo, nodeByTag: [String: NodeInfo]) -> String {
        let members = group.members.isEmpty ? nodes.map(\.tag) : group.members
        var minMs: Int? = nil
        var isTesting = false
        
        for member in members {
            if let node = nodeByTag[member] {
                let delay = node.delay
                if delay == "测试中" {
                    isTesting = true
                } else if let ms = parsedDelay(delay) {
                    if let currentMin = minMs {
                        minMs = min(currentMin, ms)
                    } else {
                        minMs = ms
                    }
                }
            }
        }
        
        if let minMs = minMs {
            return "\(minMs) ms"
        }
        
        if isTesting {
            return "测试中"
        }
        
        return "—"
    }

    func parsedDelay(_ value: String) -> Int? {
        let digits = value.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    func updateURLTestSelectionsFromMeasuredDelays() {
        let delayByTag = Dictionary(uniqueKeysWithValues: nodes.compactMap { node -> (String, Int)? in
            guard let delay = parsedDelay(node.delay) else { return nil }
            return (node.tag, delay)
        })

        for index in nodeGroups.indices {
            let groupTag = nodeGroups[index].tag
            let type = nodeGroups[index].type.lowercased()
            guard ["urltest", "url-test", "fallback"].contains(type) else { continue }
            let candidates = nodeGroups[index].members.compactMap { tag -> (String, Int)? in
                guard let delay = delayByTag[tag] else { return nil }
                return (tag, delay)
            }
            guard let best = candidates.min(by: { $0.1 < $1.1 }) else { continue }
            
            let oldCurrent = nodeGroups[index].current
            nodeGroups[index].current = best.0
            
            if isProxyRuntimeRunning() && oldCurrent != best.0 {
                let nodeTag = best.0
                Task {
                    do {
                        try await ClashAPI.selectProxy(group: groupTag, node: nodeTag)
                        _ = try? await ClashAPI.closeConnections()
                        await MainActor.run { [weak self] in
                            self?.appendLog("[节点] 测速后自动将 \(groupTag) 切换到最快节点: \(nodeTag)，并已断开旧连接\n")
                        }
                    } catch {
                        await MainActor.run { [weak self] in
                            self?.appendLog("[节点] 自动切换 \(groupTag) 至 \(nodeTag) 失败: \(error.localizedDescription)\n")
                        }
                    }
                }
            }
        }
    }

    func testGroupNodes(_ group: NodeGroupInfo) {
        // 切换订阅/启停代理过渡期间禁止测速：此时 sing-box 实例可能正在销毁/重建，
        // 用过渡中的状态去 ClashAPI 测速会拿到"旧实例 + 新节点 tag"的混合错误
        // （典型表现：FATAL initialize outbound[N]: TLS required）。
        if isProxyServiceTransitioning {
            showToast("正在切换运行状态，请稍后再测")
            return
        }
        do {
            let config = try saveCurrent()
            let testURL = nodeTestURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalURL = testURL.isEmpty ? TungBoxConfig.urlTestURL : testURL
            
            let members = group.members.isEmpty ? nodes.map(\.tag) : group.members
            guard !members.isEmpty else { return }
            
            appendLog("[节点] 开始测试分组 \(group.tag) 中的 \(members.count) 个节点\n")

            for tag in members {
                if let idx = nodes.firstIndex(where: { $0.tag == tag }) {
                    nodes[idx].delay = "测试中"
                }
            }
            refreshNodeGroupsView()

            let runner = runner
            let apiPort = delayAPIPort()
            let runtimeRunning = isProxyRuntimeRunning()
            let groupName = group.tag
            // 关代理时用 TCP 直拨 → 不启动 sing-box，几十 ms 完成（接近竞品速度）。
            // 提前把每个 tag 对应的 server:port 拷贝出来，detached 任务能直接读。
            let serverByTag = Dictionary(uniqueKeysWithValues: nodes.map { ($0.tag, $0.server) })
            Task { @MainActor [weak self] in
                guard let self else { return }
                await withTaskGroup(of: (String, String).self) { tg in
                    for tag in members {
                        let server = serverByTag[tag]
                        tg.addTask { @Sendable in
                            if runtimeRunning {
                                do {
                                    let ms = try await ClashAPI.delay(node: tag, url: finalURL, port: apiPort)
                                    return (tag, "\(ms) ms")
                                } catch {
                                    return (tag, error.localizedDescription.contains("超时") ? "超时" : "失败")
                                }
                            }
                            return (tag, await MainWindowController.fastDelayProbe(serverHostPort: server, runner: runner, config: config, outbound: tag, testURL: finalURL))
                        }
                    }
                    for await (tag, result) in tg {
                        if let idx = self.nodes.firstIndex(where: { $0.tag == tag }) {
                            self.nodes[idx].delay = result
                        }
                        if result == "失败" || result == "超时" {
                            self.appendLog("[节点] 测试 \(tag): \(result)\n")
                        }
                    }
                }
                self.updateURLTestSelectionsFromMeasuredDelays()
                self.refreshNodeGroupsView()
                let summary = self.delayTestSummary(memberTags: members)
                self.showToast("\(groupName) 测速完成（\(summary)）", style: summary.contains("可用 0") ? .warning : .success)
            }
        } catch {
            showError(error)
        }
    }

    /// 关代理时的快速测速：先 TCP 直拨节点 server:port（几十 ms 完成），
    /// 失败/不可达则回退到 sing-box fetch（UDP-only 节点如 hy2/tuic 需要）。
    nonisolated static func fastDelayProbe(serverHostPort: String?, runner: Runner, config: URL, outbound: String, testURL: String) async -> String {
        if let hp = serverHostPort, !hp.isEmpty, !hp.hasSuffix(":") {
            if let ms = await Runner.tcpDialDelayMs(serverHostPort: hp, timeout: 3.0) {
                return "\(ms) ms"
            }
        }
        do {
            return try await runner.urlTest(config: config, outbound: outbound, testURL: testURL)
        } catch {
            return error.localizedDescription.contains("超时") ? "超时" : "失败"
        }
    }

    /// 统计指定节点们的"可用 X / 共 N · 最快 Yms"概要。
    func delayTestSummary(memberTags: [String]) -> String {
        let total = memberTags.count
        var ok = 0
        var fastest = Int.max
        for t in memberTags {
            guard let n = nodes.first(where: { $0.tag == t }) else { continue }
            let v = n.delay.replacingOccurrences(of: " ms", with: "")
            if let ms = Int(v) {
                ok += 1
                fastest = min(fastest, ms)
            }
        }
        if ok == 0 { return "可用 0 / 共 \(total)" }
        return "可用 \(ok) / 共 \(total) · 最快 \(fastest)ms"
    }

    @objc func groupTestClicked(_ sender: NSButton) {
        guard let groupTag = groupTestActions[sender.tag],
              let group = nodeGroups.first(where: { $0.tag == groupTag }) else { return }
        testGroupNodes(group)
    }

    func testSingleNode(tag: String) {
        if isProxyServiceTransitioning {
            showToast("正在切换运行状态，请稍后再测")
            return
        }
        do {
            let config = try saveCurrent()
            let testURL = nodeTestURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalURL = testURL.isEmpty ? TungBoxConfig.urlTestURL : testURL
            
            if let idx = nodes.firstIndex(where: { $0.tag == tag }) {
                nodes[idx].delay = "测试中"
                refreshNodeGroupsView()
            }
            
            let runner = runner
            let apiPort = delayAPIPort()
            let runtimeRunning = isProxyRuntimeRunning()
            let server = nodes.first(where: { $0.tag == tag })?.server
            Task.detached { [weak self, runner, apiPort, runtimeRunning, server] in
                let result: String
                if runtimeRunning {
                    do {
                        let ms = try await ClashAPI.delay(node: tag, url: finalURL, port: apiPort)
                        result = "\(ms) ms"
                    } catch {
                        let msg = error.localizedDescription
                        await MainActor.run { [weak self] in self?.appendLog("[节点] 测试 \(tag) 失败原因: \(msg)\n") }
                        result = msg.contains("超时") ? "超时" : "失败"
                    }
                } else {
                    result = await MainWindowController.fastDelayProbe(serverHostPort: server, runner: runner, config: config, outbound: tag, testURL: finalURL)
                }

                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    if let idx = self.nodes.firstIndex(where: { $0.tag == tag }) {
                        self.nodes[idx].delay = result
                    }
                    self.updateURLTestSelectionsFromMeasuredDelays()
                    self.refreshNodeGroupsView()
                }
            }
        } catch {
            showError(error)
        }
    }

    @objc func testAllNodesClicked() {
        if isProxyServiceTransitioning {
            showToast("正在切换运行状态，请稍后再测")
            return
        }
        do {
            let config = try saveCurrent()
            refreshNodesFromEditor()
            guard !nodes.isEmpty else {
                showError(NSError.user("当前配置没有可测试的节点"))
                return
            }
            let testURL = nodeTestURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !testURL.isEmpty else {
                showError(NSError.user("请输入测试 URL"))
                return
            }
            nodeTestStatusLabel.stringValue = "节点 URLTest：测试中，\(nodes.count) 个节点"
            appendLog("[节点] 开始测试 \(nodes.count) 个节点\n")
            for index in nodes.indices {
                nodes[index].delay = "测试中"
            }
            nodeTable.reloadData()
            refreshNodeGroupsView()

            let runner = runner
            let apiPort = delayAPIPort()
            let runtimeRunning = isProxyRuntimeRunning()
            let tags = nodes.map(\.tag)
            let serverByTag = Dictionary(uniqueKeysWithValues: nodes.map { ($0.tag, $0.server) })
            // 全部并发测速：关代理时 TCP 直拨 + 开代理时 ClashAPI。30 节点几秒搞定。
            Task { @MainActor [weak self] in
                guard let self else { return }
                await withTaskGroup(of: (String, String).self) { tg in
                    for tag in tags {
                        let server = serverByTag[tag]
                        tg.addTask { @Sendable in
                            if runtimeRunning {
                                do {
                                    let ms = try await ClashAPI.delay(node: tag, url: testURL, port: apiPort)
                                    return (tag, "\(ms) ms")
                                } catch {
                                    return (tag, error.localizedDescription.contains("超时") ? "超时" : "失败")
                                }
                            }
                            return (tag, await MainWindowController.fastDelayProbe(serverHostPort: server, runner: runner, config: config, outbound: tag, testURL: testURL))
                        }
                    }
                    for await (tag, result) in tg {
                        if let idx = self.nodes.firstIndex(where: { $0.tag == tag }) {
                            self.nodes[idx].delay = result
                            self.nodeTable.reloadData()
                            self.refreshNodeGroupsView()
                        }
                    }
                }
                self.updateURLTestSelectionsFromMeasuredDelays()
                self.refreshNodeGroupsView()
                self.nodeTestStatusLabel.stringValue = "节点 URLTest：已完成，\(tags.count) 个节点"
                self.appendLog("[节点] 测试完成\n")
                let summary = self.delayTestSummary(memberTags: tags)
                self.showToast("全部节点测速完成（\(summary)）", style: summary.contains("可用 0") ? .warning : .success)
            }
        } catch {
            showError(error)
        }
    }


    @objc func modeChanged() {
        nodesModeControl.selectedSegment = modeControl.selectedSegment
        do {
            try applySelectedMode()
            showToast("出站模式：\(selectedMode().displayName)", style: .info)
        } catch {
            refreshModeFromEditor()
            showError(error)
        }
    }

    @objc func nodesModeChanged() {
        modeControl.selectedSegment = nodesModeControl.selectedSegment
        do {
            try applySelectedMode()
            showToast("出站模式：\(selectedMode().displayName)", style: .info)
        } catch {
            refreshModeFromEditor()
            showError(error)
        }
    }

    @objc func nodeTileClicked(_ sender: NSButton) {
        guard let action = nodeTileActions[sender.tag] else { return }
        selectNode(action.node, inGroup: action.group)
    }

    func selectCurrentNodeInTable() {
        var targetTag = ""
        if let config = parseConfigObject(from: editor.string),
           let outbounds = config["outbounds"] as? [[String: Any]],
           let selector = outbounds.first(where: { $0["tag"] as? String == TungBoxConfig.tagManual }),
           let defNode = selector["default"] as? String {
            targetTag = defNode
        }
        if targetTag.isEmpty, let firstNode = nodes.first {
            targetTag = firstNode.tag
        }
        guard !targetTag.isEmpty else { return }
        if let idx = nodes.firstIndex(where: { $0.tag == targetTag }) {
            nodeTable.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            nodeTable.scrollRowToVisible(idx)
        }
    }

    @objc func refreshNodesClicked() {
        refreshNodesFromEditor()
        showToast("节点列表已刷新（\(nodes.count) 个）", style: .info)
    }
}
