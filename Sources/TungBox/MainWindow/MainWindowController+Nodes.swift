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

        nodesModeControl.items = ["直接连接", "全局代理", "规则判定"]
        nodesModeControl.selectedSegment = 2
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

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        nodeGroupsStack.orientation = .vertical
        nodeGroupsStack.spacing = 16
        nodeGroupsStack.alignment = .leading
        nodeGroupsStack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(nodeGroupsStack)
        NSLayoutConstraint.activate([
            nodeGroupsStack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 8),
            nodeGroupsStack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -8),
            nodeGroupsStack.topAnchor.constraint(equalTo: document.topAnchor, constant: 8),
            nodeGroupsStack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -8)
        ])
        scroll.documentView = document
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

        let panel = MD3Panel()
        panel.type = .filled
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(scroll)

        let view = NSView()
        view.addSubview(title)
        view.addSubview(topBar)
        view.addSubview(panel)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),

            topBar.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            topBar.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),
            topBar.heightAnchor.constraint(equalToConstant: 42),
            nodesModeControl.widthAnchor.constraint(equalToConstant: 520),

            panel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            panel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 16),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8)
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

        guard !nodeGroups.isEmpty else {
            let empty = NSTextField(labelWithString: "当前配置没有代理分组。刷新订阅后会显示 selector / urltest 分组。")
            empty.textColor = MD3.onSurfaceVariant
            empty.font = .systemFont(ofSize: 13)
            empty.translatesAutoresizingMaskIntoConstraints = false
            nodeGroupsStack.addArrangedSubview(empty)
            empty.leadingAnchor.constraint(equalTo: nodeGroupsStack.leadingAnchor).isActive = true
            empty.trailingAnchor.constraint(equalTo: nodeGroupsStack.trailingAnchor).isActive = true
            return
        }

        let nodeByTag = Dictionary(uniqueKeysWithValues: nodes.map { ($0.tag, $0) })
        let sortedGroups = nodeGroups.sorted { g1, g2 in
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
        let displayNode = resolved.isAuto ? "\(resolved.name) (自动)" : resolved.name
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
            let resolvedNode = autoGroup.current
            if !resolvedNode.isEmpty {
                displayName = "\(resolvedNode) (自动)"
                if let resolvedNodeInfo = nodes.first(where: { $0.tag == resolvedNode }) {
                    displayDelay = resolvedNodeInfo.delay
                }
            }
        }
        
        tile.nameLabel.stringValue = displayName
        tile.subLabel.stringValue = "\(displayType) / udp"
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
        do {
            let config = try saveCurrent()
            let testURL = nodeTestURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalURL = testURL.isEmpty ? "https://www.gstatic.com/generate_204" : testURL
            
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
            let runtimeRunning = isProxyRuntimeRunning()
            for tag in members {
                Task.detached { [weak self, runner, runtimeRunning] in
                    let result: String
                    do {
                        if runtimeRunning {
                            let ms = try await ClashAPI.delay(node: tag, url: finalURL)
                            result = "\(ms) ms"
                        } else {
                            result = try runner.urlTest(config: config, outbound: tag, testURL: finalURL)
                        }
                    } catch {
                        result = "失败"
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
            }
        } catch {
            showError(error)
        }
    }

    @objc func groupTestClicked(_ sender: NSButton) {
        guard let groupTag = groupTestActions[sender.tag],
              let group = nodeGroups.first(where: { $0.tag == groupTag }) else { return }
        testGroupNodes(group)
    }

    func testSingleNode(tag: String) {
        do {
            let config = try saveCurrent()
            let testURL = nodeTestURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalURL = testURL.isEmpty ? "https://www.gstatic.com/generate_204" : testURL
            
            if let idx = nodes.firstIndex(where: { $0.tag == tag }) {
                nodes[idx].delay = "测试中"
                refreshNodeGroupsView()
            }
            
            let runner = runner
            let runtimeRunning = isProxyRuntimeRunning()
            Task.detached { [weak self, runner, runtimeRunning] in
                let result: String
                do {
                    if runtimeRunning {
                        let ms = try await ClashAPI.delay(node: tag, url: finalURL)
                        result = "\(ms) ms"
                    } else {
                        result = try runner.urlTest(config: config, outbound: tag, testURL: finalURL)
                    }
                } catch {
                    result = "失败"
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
            let runtimeRunning = isProxyRuntimeRunning()
            let tags = nodes.map(\.tag)
            Task.detached { [weak self, runner, runtimeRunning] in
                for (index, tag) in tags.enumerated() {
                    let result: String
                    do {
                        if runtimeRunning {
                            let ms = try await ClashAPI.delay(node: tag, url: testURL)
                            result = "\(ms) ms"
                        } else {
                            result = try runner.urlTest(config: config, outbound: tag, testURL: testURL)
                        }
                    } catch {
                        result = "失败"
                    }
                    await MainActor.run { [weak self] in
                        guard let self, self.nodes.indices.contains(index), self.nodes[index].tag == tag else { return }
                        self.nodes[index].delay = result
                        self.nodeTable.reloadData()
                        self.refreshNodeGroupsView()
                    }
                }
                await MainActor.run { [weak self] in
                    self?.updateURLTestSelectionsFromMeasuredDelays()
                    self?.refreshNodeGroupsView()
                    self?.nodeTestStatusLabel.stringValue = "节点 URLTest：已完成，\(tags.count) 个节点"
                    self?.appendLog("[节点] 测试完成\n")
                }
            }
        } catch {
            showError(error)
        }
    }

    @objc func testAllNodesTCPClicked() {
        do {
            let config = try saveCurrent()
            refreshNodesFromEditor()
            guard !nodes.isEmpty else {
                showError(NSError.user("当前配置没有可测试的节点"))
                return
            }
            let address = tcpAddressField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else {
                showError(NSError.user("请输入 TCP 测试地址"))
                return
            }
            appendLog("[节点] 开始 TCP 测试 \(nodes.count) 个节点\n")
            for index in nodes.indices {
                nodes[index].tcp = "测试中"
            }
            nodeTable.reloadData()

            let runner = runner
            let tags = nodes.map(\.tag)
            Task.detached { [weak self, runner] in
                for (index, tag) in tags.enumerated() {
                    let result: String
                    do {
                        result = try runner.tcpTest(config: config, outbound: tag, address: address)
                    } catch {
                        result = "失败"
                    }
                    await MainActor.run { [weak self] in
                        guard let self, self.nodes.indices.contains(index), self.nodes[index].tag == tag else { return }
                        self.nodes[index].tcp = result
                        self.nodeTable.reloadData()
                    }
                }
                await MainActor.run { [weak self] in
                    self?.appendLog("[节点] TCP 测试完成\n")
                }
            }
        } catch {
            showError(error)
        }
    }

    @objc func modeChanged() {
        nodesModeControl.selectedSegment = modeControl.selectedSegment
        do {
            try applySelectedMode()
        } catch {
            refreshModeFromEditor()
            showError(error)
        }
    }

    @objc func nodesModeChanged() {
        modeControl.selectedSegment = nodesModeControl.selectedSegment
        do {
            try applySelectedMode()
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
    }
}

