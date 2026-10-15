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

        let resolved = resolveActiveOutboundForGroup(groupTag: group.tag, proxiesObj: isProxyRuntimeRunning() ? lastProxiesObj : nil)
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
        let proxies = lastProxiesObj?["proxies"] as? [String: Any]
        let runtimeGroup = proxies?[group.tag] as? [String: Any]
        let current = isProxyRuntimeRunning() ? (runtimeGroup?["now"] as? String ?? group.current) : group.current
        let isSelected = nodeTag == current
        let tile = MD3NodeTileView()
        tile.groupTag = group.tag
        tile.nodeTag = nodeTag
        tile.isSelected = isSelected
        let isAutoMember = nodeGroups.contains { candidate in
            candidate.tag == nodeTag && ["urltest", "url-test", "fallback"].contains(candidate.type.lowercased())
        }
        tile.isActionEnabled = !isAutoMember
        let isSelector = group.type.lowercased() == "selector"
        // Auto groups are selectable in a Selector, but their delay affordance
        // remains display-only. Selecting the group must not start a test.
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
            let resolvedTag = resolveActiveOutboundForGroup(groupTag: autoGroup.tag, proxiesObj: isProxyRuntimeRunning() ? lastProxiesObj : nil).name
            if let resolvedNodeInfo = nodes.first(where: { $0.tag == (resolvedTag.isEmpty ? autoGroup.current : resolvedTag) }) {
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

        // Individual leaf nodes remain manually testable. An auto-group tile is
        // display-only; its result is refreshed when any of its members is tested
        // or when the group header/page test is used.
        if !isAutoMember {
            tile.onTestClick = { [weak self] in
                self?.testSingleNode(tag: nodeTag)
            }
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
        let current = resolveActiveOutboundForGroup(groupTag: group.tag, proxiesObj: isProxyRuntimeRunning() ? lastProxiesObj : nil).name
        let delay = nodeByTag[current]?.delay ?? "—"
        return delay == "未测试" || delay.isEmpty ? "—" : delay
    }

    func parsedDelay(_ value: String) -> Int? {
        let digits = value.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    func testGroupNodes(_ group: NodeGroupInfo) {
        runNodeDelayTest(tags: group.members.isEmpty ? nodes.map(\.tag) : group.members, title: group.tag)
    }

    /// Every entry point shares runtime reselection and freshness checks.
    func runNodeDelayTest(tags requestedTags: [String], title: String) {
        guard !nodeDelayTestState.isActive else {
            showToast("测速正在进行，请等待完成", style: .warning)
            return
        }
        guard !isProxyServiceTransitioning else {
            showToast("正在切换运行状态，请稍后再测")
            return
        }
        do {
            let config = try saveCurrent()
            let tags = Array(Set(requestedTags)).sorted()
            guard !tags.isEmpty else { return }
            let enteredURL = nodeTestURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let testURL = enteredURL.isEmpty ? TungBoxConfig.urlTestURL : enteredURL
            let requestID = UUID()
            nodeDelayTestID = requestID
            guard nodeDelayTestState.begin(id: requestID, tags: tags) else { return }
            let transitionID = runtimeTransitionID
            let configText = editor.string
            let configIdentity = NodeDelayTestPolicy.configurationIdentity(configText)
            let profileID = selectedIndex.map { profiles[$0].id }
            let runtimeRunning = isProxyRuntimeRunning()
            let apiPort = delayAPIPort()
            let tunRunning = isTunRuntimeRunning()
            let userRunning = runner.isRunning
            let runner = runner
            let serverByTag = Dictionary(uniqueKeysWithValues: nodes.map { ($0.tag, $0.server) })
            // Resolve nested membership, including a test of an auto-group tile itself.
            let groups = nodeGroups
            func containsTested(_ tag: String, visited: Set<String> = []) -> Bool {
                if tags.contains(tag) { return true }
                guard !visited.contains(tag), let group = groups.first(where: { $0.tag == tag }) else { return false }
                return group.members.contains { containsTested($0, visited: visited.union([tag])) }
            }
            let autoGroups = groups.filter {
                ["urltest", "url-test", "fallback"].contains($0.type.lowercased()) && containsTested($0.tag)
            }.map(\.tag)
            for index in nodes.indices {
                if nodes[index].delay == "测试中" { nodes[index].delay = "未测试" }
                if tags.contains(nodes[index].tag) { nodes[index].delay = "测试中" }
            }
            nodeTestStatusLabel.stringValue = nodeDelayTestState.statusText
            refreshNodeGroupsView()
            appendLog("[节点] 开始测速：\(tags.count) 个节点\n")
            nodeDelayTestTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.finishNodeDelayTest(id: requestID, succeeded: false) }
                @MainActor func isCurrent() -> Bool {
                    !Task.isCancelled && self.nodeDelayTestID == requestID && self.runtimeTransitionID == transitionID
                        && (self.editor.string == configText || (configIdentity != nil && NodeDelayTestPolicy.configurationIdentity(self.editor.string) == configIdentity))
                        && self.selectedIndex.map { self.profiles[$0].id } == profileID
                        && !self.isProxyServiceTransitioning
                        && self.runner.isRunning == userRunning && self.isTunRuntimeRunning() == tunRunning
                        && self.delayAPIPort() == apiPort
                }
                await withTaskGroup(of: (String, String).self) { tasks in
                    for tag in tags {
                        let server = serverByTag[tag]
                        tasks.addTask {
                            if runtimeRunning {
                                do { return (tag, "\(try await ClashAPI.delay(node: tag, url: testURL, port: apiPort)) ms") }
                                catch { return (tag, "失败") }
                            }
                            return (tag, await MainWindowController.fastDelayProbe(serverHostPort: server, runner: runner, config: config, outbound: tag, testURL: testURL))
                        }
                    }
                    for await (tag, result) in tasks {
                        guard isCurrent() else { tasks.cancelAll(); continue }
                        if let index = self.nodes.firstIndex(where: { $0.tag == tag }) { self.nodes[index].delay = result }
                        self.nodeDelayTestState.receivedResult(id: requestID, tag: tag)
                        self.nodeTestStatusLabel.stringValue = self.nodeDelayTestState.statusText
                        self.nodeTable.reloadData()
                        self.refreshNodeDelayTiles()
                    }
                }
                guard isCurrent() else { return }
                var selectionRefreshFailed = false
                if runtimeRunning {
                    self.nodeDelayTestState.refreshSelection(id: requestID)
                    self.nodeTestStatusLabel.stringValue = self.nodeDelayTestState.statusText
                    self.appendLog("[节点] 节点结果已返回，开始刷新自动选择\n")
                    // Both independent cores must retest; no selector PUT or invented minimum selection.
                    let ports: [Int?] = userRunning && tunRunning ? [nil, TungBoxConfig.tunDaemonClashPort] : [apiPort]
                    for port in ports {
                        for group in autoGroups {
                            guard isCurrent() else { return }
                            do {
                                try await ClashAPI.testGroup(group, url: testURL, port: port)
                                guard isCurrent() else { return }
                            } catch {
                                guard isCurrent() else { return }
                                selectionRefreshFailed = true
                                self.appendLog("[节点] 自动分组 \(group) 测速失败：\(error.localizedDescription)\n")
                            }
                        }
                    }
                    do {
                        let proxies = try await ClashAPI.proxies(port: apiPort)
                        guard isCurrent() else { return }
                        self.lastProxiesObj = proxies
                        self.syncNodeDelaysFromClashAPI(proxiesObj: proxies)
                        let active = self.resolveActiveOutbound(proxiesObj: proxies)
                        self.currentNodeNameLabel.stringValue = active.name
                        self.currentNodeAutoBadge.isHidden = !active.isAuto
                        self.currentNodeDelayLabel.stringValue = self.nodes.first(where: { $0.tag == active.name })?.delay ?? "—"
                        self.currentNodeDelayLabel.textColor = MD3.latencyTextColor(self.currentNodeDelayLabel.stringValue)
                        self.refreshTrayIcon()
                    } catch {
                        guard isCurrent() else { return }
                        selectionRefreshFailed = true
                        self.appendLog("[节点] 读取实际选中节点失败：\(error.localizedDescription)\n")
                    }
                }
                guard isCurrent() else { return }
                self.finishNodeDelayTest(id: requestID, succeeded: true)
                let summary = self.delayTestSummary(memberTags: tags)
                self.showToast(selectionRefreshFailed ? "测速完成，但自动选择状态刷新失败" : "\(title) 测速完成（\(summary)）", style: selectionRefreshFailed || summary.contains("可用 0") ? .warning : .success)
            }
        } catch { showError(error) }
    }

    func finishNodeDelayTest(id: UUID, succeeded: Bool) {
        guard nodeDelayTestState.finish(id: id, succeeded: succeeded) else { return }
        nodeDelayTestTask = nil
        NodeDelayTestState.clearPendingDelays(in: &nodes)
        nodeTestStatusLabel.stringValue = nodeDelayTestState.statusText
        nodeTable.reloadData()
        refreshNodeGroupsView()
        appendLog(succeeded ? "[节点] 测速已完成\n" : "[节点] 测速已取消，运行状态或配置已变化\n")
    }

    func refreshNodeDelayTiles() {
        var delays = Dictionary(nodes.map { ($0.tag, $0.delay) }, uniquingKeysWith: { first, _ in first })
        for group in nodeGroups where ["urltest", "url-test", "fallback"].contains(group.type.lowercased()) {
            let resolved = resolveActiveOutboundForGroup(groupTag: group.tag, proxiesObj: isProxyRuntimeRunning() ? lastProxiesObj : nil).name
            delays[group.tag] = delays[resolved.isEmpty ? group.current : resolved]
        }
        MD3NodeTileView.refreshDelays(in: nodeGroupsStack, delays: delays)
    }

    /// 以节点服务器 TCP 连接作为稳定的可用性与延迟基准；UDP-only 节点
    /// 或 TCP 失败时再回退到 sing-box URLTest。
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
        runNodeDelayTest(tags: [tag], title: tag)
    }

    @objc func testAllNodesClicked() {
        runNodeDelayTest(tags: nodes.map(\.tag), title: "全部节点")
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

    func refreshNodesFromEditor() {
        // Re-parsing the editor rebuilds NodeInfo with delay "未测试", which would
        // wipe latencies already measured this session (e.g. when switching the
        // selected node from auto to a manual one). Carry the measured delay over
        // for nodes that are still the same (matched by tag + server).
        let previousDelays = Dictionary(
            nodes.map { ("\($0.tag)\u{1}\($0.server)", $0.delay) },
            uniquingKeysWith: { first, _ in first }
        )
        var parsed = parseNodes(from: editor.string)
        for index in parsed.indices {
            let key = "\(parsed[index].tag)\u{1}\(parsed[index].server)"
            if let previous = previousDelays[key], previous != "未测试", previous != "测试中" {
                parsed[index].delay = previous
            }
        }
        nodes = parsed
        nodeGroups = parseNodeGroups(from: editor.string)
        nodeTable.reloadData()
        populateRuleStrategyPopup()
        refreshNodeGroupsView()
        selectCurrentNodeInTable()
    }

    func activeSelectorAPIPorts() -> [Int] {
        var ports: [Int] = []
        if runner.isRunning { ports.append(9090) }
        if isTunRuntimeRunning() { ports.append(TungBoxConfig.tunDaemonClashPort) }
        return ports
    }

    func selectNode(at index: Int) {
        guard nodes.indices.contains(index) else { return }
        selectNode(nodes[index].tag, inGroup: TungBoxConfig.tagManual)
    }

    static func optimisticSelectionState(
        nodeGroups: [NodeGroupInfo],
        proxiesObj: [String: Any]?,
        nodeTag: String,
        groupTag: String
    ) -> (nodeGroups: [NodeGroupInfo], proxiesObj: [String: Any]?) {
        var updatedGroups = nodeGroups
        if let index = updatedGroups.firstIndex(where: { $0.tag == groupTag }) {
            updatedGroups[index].current = nodeTag
        }

        var updatedProxiesObj = proxiesObj
        if var root = updatedProxiesObj,
           var proxies = root["proxies"] as? [String: Any] {
            var runtimeGroup = proxies[groupTag] as? [String: Any] ?? [:]
            runtimeGroup["now"] = nodeTag
            proxies[groupTag] = runtimeGroup
            root["proxies"] = proxies
            updatedProxiesObj = root
        }
        return (updatedGroups, updatedProxiesObj)
    }

    func applyOptimisticNodeSelection(nodeTag: String, groupTag: String) {
        let state = Self.optimisticSelectionState(
            nodeGroups: nodeGroups,
            proxiesObj: lastProxiesObj,
            nodeTag: nodeTag,
            groupTag: groupTag
        )
        nodeGroups = state.nodeGroups
        lastProxiesObj = state.proxiesObj
        refreshNodeGroupsView()

        if groupTag == TungBoxConfig.tagManual && isProxyServiceActiveOrRequested() {
            let active = resolveActiveOutbound(proxiesObj: lastProxiesObj)
            currentNodeNameLabel.stringValue = active.name.isEmpty ? nodeTag : active.name
            currentNodeAutoBadge.isHidden = !active.isAuto
            let delay = nodes.first(where: { $0.tag == active.name })?.delay ?? "—"
            currentNodeDelayLabel.stringValue = delay == "未测试" ? "—" : delay
            currentNodeDelayLabel.textColor = MD3.latencyTextColor(currentNodeDelayLabel.stringValue)
            refreshTrayIcon()
        }
    }

    func selectNode(_ nodeTag: String, inGroup groupTag: String) {
        guard !runtimeCoordinator.state.isTerminating else { return }
        selectorSelectionID = UUID()
        let selectionID = selectorSelectionID
        let transitionID = runtimeTransitionID
        let apiPorts = activeSelectorAPIPorts()
        let previousNodeGroups = nodeGroups
        let previousProxiesObj = lastProxiesObj

        // Reflect the click before any control API, connection cleanup or disk I/O.
        // The runtime/config work below remains serialized in the background task.
        applyOptimisticNodeSelection(nodeTag: nodeTag, groupTag: groupTag)

        selectorSelectionTask = Task {
            guard selectorSelectionID == selectionID, runtimeTransitionID == transitionID else { return }
            var switchedByAPI = false
            if isProxyRuntimeRunning() {
                do {
                    for apiPort in apiPorts {
                        guard selectorSelectionID == selectionID, runtimeTransitionID == transitionID else { return }
                        try await ClashAPI.selectProxyAndCloseConnections(group: groupTag, node: nodeTag, port: apiPort)
                    }
                    switchedByAPI = true
                    appendLog("[节点] \(groupTag) 已通过运行时 API 切换到: \(nodeTag)\n")
                } catch {
                    appendLog("[节点] 运行时 API 切换失败，改用配置重启：\(error.localizedDescription)\n")
                }
            }
            guard self.selectorSelectionID == selectionID, self.runtimeTransitionID == transitionID else { return }
            do {
                guard var config = self.parseConfigObject(from: self.editor.string) else {
                    throw NSError.user("当前配置不是有效 JSON")
                }
                var outbounds = config["outbounds"] as? [[String: Any]] ?? []
                var found = false
                for i in outbounds.indices {
                    if outbounds[i]["tag"] as? String == groupTag,
                       ((outbounds[i]["type"] as? String)?.lowercased() == "selector") {
                        outbounds[i]["default"] = nodeTag
                        found = true
                    }
                }
                if found {
                    config["outbounds"] = outbounds
                    self.editor.string = try self.renderConfig(config)
                    _ = try self.saveCurrent()
                    self.appendLog("[节点] \(groupTag) 已选择: \(nodeTag)\n")
                    self.refreshNodesFromEditor()
                    if self.isProxyRuntimeRunning() && !switchedByAPI {
                        if self.isTunEnabled {
                            // TUN is already running; hot-reload the config in
                            // place. A full restart here re-runs start-time
                            // checks that can throw and tear the live TUN down
                            // (the reported "switching node killed the proxy").
                            let reloaded = await self.reloadTunConfigInPlace(configText: self.editor.string)
                            guard self.selectorSelectionID == selectionID, self.runtimeTransitionID == transitionID else { return }
                            if reloaded { self.appendLog("[节点] 已按新节点热重载 TUN\n") }
                            if self.isSystemProxyEnabled { self.reconcileRuntime(reason: "节点切换后重启", forceRestart: true) }
                        } else {
                            self.reconcileRuntime(reason: "节点切换后重启", forceRestart: true)
                            self.appendLog("[节点] 服务已按新节点重启\n")
                        }
                        self.refreshStatus()
                    } else {
                        self.refreshStatus()
                    }
                } else {
                    throw NSError.user("当前配置中未找到节点选择组：\(groupTag)")
                }
            } catch {
                // If neither the runtime nor the persisted config accepted the
                // change, restore the rendered state. When the runtime switch
                // succeeded, keep showing that real state and only report that
                // persistence failed.
                if !switchedByAPI {
                    self.nodeGroups = previousNodeGroups
                    self.lastProxiesObj = previousProxiesObj
                    self.refreshNodeGroupsView()
                    self.refreshStatus()
                }
                self.showError(error)
            }
        }
    }
    func parseNodes(from text: String) -> [NodeInfo] {
        ConfigInspection.parseNodes(from: text)
    }

    func parseNodeGroups(from text: String) -> [NodeGroupInfo] {
        ConfigInspection.parseNodeGroups(from: text)
    }
    func resolveActiveOutbound(proxiesObj: [String: Any]?) -> (name: String, isAuto: Bool) {
        return resolveActiveOutboundForGroup(groupTag: "节点选择", proxiesObj: proxiesObj)
    }

    nonisolated static func automaticSelectionTransition(
        previous: String?,
        currentName: String,
        isAutomatic: Bool
    ) -> (next: String?, didChange: Bool) {
        guard isAutomatic, !currentName.isEmpty, currentName != "自动选择" else {
            return (nil, false)
        }
        return (currentName, previous != nil && previous != currentName)
    }

    func resolveActiveOutboundForGroup(groupTag: String, proxiesObj: [String: Any]?) -> (name: String, isAuto: Bool) {
        guard let proxiesObj = proxiesObj,
              let proxies = proxiesObj["proxies"] as? [String: Any] else {
            if let group = nodeGroups.first(where: { $0.tag == groupTag }) {
                if group.current == "自动选择" {
                    if let autoGroup = nodeGroups.first(where: { $0.tag == "自动选择" }) {
                        return (autoGroup.current.isEmpty ? "自动选择" : autoGroup.current, true)
                    }
                }
                return (group.current.isEmpty ? "默认" : group.current, false)
            }

            var offlineNode = "默认"
            if let config = parseConfigObject(from: editor.string),
               let outbounds = config["outbounds"] as? [[String: Any]],
               let selector = outbounds.first(where: { $0["tag"] as? String == groupTag }),
               let defNode = selector["default"] as? String {
                offlineNode = defNode
            } else if let firstNode = nodes.first {
                offlineNode = firstNode.tag
            }
            return (offlineNode, false)
        }

        var current = groupTag
        var isAuto = false
        var visited = Set<String>()

        while let group = proxies[current] as? [String: Any], !visited.contains(current) {
            visited.insert(current)
            if let now = group["now"] as? String {
                let type = (group["type"] as? String)?.lowercased() ?? ""
                if current == "自动选择" || type == "urltest" || type == "fallback" {
                    isAuto = true
                }
                current = now
            } else {
                break
            }
        }

        return (current, isAuto)
    }

    func syncNodeDelaysFromClashAPI(proxiesObj: [String: Any]?) {
        guard let proxiesObj = proxiesObj,
              let proxies = proxiesObj["proxies"] as? [String: Any] else { return }

        var updated = nodeDelayTestState.syncBackgroundDelays(proxies: proxies, in: &nodes)

        // Sync group active nodes (current values) from Clash API
        for index in nodeGroups.indices {
            let groupTag = nodeGroups[index].tag
            if let groupData = proxies[groupTag] as? [String: Any],
               let now = groupData["now"] as? String {
                if nodeGroups[index].current != now {
                    nodeGroups[index].current = now
                    updated = true
                }
            }
        }

        if updated {
            nodeTable.reloadData()
            refreshNodeGroupsView()
        }
    }

    func modeDisplayName(_ mode: String) -> String {
        ConfigInspection.modeDisplayName(mode)
    }

    func refreshModeFromEditor() {
        guard let config = parseConfigObject(from: editor.string) else {
            syncModeControls(mode: "Rule")
            modeStatusLabel.stringValue = "当前模式：无法读取配置"
            return
        }
        let mode = readMode(from: config)
        syncModeControls(mode: mode)
        updateModeStatus()
    }

    func syncModeControls(mode: String) {
        let segment = modeSegment(for: mode)
        modeControl.selectedSegment = segment
        nodesModeControl.selectedSegment = segment
        modeControl.layoutSubtreeIfNeeded()
        nodesModeControl.layoutSubtreeIfNeeded()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.modeControl.selectedSegment = segment
            self.nodesModeControl.selectedSegment = segment
            self.modeControl.layoutSubtreeIfNeeded()
            self.nodesModeControl.layoutSubtreeIfNeeded()
        }
    }

    func updateModeStatus() {
        let mode = selectedMode()
        let hasClashModeRules = editor.string.contains("\"clash_mode\"")
        let suffix = hasClashModeRules
            ? "配置中已包含 clash_mode 规则。"
            : "配置中暂未看到 clash_mode 规则，切换模式时会补 direct/global 前置规则。"
        modeStatusLabel.stringValue = "当前模式：\(mode.displayName)\n\(suffix)"
    }

    func applySelectedMode() throws {
        guard !runtimeCoordinator.state.isTerminating else { return }
        guard var config = parseConfigObject(from: editor.string) else {
            throw NSError.user("当前配置不是有效 JSON")
        }
        let previousMode = readMode(from: config)
        let mode = selectedMode()
        let refreshDelays = NodeDelayTestPolicy.refreshAfterModeChange(
            from: previousMode, to: mode.value,
            pendingRefresh: modeChangeNeedsDelayRefresh
        )
        config = ensureModeSupport(in: config, mode: mode)
        editor.string = try renderConfig(config)
        let url = try saveCurrent()
        let output = try runner.check(config: url)
        appendLog("[mode] 已切换到 \(mode.displayName)：\(output)\n")
        refreshModeFromEditor()
        refreshNodeGroupsView()   // re-filter shown groups for the new mode

        if isProxyServiceActiveOrRequested() {
            applyRuntimeMode(mode.value, refreshNodeDelays: refreshDelays)
        } else if refreshDelays {
            testAllNodesClicked()
        }
    }
    struct Mode {
        var value: String
        var displayName: String
    }

    func selectedMode() -> Mode {
        switch modeControl.selectedSegment {
        case 0: return Mode(value: "Direct", displayName: "直连/绕过代理")
        case 1: return Mode(value: "Global", displayName: "全局代理")
        default: return Mode(value: "Rule", displayName: "规则判定")
        }
    }

    func modeSegment(for mode: String) -> Int {
        switch mode.lowercased() {
        case "direct": return 0
        case "global": return 1
        default: return 2
        }
    }

    func nodesModeSegment(forHomeSegment segment: Int) -> Int {
        segment
    }

    func homeModeSegment(forNodesSegment segment: Int) -> Int {
        segment
    }
}
