import AppKit

/// Pure dashboard layout and card construction; contains no controller, services or networking.
@MainActor
enum HomeDashboardLayout {
    /// Modern 4-2-3 Grid layout matching the new console design:
    /// - Row 1: 4 equal control cards (System Proxy, TUN Mode, Outbound Mode, Current Node)
    /// - Row 2: 2 monitoring cards (Traffic Trend ~60%, Realtime Speed ~40%)
    /// - Row 3: 3 metric/activity cards (Active Connections, Traffic Breakdown, Recent Status)
    static func dashboardGrid(
        systemProxyCard: NSView,
        tunCard: NSView,
        outboundCard: NSView,
        currentNodeCard: NSView,
        trafficTrendCard: NSView,
        realtimeSpeedCard: NSView,
        activeConnectionsCard: NSView,
        trafficDestinationCard: NSView,
        recentStatusCard: NSView
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let allCards = [
            systemProxyCard, tunCard, outboundCard, currentNodeCard,
            trafficTrendCard, realtimeSpeedCard,
            activeConnectionsCard, trafficDestinationCard, recentStatusCard
        ]
        allCards.forEach { container.addSubview($0) }

        let spacing: CGFloat = 12

        NSLayoutConstraint.activate([
            // --- Row 1 (4 Cards: 192 : 176 : 226 : 168, Height: 90) ---
            systemProxyCard.topAnchor.constraint(equalTo: container.topAnchor),
            systemProxyCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            tunCard.topAnchor.constraint(equalTo: container.topAnchor),
            tunCard.leadingAnchor.constraint(equalTo: systemProxyCard.trailingAnchor, constant: spacing),
            tunCard.widthAnchor.constraint(equalTo: systemProxyCard.widthAnchor, multiplier: 176.0 / 192.0),

            outboundCard.topAnchor.constraint(equalTo: container.topAnchor),
            outboundCard.leadingAnchor.constraint(equalTo: tunCard.trailingAnchor, constant: spacing),
            outboundCard.widthAnchor.constraint(equalTo: systemProxyCard.widthAnchor, multiplier: 226.0 / 192.0),

            currentNodeCard.topAnchor.constraint(equalTo: container.topAnchor),
            currentNodeCard.leadingAnchor.constraint(equalTo: outboundCard.trailingAnchor, constant: spacing),
            currentNodeCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            currentNodeCard.widthAnchor.constraint(equalTo: systemProxyCard.widthAnchor, multiplier: 168.0 / 192.0),

            systemProxyCard.heightAnchor.constraint(equalToConstant: 90),
            tunCard.heightAnchor.constraint(equalTo: systemProxyCard.heightAnchor),
            outboundCard.heightAnchor.constraint(equalTo: systemProxyCard.heightAnchor),
            currentNodeCard.heightAnchor.constraint(equalTo: systemProxyCard.heightAnchor),

            // --- Row 2 (Traffic Trend 506 : Realtime Speed 277, Height: 215) ---
            trafficTrendCard.topAnchor.constraint(equalTo: systemProxyCard.bottomAnchor, constant: spacing),
            trafficTrendCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            realtimeSpeedCard.topAnchor.constraint(equalTo: systemProxyCard.bottomAnchor, constant: spacing),
            realtimeSpeedCard.leadingAnchor.constraint(equalTo: trafficTrendCard.trailingAnchor, constant: spacing),
            realtimeSpeedCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            trafficTrendCard.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 506.0 / 794.0, constant: -spacing * 0.5),
            trafficTrendCard.heightAnchor.constraint(equalToConstant: 215),
            realtimeSpeedCard.heightAnchor.constraint(equalTo: trafficTrendCard.heightAnchor),

            // --- Row 3 (Connections 251 : Destinations 279 : Recent Status 243, Height: 200) ---
            activeConnectionsCard.topAnchor.constraint(equalTo: trafficTrendCard.bottomAnchor, constant: spacing),
            activeConnectionsCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            trafficDestinationCard.topAnchor.constraint(equalTo: trafficTrendCard.bottomAnchor, constant: spacing),
            trafficDestinationCard.leadingAnchor.constraint(equalTo: activeConnectionsCard.trailingAnchor, constant: spacing),
            trafficDestinationCard.widthAnchor.constraint(equalTo: activeConnectionsCard.widthAnchor, multiplier: 279.0 / 251.0),

            recentStatusCard.topAnchor.constraint(equalTo: trafficTrendCard.bottomAnchor, constant: spacing),
            recentStatusCard.leadingAnchor.constraint(equalTo: trafficDestinationCard.trailingAnchor, constant: spacing),
            recentStatusCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            recentStatusCard.widthAnchor.constraint(equalTo: activeConnectionsCard.widthAnchor, multiplier: 243.0 / 251.0),

            activeConnectionsCard.heightAnchor.constraint(equalToConstant: 200),
            trafficDestinationCard.heightAnchor.constraint(equalTo: activeConnectionsCard.heightAnchor),
            recentStatusCard.heightAnchor.constraint(equalTo: activeConnectionsCard.heightAnchor),

            container.bottomAnchor.constraint(equalTo: activeConnectionsCard.bottomAnchor)
        ])

