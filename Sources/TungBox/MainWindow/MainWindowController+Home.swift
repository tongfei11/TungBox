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
        subtitle.font = .systemFont(ofSize: 13, weight: .regular)
        subtitle.textColor = MD3.onSurfaceVariant
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let titleCol = NSStackView(views: [title, subtitle])
        titleCol.orientation = .vertical
        titleCol.alignment = .leading
        titleCol.spacing = 3

        func makeHeaderDivider() -> NSView {
            let div = NSView()
            div.wantsLayer = true
            div.layer?.backgroundColor = (MD3.isDark
                ? MD3.outlineVariant.withAlphaComponent(0.35)
                : MD3.outline.withAlphaComponent(0.3)).cgColor
            div.translatesAutoresizingMaskIntoConstraints = false
            div.widthAnchor.constraint(equalToConstant: 1).isActive = true
            div.heightAnchor.constraint(equalToConstant: 13).isActive = true
            return div
        }

        // Section 1: Wi-Fi status
        let wifiImageView = NSImageView()
        if let wifiIcon = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil) {
            wifiIcon.isTemplate = true
            wifiImageView.image = wifiIcon
        }
        wifiImageView.contentTintColor = MD3.primary
        wifiImageView.translatesAutoresizingMaskIntoConstraints = false
        wifiImageView.widthAnchor.constraint(equalToConstant: 13).isActive = true
        wifiImageView.heightAnchor.constraint(equalToConstant: 13).isActive = true

        wifiStatusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        wifiStatusLabel.textColor = MD3.onSurface
        wifiStatusLabel.stringValue = NetworkReachability.shared.currentType.rawValue

        NetworkReachability.shared.onInterfaceChanged = { [weak self] type in
            self?.wifiStatusLabel.stringValue = type.rawValue
        }

        let wifiStack = NSStackView(views: [wifiImageView, wifiStatusLabel])
        wifiStack.orientation = .horizontal
        wifiStack.alignment = .centerY
        wifiStack.spacing = 5

        // Section 2: Profile / Subscription Popup
        let profileTitleLabel = NSTextField(labelWithString: "配置")
        profileTitleLabel.font = .systemFont(ofSize: 11)
        profileTitleLabel.textColor = MD3.onSurfaceVariant

        homeProfileSelectorPopup.isBorderless = true
        homeProfileSelectorPopup.font = .systemFont(ofSize: 11, weight: .medium)
        homeProfileSelectorPopup.translatesAutoresizingMaskIntoConstraints = false
        homeProfileSelectorPopup.target = self
        homeProfileSelectorPopup.action = #selector(homeProfilePopupChanged(_:))
        refreshHomeProfilePopup()

        let profileStack = NSStackView(views: [profileTitleLabel, homeProfileSelectorPopup])
        profileStack.orientation = .horizontal
        profileStack.alignment = .centerY
        profileStack.spacing = 4

        // Section 3: External IP
        let ipTitleLabel = NSTextField(labelWithString: "外部 IP")
        ipTitleLabel.font = .systemFont(ofSize: 11)
        ipTitleLabel.textColor = MD3.onSurfaceVariant

        externalIPLabel.font = .systemFont(ofSize: 11, weight: .medium)
        externalIPLabel.textColor = MD3.onSurface

        let ipStack = NSStackView(views: [ipTitleLabel, externalIPLabel])
        ipStack.orientation = .horizontal
        ipStack.alignment = .centerY
        ipStack.spacing = 4

        // Section 4: External IP Reload
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
        externalIPRefreshButton.widthAnchor.constraint(equalToConstant: 13).isActive = true
        externalIPRefreshButton.heightAnchor.constraint(equalToConstant: 13).isActive = true

        refreshExternalIP(force: false)

        let div1 = makeHeaderDivider()
        let div2 = makeHeaderDivider()
        let div3 = makeHeaderDivider()

        let pillStack = NSStackView(views: [wifiStack, div1, profileStack, div2, ipStack, div3, externalIPRefreshButton])
        pillStack.orientation = .horizontal
        pillStack.alignment = .centerY
        pillStack.spacing = 9
        pillStack.translatesAutoresizingMaskIntoConstraints = false

        let unifiedHeaderPill = MD3Panel()
        unifiedHeaderPill.type = .filled
        unifiedHeaderPill.wantsLayer = true
        unifiedHeaderPill.layer?.cornerRadius = 15.5
        unifiedHeaderPill.layer?.masksToBounds = true
        unifiedHeaderPill.translatesAutoresizingMaskIntoConstraints = false
        unifiedHeaderPill.addSubview(pillStack)

        NSLayoutConstraint.activate([
            unifiedHeaderPill.heightAnchor.constraint(equalToConstant: 31),
            pillStack.leadingAnchor.constraint(equalTo: unifiedHeaderPill.leadingAnchor, constant: 14),
            pillStack.trailingAnchor.constraint(equalTo: unifiedHeaderPill.trailingAnchor, constant: -14),
            pillStack.centerYAnchor.constraint(equalTo: unifiedHeaderPill.centerYAnchor)
        ])

        let headerRow = NSView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(titleCol)
        headerRow.addSubview(unifiedHeaderPill)

        NSLayoutConstraint.activate([
            titleCol.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            titleCol.topAnchor.constraint(equalTo: headerRow.topAnchor),
            titleCol.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor),

            unifiedHeaderPill.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
            unifiedHeaderPill.centerYAnchor.constraint(equalTo: title.centerYAnchor)
        ])

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

        let serviceCard = homeCard(title: "系统代理", iconName: "display", views: [systemProxyRow])

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

        let tunCard = homeCard(title: "TUN 模式", iconName: "network.badge.shield.half.filled", views: [tunControlRow])

        // Card 3: 出站模式
        modeControl.items = ["直接连接", "全局代理", "规则判定"]
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.selectedSegment = 2
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let outboundCard = homeCard(title: "出站模式", iconName: "arrow.triangle.swap", views: [modeControl])

        // Card 4: 当前节点
        currentNodeNameLabel.font = .systemFont(ofSize: 17, weight: .bold)
        currentNodeNameLabel.textColor = MD3.onSurface
        currentNodeNameLabel.lineBreakMode = .byTruncatingTail
        currentNodeNameLabel.maximumNumberOfLines = 1
        currentNodeNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        currentNodeNameLabel.translatesAutoresizingMaskIntoConstraints = false

        currentNodeAutoBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        currentNodeAutoBadge.textColor = MD3.onSuccessContainer
        currentNodeAutoBadge.backgroundColor = MD3.successContainer
        currentNodeAutoBadge.drawsBackground = true
        currentNodeAutoBadge.isBezeled = false
        currentNodeAutoBadge.alignment = .center
        currentNodeAutoBadge.wantsLayer = true
        currentNodeAutoBadge.layer?.cornerRadius = 11
        currentNodeAutoBadge.layer?.masksToBounds = true
        currentNodeAutoBadge.horizontalPadding = 8
        currentNodeAutoBadge.translatesAutoresizingMaskIntoConstraints = false
        currentNodeAutoBadge.isHidden = true
        currentNodeAutoBadge.heightAnchor.constraint(equalToConstant: 22).isActive = true
        currentNodeAutoBadge.setContentHuggingPriority(.required, for: .horizontal)
        currentNodeAutoBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        currentNodeDelayLabel.font = .systemFont(ofSize: 14, weight: .bold)
        currentNodeDelayLabel.textColor = MD3.success
        currentNodeDelayLabel.lineBreakMode = .byClipping
        currentNodeDelayLabel.maximumNumberOfLines = 1
        currentNodeDelayLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        currentNodeDelayLabel.setContentHuggingPriority(.required, for: .horizontal)
        currentNodeDelayLabel.translatesAutoresizingMaskIntoConstraints = false

        let nodeSpacer = NSView()
        nodeSpacer.translatesAutoresizingMaskIntoConstraints = false
        nodeSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let nodeRow = NSStackView(views: [currentNodeNameLabel, nodeSpacer, currentNodeDelayLabel])
        nodeRow.orientation = .horizontal
        nodeRow.alignment = .centerY
        nodeRow.distribution = .fill
        nodeRow.translatesAutoresizingMaskIntoConstraints = false
        nodeRow.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let currentNodeCard = homeCard(
            title: "当前节点",
            iconName: "globe",
            titleAccessoryView: currentNodeAutoBadge,
            views: [nodeRow]
        )

        // Card 5: 流量趋势
        trafficPeriodControl.items = ["今日", "近 7 天", "近 30 天"]
        trafficPeriodControl.target = self
        trafficPeriodControl.action = #selector(trafficPeriodChanged)
        trafficPeriodControl.selectedSegment = 0
        trafficPeriodControl.translatesAutoresizingMaskIntoConstraints = false
        trafficPeriodControl.heightAnchor.constraint(equalToConstant: 24).isActive = true
        trafficPeriodControl.widthAnchor.constraint(equalToConstant: 185).isActive = true

        trafficTotalValueLabel.font = .systemFont(ofSize: 32, weight: .bold)
        trafficTotalValueLabel.textColor = MD3.onSurface
        trafficTotalValueLabel.translatesAutoresizingMaskIntoConstraints = false

        let trafficTotalDescLabel = NSTextField(labelWithString: "总流量")
        trafficTotalDescLabel.font = .systemFont(ofSize: 13, weight: .regular)
        trafficTotalDescLabel.textColor = MD3.onSurfaceVariant
        trafficTotalDescLabel.translatesAutoresizingMaskIntoConstraints = false

        let totalCol = NSStackView(views: [trafficTotalValueLabel, trafficTotalDescLabel])
        totalCol.orientation = .vertical
        totalCol.alignment = .leading
        totalCol.spacing = 2

        func makeTrendStatRow(dotColor: NSColor, title: String, valueLabel: NSTextField) -> (row: NSStackView, label: NSTextField, dot: NSView) {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.backgroundColor = dotColor.cgColor
            dot.layer?.cornerRadius = 3
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 6).isActive = true

            let tLabel = NSTextField(labelWithString: title)
            tLabel.font = .systemFont(ofSize: 13, weight: .regular)
            tLabel.textColor = MD3.onSurfaceVariant

            valueLabel.font = .systemFont(ofSize: 13, weight: .bold)
            valueLabel.textColor = MD3.onSurface

            let row = NSStackView(views: [dot, tLabel, valueLabel])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            return (row, tLabel, dot)
        }

        let upTrendInfo = makeTrendStatRow(dotColor: MD3.primary, title: "上传", valueLabel: trafficUploadStatLabel)
        let downTrendInfo = makeTrendStatRow(dotColor: MD3.downloadColor, title: "下载", valueLabel: trafficDownloadStatLabel)

        let trendStatsCol = NSStackView(views: [totalCol, upTrendInfo.row, downTrendInfo.row])
        trendStatsCol.orientation = .vertical
        trendStatsCol.alignment = .leading
        trendStatsCol.spacing = 10
        trendStatsCol.translatesAutoresizingMaskIntoConstraints = false
        trendStatsCol.widthAnchor.constraint(equalToConstant: 125).isActive = true

        trafficTrendChartView.translatesAutoresizingMaskIntoConstraints = false
        trafficTrendChartView.heightAnchor.constraint(greaterThanOrEqualToConstant: 115).isActive = true

        let trendContentRow = NSStackView(views: [trendStatsCol, trafficTrendChartView])
        trendContentRow.orientation = .horizontal
        trendContentRow.alignment = .centerY
        trendContentRow.spacing = 8
        trendContentRow.distribution = .fill
        trendContentRow.translatesAutoresizingMaskIntoConstraints = false
        trafficTrendChartView.trailingAnchor.constraint(equalTo: trendContentRow.trailingAnchor).isActive = true

        let trafficTrendCard = homeCard(
            title: "流量趋势",
            iconName: "chart.bar.xaxis",
            titleAccessoryView: trafficPeriodControl,
            views: [trendContentRow]
        )

        // Card 6: 实时速度
        let speedSublabel = NSTextField(labelWithString: "当前网络传输速度")
        speedSublabel.font = .systemFont(ofSize: 13, weight: .regular)
        speedSublabel.textColor = MD3.isDark ? MD3.onSurfaceVariant.withAlphaComponent(0.7) : MD3.onSurfaceVariant

        func makeSpeedSubcard(
            iconName: String,
            iconColor: NSColor,
            tagText: String,
            valueLabel: NSTextField,
            chartView: SpeedWaveChartView
        ) -> (subcard: NSView, tagLabel: NSTextField, iconView: NSImageView, iconContainer: NSView) {
            let subcard = NSView()
            subcard.wantsLayer = true
            subcard.layer?.cornerRadius = 10
            let initialBg = MD3.isDark
                ? MD3.surfaceContainer.mixed(with: MD3.surface, ratio: 0.25)
                : MD3.surfaceContainerHighest.mixed(with: MD3.surface, ratio: 0.35)
            subcard.layer?.backgroundColor = initialBg.cgColor
            subcard.translatesAutoresizingMaskIntoConstraints = false

            let iconContainer = NSView()
            iconContainer.wantsLayer = true
            iconContainer.layer?.cornerRadius = 10
            iconContainer.layer?.backgroundColor = iconColor.withAlphaComponent(0.18).cgColor
            iconContainer.translatesAutoresizingMaskIntoConstraints = false
            iconContainer.widthAnchor.constraint(equalToConstant: 20).isActive = true
            iconContainer.heightAnchor.constraint(equalToConstant: 20).isActive = true

            let iv = NSImageView()
            if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                img.isTemplate = true
                iv.image = img
            }
            iv.contentTintColor = iconColor
            iv.translatesAutoresizingMaskIntoConstraints = false
            iconContainer.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
                iv.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: 12),
                iv.heightAnchor.constraint(equalToConstant: 12)
            ])

            let tagLabel = NSTextField(labelWithString: tagText)
            tagLabel.font = .systemFont(ofSize: 13, weight: .regular)
            tagLabel.textColor = MD3.onSurface

            let tagHeader = NSStackView(views: [iconContainer, tagLabel])
            tagHeader.orientation = .horizontal
            tagHeader.alignment = .centerY
            tagHeader.spacing = 6

            valueLabel.font = .systemFont(ofSize: 17, weight: .bold)
            valueLabel.textColor = iconColor

            let textCol = NSStackView(views: [tagHeader, valueLabel])
            textCol.orientation = .vertical
            textCol.alignment = .leading
            textCol.spacing = 3
            textCol.translatesAutoresizingMaskIntoConstraints = false
            textCol.widthAnchor.constraint(equalToConstant: 95).isActive = true

            chartView.translatesAutoresizingMaskIntoConstraints = false

            let row = NSStackView(views: [textCol, chartView])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            row.distribution = .fill
            row.translatesAutoresizingMaskIntoConstraints = false
            subcard.addSubview(row)

            NSLayoutConstraint.activate([
                subcard.heightAnchor.constraint(equalToConstant: 64),
                row.leadingAnchor.constraint(equalTo: subcard.leadingAnchor, constant: 12),
                row.trailingAnchor.constraint(equalTo: subcard.trailingAnchor, constant: -8),
                row.topAnchor.constraint(equalTo: subcard.topAnchor, constant: 6),
                row.bottomAnchor.constraint(equalTo: subcard.bottomAnchor, constant: -6),
                chartView.heightAnchor.constraint(equalTo: row.heightAnchor)
            ])

            return (subcard, tagLabel, iv, iconContainer)
        }

        uploadWaveChartView.lineColor = MD3.primary
        downloadWaveChartView.lineColor = MD3.downloadColor

        let uploadSub = makeSpeedSubcard(iconName: "arrow.up", iconColor: MD3.primary, tagText: "上传", valueLabel: uploadValueLabel, chartView: uploadWaveChartView)
        let downloadSub = makeSpeedSubcard(iconName: "arrow.down", iconColor: MD3.downloadColor, tagText: "下载", valueLabel: downloadValueLabel, chartView: downloadWaveChartView)

        let speedStack = NSStackView(views: [uploadSub.subcard, downloadSub.subcard])
        speedStack.orientation = .vertical
        speedStack.alignment = .leading
        speedStack.spacing = 8
        speedStack.translatesAutoresizingMaskIntoConstraints = false
        uploadSub.subcard.leadingAnchor.constraint(equalTo: speedStack.leadingAnchor).isActive = true
        uploadSub.subcard.trailingAnchor.constraint(equalTo: speedStack.trailingAnchor).isActive = true
        downloadSub.subcard.leadingAnchor.constraint(equalTo: speedStack.leadingAnchor).isActive = true
        downloadSub.subcard.trailingAnchor.constraint(equalTo: speedStack.trailingAnchor).isActive = true

        let realtimeSpeedCard = homeCard(
            title: "实时速度",
            iconName: "waveform.path.ecg",
            titleAccessoryView: speedSublabel,
            views: [speedStack]
        )

        // Card 7: 活动连接
        connectionsValueLabel.font = .systemFont(ofSize: 32, weight: .bold)
        connectionsValueLabel.textColor = MD3.onSurface
        let connUnit = NSTextField(labelWithString: "个活动连接")
        connUnit.font = .systemFont(ofSize: 13, weight: .regular)
        connUnit.textColor = MD3.onSurfaceVariant
        let connTextCol = NSStackView(views: [connectionsValueLabel, connUnit])
        connTextCol.orientation = .vertical
        connTextCol.alignment = .leading
        connTextCol.spacing = 1

        equalizerBarsView.translatesAutoresizingMaskIntoConstraints = false
        equalizerBarsView.heightAnchor.constraint(equalToConstant: 33).isActive = true
        equalizerBarsView.widthAnchor.constraint(equalToConstant: 115).isActive = true

        let connSpacer = NSView()
        connSpacer.translatesAutoresizingMaskIntoConstraints = false
        connSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let connRow = NSStackView(views: [connTextCol, connSpacer, equalizerBarsView])
        connRow.orientation = .horizontal
        connRow.alignment = .bottom
        connRow.distribution = .fill
        connRow.translatesAutoresizingMaskIntoConstraints = false

        // Memory Subcard (单独底色)
        let memSubcard = NSView()
        memSubcard.wantsLayer = true
        memSubcard.layer?.cornerRadius = 10
        let memInitialBg = MD3.isDark
            ? MD3.surfaceContainer.mixed(with: MD3.surface, ratio: 0.3)
            : MD3.surfaceContainerHighest.mixed(with: MD3.surface, ratio: 0.35)
        memSubcard.layer?.backgroundColor = memInitialBg.cgColor
        memSubcard.translatesAutoresizingMaskIntoConstraints = false

        let memIconContainer = NSView()
        memIconContainer.wantsLayer = true
        memIconContainer.layer?.cornerRadius = 8
        memIconContainer.layer?.backgroundColor = MD3.primary.withAlphaComponent(MD3.isDark ? 0.18 : 0.12).cgColor
        memIconContainer.translatesAutoresizingMaskIntoConstraints = false
        memIconContainer.widthAnchor.constraint(equalToConstant: 30).isActive = true
        memIconContainer.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let memIv = NSImageView()
        if let memImg = NSImage(systemSymbolName: "memorychip", accessibilityDescription: nil) ?? NSImage(systemSymbolName: "cpu", accessibilityDescription: nil) {
            memImg.isTemplate = true
            memIv.image = memImg
            memIv.contentTintColor = MD3.primary
            memIv.translatesAutoresizingMaskIntoConstraints = false
            memIconContainer.addSubview(memIv)
            NSLayoutConstraint.activate([
                memIv.centerXAnchor.constraint(equalTo: memIconContainer.centerXAnchor),
                memIv.centerYAnchor.constraint(equalTo: memIconContainer.centerYAnchor),
                memIv.widthAnchor.constraint(equalToConstant: 18),
                memIv.heightAnchor.constraint(equalToConstant: 18)
            ])
        }

        let memTitle = NSTextField(labelWithString: "内存占用")
        memTitle.font = .systemFont(ofSize: 13, weight: .regular)
        memTitle.textColor = MD3.onSurfaceVariant

        memoryValueLabel.font = .systemFont(ofSize: 15, weight: .bold)
        memoryValueLabel.textColor = MD3.onSurface

        let memInfoCol = NSStackView(views: [memTitle, memoryValueLabel])
        memInfoCol.orientation = .vertical
        memInfoCol.alignment = .leading
        memInfoCol.spacing = 2

        memoryRingView.translatesAutoresizingMaskIntoConstraints = false
        memoryRingView.heightAnchor.constraint(equalToConstant: 34).isActive = true
        memoryRingView.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let memSpacer = NSView()
        memSpacer.translatesAutoresizingMaskIntoConstraints = false
        memSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let memRow = NSStackView(views: [memIconContainer, memInfoCol, memSpacer, memoryRingView])
        memRow.orientation = .horizontal
        memRow.alignment = .centerY
        memRow.spacing = 10
        memRow.translatesAutoresizingMaskIntoConstraints = false
        memSubcard.addSubview(memRow)

        NSLayoutConstraint.activate([
            memSubcard.heightAnchor.constraint(equalToConstant: 58),
            memRow.leadingAnchor.constraint(equalTo: memSubcard.leadingAnchor, constant: 12),
            memRow.trailingAnchor.constraint(equalTo: memSubcard.trailingAnchor, constant: -12),
            memRow.centerYAnchor.constraint(equalTo: memSubcard.centerYAnchor),
            equalizerBarsView.bottomAnchor.constraint(equalTo: connUnit.bottomAnchor)
        ])

        let connAndMemStack = NSStackView(views: [connRow, memSubcard])
        connAndMemStack.orientation = .vertical
        connAndMemStack.alignment = .leading
        connAndMemStack.spacing = 12
        connAndMemStack.translatesAutoresizingMaskIntoConstraints = false
        connRow.leadingAnchor.constraint(equalTo: connAndMemStack.leadingAnchor).isActive = true
        connRow.trailingAnchor.constraint(equalTo: connAndMemStack.trailingAnchor).isActive = true
        memSubcard.leadingAnchor.constraint(equalTo: connAndMemStack.leadingAnchor).isActive = true
        memSubcard.trailingAnchor.constraint(equalTo: connAndMemStack.trailingAnchor).isActive = true

        let activeConnectionsCard = homeCard(
            title: "活动连接",
            iconName: "link",
            views: [connAndMemStack]
        )

        // Card 8: 流量去向
        trafficDonutChartView.translatesAutoresizingMaskIntoConstraints = false
        trafficDonutChartView.widthAnchor.constraint(equalToConstant: 98).isActive = true
        trafficDonutChartView.heightAnchor.constraint(equalToConstant: 98).isActive = true
        trafficDonutChartView.setContentHuggingPriority(.required, for: .horizontal)
        trafficDonutChartView.setContentCompressionResistancePriority(.required, for: .horizontal)

        func makeLegendTabularRow(color: NSColor, name: String, amountLabel: NSTextField, ratioLabel: NSTextField) -> (row: NSStackView, dot: NSView, nameLabel: NSTextField, ratioLabel: NSTextField) {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.backgroundColor = color.cgColor
            dot.layer?.cornerRadius = 3
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 6).isActive = true

            let nameLabel = NSTextField(labelWithString: name)
            nameLabel.font = .systemFont(ofSize: 13, weight: .regular)
            nameLabel.textColor = MD3.onSurfaceVariant
            nameLabel.translatesAutoresizingMaskIntoConstraints = false

            let nameStack = NSStackView(views: [dot, nameLabel])
            nameStack.orientation = .horizontal
            nameStack.alignment = .centerY
            nameStack.spacing = 5
            nameStack.translatesAutoresizingMaskIntoConstraints = false
            nameStack.widthAnchor.constraint(equalToConstant: 38).isActive = true

            amountLabel.font = .systemFont(ofSize: 11, weight: .bold)
            amountLabel.textColor = MD3.onSurface
            amountLabel.alignment = .right
            amountLabel.lineBreakMode = .byClipping
            amountLabel.translatesAutoresizingMaskIntoConstraints = false
            amountLabel.widthAnchor.constraint(equalToConstant: 62).isActive = true

            ratioLabel.font = .systemFont(ofSize: 13, weight: .regular)
            ratioLabel.textColor = MD3.onSurfaceVariant
            ratioLabel.alignment = .right
            ratioLabel.translatesAutoresizingMaskIntoConstraints = false
            ratioLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true

            let row = NSStackView(views: [nameStack, amountLabel, ratioLabel])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            row.distribution = .fill
            return (row, dot, nameLabel, ratioLabel)
        }

        let proxyLegend = makeLegendTabularRow(color: MD3.primary, name: "代理", amountLabel: donutProxyAmountLabel, ratioLabel: donutProxyRatioLabel)
        let directLegend = makeLegendTabularRow(color: MD3.downloadColor, name: "直连", amountLabel: donutDirectAmountLabel, ratioLabel: donutDirectRatioLabel)
        let otherLegend = makeLegendTabularRow(color: MD3.outlineVariant, name: "其他", amountLabel: donutOtherAmountLabel, ratioLabel: donutOtherRatioLabel)

        let legendStack = NSStackView(views: [proxyLegend.row, directLegend.row, otherLegend.row])
        legendStack.orientation = .vertical
        legendStack.alignment = .leading
        legendStack.spacing = 10
        legendStack.translatesAutoresizingMaskIntoConstraints = false
        legendStack.setContentHuggingPriority(.required, for: .horizontal)
        legendStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        let donutSpacer = NSView()
        donutSpacer.translatesAutoresizingMaskIntoConstraints = false
        donutSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        donutSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 8).isActive = true

        let donutContentStack = NSStackView(views: [trafficDonutChartView, donutSpacer, legendStack])
        donutContentStack.orientation = .horizontal
        donutContentStack.alignment = .centerY
        donutContentStack.spacing = 0
        donutContentStack.distribution = .fill
        donutContentStack.translatesAutoresizingMaskIntoConstraints = false

        let trafficDestinationCard = homeCard(
            title: "流量去向",
            iconName: "chart.pie",
            views: [donutContentStack]
        )

        // Card 9: 最近运行状态
        recentStatusPill.translatesAutoresizingMaskIntoConstraints = false
        recentStatusPill.setContentHuggingPriority(.required, for: .horizontal)
        recentStatusPill.setContentCompressionResistancePriority(.required, for: .horizontal)

        recentStatusStack.orientation = .vertical
        recentStatusStack.alignment = .leading
        recentStatusStack.spacing = 11
        recentStatusStack.translatesAutoresizingMaskIntoConstraints = false

        RecentStatusTracker.shared.onItemsUpdated = { [weak self] items in
            self?.refreshRecentStatusTimeline(items: items)
        }
        refreshRecentStatusTimeline(items: RecentStatusTracker.shared.items)

        let recentStatusCard = homeCard(
            title: "最近运行状态",
            iconName: "list.bullet.rectangle",
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

            headerRow.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 16),
            headerRow.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -16),
            headerRow.topAnchor.constraint(equalTo: doc.topAnchor, constant: 18),

            grid.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -16),
            grid.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 14),
            grid.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -18)
        ])

        registerThemeObserver { [
            weak self,
            weak title,
            weak subtitle,
            weak div1,
            weak div2,
            weak div3,
            weak wifiImageView,
            weak profileTitleLabel,
            weak ipTitleLabel,
            weak trafficTotalDescLabel,
            weak upTrendLabel = upTrendInfo.label,
            weak upTrendDot = upTrendInfo.dot,
            weak downTrendLabel = downTrendInfo.label,
            weak downTrendDot = downTrendInfo.dot,
            weak speedSublabel,
            weak uploadSubcard = uploadSub.subcard,
            weak uploadTag = uploadSub.tagLabel,
            weak uploadIconContainer = uploadSub.iconContainer,
            weak uploadIcon = uploadSub.iconView,
            weak downloadSubcard = downloadSub.subcard,
            weak downloadTag = downloadSub.tagLabel,
            weak downloadIconContainer = downloadSub.iconContainer,
            weak downloadIcon = downloadSub.iconView,
            weak connUnit,
            weak memSubcard,
            weak memIconContainer,
            weak memIv,
            weak memTitle,
            weak proxyLegendDot = proxyLegend.dot,
            weak proxyLegendName = proxyLegend.nameLabel,
            weak directLegendDot = directLegend.dot,
            weak directLegendName = directLegend.nameLabel,
            weak otherLegendDot = otherLegend.dot,
            weak otherLegendName = otherLegend.nameLabel
        ] in
            guard let self = self else { return }
            title?.textColor = MD3.onSurface
            subtitle?.textColor = MD3.onSurfaceVariant
            [div1, div2, div3].compactMap { $0 }.forEach {
                $0.layer?.backgroundColor = (MD3.isDark
                    ? MD3.outlineVariant.withAlphaComponent(0.35)
                    : MD3.outline.withAlphaComponent(0.3)).cgColor
            }
            wifiImageView?.contentTintColor = MD3.primary
            self.wifiStatusLabel.textColor = MD3.onSurface
            profileTitleLabel?.textColor = MD3.onSurfaceVariant
            ipTitleLabel?.textColor = MD3.onSurfaceVariant
            self.externalIPLabel.textColor = MD3.onSurface
            self.externalIPRefreshButton.contentTintColor = MD3.onSurfaceVariant

            self.currentNodeNameLabel.textColor = MD3.onSurface
            self.currentNodeDelayLabel.textColor = MD3.latencyTextColor(self.currentNodeDelayLabel.stringValue)
            self.currentNodeAutoBadge.textColor = MD3.onSuccessContainer
            self.currentNodeAutoBadge.backgroundColor = MD3.successContainer

            self.trafficTotalValueLabel.textColor = MD3.onSurface
            trafficTotalDescLabel?.textColor = MD3.onSurfaceVariant

            upTrendLabel?.textColor = MD3.onSurfaceVariant
            upTrendDot?.layer?.backgroundColor = MD3.primary.cgColor
            self.trafficUploadStatLabel.textColor = MD3.onSurface

            downTrendLabel?.textColor = MD3.onSurfaceVariant
            downTrendDot?.layer?.backgroundColor = MD3.downloadColor.cgColor
            self.trafficDownloadStatLabel.textColor = MD3.onSurface

            speedSublabel?.textColor = MD3.isDark ? MD3.onSurfaceVariant.withAlphaComponent(0.7) : MD3.onSurfaceVariant

            let speedBg = (MD3.isDark
                ? MD3.surfaceContainer.mixed(with: MD3.surface, ratio: 0.25)
                : MD3.surfaceContainerHighest.mixed(with: MD3.surface, ratio: 0.35)).cgColor
            uploadSubcard?.layer?.backgroundColor = speedBg
            uploadTag?.textColor = MD3.onSurfaceVariant
            uploadIconContainer?.layer?.backgroundColor = MD3.primary.withAlphaComponent(0.18).cgColor
            uploadIcon?.contentTintColor = MD3.primary
            self.uploadValueLabel.textColor = MD3.primary
            self.uploadWaveChartView.lineColor = MD3.primary

            downloadSubcard?.layer?.backgroundColor = speedBg
            downloadTag?.textColor = MD3.onSurfaceVariant
            downloadIconContainer?.layer?.backgroundColor = MD3.downloadColor.withAlphaComponent(0.18).cgColor
            downloadIcon?.contentTintColor = MD3.downloadColor
            self.downloadValueLabel.textColor = MD3.downloadColor
            self.downloadWaveChartView.lineColor = MD3.downloadColor

            self.connectionsValueLabel.textColor = MD3.onSurface
            connUnit?.textColor = MD3.onSurfaceVariant

            let memBg = (MD3.isDark
                ? MD3.surfaceContainer.mixed(with: MD3.surface, ratio: 0.3)
                : MD3.surfaceContainerHighest.mixed(with: MD3.surface, ratio: 0.35)).cgColor
            memSubcard?.layer?.backgroundColor = memBg
            memIconContainer?.layer?.backgroundColor = MD3.primary.withAlphaComponent(MD3.isDark ? 0.18 : 0.12).cgColor
            memIv?.contentTintColor = MD3.primary
            memTitle?.textColor = MD3.onSurfaceVariant
            self.memoryValueLabel.textColor = MD3.onSurface

            proxyLegendDot?.layer?.backgroundColor = MD3.primary.cgColor
            proxyLegendName?.textColor = MD3.onSurfaceVariant
            self.donutProxyAmountLabel.textColor = MD3.onSurface
            self.donutProxyRatioLabel.textColor = MD3.onSurfaceVariant

            directLegendDot?.layer?.backgroundColor = MD3.downloadColor.cgColor
            directLegendName?.textColor = MD3.onSurfaceVariant
            self.donutDirectAmountLabel.textColor = MD3.onSurface
            self.donutDirectRatioLabel.textColor = MD3.onSurfaceVariant

            otherLegendDot?.layer?.backgroundColor = MD3.outlineVariant.cgColor
            otherLegendName?.textColor = MD3.onSurfaceVariant
            self.donutOtherAmountLabel.textColor = MD3.onSurface
            self.donutOtherRatioLabel.textColor = MD3.onSurfaceVariant

            self.recentStatusPill.themeChanged()

            self.refreshRecentStatusTimeline(items: RecentStatusTracker.shared.items)
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
        registerThemeObserver { [weak titleLabel = card.title, weak iconView = card.iconView, weak subLabel = card.subtitle] in
            titleLabel?.textColor = MD3.onSurface
            iconView?.contentTintColor = MD3.primary
            subLabel?.textColor = MD3.isDark ? MD3.onSurfaceVariant.withAlphaComponent(0.75) : MD3.onSurfaceVariant
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
        trafficTotalValueLabel.stringValue = formatBytes(total)
        trafficStatsValueLabel.stringValue = formatBytes(total)
        trafficStatsDetailLabel.stringValue = "上传: \(formatBytes(up))   下载: \(formatBytes(down))"
        trafficUploadStatLabel.stringValue = formatBytes(up)
        trafficDownloadStatLabel.stringValue = formatBytes(down)
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
        if force || externalIPLabel.stringValue.isEmpty || externalIPLabel.stringValue == "未获取到公网 IP" {
            externalIPLabel.stringValue = "查询中…"
        }
        Task { [weak self] in
            let ip = await ExternalIPService.shared.getExternalIP(force: force)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let ip {
                    self.externalIPLabel.stringValue = ip
                } else {
                    self.externalIPLabel.stringValue = "未获取到公网 IP"
                    if !force {
                        Task { [weak self] in
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            await MainActor.run { [weak self] in
                                guard let self else { return }
                                if self.externalIPLabel.stringValue == "未获取到公网 IP" {
                                    self.refreshExternalIP(force: true)
                                }
                            }
                        }
                    }
                }
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
        let displayItems = Array(items.prefix(5))
        for (index, item) in displayItems.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 10
            row.translatesAutoresizingMaskIntoConstraints = false

            let isFirst = index == 0
            let isLast = index == displayItems.count - 1

            let dotColor: NSColor
            let lineColor: NSColor
            switch item.level {
            case .success:
                dotColor = MD3.isDark ? MD3.success : NSColor(calibratedRed: 0.04, green: 0.78, blue: 0.68, alpha: 1.0)
                lineColor = MD3.isDark ? MD3.success.withAlphaComponent(0.35) : NSColor(calibratedRed: 0.73, green: 0.96, blue: 0.93, alpha: 1.0)
            case .info:
                dotColor = MD3.isDark ? MD3.primary : NSColor(calibratedRed: 0.04, green: 0.78, blue: 0.68, alpha: 1.0)
                lineColor = MD3.isDark ? MD3.primary.withAlphaComponent(0.35) : NSColor(calibratedRed: 0.73, green: 0.96, blue: 0.93, alpha: 1.0)
            case .warning:
                dotColor = MD3.warning
                lineColor = MD3.warning.withAlphaComponent(0.35)
            case .neutral:
                dotColor = MD3.isDark ? NSColor(white: 0.5, alpha: 1.0) : NSColor(calibratedRed: 0.71, green: 0.75, blue: 0.81, alpha: 1.0)
                lineColor = MD3.isDark ? NSColor(white: 0.25, alpha: 0.6) : NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.97, alpha: 1.0)
            }

            let indicator = NSView()
            indicator.wantsLayer = true
            indicator.translatesAutoresizingMaskIntoConstraints = false

            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3.5
            dot.layer?.backgroundColor = dotColor.cgColor
            dot.translatesAutoresizingMaskIntoConstraints = false

            let topLine = NSView()
            topLine.wantsLayer = true
            topLine.layer?.backgroundColor = lineColor.cgColor
            topLine.translatesAutoresizingMaskIntoConstraints = false
            topLine.isHidden = isFirst

            let bottomLine = NSView()
            bottomLine.wantsLayer = true
            bottomLine.layer?.backgroundColor = lineColor.cgColor
            bottomLine.translatesAutoresizingMaskIntoConstraints = false
            bottomLine.isHidden = isLast

            indicator.addSubview(topLine)
            indicator.addSubview(bottomLine)
            indicator.addSubview(dot)

            indicator.widthAnchor.constraint(equalToConstant: 10).isActive = true
            indicator.heightAnchor.constraint(equalToConstant: 16).isActive = true

            NSLayoutConstraint.activate([
                dot.centerXAnchor.constraint(equalTo: indicator.centerXAnchor),
                dot.centerYAnchor.constraint(equalTo: indicator.centerYAnchor),
                dot.widthAnchor.constraint(equalToConstant: 7),
                dot.heightAnchor.constraint(equalToConstant: 7),

                topLine.centerXAnchor.constraint(equalTo: indicator.centerXAnchor),
                topLine.widthAnchor.constraint(equalToConstant: 1.5),
                topLine.bottomAnchor.constraint(equalTo: dot.centerYAnchor),
                topLine.topAnchor.constraint(equalTo: dot.centerYAnchor, constant: -13.5),

                bottomLine.centerXAnchor.constraint(equalTo: indicator.centerXAnchor),
                bottomLine.widthAnchor.constraint(equalToConstant: 1.5),
                bottomLine.topAnchor.constraint(equalTo: dot.centerYAnchor),
                bottomLine.bottomAnchor.constraint(equalTo: dot.centerYAnchor, constant: 13.5)
            ])

            let timeLabel = NSTextField(labelWithString: RecentStatusTracker.timeString(from: item.timestamp))
            timeLabel.font = .systemFont(ofSize: 13, weight: .regular)
            timeLabel.textColor = MD3.isDark ? MD3.onSurfaceVariant.withAlphaComponent(0.7) : MD3.onSurfaceVariant
            timeLabel.setContentHuggingPriority(.required, for: .horizontal)
            timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            let msgLabel = NSTextField(labelWithString: item.message)
            msgLabel.font = .systemFont(ofSize: 13, weight: .regular)
            msgLabel.textColor = MD3.onSurface
            msgLabel.lineBreakMode = .byTruncatingTail
            msgLabel.maximumNumberOfLines = 1
            msgLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            msgLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            row.addArrangedSubview(indicator)
            row.addArrangedSubview(timeLabel)
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
                self.currentNodeNameLabel.stringValue = nodeName
                self.currentNodeAutoBadge.isHidden = !activeNodeInfo.isAuto
                if !activeNodeInfo.name.isEmpty && self.lastRecordedActiveNode != activeNodeInfo.name {
                    self.lastRecordedActiveNode = activeNodeInfo.name
                    RecentStatusTracker.shared.record("已连接到 \(activeNodeInfo.name)", level: .success)
                    self.refreshExternalIP(force: true)
                }
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

                    let totalBytes = SaturatingArithmetic.add(self.totalUploadBytes, self.totalDownloadBytes)
                    if totalBytes > 0 {
                        self.donutProxyAmountLabel.stringValue = self.formatBytes(Int(Double(totalBytes) * pRatio))
                        self.donutDirectAmountLabel.stringValue = self.formatBytes(Int(Double(totalBytes) * dRatio))
                        self.donutOtherAmountLabel.stringValue = self.formatBytes(Int(Double(totalBytes) * oRatio))
                    } else {
                        self.donutProxyAmountLabel.stringValue = "\(proxyCount) 条"
                        self.donutDirectAmountLabel.stringValue = "\(directCount) 条"
                        self.donutOtherAmountLabel.stringValue = "\(otherCount) 条"
                    }
                    self.donutProxyRatioLabel.stringValue = "\(Int(pRatio * 100))%"
                    self.donutDirectRatioLabel.stringValue = "\(Int(dRatio * 100))%"
                    self.donutOtherRatioLabel.stringValue = "\(Int(oRatio * 100))%"
                }

                self.recentStatusPill.stringValue = self.isProxyRuntimeRunning() ? "运行正常" : "服务未启动"

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
            RecentStatusTracker.shared.record("配置已保存并生效", level: .info)
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
