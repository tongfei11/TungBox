import AppKit
import Foundation

private final class HomeDocumentView: NSView {
    override var isFlipped: Bool { true }
}

extension MainWindowController {
    
    func makeHomeView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        // Header Title & Subtitle
        let title = NSTextField(labelWithString: "首页")
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "服务状态、出站模式和网络运行统计")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = MD3.onSurfaceVariant
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let titleCol = NSStackView(views: [title, subtitle])
        titleCol.orientation = .vertical
        titleCol.alignment = .leading
        titleCol.spacing = 3

        // Header Pill 1: Wi-Fi status pill
        let wifiImageView = NSImageView()
        if let wifiIcon = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil) {
            wifiIcon.isTemplate = true
            wifiImageView.image = wifiIcon
        }
        wifiImageView.contentTintColor = MD3.primary
        wifiImageView.translatesAutoresizingMaskIntoConstraints = false
        wifiImageView.widthAnchor.constraint(equalToConstant: 14).isActive = true
        wifiImageView.heightAnchor.constraint(equalToConstant: 14).isActive = true

        wifiStatusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        wifiStatusLabel.textColor = MD3.onSurface
        wifiStatusLabel.stringValue = NetworkReachability.shared.currentType.rawValue

        NetworkReachability.shared.onInterfaceChanged = { [weak self] type in
            self?.wifiStatusLabel.stringValue = type.rawValue
        }

        let wifiPill = MD3Panel()
        wifiPill.type = .filled
        wifiPill.translatesAutoresizingMaskIntoConstraints = false
        let wifiStack = NSStackView(views: [wifiImageView, wifiStatusLabel])
        wifiStack.orientation = .horizontal
        wifiStack.alignment = .centerY
        wifiStack.spacing = 6
        wifiStack.translatesAutoresizingMaskIntoConstraints = false
        wifiPill.addSubview(wifiStack)
        NSLayoutConstraint.activate([
            wifiPill.heightAnchor.constraint(equalToConstant: 30),
            wifiStack.leadingAnchor.constraint(equalTo: wifiPill.leadingAnchor, constant: 10),
            wifiStack.trailingAnchor.constraint(equalTo: wifiPill.trailingAnchor, constant: -10),
            wifiStack.centerYAnchor.constraint(equalTo: wifiPill.centerYAnchor)
        ])

        // Header Pill 2: Profile / Subscription Popup
        homeProfileSelectorPopup.translatesAutoresizingMaskIntoConstraints = false
        homeProfileSelectorPopup.heightAnchor.constraint(equalToConstant: 30).isActive = true
        homeProfileSelectorPopup.target = self
        homeProfileSelectorPopup.action = #selector(homeProfilePopupChanged(_:))
        refreshHomeProfilePopup()

        // Header Pill 3: External IP Pill
        let ipImageView = NSImageView()
        if let ipIcon = NSImage(systemSymbolName: "network", accessibilityDescription: nil) {
            ipIcon.isTemplate = true
            ipImageView.image = ipIcon
        }
        ipImageView.contentTintColor = MD3.primary
        ipImageView.translatesAutoresizingMaskIntoConstraints = false
        ipImageView.widthAnchor.constraint(equalToConstant: 14).isActive = true
        ipImageView.heightAnchor.constraint(equalToConstant: 14).isActive = true

        externalIPLabel.font = .systemFont(ofSize: 11, weight: .medium)
        externalIPLabel.textColor = MD3.onSurface

        externalIPRefreshButton.bezelStyle = .inline
        externalIPRefreshButton.isBordered = false
        externalIPRefreshButton.title = ""
        if let reloadIcon = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil) {
            reloadIcon.isTemplate = true
            externalIPRefreshButton.image = reloadIcon
        }
        externalIPRefreshButton.contentTintColor = MD3.onSurfaceVariant
        externalIPRefreshButton.target = self
        externalIPRefreshButton.action = #selector(refreshExternalIPClicked(_:))
        externalIPRefreshButton.toolTip = "刷新公网 IP"
        externalIPRefreshButton.translatesAutoresizingMaskIntoConstraints = false
        externalIPRefreshButton.widthAnchor.constraint(equalToConstant: 14).isActive = true
        externalIPRefreshButton.heightAnchor.constraint(equalToConstant: 14).isActive = true

        let ipPill = MD3Panel()
        ipPill.type = .filled
        ipPill.translatesAutoresizingMaskIntoConstraints = false
        let ipStack = NSStackView(views: [ipImageView, externalIPLabel, externalIPRefreshButton])
        ipStack.orientation = .horizontal
        ipStack.alignment = .centerY
        ipStack.spacing = 6
        ipStack.translatesAutoresizingMaskIntoConstraints = false
        ipPill.addSubview(ipStack)
        NSLayoutConstraint.activate([
            ipPill.heightAnchor.constraint(equalToConstant: 30),
            ipStack.leadingAnchor.constraint(equalTo: ipPill.leadingAnchor, constant: 10),
            ipStack.trailingAnchor.constraint(equalTo: ipPill.trailingAnchor, constant: -10),
            ipStack.centerYAnchor.constraint(equalTo: ipPill.centerYAnchor)
        ])

        refreshExternalIP(force: false)

        let headerAccessories = NSStackView(views: [wifiPill, homeProfileSelectorPopup, ipPill])
        headerAccessories.orientation = .horizontal
        headerAccessories.alignment = .centerY
        headerAccessories.spacing = 8

        let headerSpacer = NSView()
        headerSpacer.translatesAutoresizingMaskIntoConstraints = false
        let headerRow = NSStackView(views: [titleCol, headerSpacer, headerAccessories])
        headerRow.orientation = .horizontal
        headerRow.distribution = .fill
        headerRow.alignment = .centerY
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        // Card 1: 系统代理
        statusChip.translatesAutoresizingMaskIntoConstraints = false
        statusChip.heightAnchor.constraint(equalToConstant: 28).isActive = true
        statusChip.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true

        serviceSwitch.target = self
        serviceSwitch.action = #selector(switchToggled(_:))

        let systemProxySpacer = NSView()
        systemProxySpacer.translatesAutoresizingMaskIntoConstraints = false
        let systemProxyRow = NSStackView(views: [statusChip, systemProxySpacer, serviceSwitch])
        systemProxyRow.orientation = .horizontal
        systemProxyRow.distribution = .fill
        systemProxyRow.spacing = 4
        systemProxyRow.alignment = .centerY
        systemProxyRow.translatesAutoresizingMaskIntoConstraints = false

        let serviceDesc = NSTextField(labelWithString: "接管系统网络代理设置")
        serviceDesc.font = .systemFont(ofSize: 11)
        serviceDesc.textColor = MD3.onSurfaceVariant
        registerThemeObserver { [weak serviceDesc] in serviceDesc?.textColor = MD3.onSurfaceVariant }

        let serviceStack = NSStackView(views: [systemProxyRow, serviceDesc])
        serviceStack.orientation = .vertical
        serviceStack.alignment = .leading
        serviceStack.spacing = 8
        serviceStack.translatesAutoresizingMaskIntoConstraints = false
        systemProxyRow.leadingAnchor.constraint(equalTo: serviceStack.leadingAnchor).isActive = true
        systemProxyRow.trailingAnchor.constraint(equalTo: serviceStack.trailingAnchor).isActive = true
        let serviceCard = homeCard(title: "系统代理", iconName: "network", views: [serviceStack])

        // Card 2: TUN 模式
        tunStatusChip.translatesAutoresizingMaskIntoConstraints = false
        tunStatusChip.heightAnchor.constraint(equalToConstant: 28).isActive = true
        tunStatusChip.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true

        tunSwitch.target = self
        tunSwitch.action = #selector(tunSwitchToggled(_:))
        tunSwitch.isOn = isTunEnabled
        tunSwitch.translatesAutoresizingMaskIntoConstraints = false

        let tunSpacer = NSView()
        tunSpacer.translatesAutoresizingMaskIntoConstraints = false
        let tunControlRow = NSStackView(views: [tunStatusChip, tunSpacer, tunSwitch])
        tunControlRow.orientation = .horizontal
        tunControlRow.distribution = .fill
        tunControlRow.spacing = 4
        tunControlRow.alignment = .centerY
        tunControlRow.translatesAutoresizingMaskIntoConstraints = false

        let tunDesc = NSTextField(labelWithString: "虚拟网卡接管所有流量")
        tunDesc.font = .systemFont(ofSize: 11)
        tunDesc.textColor = MD3.onSurfaceVariant
        registerThemeObserver { [weak tunDesc] in tunDesc?.textColor = MD3.onSurfaceVariant }

        let tunStack = NSStackView(views: [tunControlRow, tunDesc])
        tunStack.orientation = .vertical
        tunStack.alignment = .leading
        tunStack.spacing = 8
        tunStack.translatesAutoresizingMaskIntoConstraints = false
        tunControlRow.leadingAnchor.constraint(equalTo: tunStack.leadingAnchor).isActive = true
        tunControlRow.trailingAnchor.constraint(equalTo: tunStack.trailingAnchor).isActive = true
        let tunCard = homeCard(title: "TUN 模式", iconName: "shield.checkerboard", views: [tunStack])

        // Card 3: 出站模式
        modeControl.items = ["直接连接", "全局代理", "规则判定"]
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.selectedSegment = 2
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.heightAnchor.constraint(equalToConstant: 32).isActive = true

        modeStatusLabel.textColor = MD3.onSurfaceVariant
        modeStatusLabel.font = .systemFont(ofSize: 11)
        modeStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak self] in
            self?.modeStatusLabel.textColor = MD3.onSurfaceVariant
        }

        let outboundStack = NSStackView(views: [modeControl, modeStatusLabel])
        outboundStack.orientation = .vertical
        outboundStack.alignment = .leading
        outboundStack.spacing = 8
        outboundStack.translatesAutoresizingMaskIntoConstraints = false
        modeControl.leadingAnchor.constraint(equalTo: outboundStack.leadingAnchor).isActive = true
        modeControl.trailingAnchor.constraint(equalTo: outboundStack.trailingAnchor).isActive = true
        let outboundCard = homeCard(title: "出站模式", iconName: "arrow.triangle.swap", views: [outboundStack])

        // Card 4: 当前节点
        currentNodeNameLabel.font = .systemFont(ofSize: 16, weight: .bold)
        currentNodeNameLabel.textColor = MD3.primary
        currentNodeNameLabel.lineBreakMode = .byTruncatingTail
        currentNodeNameLabel.maximumNumberOfLines = 1
        currentNodeNameLabel.translatesAutoresizingMaskIntoConstraints = false

        currentNodeAutoBadge.font = .systemFont(ofSize: 10, weight: .semibold)
        currentNodeAutoBadge.textColor = MD3.onSuccessContainer
        currentNodeAutoBadge.backgroundColor = MD3.successContainer
        currentNodeAutoBadge.drawsBackground = true
        currentNodeAutoBadge.isBezeled = false
        currentNodeAutoBadge.alignment = .center
        currentNodeAutoBadge.wantsLayer = true
        currentNodeAutoBadge.layer?.cornerRadius = 6
        currentNodeAutoBadge.layer?.masksToBounds = true
        currentNodeAutoBadge.translatesAutoresizingMaskIntoConstraints = false
        currentNodeAutoBadge.isHidden = true
        currentNodeAutoBadge.heightAnchor.constraint(equalToConstant: 18).isActive = true
        currentNodeAutoBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true

        let delayTitleLabel = NSTextField(labelWithString: "延迟:")
        delayTitleLabel.font = .systemFont(ofSize: 11)
        delayTitleLabel.textColor = MD3.onSurfaceVariant

        currentNodeDelayLabel.font = .systemFont(ofSize: 13, weight: .bold)
        currentNodeDelayLabel.textColor = MD3.success
        currentNodeDelayLabel.lineBreakMode = .byClipping
        currentNodeDelayLabel.maximumNumberOfLines = 1
        currentNodeDelayLabel.translatesAutoresizingMaskIntoConstraints = false

        let delayRow = NSStackView(views: [delayTitleLabel, currentNodeDelayLabel])
        delayRow.orientation = .horizontal
        delayRow.alignment = .centerY
        delayRow.spacing = 4

        let nodeStack = NSStackView(views: [currentNodeNameLabel, delayRow])
        nodeStack.orientation = .vertical
        nodeStack.alignment = .leading
        nodeStack.spacing = 8
        nodeStack.translatesAutoresizingMaskIntoConstraints = false
        currentNodeNameLabel.leadingAnchor.constraint(equalTo: nodeStack.leadingAnchor).isActive = true
        currentNodeNameLabel.trailingAnchor.constraint(equalTo: nodeStack.trailingAnchor).isActive = true
        let currentNodeCard = homeCard(
            title: "当前节点",
            iconName: "antenna.radiowaves.left.and.right",
            titleAccessoryView: currentNodeAutoBadge,
            views: [nodeStack]
        )

        // Card 5: 流量趋势
        trafficPeriodControl.items = ["今日", "近7天", "近30天"]
        trafficPeriodControl.target = self
        trafficPeriodControl.action = #selector(trafficPeriodChanged)
        trafficPeriodControl.selectedSegment = 0
        trafficPeriodControl.translatesAutoresizingMaskIntoConstraints = false
        trafficPeriodControl.heightAnchor.constraint(equalToConstant: 24).isActive = true
        trafficPeriodControl.widthAnchor.constraint(equalToConstant: 170).isActive = true

        trafficUploadStatLabel.font = .systemFont(ofSize: 11, weight: .medium)
        trafficUploadStatLabel.textColor = MD3.primary
        trafficDownloadStatLabel.font = .systemFont(ofSize: 11, weight: .medium)
        trafficDownloadStatLabel.textColor = NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0)

        let statsHeaderRow = NSStackView(views: [trafficUploadStatLabel, trafficDownloadStatLabel])
        statsHeaderRow.orientation = .horizontal
        statsHeaderRow.spacing = 16

        trafficTrendChartView.translatesAutoresizingMaskIntoConstraints = false

        let trendStack = NSStackView(views: [statsHeaderRow, trafficTrendChartView])
        trendStack.orientation = .vertical
        trendStack.alignment = .leading
        trendStack.spacing = 6
        trendStack.translatesAutoresizingMaskIntoConstraints = false
        trafficTrendChartView.leadingAnchor.constraint(equalTo: trendStack.leadingAnchor).isActive = true
        trafficTrendChartView.trailingAnchor.constraint(equalTo: trendStack.trailingAnchor).isActive = true
        trafficTrendChartView.heightAnchor.constraint(greaterThanOrEqualToConstant: 105).isActive = true

        let trafficTrendCard = homeCard(
            title: "流量趋势",
            iconName: "chart.xyaxis.line",
            titleAccessoryView: trafficPeriodControl,
            views: [trendStack]
        )

        // Card 6: 实时速度
        uploadValueLabel.font = .systemFont(ofSize: 14, weight: .bold)
        uploadValueLabel.textColor = MD3.primary
        let uploadTag = NSTextField(labelWithString: "上传")
        uploadTag.font = .systemFont(ofSize: 11, weight: .medium)
        uploadTag.textColor = MD3.onSurfaceVariant
        let uploadHeader = NSStackView(views: [uploadTag, uploadValueLabel])
        uploadHeader.orientation = .horizontal
        uploadHeader.spacing = 6
        uploadHeader.alignment = .centerY

        uploadWaveChartView.translatesAutoresizingMaskIntoConstraints = false
        uploadWaveChartView.lineColor = MD3.primary
        uploadWaveChartView.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let uploadSub = NSStackView(views: [uploadHeader, uploadWaveChartView])
        uploadSub.orientation = .vertical
        uploadSub.alignment = .leading
        uploadSub.spacing = 2
        uploadSub.translatesAutoresizingMaskIntoConstraints = false
        uploadWaveChartView.leadingAnchor.constraint(equalTo: uploadSub.leadingAnchor).isActive = true
        uploadWaveChartView.trailingAnchor.constraint(equalTo: uploadSub.trailingAnchor).isActive = true

        downloadValueLabel.font = .systemFont(ofSize: 14, weight: .bold)
        downloadValueLabel.textColor = NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0)
        let downloadTag = NSTextField(labelWithString: "下载")
        downloadTag.font = .systemFont(ofSize: 11, weight: .medium)
        downloadTag.textColor = MD3.onSurfaceVariant
        let downloadHeader = NSStackView(views: [downloadTag, downloadValueLabel])
        downloadHeader.orientation = .horizontal
        downloadHeader.spacing = 6
        downloadHeader.alignment = .centerY

        downloadWaveChartView.translatesAutoresizingMaskIntoConstraints = false
        downloadWaveChartView.lineColor = NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0)
        downloadWaveChartView.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let downloadSub = NSStackView(views: [downloadHeader, downloadWaveChartView])
        downloadSub.orientation = .vertical
        downloadSub.alignment = .leading
        downloadSub.spacing = 2
        downloadSub.translatesAutoresizingMaskIntoConstraints = false
        downloadWaveChartView.leadingAnchor.constraint(equalTo: downloadSub.leadingAnchor).isActive = true
        downloadWaveChartView.trailingAnchor.constraint(equalTo: downloadSub.trailingAnchor).isActive = true

        let speedStack = NSStackView(views: [uploadSub, downloadSub])
        speedStack.orientation = .vertical
        speedStack.alignment = .leading
        speedStack.spacing = 8
        speedStack.translatesAutoresizingMaskIntoConstraints = false
        uploadSub.leadingAnchor.constraint(equalTo: speedStack.leadingAnchor).isActive = true
        uploadSub.trailingAnchor.constraint(equalTo: speedStack.trailingAnchor).isActive = true
        downloadSub.leadingAnchor.constraint(equalTo: speedStack.leadingAnchor).isActive = true
        downloadSub.trailingAnchor.constraint(equalTo: speedStack.trailingAnchor).isActive = true

        let realtimeSpeedCard = homeCard(
            title: "实时速度",
            iconName: "speedometer",
            views: [speedStack]
        )

        // Card 7: 活动连接与内存
        connectionsValueLabel.font = .systemFont(ofSize: 26, weight: .bold)
        connectionsValueLabel.textColor = MD3.primary
        let connUnit = NSTextField(labelWithString: "个活动连接")
        connUnit.font = .systemFont(ofSize: 12)
        connUnit.textColor = MD3.onSurfaceVariant
        let connRow = NSStackView(views: [connectionsValueLabel, connUnit])
        connRow.orientation = .horizontal
        connRow.alignment = .lastBaseline
        connRow.spacing = 6

        let memTitle = NSTextField(labelWithString: "内存占用")
        memTitle.font = .systemFont(ofSize: 12, weight: .medium)
        memTitle.textColor = MD3.onSurfaceVariant

        memoryValueLabel.font = .systemFont(ofSize: 13, weight: .bold)
        memoryValueLabel.textColor = MD3.onSurface

        let memInfoCol = NSStackView(views: [memTitle, memoryValueLabel])
        memInfoCol.orientation = .vertical
        memInfoCol.alignment = .leading
        memInfoCol.spacing = 2

        memoryRingView.translatesAutoresizingMaskIntoConstraints = false
        memoryRingView.heightAnchor.constraint(equalToConstant: 28).isActive = true
        memoryRingView.widthAnchor.constraint(equalToConstant: 68).isActive = true

        let memRow = NSStackView(views: [memInfoCol, memoryRingView])
        memRow.orientation = .horizontal
        memRow.alignment = .centerY
        memRow.spacing = 10

        let connAndMemStack = NSStackView(views: [connRow, memRow])
        connAndMemStack.orientation = .vertical
        connAndMemStack.alignment = .leading
        connAndMemStack.spacing = 16
        connAndMemStack.translatesAutoresizingMaskIntoConstraints = false

        equalizerBarsView.translatesAutoresizingMaskIntoConstraints = false
        equalizerBarsView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        equalizerBarsView.widthAnchor.constraint(equalToConstant: 54).isActive = true

        let activeConnectionsCard = homeCard(
            title: "活动连接与内存",
            iconName: "bolt.horizontal",
            titleAccessoryView: equalizerBarsView,
            views: [connAndMemStack]
        )

        // Card 8: 流量去向
        trafficDonutChartView.translatesAutoresizingMaskIntoConstraints = false
        trafficDonutChartView.widthAnchor.constraint(equalToConstant: 92).isActive = true
        trafficDonutChartView.heightAnchor.constraint(equalToConstant: 92).isActive = true

        func makeLegendRow(color: NSColor, label: NSTextField) -> NSStackView {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.backgroundColor = color.cgColor
            dot.layer?.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            label.font = .systemFont(ofSize: 11)
            label.textColor = MD3.onSurfaceVariant
            let row = NSStackView(views: [dot, label])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            return row
        }

        let proxyRow = makeLegendRow(color: MD3.primary, label: donutProxyLabel)
        let directRow = makeLegendRow(color: NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0), label: donutDirectLabel)
        let otherRow = makeLegendRow(color: MD3.outlineVariant, label: donutOtherLabel)

        let legendStack = NSStackView(views: [proxyRow, directRow, otherRow])
        legendStack.orientation = .vertical
        legendStack.alignment = .leading
        legendStack.spacing = 6

        let donutContentStack = NSStackView(views: [trafficDonutChartView, legendStack])
        donutContentStack.orientation = .horizontal
        donutContentStack.alignment = .centerY
        donutContentStack.spacing = 12
        donutContentStack.translatesAutoresizingMaskIntoConstraints = false

        let trafficDestinationCard = homeCard(
            title: "流量去向",
            iconName: "chart.pie",
            views: [donutContentStack]
        )

        // Card 9: 最近运行状态
        recentStatusPill.font = .systemFont(ofSize: 10, weight: .semibold)
        recentStatusPill.textColor = MD3.onSuccessContainer
        recentStatusPill.backgroundColor = MD3.successContainer
        recentStatusPill.drawsBackground = true
        recentStatusPill.isBezeled = false
        recentStatusPill.alignment = .center
        recentStatusPill.wantsLayer = true
        recentStatusPill.layer?.cornerRadius = 8
        recentStatusPill.layer?.masksToBounds = true
        recentStatusPill.translatesAutoresizingMaskIntoConstraints = false
        recentStatusPill.heightAnchor.constraint(equalToConstant: 18).isActive = true
        recentStatusPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true

        recentStatusStack.orientation = .vertical
        recentStatusStack.alignment = .leading
        recentStatusStack.spacing = 8
        recentStatusStack.translatesAutoresizingMaskIntoConstraints = false

        RecentStatusTracker.shared.onItemsUpdated = { [weak self] items in
            self?.refreshRecentStatusTimeline(items: items)
        }
        refreshRecentStatusTimeline(items: RecentStatusTracker.shared.items)

        let recentStatusCard = homeCard(
            title: "最近运行状态",
            iconName: "clock.arrow.circlepath",
            titleAccessoryView: recentStatusPill,
            views: [recentStatusStack]
        )

        // Assembled 4-2-3 Grid
        let grid = HomeDashboardLayout.dashboardGrid(
            systemProxyCard: serviceCard,
            tunCard: tunCard,
            outboundCard: outboundCard,
            currentNodeCard: currentNodeCard,
            trafficTrendCard: trafficTrendCard,
            realtimeSpeedCard: realtimeSpeedCard,
            activeConnectionsCard: activeConnectionsCard,
            trafficDestinationCard: trafficDestinationCard,
            recentStatusCard: recentStatusCard
        )

        // Embed inside scrollable document view
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let doc = HomeDocumentView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(headerRow)
        doc.addSubview(grid)
        scroll.documentView = doc

        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            headerRow.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 20),
            headerRow.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -20),
            headerRow.topAnchor.constraint(equalTo: doc.topAnchor, constant: 18),

            grid.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 14),
            grid.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -20)
        ])

        registerThemeObserver { [weak self, weak title, weak subtitle, weak wifiImageView, weak ipImageView] in
            guard let self = self else { return }
            title?.textColor = MD3.onSurface
            subtitle?.textColor = MD3.onSurfaceVariant
            self.currentNodeNameLabel.textColor = MD3.primary
            self.currentNodeDelayLabel.textColor = MD3.latencyTextColor(self.currentNodeDelayLabel.stringValue)
            self.trafficStatsValueLabel.textColor = MD3.primary
            self.trafficStatsDetailLabel.textColor = MD3.onSurfaceVariant
            self.trafficUploadStatLabel.textColor = MD3.primary
            self.uploadValueLabel.textColor = MD3.primary
            self.uploadWaveChartView.lineColor = MD3.primary
            self.connectionsValueLabel.textColor = MD3.primary
            self.connectionsDetailLabel.textColor = MD3.onSurfaceVariant
            self.memoryValueLabel.textColor = MD3.onSurface
            wifiImageView?.contentTintColor = MD3.primary
            ipImageView?.contentTintColor = MD3.primary
            self.wifiStatusLabel.textColor = MD3.onSurface
            self.externalIPLabel.textColor = MD3.onSurface
            self.externalIPRefreshButton.contentTintColor = MD3.onSurfaceVariant
            self.recentStatusPill.textColor = MD3.onSuccessContainer
            self.recentStatusPill.backgroundColor = MD3.successContainer
        }

        updateTrafficLabels()
        syncProxyPreferenceControls()
        refreshHomeFeatureStatus()

        return view
    }

    func homeActionButton(title: String, action: Selector, style: MD3Button.ButtonStyle = .filled) -> MD3Button {
        let button = MD3Button()
        button.title = title
        button.style = style
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    func refreshHomeFeatureStatus() {
        apiStatusLabel.stringValue = isProxyRuntimeRunning()
            ? "运行态 API：\(TungBoxConfig.clashAPIListen)"
            : "运行态 API：服务未启动"
        let latestSubscription = subscriptions.compactMap(\.updatedAt).max().map { DateFormatter.short.string(from: $0) } ?? "尚未刷新"
        let intervalText = SubscriptionRefreshSchedule.statusText(minutes: SubscriptionRefreshSchedule.minutes())
        subscriptionAutoStatusLabel.stringValue = "订阅自动刷新：\(intervalText)；上次刷新 \(latestSubscription)"
        coreStatusLabel.stringValue = "sing-box Core：\(detectedCoreVersion)"
        logStatusLabel.stringValue = "日志：\(logs.string.components(separatedBy: .newlines).filter { !$0.isEmpty }.count) 行"
        tunRuntimeStatusLabel.stringValue = isTunEnabled
            ? (TunServiceManager.hasInstalledServiceFiles ? "TUN 服务：已安装，随代理开启" : "TUN 服务：不可用，请重新安装")
            : "TUN 权限：未启用"
    }

    func detailsTextConfig(_ label: NSTextField) {
        label.textColor = MD3.onSurfaceVariant
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
    }

    func homeCard(
        title: String,
        iconName: String? = nil,
        subtitle: String? = nil,
        titleInlineView: NSView? = nil,
        titleAccessoryView: NSView? = nil,
        views: [NSView]
    ) -> NSView {
        let card = HomeDashboardLayout.card(
            title: title,
            iconName: iconName,
            subtitle: subtitle,
            titleInlineView: titleInlineView,
            titleAccessoryView: titleAccessoryView,
            views: views
        )
        registerThemeObserver { [weak titleLabel = card.title] in
            titleLabel?.textColor = MD3.onSurface
        }
        return card.view
    }

    func getTodayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    func recordTraffic(upload: Int, download: Int) {
        let today = getTodayKey()
        var history = UserDefaults.standard.dictionary(forKey: "tungbox_traffic_history") as? [String: [String: Int]] ?? [:]
        var todayTraffic = history[today] ?? ["upload": 0, "download": 0]
        todayTraffic["upload"] = SaturatingArithmetic.add(todayTraffic["upload"] ?? 0, upload)
        todayTraffic["download"] = SaturatingArithmetic.add(todayTraffic["download"] ?? 0, download)
        history[today] = todayTraffic
        UserDefaults.standard.set(history, forKey: "tungbox_traffic_history")
    }

    func getTrafficSum(days: Int) -> (upload: Int, download: Int) {
        let history = UserDefaults.standard.dictionary(forKey: "tungbox_traffic_history") as? [String: [String: Int]] ?? [:]
        var totalUp = 0
        var totalDown = 0
        
        let calendar = Calendar.current
        let now = Date()
        
        for i in 0..<days {
            if let date = calendar.date(byAdding: .day, value: -i, to: now) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let key = formatter.string(from: date)
                if let dayData = history[key] {
                    totalUp = SaturatingArithmetic.add(totalUp, dayData["upload"] ?? 0)
                    totalDown = SaturatingArithmetic.add(totalDown, dayData["download"] ?? 0)
                }
            }
        }
        return (totalUp, totalDown)
    }

    func updateTrafficLabels() {
        let up: Int
        let down: Int
        let period: TrafficPeriod
        switch trafficPeriodControl.selectedSegment {
        case 0: // 今日
            let sum = getTrafficSum(days: 1)
            up = sum.upload
            down = sum.download
            period = .today
        case 1: // 近7天
            let sum = getTrafficSum(days: 7)
            up = sum.upload
            down = sum.download
            period = .last7Days
        case 2: // 近30天
            let sum = getTrafficSum(days: 30)
            up = sum.upload
            down = sum.download
            period = .last30Days
        default:
            up = totalUploadBytes
            down = totalDownloadBytes
            period = .today
        }
        
        let total = SaturatingArithmetic.add(up, down)
        trafficStatsValueLabel.stringValue = formatBytes(total)
        trafficStatsDetailLabel.stringValue = "上传: \(formatBytes(up))   下载: \(formatBytes(down))"
        trafficUploadStatLabel.stringValue = "上传: \(formatBytes(up))"
        trafficDownloadStatLabel.stringValue = "下载: \(formatBytes(down))"
        trafficTrendChartView.data = TrafficTrendStore.trendData(for: period, totalUploadBytes: Int64(up), totalDownloadBytes: Int64(down))
        trafficDonutChartView.centerTotalText = formatBytes(total)
    }

    @objc func trafficPeriodChanged() {
        updateTrafficLabels()
    }

    func refreshHomeProfilePopup() {
        homeProfileSelectorPopup.removeAllItems()
        if subscriptions.isEmpty {
            let name = (selectedIndex.flatMap { profiles.indices.contains($0) ? profiles[$0].name : nil }) ?? profiles.first?.name ?? "默认配置"
            homeProfileSelectorPopup.addItem(withTitle: name)
        } else {
            for sub in subscriptions {
                let flag = CountryFlagHelper.flag(for: sub.name)
                let title = sub.name.isEmpty ? "未命名订阅" : sub.name
                homeProfileSelectorPopup.addItem(withTitle: "\(flag) \(title)")
            }
            let sel = selectedSubscriptionIndex ?? 0
            if sel < homeProfileSelectorPopup.numberOfItems {
                homeProfileSelectorPopup.selectItem(at: sel)
            }
        }
    }

    @objc func homeProfilePopupChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0 else { return }
        if subscriptions.indices.contains(idx) {
            selectSubscription(at: idx)
        } else if profiles.indices.contains(idx) {
            selectProfile(at: idx)
        }
    }

    func refreshExternalIP(force: Bool = false) {
        externalIPLabel.stringValue = "查询中…"
        Task {
            let ip = await ExternalIPService.shared.getExternalIP(force: force)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.externalIPLabel.stringValue = ip ?? "未获取到公网 IP"
            }
        }
    }

    @objc func refreshExternalIPClicked(_ sender: Any) {
        refreshExternalIP(force: true)
    }

    func refreshRecentStatusTimeline(items: [RecentStatusTracker.Item]) {
        recentStatusStack.arrangedSubviews.forEach {
            recentStatusStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for item in items.prefix(4) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8

            let timeLabel = NSTextField(labelWithString: RecentStatusTracker.timeString(from: item.timestamp))
            timeLabel.font = .systemFont(ofSize: 10, weight: .regular)
            timeLabel.textColor = MD3.onSurfaceVariant.withAlphaComponent(0.65)

            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3
            let dotColor: NSColor
            switch item.level {
            case .success: dotColor = MD3.success
            case .info: dotColor = MD3.primary
            case .warning: dotColor = MD3.warning
            case .neutral: dotColor = MD3.outlineVariant
            }
            dot.layer?.backgroundColor = dotColor.cgColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 6).isActive = true

            let msgLabel = NSTextField(labelWithString: item.message)
            msgLabel.font = .systemFont(ofSize: 11, weight: .medium)
            msgLabel.textColor = MD3.onSurface
            msgLabel.lineBreakMode = .byTruncatingTail
            msgLabel.maximumNumberOfLines = 1

            row.addArrangedSubview(timeLabel)
            row.addArrangedSubview(dot)
            row.addArrangedSubview(msgLabel)

            recentStatusStack.addArrangedSubview(row)
        }
    }

    func updateRunningStats() {
        guard !isUpdatingRunningStats else { return }
        guard isProxyRuntimeRunning(), let pid = currentProxyPID() else {
            // Tolerate transient unavailability (e.g. the daemon hot-reloading
            // sing-box for a node switch) so a single blip doesn't permanently
            // kill the stats panel. Only stop after several consecutive misses.
            runningStatsMissCount += 1
            if runningStatsMissCount >= 3 {
                stopStatsTimer()
            }
            return
        }
        runningStatsMissCount = 0
        isUpdatingRunningStats = true

        // TUN 守护进程是独立 sing-box 进程，clash_api 在 9091。要算 TUN 流量
        // 必须把那个端口也拉上，否则 TUN-only 时 delta 永远是 0、流量统计为 0。
        let extraPorts: [Int] = isTunRuntimeRunning() ? [TungBoxConfig.tunDaemonClashPort] : []
        let allPorts: [Int] = [9090] + extraPorts
        let proxyAPIPort = delayAPIPort()
        let selectorAPIPorts = activeSelectorAPIPorts()
        let statsTransitionID = runtimeTransitionID
        let statsSelectionID = selectorSelectionID
        let prevTotals = prevTrafficTotals
        let elapsedSinceLast = max(Date().timeIntervalSince(connectionRefreshTime), 0.5)
        Task { [self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.isUpdatingRunningStats = false
                }
            }
            let apiConnections = try? await ClashAPI.connectionsFromAll(extraPorts: extraPorts)
            let totals = (try? await ClashAPI.trafficTotals(ports: allPorts)) ?? [:]
            var proxiesByPort: [Int: [String: Any]] = [:]
            for port in selectorAPIPorts {
                if let proxies = try? await ClashAPI.proxies(port: port) {
                    proxiesByPort[port] = proxies
                }
            }
            let proxiesObj = proxiesByPort[proxyAPIPort ?? 9090]
            
            let connectionCount = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                DispatchQueue.global(qos: .background).async {
                    if let apiConnections {
                        continuation.resume(returning: apiConnections.count)
                    } else {
                        let lsof = self.runProcessAndGetOutput("/usr/sbin/lsof", args: ["-i", "-a", "-p", "\(pid)", "-n", "-P"])
                        let lines = lsof.components(separatedBy: .newlines)
                        let establishedCount = lines.filter { $0.contains("ESTABLISHED") }.count
                        continuation.resume(returning: establishedCount)
                    }
                }
            }
            
            let memBytes = ProcessResourceProbe.currentProcessMemoryBytes()
            let memFormatted = ProcessResourceProbe.formattedMemory(bytes: memBytes)
            let memRatio = ProcessResourceProbe.memoryRatio(bytes: memBytes)
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                guard self.isProxyRuntimeRunning(), self.runtimeTransitionID == statsTransitionID, self.selectorSelectionID == statsSelectionID else { return }

                if let apiConnections {
                    self.applyConnections(apiConnections, detail: "实时刷新")
                }

                // 流量累计走 totals 路径（包含 UDP/IPv6/已关闭短连接），同时算出
                // 这次 ↔ 上次的 delta 用作实时速率显示。
                if !totals.isEmpty {
                    var deltaUp: Int64 = 0, deltaDown: Int64 = 0
                    for (port, curr) in totals {
                        if let p = prevTotals[port], curr.upload >= p.upload, curr.download >= p.download {
                            deltaUp = SaturatingArithmetic.add(deltaUp, SaturatingArithmetic.nonnegativeDifference(curr.upload, p.upload))
                            deltaDown = SaturatingArithmetic.add(deltaDown, SaturatingArithmetic.nonnegativeDifference(curr.download, p.download))
                        }
                    }
                    self.accumulateTrafficFromTotals(totals)
                    if !prevTotals.isEmpty {
                        let upSpeed = SaturatingArithmetic.rate(bytes: deltaUp, elapsed: elapsedSinceLast)
                        let downSpeed = SaturatingArithmetic.rate(bytes: deltaDown, elapsed: elapsedSinceLast)
                        self.updateRealtimeSpeed(uploadSpeed: upSpeed, downloadSpeed: downSpeed)
                    }
                }

                // Sync active node from Clash API. Delay values are updated only by
                // the explicit automatic/all-node delay test, not by this poll.
                self.lastProxiesObj = proxiesObj
                for port in selectorAPIPorts {
                    guard let portProxies = proxiesByPort[port] else { continue }
                    let active = self.resolveActiveOutbound(proxiesObj: portProxies)
                    let transition = Self.automaticSelectionTransition(
                        previous: self.lastAutomaticNodeByAPIPort[port],
                        currentName: active.name,
                        isAutomatic: active.isAuto
                    )
                    self.lastAutomaticNodeByAPIPort[port] = transition.next
                    if transition.didChange {
                        self.appendLog("[节点] 自动选择已切换到 \(active.name)，正在断开旧节点连接\n")
                        RecentStatusTracker.shared.record("节点切换至 \(active.name)", level: .info)
                        Task { _ = try? await ClashAPI.closeConnections(port: port) }
                    }
                }
                if let proxies = proxiesObj?["proxies"] as? [String: Any] {
                    var changed = false
                    for index in self.nodeGroups.indices {
                        if let group = proxies[self.nodeGroups[index].tag] as? [String: Any],
                           let now = group["now"] as? String, !now.isEmpty,
                           self.nodeGroups[index].current != now {
                            self.nodeGroups[index].current = now
                            changed = true
                        }
                    }
                    if changed { self.refreshNodeGroupsView() }
                }
                let activeNodeInfo = self.resolveActiveOutbound(proxiesObj: proxiesObj)
                let nodeName = activeNodeInfo.name.isEmpty ? "（选择中…）" : activeNodeInfo.name
                let flag = CountryFlagHelper.flag(for: nodeName)
                self.currentNodeNameLabel.stringValue = "\(flag) \(nodeName)"
                self.currentNodeAutoBadge.isHidden = !activeNodeInfo.isAuto
                let activeDelay = self.nodes.first(where: { $0.tag == activeNodeInfo.name })?.delay ?? "—"
                self.currentNodeDelayLabel.stringValue = activeDelay == "未测试" ? "—" : activeDelay
                self.currentNodeDelayLabel.textColor = MD3.latencyTextColor(self.currentNodeDelayLabel.stringValue)

                // 1. Update connections card and memory
                self.updateConnectionsCard(value: "\(connectionCount)", detail: "内存占用: \(memFormatted)")
                self.memoryValueLabel.stringValue = memFormatted
                self.memoryRingView.ratio = memRatio

                if let conns = apiConnections {
                    var proxyCount = 0
                    var directCount = 0
                    var otherCount = 0
                    for c in conns {
                        let ob = c.outbound.lowercased()
                        if ob.contains("direct") {
                            directCount += 1
                        } else if ob.contains("reject") || ob.contains("block") {
                            otherCount += 1
                        } else {
                            proxyCount += 1
                        }
                    }
                    let totalC = max(Double(proxyCount + directCount + otherCount), 1.0)
                    let pRatio = Double(proxyCount) / totalC
                    let dRatio = Double(directCount) / totalC
                    let oRatio = Double(otherCount) / totalC
                    self.trafficDonutChartView.proxyRatio = pRatio
                    self.trafficDonutChartView.directRatio = dRatio
                    self.trafficDonutChartView.otherRatio = oRatio
                    self.donutProxyLabel.stringValue = "代理 \(proxyCount) (\(Int(pRatio * 100))%)"
                    self.donutDirectLabel.stringValue = "直连 \(directCount) (\(Int(dRatio * 100))%)"
                    self.donutOtherLabel.stringValue = "其他 \(otherCount) (\(Int(oRatio * 100))%)"
                }

                if self.isProxyRuntimeRunning() {
                    self.recentStatusPill.stringValue = "运行正常"
                    self.recentStatusPill.textColor = MD3.onSuccessContainer
                    self.recentStatusPill.backgroundColor = MD3.successContainer
                } else {
                    self.recentStatusPill.stringValue = "服务未启动"
                    self.recentStatusPill.textColor = MD3.onSurfaceVariant
                    self.recentStatusPill.backgroundColor = MD3.surfaceContainer
                }

                if apiConnections == nil {
                    self.uploadValueLabel.stringValue = "—"
                    self.downloadValueLabel.stringValue = "—"
                    self.currentUploadSpeed = 0
                    self.currentDownloadSpeed = 0
                    self.refreshTrayIcon()
                }
            }
        }
    }
    
    nonisolated func runProcessAndGetOutput(_ binary: String, args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    func updateConnectionsCard(value: String, detail: String) {
        connectionsValueLabel.stringValue = value
        connectionsDetailLabel.stringValue = detail
    }

    func formatBytes(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 {
            return "\(Int(value)) \(units[index])"
        }
        return String(format: "%.1f %@", value, units[index])
    }

    // System-proxy switch — independent of TUN; both can be on together.
    @objc func switchToggled(_ sender: MD3Switch) {
        guard !runtimeCoordinator.state.isTerminating else { return }
        isSystemProxyEnabled = sender.isOn
        UserDefaults.standard.set(isSystemProxyEnabled, forKey: "systemProxyEnabled")
        beginFeatureTransition(systemProxy: sender.isOn ? .starting : .stopping)
        syncProxyPreferenceControls()
        refreshStatus()   // show 启动中/关闭中 + spinner right away
        RecentStatusTracker.shared.record(sender.isOn ? "系统代理已开启" : "系统代理已关闭", level: sender.isOn ? .success : .info)
        showToast(sender.isOn ? "系统代理已开启" : "系统代理已关闭", style: sender.isOn ? .success : .info)
        reconcileRuntime(reason: sender.isOn ? "开启系统代理" : "关闭系统代理")
    }

    // TUN switch — independent of system proxy.
    @objc func tunSwitchToggled(_ sender: MD3Switch) {
        setCaptureMode(tunEnabled: sender.isOn, source: "首页")
    }

    /// Toggle the TUN switch (shared by the home switch, tray, and settings). System
    /// proxy state is untouched; reconcileRuntime() converges the runtime.
    func setCaptureMode(tunEnabled: Bool, source: String) {
        guard !runtimeCoordinator.state.isTerminating else { return }
        tunCaptureIntentID = UUID()
        let intent = tunCaptureIntentID
        if tunEnabled {
            let storeCopy = store
            beginFeatureTransition(tun: .starting)
            syncProxyPreferenceControls()
            Task.detached { [weak self] in
                let status = TunServiceManager.status(store: storeCopy)
                let route = self?.runCommand("/sbin/route", args: ["-n", "get", "default"]) ?? ""
                let virtualRoute = route.split(separator: "\n").contains { $0.contains("interface:") && $0.contains("utun") }
                let blockedRoute = virtualRoute && TunServiceManager.defaultNetworkInterface() == nil
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.tunCaptureIntentID == intent, !self.isTunEnabled else { return }
                    guard status.isUsable else {
                        self.clearFeatureTransitions()
                        self.syncProxyPreferenceControls()
                        self.showToast("请先安装 TUN 服务")
                        self.showError(NSError.user("TUN 服务不可用：\(status.displayText)。请到 设置 > TUN 设置处理。"))
                        return
                    }
                    do {
                        if blockedRoute { throw NSError.user("系统默认路由位于 TUN/VPN，且没有可用物理出口。请检查网络后重试。") }
                        self.commitCaptureMode(tunEnabled: true, source: source)
                    } catch {
                        self.clearFeatureTransitions()
                        self.syncProxyPreferenceControls()
                        self.showToast("TUN 已被保护拦截")
                        self.showError(error)
                    }
                }
            }
            return
        }
        commitCaptureMode(tunEnabled: false, source: source)
    }

    private func commitCaptureMode(tunEnabled: Bool, source: String) {
        isTunEnabled = tunEnabled
        UserDefaults.standard.set(isTunEnabled, forKey: "tunEnabled")
        if !tunEnabled {
            // Remove the request before scheduling the async runtime converge.
            // This closes the race where a rapid off/on sequence leaves the
            // daemon with an old request after the UI switch is already off.
            stopTunRequestHeartbeat()
            try? TunServiceManager.disable(store: store)
        }
        beginFeatureTransition(tun: tunEnabled ? .starting : .stopping)
        syncProxyPreferenceControls()
        refreshStatus()   // show 启动中/关闭中 + spinner right away
        RecentStatusTracker.shared.record(tunEnabled ? "正在启动 TUN" : "TUN 模式已关闭", level: .info)
        appendLog("[\(source)] \(tunEnabled ? "正在启动 TUN" : "TUN 模式已关闭")\n")
        showToast(tunEnabled ? "正在启动 TUN" : "TUN 模式已关闭", style: .info)
        reconcileRuntime(reason: tunEnabled ? "开启 TUN" : "关闭 TUN")
    }

    @objc func saveClicked() {
        do {
            try saveCurrent()
            appendLog("[TungBox] 已保存\n")
            showToast("配置已保存", style: .success)
        } catch {
            showError(error)
        }
    }

    func configureCaptureRadio(_ radio: MD3RadioButton, tag: Int, action: Selector) {
        radio.tag = tag
        radio.target = self
        radio.action = action
    }

    private func makeOptionWithHint(radio: MD3RadioButton, hint: String) -> NSStackView {
        let hintLabel = NSTextField(labelWithString: hint)
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = MD3.onSurfaceVariant
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.maximumNumberOfLines = 1
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak hintLabel] in
            hintLabel?.textColor = MD3.onSurfaceVariant
        }
        
        let hintContainer = NSView()
        hintContainer.translatesAutoresizingMaskIntoConstraints = false
        hintContainer.addSubview(hintLabel)
        
        NSLayoutConstraint.activate([
            hintLabel.leadingAnchor.constraint(equalTo: hintContainer.leadingAnchor, constant: 28),
            hintLabel.trailingAnchor.constraint(equalTo: hintContainer.trailingAnchor),
            hintLabel.topAnchor.constraint(equalTo: hintContainer.topAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: hintContainer.bottomAnchor)
        ])
        
        let stack = NSStackView(views: [radio, hintContainer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        hintContainer.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        hintContainer.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        
        return stack
    }
}