        return container
    }

    /// Legacy 8-card grid preserved for backward compatibility and layout tests.
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
            tunCard.widthAnchor.constraint(equalTo: serviceCard.widthAnchor),
            uploadCard.widthAnchor.constraint(equalTo: serviceCard.widthAnchor),
            downloadCard.widthAnchor.constraint(equalTo: serviceCard.widthAnchor),

            outboundCard.widthAnchor.constraint(equalTo: serviceCard.widthAnchor, multiplier: 2.0, constant: 12),
            nodeLatencyCard.widthAnchor.constraint(equalTo: outboundCard.widthAnchor),
            activeConnectionsCard.widthAnchor.constraint(equalTo: outboundCard.widthAnchor),
            trafficStatsCard.widthAnchor.constraint(equalTo: outboundCard.widthAnchor),

            serviceCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 128),
            tunCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            outboundCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            nodeLatencyCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            uploadCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            downloadCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            activeConnectionsCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            trafficStatsCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),

            serviceCard.topAnchor.constraint(equalTo: container.topAnchor),
            serviceCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            tunCard.topAnchor.constraint(equalTo: container.topAnchor),
            tunCard.leadingAnchor.constraint(equalTo: serviceCard.trailingAnchor, constant: 12),

            outboundCard.topAnchor.constraint(equalTo: container.topAnchor),
            outboundCard.leadingAnchor.constraint(equalTo: tunCard.trailingAnchor, constant: 12),
            outboundCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            nodeLatencyCard.topAnchor.constraint(equalTo: serviceCard.bottomAnchor, constant: 12),
            nodeLatencyCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            uploadCard.topAnchor.constraint(equalTo: serviceCard.bottomAnchor, constant: 12),
            uploadCard.leadingAnchor.constraint(equalTo: nodeLatencyCard.trailingAnchor, constant: 12),

            downloadCard.topAnchor.constraint(equalTo: serviceCard.bottomAnchor, constant: 12),
            downloadCard.leadingAnchor.constraint(equalTo: uploadCard.trailingAnchor, constant: 12),
            downloadCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            activeConnectionsCard.topAnchor.constraint(equalTo: nodeLatencyCard.bottomAnchor, constant: 12),
            activeConnectionsCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            trafficStatsCard.topAnchor.constraint(equalTo: nodeLatencyCard.bottomAnchor, constant: 12),
            trafficStatsCard.leadingAnchor.constraint(equalTo: activeConnectionsCard.trailingAnchor, constant: 12),
            trafficStatsCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            container.bottomAnchor.constraint(equalTo: activeConnectionsCard.bottomAnchor)
        ])

        return container
    }

    static func card(
        title: String,
        iconName: String? = nil,
        subtitle: String? = nil,
        titleInlineView: NSView? = nil,
        titleAccessoryView: NSView? = nil,
        views: [NSView]
    ) -> (view: NSView, title: NSTextField) {
        let panel = MD3Panel()
        panel.type = .elevated
        panel.translatesAutoresizingMaskIntoConstraints = false

        let titleStack = NSStackView()
        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 8
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        if let icon = iconName, let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            img.isTemplate = true
            let iconView = NSImageView(image: img)
            iconView.contentTintColor = MD3.primary
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
            iconView.heightAnchor.constraint(equalToConstant: 16).isActive = true
            titleStack.addArrangedSubview(iconView)
        }

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = MD3.onSurface
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleStack.addArrangedSubview(titleLabel)

        if let sub = subtitle {
            let subLabel = NSTextField(labelWithString: sub)
            subLabel.font = .systemFont(ofSize: 11)
            subLabel.textColor = MD3.onSurfaceVariant.withAlphaComponent(0.7)
            subLabel.translatesAutoresizingMaskIntoConstraints = false
            titleStack.addArrangedSubview(subLabel)
        }

        if let inline = titleInlineView {
            titleStack.addArrangedSubview(inline)
        }

        if let accessory = titleAccessoryView {
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            titleStack.addArrangedSubview(spacer)
            titleStack.addArrangedSubview(accessory)
        }

        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        if views.count == 1, let single = views.first {
            contentContainer.addSubview(single)
            NSLayoutConstraint.activate([
                single.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                single.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                single.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                single.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
            ])
        } else {
            let stack = NSStackView(views: views)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                stack.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: contentContainer.bottomAnchor)
            ])
            views.forEach { subview in
                subview.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
                subview.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
            }
        }

        panel.addSubview(titleStack)
        panel.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            titleStack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            titleStack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            titleStack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            titleStack.heightAnchor.constraint(equalToConstant: 24),

            contentContainer.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            contentContainer.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            contentContainer.topAnchor.constraint(equalTo: titleStack.bottomAnchor, constant: 8),
            contentContainer.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12)
        ])

        return (panel, titleLabel)
    }
}
