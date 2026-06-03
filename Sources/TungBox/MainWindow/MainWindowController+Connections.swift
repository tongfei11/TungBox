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
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak title] in
            title?.textColor = MD3.onSurface
        }

        // Filter bar
        let filterField = connectionFilterField
        filterField.placeholderString = "过滤节点 / 域名 / IP / 规则..."
        filterField.target = self
        filterField.action = #selector(connectionFilterChanged)
        filterField.translatesAutoresizingMaskIntoConstraints = false
        filterField.heightAnchor.constraint(equalToConstant: 32).isActive = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectionFilterChanged),
            name: NSControl.textDidChangeNotification,
            object: filterField
        )

        let refreshButton = MD3Button()
        refreshButton.title = "刷新"
        refreshButton.style = .tonal
        refreshButton.target = self
        refreshButton.action = #selector(refreshConnectionsClicked)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        refreshButton.widthAnchor.constraint(equalToConstant: 80).isActive = true

        let closeButton = MD3Button()
        closeButton.title = "关闭全部"
        closeButton.style = .outlined
        closeButton.target = self
        closeButton.action = #selector(closeAllConnectionsClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        closeButton.widthAnchor.constraint(equalToConstant: 100).isActive = true

        let buttons = NSStackView(views: [refreshButton, closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let toolbar = NSStackView(views: [filterField, buttons])
        toolbar.orientation = .horizontal
        toolbar.spacing = 12
        toolbar.alignment = .centerY
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        filterField.widthAnchor.constraint(equalTo: toolbar.widthAnchor, multiplier: 0.55).isActive = true

        let panel = MD3Panel()
        panel.type = .filled
        panel.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        connectionsTable.backgroundColor = .clear
        connectionsTable.addTableColumn(connectionColumn("network", "网络", 70))
        connectionsTable.addTableColumn(connectionColumn("source", "来源", 150))
        connectionsTable.addTableColumn(connectionColumn("destination", "目标", 240))
        connectionsTable.addTableColumn(connectionColumn("rule", "规则", 140))
        connectionsTable.addTableColumn(connectionColumn("outbound", "出站", 130))
        connectionsTable.addTableColumn(connectionColumn("traffic", "流量", 120))
        connectionsTable.delegate = self
        connectionsTable.dataSource = self
        connectionsTable.rowHeight = 40
        connectionsTable.gridStyleMask = [.solidHorizontalGridLineMask]
        connectionsTable.menu = connectionContextMenu()
        scroll.documentView = connectionsTable

        panel.addSubview(scroll)
        view.addSubview(title)
        view.addSubview(toolbar)
        view.addSubview(panel)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),

            toolbar.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            toolbar.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),

            panel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            panel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),

            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12)
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
            conn.rule.lowercased().contains(query) ||
            conn.network.lowercased().contains(query)
        }
    }

    func connectionContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "关闭此连接", action: #selector(closeSingleConnectionClicked(_:)), keyEquivalent: ""))
        return menu
    }

    @objc func connectionFilterChanged() {
        connectionsTable.reloadData()
    }

    func startConnectionsRefreshTimer() {
        guard isProxyRuntimeRunning() else {
            stopConnectionsRefreshTimer()
            clearConnections()
            return
        }
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
        connectionRefreshTime = .distantPast
        connectionsTable.reloadData()
        updateConnectionsCard(value: "0", detail: "服务未运行")
    }

    func refreshConnections(showErrors: Bool) {
        guard isProxyRuntimeRunning() else {
            clearConnections()
            return
        }
        guard !isRefreshingConnections else { return }
        isRefreshingConnections = true
        Task {
            defer {
                Task { @MainActor [weak self] in
                    self?.isRefreshingConnections = false
                }
            }
            do {
                let list = try await ClashAPI.connections()
                await MainActor.run {
                    applyConnections(list, detail: "实时刷新")
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

        var speedMap: [String: (up: Int, down: Int)] = [:]
        for prev in prevConnections {
            if let curr = list.first(where: { $0.id == prev.id }) {
                let upSpeed = max(0, curr.upload - prev.upload)
                let downSpeed = max(0, curr.download - prev.download)
                speedMap[curr.id] = (
                    Int(Double(upSpeed) / elapsed),
                    Int(Double(downSpeed) / elapsed)
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
        connectionsTable.reloadData()
        updateConnectionsCard(value: "\(connections.count)", detail: detail)
    }

    @objc func closeSingleConnectionClicked(_ sender: Any) {
        let row = connectionsTable.clickedRow
        guard row >= 0 else { return }
        let conns = filteredConnections()
        guard conns.indices.contains(row) else { return }
        let conn = conns[row]

        Task {
            do {
                try await ClashAPI.closeConnection(id: conn.id)
                await MainActor.run {
                    // Remove from the unfiltered list too
                    connections.removeAll { $0.id == conn.id }
                    connectionsTable.reloadData()
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
                _ = try await ClashAPI.closeConnections()
                connections.removeAll()
                connectionsTable.reloadData()
                appendLog("[连接] 已关闭全部连接\n")
            } catch {
                showError(error)
            }
        }
    }

    func makeConnectionCell(for connection: ConnectionInfo, columnID: String) -> NSView {
        let text: String
        switch columnID {
        case "network": text = connection.network
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

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = MD3.onSurface
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }
}
