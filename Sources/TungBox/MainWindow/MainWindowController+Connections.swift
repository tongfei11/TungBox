import AppKit
import Foundation

extension MainWindowController {

    func makeConnectionsView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        let title = NSTextField(labelWithString: "连接")
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false
        tightenLabelCell(title)
        registerThemeObserver { [weak title] in
            title?.textColor = MD3.onSurface
        }

        let subtitle = NSTextField(labelWithString: "查看当前活动网络连接和分流规则")
        subtitle.textColor = MD3.onSurfaceVariant
        subtitle.font = .systemFont(ofSize: 12)
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

        // Filter bar
        let filterField = connectionFilterField
        filterField.placeholderString = "过滤节点 / 域名 / IP / 规则..."
        filterField.target = self
        filterField.action = #selector(connectionFilterChanged)
        filterField.translatesAutoresizingMaskIntoConstraints = false
        filterField.heightAnchor.constraint(equalToConstant: 34).isActive = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectionFilterChanged),
            name: NSControl.textDidChangeNotification,
            object: filterField
        )

        let refreshButton = MD3Button()
        refreshButton.title = "刷新"
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        refreshButton.style = .filled
        refreshButton.target = self
        refreshButton.action = #selector(refreshConnectionsClicked)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.heightAnchor.constraint(equalToConstant: ConsoleControlLayout.actionHeight).isActive = true

        let closeButton = MD3Button()
        closeButton.title = "关闭全部"
        closeButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        closeButton.style = .destructive
        closeButton.target = self
        closeButton.action = #selector(closeAllConnectionsClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.heightAnchor.constraint(equalToConstant: ConsoleControlLayout.actionHeight).isActive = true

        let buttons = NSStackView(views: [refreshButton, closeButton])
        ConsoleControlLayout.equalizeActionWidths([refreshButton, closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let toolbar = NSStackView(views: [filterField, buttons])
        toolbar.orientation = .horizontal
        toolbar.spacing = 12
        toolbar.alignment = .centerY
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        filterField.widthAnchor.constraint(equalTo: toolbar.widthAnchor, multiplier: 0.58).isActive = true

        let panel = MD3Panel()
        panel.type = .filled
        panel.translatesAutoresizingMaskIntoConstraints = false

        let scroll = MD3ScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.applyThinOverlayScroller()
        scroll.drawsBackground = false

        connectionsTable.backgroundColor = .clear
        connectionsTable.addTableColumn(connectionColumn("index", "#", 30))
        connectionsTable.addTableColumn(connectionColumn("network", "网络", 50))
        connectionsTable.addTableColumn(connectionColumn("status", "状态", 80))
        connectionsTable.addTableColumn(connectionColumn("source", "来源 IP", 88))
        connectionsTable.addTableColumn(connectionColumn("destination", "目标", 164))
        connectionsTable.addTableColumn(connectionColumn("outbound", "出站", 86))
        connectionsTable.addTableColumn(connectionColumn("traffic", "流量", 112))
        connectionsTable.addTableColumn(connectionColumn("rule", "规则", 96))
        // Keep the short columns compact; the final rule column takes extra room.
        connectionsTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        connectionsTable.delegate = self
        connectionsTable.dataSource = self
        connectionsTable.rowHeight = 38
        connectionsTable.gridStyleMask = [.solidHorizontalGridLineMask]
        connectionsTable.gridColor = MD3.outlineVariant.withAlphaComponent(0.25)
        connectionsTable.menu = connectionContextMenu()
        scroll.documentView = connectionsTable

        panel.addSubview(scroll)

        connectionCountLabel.font = .systemFont(ofSize: 12)
        connectionCountLabel.textColor = MD3.onSurfaceVariant
        connectionCountLabel.translatesAutoresizingMaskIntoConstraints = false
        connectionCountLabel.stringValue = "共 \(displayedConnections.count) 条连接"
        registerThemeObserver { [weak self] in
            self?.connectionCountLabel.textColor = MD3.onSurfaceVariant
        }

        view.addSubview(headerStack)
        view.addSubview(toolbar)
        view.addSubview(panel)
        view.addSubview(connectionCountLabel)

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),

            toolbar.leadingAnchor.constraint(equalTo: headerStack.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            toolbar.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 18),

            panel.leadingAnchor.constraint(equalTo: headerStack.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            panel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 14),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -46),

            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -6),

            connectionCountLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 4),
            connectionCountLabel.topAnchor.constraint(equalTo: panel.bottomAnchor, constant: 10)
        ])

        return view
    }

    private func connectionColumn(_ id: String, _ title: String, _ width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        return column
    }

    func filteredConnections() -> [ConnectionInfo] {
        let query = connectionFilterField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return connections }
        return connections.filter { conn in
            conn.outbound.lowercased().contains(query) ||
            conn.destination.lowercased().contains(query) ||
            conn.source.lowercased().contains(query) ||
            conn.status.lowercased().contains(query) ||
            conn.rule.lowercased().contains(query) ||
            conn.network.lowercased().contains(query)
        }
    }

    /// Polling still maintains traffic totals in the background; only paint a visible table.
    func refreshConnectionsTable() {
        guard window?.isVisible == true, window?.isMiniaturized == false,
              isConnectionsPageSelected() else { return }
        let rows = filteredConnections()
        connectionCountLabel.stringValue = "共 \(rows.count) 条连接"
        guard rows != displayedConnections else { return }
        let sameOrder = rows.map(\.id) == displayedConnections.map(\.id)
        displayedConnections = rows
        if !sameOrder {
            connectionsTable.reloadData()
            return
        }
        // Retain cells and selection, including AppKit's prepared off-screen rows.
        connectionsTable.enumerateAvailableRowViews { rowView, row in
            guard rows.indices.contains(row) else { return }
            for (column, definition) in self.connectionsTable.tableColumns.enumerated() {
                let colID = definition.identifier.rawValue
                if colID == "index" {
                    if let cell = rowView.view(atColumn: column) as? ConnectionTextCell {
                        cell.update(text: String(format: "%02d", row + 1), isMuted: true)
                    }
                } else if colID == "network" {
                    if let cell = rowView.view(atColumn: column) as? ConnectionPillCell {
                        cell.update(network: rows[row].network)
                    }
                } else if colID == "status" {
                    if let cell = rowView.view(atColumn: column) as? ConnectionStatusCell {
                        cell.update(status: rows[row].status)
                    }
                } else {
                    if let cell = rowView.view(atColumn: column) as? ConnectionTextCell {
                        let isMuted = (colID == "source" || colID == "rule")
                        cell.update(text: self.connectionCellText(for: rows[row], columnID: colID), isMuted: isMuted)
                    }
                }
            }
        }
    }

    func connectionContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "关闭此连接", action: #selector(closeSingleConnectionClicked(_:)), keyEquivalent: ""))
        return menu
    }

    @objc func connectionFilterChanged() {
        refreshConnectionsTable()
    }

    func startConnectionsRefreshTimer() {
        guard isProxyRuntimeRunning() else {
            stopConnectionsRefreshTimer()
            clearConnections()
            return
        }
        guard statsTimer == nil else { return }
        if connectionsRefreshTimer == nil {
            connectionsRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshConnections(showErrors: false)
                }
            }
        }
    }

    func stopConnectionsRefreshTimer() {
        connectionsRefreshTimer?.invalidate()
        connectionsRefreshTimer = nil
    }

    func clearConnections() {
        connections.removeAll()
        prevConnections.removeAll()
        trafficDestinationTracker = TrafficDestinationTracker()
        prevTrafficTotals.removeAll()   // sing-box 重启时基准会归零，下次重新算
        connectionRefreshTime = .distantPast
        refreshConnectionsTable()
        updateConnectionsCard(value: "0", detail: "服务未运行")
    }

    func refreshConnections(showErrors: Bool) {
        guard isProxyRuntimeRunning() else {
            clearConnections()
            return
        }
        guard !isRefreshingConnections else { return }
        isRefreshingConnections = true
        // 同时拉用户代理(9090) 和 TUN 守护进程(9091) 的 connections + totals。
        // 流量累计走 totals 路径，包含 UDP/IPv6/已关闭短连接。
        let extraPorts: [Int] = isTunRuntimeRunning() ? [TungBoxConfig.tunDaemonClashPort] : []
        let allPorts: [Int] = [9090] + extraPorts
        Task { [self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.isRefreshingConnections = false
                }
            }
            do {
                let snapshot = try await ClashAPI.connectionSnapshot(ports: allPorts)
                let list = snapshot.connections
                let totals = snapshot.totals
                await MainActor.run {
                    applyConnections(list, detail: "实时刷新")
                    if !totals.isEmpty { accumulateTraffic(from: snapshot) }
                }
            } catch {
                await MainActor.run {
                    appendLog("[连接] 刷新失败：\(error.localizedDescription)\n")
                    updateConnectionsCard(value: "\(connections.count)", detail: "刷新超时，保留上次结果")
                    if showErrors {
                        showToast("连接刷新失败：\(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func applyConnections(_ list: [ConnectionInfo], detail: String) {
        let now = Date()
        let elapsed = max(now.timeIntervalSince(connectionRefreshTime), 0.5)

        // 每个 connection 的瞬时速率（仅用于显示连接表的"上传速度"列）。
        // ⚠️ 这里只算速率，**不再用于流量累计** —— per-connection delta 会丢掉
        // 短连接关闭后的字节（典型：YouTube QUIC 流），流量累计走 totals 路径。
        var previousByID: [String: ConnectionInfo] = [:]
        for previous in prevConnections { previousByID[previous.id] = previous }
        var speedMap: [String: (up: Int, down: Int)] = [:]
        for curr in list {
            if let prev = previousByID[curr.id] {
                let uploadDelta = SaturatingArithmetic.nonnegativeDifference(curr.upload, prev.upload)
                let downloadDelta = SaturatingArithmetic.nonnegativeDifference(curr.download, prev.download)
                speedMap[curr.id] = (
                    SaturatingArithmetic.rate(bytes: uploadDelta, elapsed: elapsed),
                    SaturatingArithmetic.rate(bytes: downloadDelta, elapsed: elapsed)
                )
            }
        }

        connections = list.map { conn in
            var c = conn
            c.uploadSpeed = speedMap[conn.id]?.up ?? 0
            c.downloadSpeed = speedMap[conn.id]?.down ?? 0
            return c
        }

        prevConnections = list
        connectionRefreshTime = now
        refreshConnectionsTable()
        updateConnectionsCard(value: "\(connections.count)", detail: detail)
    }

    /// 用 sing-box 进程级累计字节数（`uploadTotal` / `downloadTotal`）算 delta，
    /// 累加到持久化流量历史。包含 UDP / IPv6 / 已关闭的短连接，这是正确流量源。
    /// 同时更新右上角实时速率（基于这一次和上一次的差值 / 间隔）。
    func accumulateTraffic(from snapshot: ClashAPI.ConnectionSnapshot) {
        // Both page timers consume snapshots; a delayed older response must not
        // rewind the baseline and count the same bytes again on the next poll.
        guard snapshot.sampledAt > lastTrafficSnapshotTime else { return }
        lastTrafficSnapshotTime = snapshot.sampledAt
        let totals = snapshot.totals
        let destinations = trafficDestinationTracker.record(
            connectionsByPort: snapshot.connectionsByPort, totals: totals, previousTotals: prevTrafficTotals,
            proxyTags: Set(nodes.map(\.tag))
        )
        // 第一次拉到：仅记录基准，不算 delta（否则会把"从 sing-box 启动到现在"
        // 的累计全部一次性算进当前会话）。
        guard !prevTrafficTotals.isEmpty else {
            prevTrafficTotals = totals
            return
        }

        var deltaUp: Int64 = 0
        var deltaDown: Int64 = 0
        for (port, curr) in totals {
            if let prev = prevTrafficTotals[port], curr.upload >= prev.upload, curr.download >= prev.download {
                deltaUp = SaturatingArithmetic.add(deltaUp, SaturatingArithmetic.nonnegativeDifference(curr.upload, prev.upload))
                deltaDown = SaturatingArithmetic.add(deltaDown, SaturatingArithmetic.nonnegativeDifference(curr.download, prev.download))
            }
            // 若 sing-box 进程重启（totals 回到 0 或减小），那个端口本轮跳过，
            // 不计 delta，从下一轮重新算基准。
        }
        prevTrafficTotals = totals

        if deltaUp > 0 || deltaDown > 0 {
            let safeUp = SaturatingArithmetic.clampedInt(deltaUp)
            let safeDown = SaturatingArithmetic.clampedInt(deltaDown)
            recordTraffic(upload: safeUp, download: safeDown, proxy: destinations.proxy, direct: destinations.direct)
            totalUploadBytes = SaturatingArithmetic.add(totalUploadBytes, safeUp)
            totalDownloadBytes = SaturatingArithmetic.add(totalDownloadBytes, safeDown)
            updateTrafficLabels()
        }
    }

    /// 速率更新现在仅依赖 totals delta（流量累计同源），不再独立累加 delta。
    func updateRealtimeSpeed(uploadSpeed: Int, downloadSpeed: Int) {
        let speedChanged = (currentUploadSpeed != uploadSpeed) || (currentDownloadSpeed != downloadSpeed)
        currentUploadSpeed = uploadSpeed
        currentDownloadSpeed = downloadSpeed
        uploadValueLabel.stringValue = "\(formatBytes(uploadSpeed))/s"
        downloadValueLabel.stringValue = "\(formatBytes(downloadSpeed))/s"

        SpeedRingBuffer.shared.record(uploadSpeedBytes: uploadSpeed, downloadSpeedBytes: downloadSpeed)
        uploadWaveChartView.samples = SpeedRingBuffer.shared.uploadSamples
        downloadWaveChartView.samples = SpeedRingBuffer.shared.downloadSamples
        let maxSample = max(SpeedRingBuffer.shared.uploadSamples.max() ?? 10.0, SpeedRingBuffer.shared.downloadSamples.max() ?? 10.0, 10.0)
        let scale = ceil(maxSample / 10.0) * 10.0
        uploadWaveChartView.maxScaleKB = scale
        downloadWaveChartView.maxScaleKB = scale

        let activeState = isProxyServiceActiveOrRequested()
        if speedChanged || lastTrayActiveState == nil || activeState != lastTrayActiveState {
            lastTrayActiveState = activeState
            refreshTrayIcon()
        }
    }

    @objc func closeSingleConnectionClicked(_ sender: Any) {
        let row = connectionsTable.clickedRow
        guard row >= 0 else { return }
        let conns = displayedConnections
        guard conns.indices.contains(row) else { return }
        let conn = conns[row]
        let connectionPort: Int?
        let connectionID: String
        if conn.id.hasPrefix("p9091:") {
            connectionPort = TungBoxConfig.tunDaemonClashPort
            connectionID = String(conn.id.dropFirst("p9091:".count))
        } else {
            connectionPort = nil
            connectionID = conn.id
        }

        Task {
            do {
                try await ClashAPI.closeConnection(id: connectionID, port: connectionPort)
                await MainActor.run {
                    // Remove from the unfiltered list too
                    connections.removeAll { $0.id == conn.id }
                    refreshConnectionsTable()
                    appendLog("[连接] 已关闭 \(conn.destination)\n")
                }
            } catch {
                await MainActor.run { showError(error) }
            }
        }
    }

    @objc func refreshConnectionsClicked() {
        refreshConnections(showErrors: true)
    }

    @objc func closeAllConnectionsClicked() {
        guard isProxyRuntimeRunning() else { return }
        Task {
            do {
                _ = try await ClashAPI.closeConnections(port: delayAPIPort())
                connections.removeAll()
                refreshConnectionsTable()
                appendLog("[连接] 已关闭全部连接\n")
            } catch {
                showError(error)
            }
        }
    }

    func connectionCellText(for connection: ConnectionInfo, columnID: String) -> String {
        let text: String
        switch columnID {
        case "network": text = connection.network
        case "status": text = connection.status
        case "source": text = connection.source
        case "destination": text = connection.destination
        case "rule": text = connection.rule
        case "outbound": text = connection.outbound
        case "traffic":
            if connection.uploadSpeed > 0 || connection.downloadSpeed > 0 {
                text = "↑\(formatBytes(connection.uploadSpeed))/s ↓\(formatBytes(connection.downloadSpeed))/s"
            } else {
                text = "\(formatBytes(connection.upload)) / \(formatBytes(connection.download))"
            }
        default: text = ""
        }

        return text
    }

    func makeConnectionCell(for connection: ConnectionInfo, columnID: String, row: Int = 0) -> NSView {
        if columnID == "index" {
            let identifier = NSUserInterfaceItemIdentifier("Connection-index")
            let cell = connectionsTable.makeView(withIdentifier: identifier, owner: nil) as? ConnectionTextCell
                ?? ConnectionTextCell()
            cell.identifier = identifier
            cell.update(text: String(format: "%02d", row + 1), isMuted: true)
            return cell
        } else if columnID == "network" {
            let identifier = NSUserInterfaceItemIdentifier("Connection-network")
            let cell = connectionsTable.makeView(withIdentifier: identifier, owner: nil) as? ConnectionPillCell
                ?? ConnectionPillCell()
            cell.identifier = identifier
            cell.update(network: connection.network)
            return cell
        } else if columnID == "status" {
            let identifier = NSUserInterfaceItemIdentifier("Connection-status")
            let cell = connectionsTable.makeView(withIdentifier: identifier, owner: nil) as? ConnectionStatusCell
                ?? ConnectionStatusCell()
            cell.identifier = identifier
            cell.update(status: connection.status)
            return cell
        } else {
            let text = connectionCellText(for: connection, columnID: columnID)
            let identifier = NSUserInterfaceItemIdentifier("Connection-" + columnID)
            let cell = connectionsTable.makeView(withIdentifier: identifier, owner: nil) as? ConnectionTextCell
                ?? ConnectionTextCell()
            cell.identifier = identifier
            let isMuted = (columnID == "source" || columnID == "rule")
            cell.update(text: text, isMuted: isMuted)
            return cell
        }
    }
}
