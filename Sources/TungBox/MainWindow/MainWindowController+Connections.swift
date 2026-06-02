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

        let refreshButton = MD3Button()
        refreshButton.title = "刷新连接"
        refreshButton.style = .tonal
        refreshButton.target = self
        refreshButton.action = #selector(refreshConnectionsClicked)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let closeButton = MD3Button()
        closeButton.title = "关闭全部连接"
        closeButton.style = .outlined
        closeButton.target = self
        closeButton.action = #selector(closeAllConnectionsClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let buttons = NSStackView(views: [refreshButton, closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

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
        scroll.documentView = connectionsTable

        panel.addSubview(scroll)
        view.addSubview(title)
        view.addSubview(buttons)
        view.addSubview(panel)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),

            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            buttons.centerYAnchor.constraint(equalTo: title.centerYAnchor),

            panel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            panel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),
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

    @objc func refreshConnectionsClicked() {
        guard isProxyRuntimeRunning() else {
            connections.removeAll()
            connectionsTable.reloadData()
            return
        }
        Task {
            do {
                let list = try await ClashAPI.connections()
                connections = list
                connectionsTable.reloadData()
                updateConnectionsCard(value: "\(connections.count)", detail: "已从 Clash API 刷新")
            } catch {
                showError(error)
            }
        }
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
        case "traffic": text = "\(formatBytes(connection.upload)) / \(formatBytes(connection.download))"
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
