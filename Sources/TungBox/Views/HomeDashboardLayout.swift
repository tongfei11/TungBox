import AppKit

/// Pure dashboard construction; contains no controller, services or networking.
@MainActor
enum HomeDashboardLayout {
    static func grid(serviceCard: NSView, tunCard: NSView, outboundCard: NSView,
                     nodeLatencyCard: NSView, uploadCard: NSView, downloadCard: NSView,
                     activeConnectionsCard: NSView, trafficStatsCard: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(serviceCard)
        container.addSubview(tunCard)
        container.addSubview(outboundCard)
        container.addSubview(nodeLatencyCard)
        container.addSubview(uploadCard)
        container.addSubview(downloadCard)
        container.addSubview(activeConnectionsCard)
        container.addSubview(trafficStatsCard)

        NSLayoutConstraint.activate([
            // --- Width Constraints ---
            tunCard.widthAnchor.constraint(equalTo: serviceCard.widthAnchor),
            uploadCard.widthAnchor.constraint(equalTo: serviceCard.widthAnchor),
            downloadCard.widthAnchor.constraint(equalTo: serviceCard.widthAnchor),

            // 出站模式跨 2 个卡片宽：2 * 单卡宽 + 12(间距)
            outboundCard.widthAnchor.constraint(equalTo: serviceCard.widthAnchor, multiplier: 2.0, constant: 12),
            nodeLatencyCard.widthAnchor.constraint(equalTo: outboundCard.widthAnchor),
            activeConnectionsCard.widthAnchor.constraint(equalTo: outboundCard.widthAnchor),
            trafficStatsCard.widthAnchor.constraint(equalTo: outboundCard.widthAnchor),

            // --- Height Constraints ---
            serviceCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 128),
            tunCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            outboundCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            nodeLatencyCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            uploadCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            downloadCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            activeConnectionsCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            trafficStatsCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),

            // --- Row 1: 系统代理 | TUN | 出站模式 ---
            serviceCard.topAnchor.constraint(equalTo: container.topAnchor),
            serviceCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            tunCard.topAnchor.constraint(equalTo: container.topAnchor),
            tunCard.leadingAnchor.constraint(equalTo: serviceCard.trailingAnchor, constant: 12),

            outboundCard.topAnchor.constraint(equalTo: container.topAnchor),
            outboundCard.leadingAnchor.constraint(equalTo: tunCard.trailingAnchor, constant: 12),
            outboundCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // --- Row 2: 节点 | 上传 | 下载 ---
            nodeLatencyCard.topAnchor.constraint(equalTo: serviceCard.bottomAnchor, constant: 12),
            nodeLatencyCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            uploadCard.topAnchor.constraint(equalTo: serviceCard.bottomAnchor, constant: 12),
            uploadCard.leadingAnchor.constraint(equalTo: nodeLatencyCard.trailingAnchor, constant: 12),

            downloadCard.topAnchor.constraint(equalTo: serviceCard.bottomAnchor, constant: 12),
            downloadCard.leadingAnchor.constraint(equalTo: uploadCard.trailingAnchor, constant: 12),
            downloadCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // --- Row 3: 活动连接数 | 流量统计 ---
            activeConnectionsCard.topAnchor.constraint(equalTo: nodeLatencyCard.bottomAnchor, constant: 12),
            activeConnectionsCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            trafficStatsCard.topAnchor.constraint(equalTo: nodeLatencyCard.bottomAnchor, constant: 12),
            trafficStatsCard.leadingAnchor.constraint(equalTo: activeConnectionsCard.trailingAnchor, constant: 12),
            trafficStatsCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // Bottom constraint to calculate container height
            container.bottomAnchor.constraint(equalTo: activeConnectionsCard.bottomAnchor)
        ])

        return container
    }

    static func card(title: String, titleInlineView: NSView? = nil, titleAccessoryView: NSView? = nil, views: [NSView]) -> (view: NSView, title: NSTextField) {
        let panel = MD3Panel()
        panel.type = .elevated
        panel.translatesAutoresizingMaskIntoConstraints = false

        let titleStack = NSStackView()
        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 8
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = MD3.onSurface
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleStack.addArrangedSubview(titleLabel)

        if let inline = titleInlineView {
            titleStack.addArrangedSubview(inline)
        }

        if let accessory = titleAccessoryView {
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            titleStack.addArrangedSubview(spacer)
            titleStack.addArrangedSubview(accessory)
        }

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(titleStack)
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            titleStack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            titleStack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
            titleStack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            titleStack.heightAnchor.constraint(equalToConstant: 28),

            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: titleStack.bottomAnchor, constant: 12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -16)
        ])

        views.forEach { subview in
            subview.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            subview.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
        return (panel, titleLabel)
    }

}
