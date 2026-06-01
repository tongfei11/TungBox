import AppKit
import Foundation


final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private let store = Store()
    private lazy var runner = Runner(store: store)
    private var profiles: [ConfigProfile] = []
    private var subscriptions: [Subscription] = []
    private var customRules: [CustomRule] = []
    private var nodes: [NodeInfo] = []
    private var nodeGroups: [NodeGroupInfo] = []
    private var ruleRows: [RuleInfo] = []
    private var connections: [ConnectionInfo] = []
    private var ruleSetDownloads = Set<String>()
    private var nodeTileActions: [Int: (group: String, node: String)] = [:]
    private var groupTestActions: [Int: String] = [:]
    private var nextNodeTileTag = 1
    private var selectedIndex: Int?
    private var selectedSubscriptionIndex: Int? {
        didSet {
            if let index = selectedSubscriptionIndex {
                UserDefaults.standard.set(index, forKey: "selectedSubscriptionIndex")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedSubscriptionIndex")
            }
        }
    }

    private let split = MD3SplitView()
    private let currentNodeNameLabel = NSTextField(labelWithString: "未连接")
    private let currentNodeDelayLabel = NSTextField(labelWithString: "—")
    private var totalUploadBytes = 0
    private var totalDownloadBytes = 0
    private let trafficStatsValueLabel = NSTextField(labelWithString: "0 B")
    private let trafficStatsDetailLabel = NSTextField(labelWithString: "上传: 0 B   下载: 0 B")



    private let trafficPeriodControl = MD3SegmentedControl()
    


    private let table = NSTableView()
    private let subscriptionTable = NSTableView()
    private let nodeTable = NSTableView()
    private let rulesTable = NSTableView()
    private let connectionsTable = NSTableView()
    private let nodeGroupsStack = NSStackView()
    private let pages = NSTabView()
    private var navButtons: [MD3SidebarItem] = []
    private let editor = NSTextView()
    private let logs = NSTextView()
    private let ruleSearchField = MD3TextField()
    private let customRuleTypePopup = NSPopUpButton()
    private let customRuleStrategyPopup = NSPopUpButton()
    private let customRuleValueField = MD3TextField()
    private let customRuleNoteField = MD3TextField()
    private let ruleSetPrivateURLField = MD3TextField()
    private let ruleSetCNURLField = MD3TextField()
    private let ruleSetGeoIPCNURLField = MD3TextField()
    private let ruleSetGeolocationNotCNURLField = MD3TextField()
    private let statusChip = MD3StatusChip()
    private let subscriptionNameField = MD3TextField()
    private let subscriptionURLField = MD3TextField()
    private let serviceLabel = NSTextField(labelWithString: "sing-box：检测中")
    private let nodeTestURLField = MD3TextField(string: "https://www.gstatic.com/generate_204")
    private let tcpAddressField = MD3TextField(string: "www.google.com:443")
    private let modeControl = MD3SegmentedControl()
    private let nodesModeControl = MD3SegmentedControl()
    private let modeStatusLabel = NSTextField(labelWithString: "当前模式：规则")
    private let apiStatusLabel = NSTextField(labelWithString: "运行态 API：服务未启动")
    private let subscriptionAutoStatusLabel = NSTextField(labelWithString: "订阅自动刷新：每 60 分钟，尚未执行")
    private let nodeTestStatusLabel = NSTextField(labelWithString: "节点 URLTest：尚未测试")
    private let coreStatusLabel = NSTextField(labelWithString: "sing-box Core：检测中")
    private let logStatusLabel = NSTextField(labelWithString: "日志：0 行")
    private let tunRuntimeStatusLabel = NSTextField(labelWithString: "TUN 权限：未启用")
    private var colorSchemeRows: [MD3ColorSchemeRow] = []
    private var themeObservers: [() -> Void] = []
    private var statusItem: NSStatusItem?
    private var isSystemProxyEnabled = UserDefaults.standard.object(forKey: "systemProxyEnabled") as? Bool ?? true
    private var isTunEnabled = UserDefaults.standard.object(forKey: "tunEnabled") as? Bool ?? false
    private var detectedCoreVersion = "检测中"
    private var subscriptionTimer: Timer?
    
    private let serviceSwitch = MD3Switch()
    private let tunSwitch = MD3Switch()
    private let settingsSystemProxyCheckbox = NSButton(checkboxWithTitle: "默认开启系统代理", target: nil, action: nil)
    private let settingsTunCheckbox = NSButton(checkboxWithTitle: "默认开启 TUN 模式", target: nil, action: nil)
    private let tunServiceStatusLabel = NSTextField(labelWithString: "TUN 服务状态：未检测")
    private let tunServiceLogLabel = NSTextField(labelWithString: "最近状态：暂无")
    private let activeNodeLabel = NSTextField(labelWithString: "")
    private let connectionsValueLabel = NSTextField(labelWithString: "0")
    private let connectionsDetailLabel = NSTextField(labelWithString: "服务未运行")
    private let uploadValueLabel = NSTextField(labelWithString: "0 KB/s")
    private let downloadValueLabel = NSTextField(labelWithString: "0 KB/s")
    private var statsTimer: Timer?
    private var lastProxiesObj: [String: Any]? = nil
    private var settingsPages: [NSView] = []
    private let settingsTabView = NSView()
    private weak var toastView: NSView?

    private func registerThemeObserver(_ observer: @escaping () -> Void) {
        themeObservers.append(observer)
    }

    private func notifyThemeChanged() {
        for observer in themeObservers {
            observer()
        }
        window?.contentView?.layer?.backgroundColor = MD3.background.cgColor
        window?.contentView?.refreshSubviews()
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = TungBoxVersion.display
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        setup()
    }

    private func setup() {
        normalizeProxyPreferences()
        profiles = store.loadProfiles()
        subscriptions = store.loadSubscriptions()
        customRules = store.loadCustomRules()
        runner.onOutput = { [weak self] text in
            self?.appendLog(text)
            self?.refreshStatus()
        }

        guard let content = window?.contentView else { return }

        content.wantsLayer = true
        content.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak content] in
            content?.layer?.backgroundColor = MD3.background.cgColor
        }

        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = self
        split.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split)

        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let main = NSView()
        main.translatesAutoresizingMaskIntoConstraints = false

        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(main)

        sidebar.widthAnchor.constraint(equalToConstant: 180).isActive = true

        DispatchQueue.main.async { [weak self] in
            self?.split.setPosition(180, ofDividerAt: 0)
        }

        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.topAnchor.constraint(equalTo: content.topAnchor),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        setupSidebar(sidebar)
        setupMain(main)
        setupStatusItem()
        startSubscriptionTimer()

        // Configure profile table in memory since it's no longer on screen
        table.backgroundColor = .clear
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 40
        table.target = self
        table.action = #selector(tableClicked)
        
        // Configure editor in memory since it's no longer on screen
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.backgroundColor = .clear
        editor.textColor = MD3.onSurface
        editor.insertionPointColor = MD3.primary
        registerThemeObserver { [weak self] in
            self?.editor.textColor = MD3.onSurface
            self?.editor.insertionPointColor = MD3.primary
        }

        var loadedFromSubscription = false
        if !subscriptions.isEmpty {
            let savedIndex = UserDefaults.standard.object(forKey: "selectedSubscriptionIndex") as? Int ?? 0
            let targetIndex = subscriptions.indices.contains(savedIndex) ? savedIndex : 0
            selectedSubscriptionIndex = targetIndex
            subscriptionTable.selectRowIndexes(IndexSet(integer: targetIndex), byExtendingSelection: false)
            
            let sub = subscriptions[targetIndex]
            subscriptionNameField.stringValue = sub.name
            subscriptionURLField.stringValue = sub.url
            if let profileID = sub.profileID,
               let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) {
                selectProfile(at: profileIndex)
                loadedFromSubscription = true
            }
        }
        
        if !loadedFromSubscription {
            if profiles.isEmpty {
                createProfile(named: "默认配置", content: defaultConfig())
            } else {
                selectProfile(at: 0)
            }
        }
        
        refreshStatus()
        
        // Apply logo as Application Dock Icon
        if let logoUrl = AppResources.url(forResource: "logo", withExtension: "png", subdirectory: "Tray"),
           let logoImage = NSImage(contentsOf: logoUrl) {
            NSApplication.shared.applicationIconImage = logoImage
        }

        checkSingBoxInstall(showAlert: true)
    }

    private func normalizeProxyPreferences() {
        if isTunEnabled && !isSystemProxyEnabled {
            isTunEnabled = false
            UserDefaults.standard.set(false, forKey: "tunEnabled")
        }
    }

    private func setupSidebar(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.surface.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.surface.cgColor
        }

        let title = NSTextField(labelWithString: "TungBox")
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak title] in
            title?.textColor = MD3.onSurface
        }

        let nav = NSStackView()
        nav.orientation = .vertical
        nav.spacing = 8
        nav.alignment = .leading
        nav.translatesAutoresizingMaskIntoConstraints = false

        let items = [
            ("首页", "house"),
            ("节点", "network"),
            ("规则", "point.3.connected.trianglepath.dotted"),
            ("订阅", "link"),
            ("连接", "arrow.left.arrow.right"),
            ("日志", "terminal"),
            ("设置", "gearshape")
        ]
        navButtons = items.enumerated().map { index, item in
            let button = MD3SidebarItem()
            button.title = item.0
            button.iconName = item.1
            button.tag = index
            button.target = self
            button.action = #selector(navClicked(_:))
            button.isSelected = (index == 0)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            return button
        }
        navButtons.forEach { button in
            nav.addArrangedSubview(button)
            button.leadingAnchor.constraint(equalTo: nav.leadingAnchor).isActive = true
            button.trailingAnchor.constraint(equalTo: nav.trailingAnchor).isActive = true
        }

        let footer = NSTextField(labelWithString: TungBoxVersion.display)
        footer.font = .systemFont(ofSize: 13, weight: .medium)
        footer.textColor = MD3.onSurfaceVariant
        footer.maximumNumberOfLines = 1
        footer.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak footer] in
            footer?.textColor = MD3.onSurfaceVariant
        }

        view.addSubview(title)
        view.addSubview(nav)
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 34),

            nav.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            nav.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            nav.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 30),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -28)
        ])
    }

    private func setupMain(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        pages.translatesAutoresizingMaskIntoConstraints = false
        pages.tabViewType = .noTabsNoBorder

        let dashboardItem = NSTabViewItem(identifier: "dashboard")
        dashboardItem.label = "仪表盘"
        dashboardItem.view = makeHomeView()
        pages.addTabViewItem(dashboardItem)

        let nodesItem = NSTabViewItem(identifier: "nodes")
        nodesItem.label = "节点"
        nodesItem.view = makeNodesView()
        pages.addTabViewItem(nodesItem)

        let rulesItem = NSTabViewItem(identifier: "rules")
        rulesItem.label = "规则"
        rulesItem.view = makeRulesView()
        pages.addTabViewItem(rulesItem)

        let subscriptionItem = NSTabViewItem(identifier: "subscriptions")
        subscriptionItem.label = "订阅"
        subscriptionItem.view = makeSubscriptionsView()
        pages.addTabViewItem(subscriptionItem)

        let connectionsItem = NSTabViewItem(identifier: "connections")
        connectionsItem.label = "连接"
        connectionsItem.view = makeConnectionsView()
        pages.addTabViewItem(connectionsItem)

        let logItem = NSTabViewItem(identifier: "logs")
        logItem.label = "日志"
        logItem.view = makeLogsView()
        pages.addTabViewItem(logItem)

        let settingsItem = NSTabViewItem(identifier: "settings")
        settingsItem.label = "设置"
        settingsItem.view = makeSettingsView()
        pages.addTabViewItem(settingsItem)

        view.addSubview(pages)

        NSLayoutConstraint.activate([
            pages.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pages.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pages.topAnchor.constraint(equalTo: view.topAnchor),
            pages.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func makeHomeView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        let title = NSTextField(labelWithString: "首页")
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak title] in
            title?.textColor = MD3.onSurface
        }

        let subtitle = NSTextField(labelWithString: "服务状态、出站模式和运行统计信息")
        subtitle.textColor = MD3.onSurfaceVariant
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak subtitle] in
            subtitle?.textColor = MD3.onSurfaceVariant
        }

        statusChip.translatesAutoresizingMaskIntoConstraints = false
        statusChip.heightAnchor.constraint(equalToConstant: 32).isActive = true
        statusChip.widthAnchor.constraint(equalToConstant: 96).isActive = true

        serviceSwitch.target = self
        serviceSwitch.action = #selector(switchToggled(_:))

        let systemProxySpacer = NSView()
        systemProxySpacer.translatesAutoresizingMaskIntoConstraints = false
        let systemProxyRow = NSStackView(views: [statusChip, systemProxySpacer, serviceSwitch])
        systemProxyRow.orientation = .horizontal
        systemProxyRow.distribution = .fill
        systemProxyRow.alignment = .centerY
        systemProxyRow.translatesAutoresizingMaskIntoConstraints = false
        let systemProxyCard = homeCard(title: "系统代理", views: [systemProxyRow])

        tunSwitch.target = self
        tunSwitch.action = #selector(tunSwitchToggled(_:))
        tunSwitch.isOn = isTunEnabled
        tunSwitch.translatesAutoresizingMaskIntoConstraints = false

        let tunLabel = NSTextField(labelWithString: "启用 TUN")
        tunLabel.font = .systemFont(ofSize: 14, weight: .bold)
        tunLabel.textColor = MD3.onSurface
        registerThemeObserver { [weak tunLabel] in
            tunLabel?.textColor = MD3.onSurface
        }
        let tunSpacer = NSView()
        tunSpacer.translatesAutoresizingMaskIntoConstraints = false
        let tunControlRow = NSStackView(views: [tunLabel, tunSpacer, tunSwitch])
        tunControlRow.orientation = .horizontal
        tunControlRow.distribution = .fill
        tunControlRow.alignment = .centerY
        tunControlRow.translatesAutoresizingMaskIntoConstraints = false
        let tunCard = homeCard(title: "TUN 模式", views: [tunControlRow])

        modeControl.items = ["直接连接", "全局代理", "规则判定"]
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.selectedSegment = 2
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.heightAnchor.constraint(equalToConstant: 36).isActive = true
        
        modeStatusLabel.textColor = MD3.onSurfaceVariant
        modeStatusLabel.font = .systemFont(ofSize: 12)
        modeStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak self] in
            self?.modeStatusLabel.textColor = MD3.onSurfaceVariant
        }
        let outboundCard = homeCard(title: "出站模式", views: [modeControl, modeStatusLabel])

        currentNodeNameLabel.font = .systemFont(ofSize: 22, weight: .bold)
        currentNodeNameLabel.textColor = MD3.primary
        currentNodeNameLabel.lineBreakMode = .byTruncatingTail
        currentNodeNameLabel.maximumNumberOfLines = 1
        currentNodeNameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        currentNodeDelayLabel.font = .systemFont(ofSize: 22, weight: .bold)
        currentNodeDelayLabel.textColor = MD3.success
        currentNodeDelayLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let nodeLabelTitle = NSTextField(labelWithString: "当前节点")
        nodeLabelTitle.font = .systemFont(ofSize: 12, weight: .medium)
        nodeLabelTitle.textColor = MD3.onSurfaceVariant
        
        let delayLabelTitle = NSTextField(labelWithString: "节点延迟")
        delayLabelTitle.font = .systemFont(ofSize: 12, weight: .medium)
        delayLabelTitle.textColor = MD3.onSurfaceVariant
        
        let nodeCol = NSStackView(views: [nodeLabelTitle, currentNodeNameLabel])
        nodeCol.orientation = .vertical
        nodeCol.alignment = .leading
        nodeCol.spacing = 4
        
        let delayCol = NSStackView(views: [delayLabelTitle, currentNodeDelayLabel])
        delayCol.orientation = .vertical
        delayCol.alignment = .leading
        delayCol.spacing = 4
        
        let nodeSpacer = NSView()
        nodeSpacer.translatesAutoresizingMaskIntoConstraints = false
        let nodeRow = NSStackView(views: [nodeCol, nodeSpacer, delayCol])
        nodeRow.orientation = .horizontal
        nodeRow.distribution = .fill
        nodeRow.alignment = .centerY
        nodeRow.translatesAutoresizingMaskIntoConstraints = false
        
        let nodeLatencyCard = homeCard(title: "节点名称与延迟", views: [nodeRow])

        uploadValueLabel.font = .systemFont(ofSize: 28, weight: .bold)
        uploadValueLabel.textColor = MD3.primary
        uploadValueLabel.translatesAutoresizingMaskIntoConstraints = false
        let uploadDetail = NSTextField(labelWithString: "上传速度")
        detailsTextConfig(uploadDetail)
        uploadDetail.translatesAutoresizingMaskIntoConstraints = false
        let uploadCard = homeCard(title: "实时上传", views: [uploadValueLabel, uploadDetail])

        downloadValueLabel.font = .systemFont(ofSize: 28, weight: .bold)
        downloadValueLabel.textColor = MD3.primary
        downloadValueLabel.translatesAutoresizingMaskIntoConstraints = false
        let downloadDetail = NSTextField(labelWithString: "下载速度")
        detailsTextConfig(downloadDetail)
        downloadDetail.translatesAutoresizingMaskIntoConstraints = false
        let downloadCard = homeCard(title: "实时下载", views: [downloadValueLabel, downloadDetail])

        connectionsValueLabel.font = .systemFont(ofSize: 28, weight: .bold)
        connectionsValueLabel.textColor = MD3.primary
        connectionsValueLabel.translatesAutoresizingMaskIntoConstraints = false
        connectionsDetailLabel.font = .systemFont(ofSize: 11)
        connectionsDetailLabel.textColor = MD3.onSurfaceVariant
        connectionsDetailLabel.translatesAutoresizingMaskIntoConstraints = false
        let activeConnectionsCard = homeCard(title: "活动连接数", views: [connectionsValueLabel, connectionsDetailLabel])

        trafficPeriodControl.items = ["今日", "近7天", "近30天"]
        trafficPeriodControl.target = self
        trafficPeriodControl.action = #selector(trafficPeriodChanged)
        trafficPeriodControl.selectedSegment = 0
        trafficPeriodControl.translatesAutoresizingMaskIntoConstraints = false
        trafficPeriodControl.widthAnchor.constraint(equalToConstant: 210).isActive = true
        trafficPeriodControl.heightAnchor.constraint(equalToConstant: 26).isActive = true

        trafficStatsValueLabel.font = .systemFont(ofSize: 28, weight: .bold)
        trafficStatsValueLabel.textColor = MD3.primary
        trafficStatsValueLabel.translatesAutoresizingMaskIntoConstraints = false
        trafficStatsDetailLabel.font = .systemFont(ofSize: 11)
        trafficStatsDetailLabel.textColor = MD3.onSurfaceVariant
        trafficStatsDetailLabel.translatesAutoresizingMaskIntoConstraints = false
        let trafficStatsCard = homeCard(
            title: "流量统计",
            titleAccessoryView: trafficPeriodControl,
            views: [trafficStatsValueLabel, trafficStatsDetailLabel]
        )

        registerThemeObserver { [weak self] in
            guard let self = self else { return }
            self.currentNodeNameLabel.textColor = MD3.primary
            self.currentNodeDelayLabel.textColor = MD3.success
            self.trafficStatsValueLabel.textColor = MD3.primary
            self.trafficStatsDetailLabel.textColor = MD3.onSurfaceVariant
            self.uploadValueLabel.textColor = MD3.primary
            self.downloadValueLabel.textColor = MD3.primary
            self.connectionsValueLabel.textColor = MD3.primary
            self.connectionsDetailLabel.textColor = MD3.onSurfaceVariant
        }

        updateTrafficLabels()

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(systemProxyCard)
        container.addSubview(tunCard)
        container.addSubview(outboundCard)
        container.addSubview(nodeLatencyCard)
        container.addSubview(uploadCard)
        container.addSubview(downloadCard)
        container.addSubview(activeConnectionsCard)
        container.addSubview(trafficStatsCard)

        NSLayoutConstraint.activate([
            // --- Width Constraints ---
            tunCard.widthAnchor.constraint(equalTo: systemProxyCard.widthAnchor),
            uploadCard.widthAnchor.constraint(equalTo: systemProxyCard.widthAnchor),
            downloadCard.widthAnchor.constraint(equalTo: systemProxyCard.widthAnchor),
            
            // Span 2 cards width: 2 * size-1 width + 16 (gap)
            outboundCard.widthAnchor.constraint(equalTo: systemProxyCard.widthAnchor, multiplier: 2.0, constant: 16),
            nodeLatencyCard.widthAnchor.constraint(equalTo: outboundCard.widthAnchor),
            activeConnectionsCard.widthAnchor.constraint(equalTo: outboundCard.widthAnchor),
            trafficStatsCard.widthAnchor.constraint(equalTo: outboundCard.widthAnchor),
            
            // --- Height Constraints ---
            systemProxyCard.heightAnchor.constraint(equalToConstant: 142),
            tunCard.heightAnchor.constraint(equalTo: systemProxyCard.heightAnchor),
            outboundCard.heightAnchor.constraint(equalTo: systemProxyCard.heightAnchor),
            nodeLatencyCard.heightAnchor.constraint(equalTo: systemProxyCard.heightAnchor),
            uploadCard.heightAnchor.constraint(equalTo: systemProxyCard.heightAnchor),
            downloadCard.heightAnchor.constraint(equalTo: systemProxyCard.heightAnchor),
            activeConnectionsCard.heightAnchor.constraint(equalTo: systemProxyCard.heightAnchor),
            trafficStatsCard.heightAnchor.constraint(equalTo: systemProxyCard.heightAnchor),
            
            // --- Row 1 Layout (top) ---
            systemProxyCard.topAnchor.constraint(equalTo: container.topAnchor),
            systemProxyCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            
            tunCard.topAnchor.constraint(equalTo: container.topAnchor),
            tunCard.leadingAnchor.constraint(equalTo: systemProxyCard.trailingAnchor, constant: 16),
            
            outboundCard.topAnchor.constraint(equalTo: container.topAnchor),
            outboundCard.leadingAnchor.constraint(equalTo: tunCard.trailingAnchor, constant: 16),
            outboundCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            // --- Row 2 Layout (middle) ---
            nodeLatencyCard.topAnchor.constraint(equalTo: systemProxyCard.bottomAnchor, constant: 16),
            nodeLatencyCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            
            uploadCard.topAnchor.constraint(equalTo: systemProxyCard.bottomAnchor, constant: 16),
            uploadCard.leadingAnchor.constraint(equalTo: nodeLatencyCard.trailingAnchor, constant: 16),
            
            downloadCard.topAnchor.constraint(equalTo: systemProxyCard.bottomAnchor, constant: 16),
            downloadCard.leadingAnchor.constraint(equalTo: uploadCard.trailingAnchor, constant: 16),
            downloadCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            // --- Row 3 Layout (bottom) ---
            activeConnectionsCard.topAnchor.constraint(equalTo: nodeLatencyCard.bottomAnchor, constant: 16),
            activeConnectionsCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            
            trafficStatsCard.topAnchor.constraint(equalTo: nodeLatencyCard.bottomAnchor, constant: 16),
            trafficStatsCard.leadingAnchor.constraint(equalTo: activeConnectionsCard.trailingAnchor, constant: 16),
            trafficStatsCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            // Bottom constraint to calculate container height
            container.bottomAnchor.constraint(equalTo: activeConnectionsCard.bottomAnchor)
        ])

        view.addSubview(title)
        view.addSubview(subtitle)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),

            container.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            container.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 24),
            container.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24)
        ])

        refreshHomeFeatureStatus()
        return view
    }
    private func homeActionButton(title: String, action: Selector, style: MD3Button.ButtonStyle = .filled) -> MD3Button {
        let button = MD3Button()
        button.title = title
        button.style = style
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }

    private func refreshHomeFeatureStatus() {
        apiStatusLabel.stringValue = isProxyRuntimeRunning()
            ? "运行态 API：\(TungBoxConfig.clashAPIListen)"
            : "运行态 API：服务未启动"
        let latestSubscription = subscriptions.compactMap(\.updatedAt).max().map { DateFormatter.short.string(from: $0) } ?? "尚未刷新"
        subscriptionAutoStatusLabel.stringValue = "订阅自动刷新：每 60 分钟；上次刷新 \(latestSubscription)"
        coreStatusLabel.stringValue = "sing-box Core：\(detectedCoreVersion)"
        logStatusLabel.stringValue = "日志：\(logs.string.components(separatedBy: .newlines).filter { !$0.isEmpty }.count) 行"
        tunRuntimeStatusLabel.stringValue = isTunEnabled
            ? (TunServiceManager.status(store: store).isInstalled ? "TUN 服务：已安装，随代理开启" : "TUN 服务：未安装")
            : "TUN 权限：未启用"
    }

    private func refreshNodeGroupsView() {
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

    private func nodeGroupCard(group: NodeGroupInfo, nodeByTag: [String: NodeInfo]) -> NSView {
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

    private func nodeTile(group: NodeGroupInfo, nodeTag: String, node: NodeInfo?) -> NSView {
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

    private func specialNodeType(_ tag: String) -> String {
        switch tag {
        case TungBoxConfig.tagAuto: return "urltest"
        case TungBoxConfig.tagDirect: return "direct"
        case TungBoxConfig.tagBlock: return "reject"
        default: return "outbound"
        }
    }

    private func groupDisplayType(_ type: String) -> String {
        switch type.lowercased() {
        case "urltest", "url-test": return "URLTest"
        case "selector": return "Selector"
        case "fallback": return "Fallback"
        default: return type
        }
    }

    private func groupDelay(group: NodeGroupInfo, nodeByTag: [String: NodeInfo]) -> String {
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

    private func updateURLTestSelectionsFromMeasuredDelays() {
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

    private func parsedDelay(_ value: String) -> Int? {
        let digits = value.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }



    private func makeLogsView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }
        
        let logTitle = NSTextField(labelWithString: "日志")
        logTitle.font = .systemFont(ofSize: 30, weight: .bold)
        logTitle.textColor = MD3.onSurface
        logTitle.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak logTitle] in
            logTitle?.textColor = MD3.onSurface
        }

        let clearButton = MD3Button()
        clearButton.title = "清空日志"
        clearButton.style = .outlined
        clearButton.target = self
        clearButton.action = #selector(clearLogsClicked)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let logScroll = NSScrollView()
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        logScroll.hasVerticalScroller = true
        logScroll.drawsBackground = false
        logScroll.documentView = logs
        
        logs.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logs.isEditable = false
        logs.backgroundColor = .clear
        logs.textColor = MD3.onSurface
        registerThemeObserver { [weak self] in
            self?.logs.textColor = MD3.onSurface
        }
        
        let panel = MD3Panel()
        panel.type = .filled
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(logScroll)
        
        view.addSubview(logTitle)
        view.addSubview(clearButton)
        view.addSubview(panel)

        NSLayoutConstraint.activate([
            logTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            logTitle.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),

            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            clearButton.centerYAnchor.constraint(equalTo: logTitle.centerYAnchor),

            panel.leadingAnchor.constraint(equalTo: logTitle.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            panel.topAnchor.constraint(equalTo: logTitle.bottomAnchor, constant: 20),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            
            logScroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            logScroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            logScroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            logScroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12)
        ])

        return view
    }

    private func makeConnectionsView() -> NSView {
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

    private func makeNodesView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        let title = NSTextField(labelWithString: "节点")
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak title] in
            title?.textColor = MD3.onSurface
        }

        nodesModeControl.items = ["直接连接", "全局代理", "规则判定"]
        nodesModeControl.target = self
        nodesModeControl.action = #selector(nodesModeChanged)
        nodesModeControl.selectedSegment = 2
        nodesModeControl.translatesAutoresizingMaskIntoConstraints = false
        nodesModeControl.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let testButton = MD3Button()
        testButton.title = ""
        testButton.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "测试全部延迟")
        testButton.style = .text
        testButton.target = self
        testButton.action = #selector(testAllNodesClicked)
        testButton.translatesAutoresizingMaskIntoConstraints = false
        testButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        testButton.widthAnchor.constraint(equalToConstant: 32).isActive = true

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

    private func makeRulesView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        let title = NSTextField(labelWithString: "规则")
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak title] in
            title?.textColor = MD3.onSurface
        }

        let subtitle = NSTextField(labelWithString: "规则将按照从上到下的顺序匹配")
        subtitle.textColor = MD3.onSurfaceVariant
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak subtitle] in
            subtitle?.textColor = MD3.onSurfaceVariant
        }

        ruleSearchField.placeholderString = "搜索规则"
        ruleSearchField.target = self
        ruleSearchField.action = #selector(refreshRulesClicked)
        ruleSearchField.translatesAutoresizingMaskIntoConstraints = false
        ruleSearchField.heightAnchor.constraint(equalToConstant: 36).isActive = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshRulesClicked),
            name: NSControl.textDidChangeNotification,
            object: ruleSearchField
        )

        let addRuleButton = MD3Button()
        addRuleButton.title = "添加规则"
        addRuleButton.style = .filled
        addRuleButton.target = self
        addRuleButton.action = #selector(showAddCustomRuleDialog)
        addRuleButton.translatesAutoresizingMaskIntoConstraints = false
        addRuleButton.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = rulesTable

        rulesTable.backgroundColor = .clear
        rulesTable.usesAlternatingRowBackgroundColors = false
        rulesTable.headerView = nil
        rulesTable.delegate = self
        rulesTable.dataSource = self
        rulesTable.rowHeight = 54
        rulesTable.gridStyleMask = [.solidHorizontalGridLineMask]
        rulesTable.gridColor = MD3.outlineVariant
        rulesTable.menu = ruleContextMenu()
        rulesTable.addTableColumn(ruleColumn("enabled", width: 48))
        rulesTable.addTableColumn(ruleColumn("id", width: 56))
        rulesTable.addTableColumn(ruleColumn("type", width: 150))
        rulesTable.addTableColumn(ruleColumn("value", width: 360))
        rulesTable.addTableColumn(ruleColumn("strategy", width: 120))
        rulesTable.addTableColumn(ruleColumn("count", width: 80))
        rulesTable.addTableColumn(ruleColumn("note", width: 240))

        let panel = MD3Panel()
        panel.type = .filled
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(scroll)

        view.addSubview(title)
        view.addSubview(subtitle)
        view.addSubview(ruleSearchField)
        view.addSubview(addRuleButton)
        view.addSubview(panel)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: ruleSearchField.leadingAnchor, constant: -16),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),

            ruleSearchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            ruleSearchField.centerYAnchor.constraint(equalTo: subtitle.centerYAnchor),
            ruleSearchField.widthAnchor.constraint(equalToConstant: 360),

            addRuleButton.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            addRuleButton.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18),
            addRuleButton.widthAnchor.constraint(equalToConstant: 112),

            panel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            panel.topAnchor.constraint(equalTo: addRuleButton.bottomAnchor, constant: 14),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),

            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8)
        ])

        refreshRulesFromEditor()
        return view
    }

    private func ruleColumn(_ id: String, width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.width = width
        column.minWidth = width
        column.resizingMask = .autoresizingMask
        return column
    }

    private func ruleContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "删除自定义规则", action: #selector(deleteCustomRuleClicked), keyEquivalent: ""))
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu == rulesTable.menu else { return }
        let row = rulesTable.clickedRow
        if row >= 0 {
            rulesTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        let rows = filteredRuleRows()
        let canDelete = rows.indices.contains(rulesTable.selectedRow) && rows[rulesTable.selectedRow].customRuleID != nil
        menu.items.first?.isEnabled = canDelete
    }



    private func makeSubscriptionsView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        let title = NSTextField(labelWithString: "订阅")
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak title] in
            title?.textColor = MD3.onSurface
        }

        let addButton = MD3Button()
        addButton.title = "添加订阅"
        addButton.style = .filled
        addButton.target = self
        addButton.action = #selector(addSubscriptionClicked)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        addButton.widthAnchor.constraint(equalToConstant: 120).isActive = true
        
        let updateButton = MD3Button()
        updateButton.title = "更新选中"
        updateButton.style = .tonal
        updateButton.target = self
        updateButton.action = #selector(updateSubscriptionClicked)
        updateButton.translatesAutoresizingMaskIntoConstraints = false
        updateButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        updateButton.widthAnchor.constraint(equalToConstant: 120).isActive = true
        
        let deleteButton = MD3Button()
        deleteButton.title = "删除订阅"
        deleteButton.style = .destructive
        deleteButton.target = self
        deleteButton.action = #selector(deleteSubscriptionClicked)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        deleteButton.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let buttons = NSStackView(views: [addButton, updateButton, deleteButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        
        subscriptionTable.backgroundColor = .clear
        subscriptionTable.selectionHighlightStyle = .none
        subscriptionTable.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("subscription")))
        subscriptionTable.headerView = nil
        subscriptionTable.delegate = self
        subscriptionTable.dataSource = self
        subscriptionTable.rowHeight = 60
        subscriptionTable.target = self
        subscriptionTable.action = #selector(subscriptionTableClicked)
        scroll.documentView = subscriptionTable

        let panel = MD3Panel()
        panel.type = .filled
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(scroll)

        view.addSubview(title)
        view.addSubview(buttons)
        view.addSubview(panel)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),

            buttons.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            buttons.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),
            buttons.heightAnchor.constraint(equalToConstant: 36),

            panel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            panel.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 20),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8)
        ])

        return view
    }

    private func makeSettingsView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        let title = NSTextField(labelWithString: "设置")
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak title] in
            title?.textColor = MD3.onSurface
        }

        let tabControl = MD3SegmentedControl()
        tabControl.items = ["基础", "运行", "TUN 设置", "规则集", "外观"]
        tabControl.selectedSegment = 0
        tabControl.target = self
        tabControl.action = #selector(settingsTabChanged(_:))
        tabControl.translatesAutoresizingMaskIntoConstraints = false
        tabControl.widthAnchor.constraint(equalToConstant: 380).isActive = true
        tabControl.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let headerStack = NSStackView(views: [title])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 16
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        headerStack.addArrangedSubview(spacer)
        headerStack.addArrangedSubview(tabControl)

        settingsTabView.translatesAutoresizingMaskIntoConstraints = false
        settingsTabView.wantsLayer = true
        settingsTabView.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak self] in
            self?.settingsTabView.layer?.backgroundColor = MD3.background.cgColor
        }

        settingsPages = [
            makeSettingsGeneralPage(),
            makeSettingsRuntimePage(),
            makeSettingsTunPage(),
            makeSettingsRuleSetPage(),
            makeSettingsAppearancePage()
        ]
        
        if !settingsPages.isEmpty {
            let firstPage = settingsPages[0]
            settingsTabView.addSubview(firstPage)
            firstPage.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                firstPage.leadingAnchor.constraint(equalTo: settingsTabView.leadingAnchor),
                firstPage.trailingAnchor.constraint(equalTo: settingsTabView.trailingAnchor),
                firstPage.topAnchor.constraint(equalTo: settingsTabView.topAnchor),
                firstPage.bottomAnchor.constraint(equalTo: settingsTabView.bottomAnchor)
            ])
        }

        view.addSubview(headerStack)
        view.addSubview(settingsTabView)

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            headerStack.heightAnchor.constraint(equalToConstant: 38),

            settingsTabView.leadingAnchor.constraint(equalTo: headerStack.leadingAnchor, constant: -20),
            settingsTabView.trailingAnchor.constraint(equalTo: headerStack.trailingAnchor, constant: 20),
            settingsTabView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 20),
            settingsTabView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -28)
        ])

        return view
    }

    @objc private func settingsTabChanged(_ sender: MD3SegmentedControl) {
        let index = sender.selectedSegment
        guard index >= 0 && index < settingsPages.count else { return }
        settingsTabView.subviews.forEach { $0.removeFromSuperview() }
        let newPage = settingsPages[index]
        settingsTabView.addSubview(newPage)
        newPage.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            newPage.leadingAnchor.constraint(equalTo: settingsTabView.leadingAnchor),
            newPage.trailingAnchor.constraint(equalTo: settingsTabView.trailingAnchor),
            newPage.topAnchor.constraint(equalTo: settingsTabView.topAnchor),
            newPage.bottomAnchor.constraint(equalTo: settingsTabView.bottomAnchor)
        ])
    }

    private func makeSettingsGeneralPage() -> NSView {
        serviceLabel.font = .systemFont(ofSize: 14, weight: .bold)
        serviceLabel.textColor = MD3.onSurface
        serviceLabel.lineBreakMode = .byWordWrapping
        serviceLabel.maximumNumberOfLines = 0
        serviceLabel.usesSingleLineMode = false
        serviceLabel.cell?.wraps = true
        serviceLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailsText = NSTextField(labelWithString: """
        应用版本: \(TungBoxVersion.current)
        配置目录: \(store.baseURL.path)
        Clash API: \(TungBoxConfig.clashAPIListen)
        """)
        detailsText.textColor = MD3.onSurfaceVariant
        detailsText.font = .systemFont(ofSize: 13)
        detailsText.lineBreakMode = .byWordWrapping
        detailsText.maximumNumberOfLines = 0
        detailsText.translatesAutoresizingMaskIntoConstraints = false

        let checkUpdateButton = settingsButton(title: "检查 Core 更新", action: #selector(checkCoreUpdateClicked), style: .tonal)
        let installLatestButton = settingsButton(title: "安装最新 Core", action: #selector(installLatestCoreClicked), style: .filled)
        let importCoreButton = settingsButton(title: "导入 sing-box Core", action: #selector(importCoreClicked), style: .filled)
        let installOldCoreButton = settingsButton(title: "安装旧版 Core（测试）", action: #selector(installOldCoreForTestClicked), style: .outlined)
        let openCoreFolderButton = settingsButton(title: "打开 Core 目录", action: #selector(openCoreFolderClicked), style: .outlined)
        let openFolderButton = settingsButton(title: "打开配置目录", action: #selector(openFolderClicked), style: .outlined)
        let coreButtonGrid = settingsButtonGrid([
            checkUpdateButton,
            installLatestButton,
            importCoreButton,
            installOldCoreButton,
            openCoreFolderButton
        ])
        return settingsPageStack([
            settingsPanel(title: "基础信息", views: [detailsText, openFolderButton]),
            settingsPanel(title: "Core 管理", views: [
                serviceLabel,
                coreButtonGrid
            ])
        ])
    }

    private func makeSettingsRuntimePage() -> NSView {
        settingsSystemProxyCheckbox.target = self
        settingsSystemProxyCheckbox.action = #selector(settingsSystemProxyChanged(_:))
        settingsSystemProxyCheckbox.state = isSystemProxyEnabled ? .on : .off
        let hint = NSTextField(labelWithString: "系统代理默认开启后，点击首页代理开关会启动代理服务并接管系统代理。TUN 默认行为在 TUN 设置里配置。")
        hint.textColor = MD3.onSurfaceVariant
        hint.font = .systemFont(ofSize: 13)
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false
        return settingsPageStack([settingsPanel(title: "运行默认值", views: [settingsSystemProxyCheckbox, hint])])
    }

    private func makeSettingsTunPage() -> NSView {
        tunServiceStatusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        tunServiceStatusLabel.textColor = MD3.onSurface
        tunServiceStatusLabel.lineBreakMode = .byWordWrapping
        tunServiceStatusLabel.maximumNumberOfLines = 0
        tunServiceStatusLabel.translatesAutoresizingMaskIntoConstraints = false

        tunServiceLogLabel.textColor = MD3.onSurfaceVariant
        tunServiceLogLabel.font = .systemFont(ofSize: 13)
        tunServiceLogLabel.lineBreakMode = .byWordWrapping
        tunServiceLogLabel.maximumNumberOfLines = 0
        tunServiceLogLabel.translatesAutoresizingMaskIntoConstraints = false

        settingsTunCheckbox.title = "随代理开启 TUN"
        settingsTunCheckbox.target = self
        settingsTunCheckbox.action = #selector(settingsTunChanged(_:))
        settingsTunCheckbox.state = isTunEnabled ? .on : .off
        settingsTunCheckbox.isEnabled = isSystemProxyEnabled

        let installButton = settingsButton(title: "安装 TUN 服务", action: #selector(installTunServiceClicked), style: .filled)
        let uninstallButton = settingsButton(title: "卸载 TUN 服务", action: #selector(uninstallTunServiceClicked), style: .destructive)
        let openLogButton = settingsButton(title: "打开 TUN 日志", action: #selector(openTunLogClicked), style: .outlined)

        let hint = NSTextField(labelWithString: "安装 TUN 服务会请求一次管理员授权。服务文件安装到 /Library/Application Support/TungBox 和 /Library/LaunchDaemons；首页 TUN 开关只负责是否启用 TUN，不再临时弹密码启动。")
        hint.textColor = MD3.onSurfaceVariant
        hint.font = .systemFont(ofSize: 13)
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false

        refreshTunServiceStatus()
        return settingsPageStack([
            settingsPanel(title: "TUN 设置", views: [
                tunServiceStatusLabel,
                installButton,
                uninstallButton,
                settingsTunCheckbox,
                openLogButton,
                tunServiceLogLabel,
                hint
            ])
        ])
    }

    private func makeSettingsRuleSetPage() -> NSView {
        setupRuleSetURLFields()
        let ruleSetForm = NSGridView(views: [
            [settingsLabel("geosite-private"), ruleSetPrivateURLField],
            [settingsLabel("geosite-cn"), ruleSetCNURLField],
            [settingsLabel("geoip-cn"), ruleSetGeoIPCNURLField],
            [settingsLabel("geosite-geolocation-!cn"), ruleSetGeolocationNotCNURLField]
        ])
        ruleSetForm.translatesAutoresizingMaskIntoConstraints = false
        ruleSetForm.column(at: 0).xPlacement = .trailing
        ruleSetForm.column(at: 1).width = 560
        ruleSetForm.rowSpacing = 10
        ruleSetForm.columnSpacing = 10
        let saveRuleSetButton = settingsButton(title: "保存规则集地址", action: #selector(saveRuleSetURLsClicked))
        return settingsPageStack([settingsPanel(title: "规则集地址", views: [ruleSetForm, saveRuleSetButton])])
    }

    private func makeSettingsAppearancePage() -> NSView {
        let themeButton = settingsButton(title: "切换深浅色", action: #selector(toggleThemeClicked), style: .tonal)
        colorSchemeRows = (0..<MD3.colorSchemes.count).map { index in
            let row = MD3ColorSchemeRow(index: index)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 36).isActive = true
            row.isSelected = (index == MD3.currentSchemeIndex)
            row.onClick = { [weak self] in self?.changeColorScheme(to: index) }
            return row
        }
        
        let half = (colorSchemeRows.count + 1) / 2
        let leftRows = Array(colorSchemeRows.prefix(half))
        let rightRows = Array(colorSchemeRows.suffix(colorSchemeRows.count - half))
        
        let leftStack = NSStackView(views: leftRows)
        leftStack.orientation = .vertical
        leftStack.spacing = 4
        leftStack.alignment = .leading
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        leftRows.forEach { row in
            row.leadingAnchor.constraint(equalTo: leftStack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: leftStack.trailingAnchor).isActive = true
        }
        
        let rightStack = NSStackView(views: rightRows)
        rightStack.orientation = .vertical
        rightStack.spacing = 4
        rightStack.alignment = .leading
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightRows.forEach { row in
            row.leadingAnchor.constraint(equalTo: rightStack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: rightStack.trailingAnchor).isActive = true
        }
        
        let columnsStack = NSStackView(views: [leftStack, rightStack])
        columnsStack.orientation = .horizontal
        columnsStack.spacing = 40
        columnsStack.distribution = .fillEqually
        columnsStack.alignment = .top
        columnsStack.translatesAutoresizingMaskIntoConstraints = false
        columnsStack.widthAnchor.constraint(equalToConstant: 640).isActive = true
        
        return settingsPageStack([settingsPanel(title: "外观", views: [themeButton, columnsStack])])
    }

final class MD3SettingsPageView: NSView, MD3Themeable {
    func themeChanged() {
        self.needsDisplay = true
    }
}

    private func settingsPageStack(_ cards: [NSView]) -> NSView {
        let view = MD3SettingsPageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }
        
        let stack = NSStackView(views: cards)
        stack.orientation = .vertical
        stack.spacing = 16
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20)
        ])
        
        cards.forEach { card in
            card.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            card.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
        
        return view
    }

    private func settingsPanel(title: String, views: [NSView]) -> NSView {
        let panel = MD3Panel()
        panel.type = .filled
        panel.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = MD3.onSurface
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(titleLabel)
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: panel.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -18)
        ])
        return panel
    }

    private func settingsButton(title: String, action: Selector, style: MD3Button.ButtonStyle = .filled) -> MD3Button {
        let button = MD3Button()
        button.title = title
        button.style = style
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        return button
    }

    private func settingsButtonGrid(_ buttons: [NSView]) -> NSView {
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.spacing = 10
        grid.alignment = .width
        grid.translatesAutoresizingMaskIntoConstraints = false

        for index in stride(from: 0, to: buttons.count, by: 2) {
            var rowViews = [buttons[index]]
            if index + 1 < buttons.count {
                rowViews.append(buttons[index + 1])
            } else {
                let spacer = NSView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                rowViews.append(spacer)
            }

            let row = NSStackView(views: rowViews)
            row.orientation = .horizontal
            row.spacing = 12
            row.distribution = .fillEqually
            row.alignment = .centerY
            row.translatesAutoresizingMaskIntoConstraints = false
            grid.addArrangedSubview(row)

            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: grid.trailingAnchor)
            ])
        }

        grid.widthAnchor.constraint(equalToConstant: 520).isActive = true
        return grid
    }

    private func metricCard(title: String, value: String, detail: String) -> NSView {
        let view = MD3Panel()
        view.type = .elevated
        view.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.textColor = MD3.onSurfaceVariant
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak titleLabel] in
            titleLabel?.textColor = MD3.onSurfaceVariant
        }

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.textColor = MD3.primary
        valueLabel.font = .systemFont(ofSize: 28, weight: .bold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak valueLabel] in
            valueLabel?.textColor = MD3.primary
        }

        let detailLabel = NSTextField(labelWithString: detail)
        detailsTextConfig(detailLabel)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak detailLabel] in
            detailLabel?.textColor = MD3.onSurfaceVariant
        }

        view.addSubview(titleLabel)
        view.addSubview(valueLabel)
        view.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            detailLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 6)
        ])

        return view
    }

    private func setupRuleSetURLFields() {
        let fields = [
            (ruleSetPrivateURLField, TungBoxConfig.ruleSetPrivate),
            (ruleSetCNURLField, TungBoxConfig.ruleSetCN),
            (ruleSetGeoIPCNURLField, TungBoxConfig.ruleSetGeoIPCN),
            (ruleSetGeolocationNotCNURLField, TungBoxConfig.ruleSetGeolocationNotCN)
        ]
        for (field, tag) in fields {
            field.stringValue = TungBoxConfig.ruleSetURL(for: tag)
            field.placeholderString = TungBoxConfig.defaultRuleSetURLs[tag]
            field.translatesAutoresizingMaskIntoConstraints = false
            field.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }
    }

    private func settingsLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = MD3.onSurfaceVariant
        label.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak label] in
            label?.textColor = MD3.onSurfaceVariant
        }
        return label
    }

    private func populateRuleTypePopup() {
        let current = customRuleTypePopup.titleOfSelectedItem
        customRuleTypePopup.removeAllItems()
        let sections = [
            ["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-WILDCARD", "DOMAIN-REGEX", "RULE-SET"],
            ["IP-CIDR", "IP-CIDR6", "GEOIP", "IP-ASN", "SRC-IP"],
            ["PROCESS-NAME", "USER-AGENT", "URL-REGEX"],
            ["IN-PORT", "DEST-PORT", "PROTOCOL", "NETWORK"]
        ]
        for (index, section) in sections.enumerated() {
            if index > 0 {
                customRuleTypePopup.menu?.addItem(.separator())
            }
            customRuleTypePopup.addItems(withTitles: section)
        }
        if let current, popup(customRuleTypePopup, contains: current) {
            customRuleTypePopup.selectItem(withTitle: current)
        }
    }

    private func populateRuleStrategyPopup() {
        let current = customRuleStrategyPopup.titleOfSelectedItem
        customRuleStrategyPopup.removeAllItems()
        customRuleStrategyPopup.addItems(withTitles: ["DIRECT", "REJECT"])
        customRuleStrategyPopup.menu?.addItem(.separator())
        customRuleStrategyPopup.addItems(withTitles: ["Proxy", "AUTO"])
        let nodeTags = nodes.map(\.tag).filter { !$0.isEmpty }
        if !nodeTags.isEmpty {
            customRuleStrategyPopup.menu?.addItem(.separator())
            customRuleStrategyPopup.addItems(withTitles: nodeTags)
        }
        if let current, popup(customRuleStrategyPopup, contains: current) {
            customRuleStrategyPopup.selectItem(withTitle: current)
        } else {
            customRuleStrategyPopup.selectItem(withTitle: "Proxy")
        }
    }

    private func popup(_ popup: NSPopUpButton, contains title: String) -> Bool {
        popup.itemArray.contains { $0.title == title }
    }

    private func detailsTextConfig(_ label: NSTextField) {
        label.textColor = MD3.onSurfaceVariant
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
    }

    private func homeCard(title: String, titleAccessoryView: NSView? = nil, views: [NSView]) -> NSView {
        let panel = MD3Panel()
        panel.type = .elevated
        panel.translatesAutoresizingMaskIntoConstraints = false
        
        let titleStack = NSStackView()
        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 8
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = MD3.onSurface
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak titleLabel] in
            titleLabel?.textColor = MD3.onSurface
        }
        titleStack.addArrangedSubview(titleLabel)
        
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
            titleStack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            titleStack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 20),
            titleStack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),
            titleStack.heightAnchor.constraint(equalToConstant: 28),
            
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: titleStack.bottomAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -20)
        ])

        views.forEach { subview in
            subview.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            subview.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
        return panel
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == subscriptionTable { return subscriptions.count }
        if tableView == nodeTable { return nodes.count }
        if tableView == rulesTable { return filteredRuleRows().count }
        if tableView == connectionsTable { return connections.count }
        return profiles.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == subscriptionTable {
            let identifier = NSUserInterfaceItemIdentifier("SubCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? MD3SubscriptionCellView ?? MD3SubscriptionCellView(frame: .zero)
            cell.identifier = identifier
            cell.configure(with: subscriptions[row], selected: tableView.selectedRow == row)
            return cell
        } else if tableView == nodeTable {
            let identifier = NSUserInterfaceItemIdentifier("NodeCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? MD3NodeCellView ?? MD3NodeCellView(frame: .zero)
            cell.identifier = identifier
            cell.configure(with: nodes[row])
            return cell
        } else if tableView == rulesTable {
            let rows = filteredRuleRows()
            guard rows.indices.contains(row), let columnID = tableColumn?.identifier.rawValue else { return nil }
            return makeRuleCell(for: rows[row], columnID: columnID)
        } else if tableView == connectionsTable {
            guard connections.indices.contains(row), let columnID = tableColumn?.identifier.rawValue else { return nil }
            return makeConnectionCell(for: connections[row], columnID: columnID)
        } else {
            let identifier = NSUserInterfaceItemIdentifier("ProfileCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? MD3ProfileCellView ?? MD3ProfileCellView(frame: .zero)
            cell.identifier = identifier
            cell.configure(with: profiles[row], isSelected: tableView.selectedRow == row)
            return cell
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return MD3TableRowView()
    }

    private func makeRuleCell(for rule: RuleInfo, columnID: String) -> NSView {
        if columnID == "enabled" && !rule.isSection {
            let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            button.state = rule.enabled ? .on : .off
            button.isEnabled = false
            button.translatesAutoresizingMaskIntoConstraints = false
            let container = NSView()
            container.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            return container
        }

        let text: String
        switch columnID {
        case "enabled": text = rule.isSection ? "#" : ""
        case "id": text = rule.id
        case "type": text = rule.type
        case "value": text = rule.value
        case "strategy": text = rule.strategy
        case "count": text = rule.count
        case "note": text = rule.note
        default: text = ""
        }

        let label = NSTextField(labelWithString: text)
        label.font = rule.isSection ? .systemFont(ofSize: 13, weight: .bold) : .systemFont(ofSize: 13)
        label.textColor = rule.isSection ? MD3.onSurfaceVariant : MD3.onSurface
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
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

    private func makeConnectionCell(for connection: ConnectionInfo, columnID: String) -> NSView {
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

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        if tableView == table {
            if tableView.selectedRow >= 0 {
                selectProfile(at: tableView.selectedRow)
            }
        } else if tableView == subscriptionTable {
            if tableView.selectedRow >= 0 {
                selectedSubscriptionIndex = tableView.selectedRow
                let subscription = subscriptions[tableView.selectedRow]
                subscriptionNameField.stringValue = subscription.name
                subscriptionURLField.stringValue = subscription.url
                
                // Load associated profile
                if let profileID = subscription.profileID,
                   let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) {
                    selectProfile(at: profileIndex)
                } else {
                    nodes = []
                    nodeTable.reloadData()
                }
            }
        } else if tableView == nodeTable {
            if tableView.selectedRow >= 0 {
                let selectedNode = nodes[tableView.selectedRow]
                if let config = parseConfigObject(from: editor.string),
                   let outbounds = config["outbounds"] as? [[String: Any]],
                   let selector = outbounds.first(where: { $0["tag"] as? String == "节点选择" }),
                   let defNode = selector["default"] as? String,
                   defNode == selectedNode.tag {
                    return
                }
                selectNode(at: tableView.selectedRow)
            }
        }
    }

    @objc private func trafficPeriodChanged() {
        updateTrafficLabels()
    }

    private func getTodayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func recordTraffic(upload: Int, download: Int) {
        let today = getTodayKey()
        var history = UserDefaults.standard.dictionary(forKey: "tungbox_traffic_history") as? [String: [String: Int]] ?? [:]
        var todayTraffic = history[today] ?? ["upload": 0, "download": 0]
        todayTraffic["upload"] = (todayTraffic["upload"] ?? 0) + upload
        todayTraffic["download"] = (todayTraffic["download"] ?? 0) + download
        history[today] = todayTraffic
        UserDefaults.standard.set(history, forKey: "tungbox_traffic_history")
    }

    private func getTrafficSum(days: Int) -> (upload: Int, download: Int) {
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
                    totalUp += dayData["upload"] ?? 0
                    totalDown += dayData["download"] ?? 0
                }
            }
        }
        return (totalUp, totalDown)
    }

    private func updateTrafficLabels() {
        let up: Int
        let down: Int
        switch trafficPeriodControl.selectedSegment {
        case 0: // 今日
            let sum = getTrafficSum(days: 1)
            up = sum.upload
            down = sum.download
        case 1: // 近7天
            let sum = getTrafficSum(days: 7)
            up = sum.upload
            down = sum.download
        case 2: // 近30天
            let sum = getTrafficSum(days: 30)
            up = sum.upload
            down = sum.download
        default:
            up = totalUploadBytes
            down = totalDownloadBytes
        }
        
        let total = up + down
        trafficStatsValueLabel.stringValue = formatBytes(total)
        trafficStatsDetailLabel.stringValue = "上传: \(formatBytes(up))   下载: \(formatBytes(down))"
    }

    @objc private func navClicked(_ sender: MD3SidebarItem) {
        selectPage(at: sender.tag)
    }

    private func selectPage(at index: Int) {
        guard index >= 0, index < pages.numberOfTabViewItems else { return }
        pages.selectTabViewItem(at: index)
        for button in navButtons {
            button.isSelected = (button.tag == index)
        }
        if index == 6 {
            checkSingBoxInstall(showAlert: false)
        }
        window?.contentView?.refreshSubviews()
    }

    @objc private func toggleThemeClicked() {
        MD3.isDark.toggle()
        NSApp.appearance = NSAppearance(named: MD3.isDark ? .darkAqua : .aqua)
        notifyThemeChanged()
        appendLog("[TungBox] 已切换到\(MD3.isDark ? "深色" : "浅色")外观\n")
    }

    @objc private func openFolderClicked() {
        NSWorkspace.shared.open(store.baseURL)
    }

    @objc private func openCoreFolderClicked() {
        NSWorkspace.shared.open(store.coreURL)
    }

    @objc private func importCoreClicked() {
        let panel = NSOpenPanel()
        panel.title = "选择 sing-box Core"
        panel.message = "请选择 sing-box 或 singbox 可执行文件。TungBox 会复制一份到自己的 Core 目录。"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let source = panel.url {
            do {
                if FileManager.default.fileExists(atPath: store.coreBinaryURL.path) {
                    try FileManager.default.removeItem(at: store.coreBinaryURL)
                }
                try FileManager.default.copyItem(at: source, to: store.coreBinaryURL)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.coreBinaryURL.path)
                appendLog("[Core] 已导入 sing-box Core：\(store.coreBinaryURL.path)\n")
                checkSingBoxInstall(showAlert: true)
            } catch {
                showError(NSError.user("导入 sing-box Core 失败：\(error.localizedDescription)"))
            }
        }
    }

    @objc private func checkCoreUpdateClicked() {
        serviceLabel.stringValue = "sing-box Core：正在检查更新..."
        Task {
            do {
                let release = try await CoreUpdater.latestStableRelease()
                await MainActor.run { [weak self] in
                    self?.handleCoreUpdateCheck(release)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.serviceLabel.stringValue = "sing-box Core：检查更新失败\n\(error.localizedDescription)"
                    self?.showToast("Core 更新检查失败")
                    self?.showError(error)
                }
            }
        }
    }

    @objc private func installLatestCoreClicked() {
        serviceLabel.stringValue = "sing-box Core：正在准备安装最新版本..."
        Task {
            do {
                let release = try await CoreUpdater.latestStableRelease()
                await MainActor.run { [weak self] in
                    self?.installCoreRelease(release, reason: "最新版本")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.serviceLabel.stringValue = "sing-box Core：获取最新版本失败\n\(error.localizedDescription)"
                    self?.showToast("获取 Core 最新版本失败")
                    self?.showError(error)
                }
            }
        }
    }

    @objc private func installOldCoreForTestClicked() {
        serviceLabel.stringValue = "sing-box Core：正在准备安装测试旧版..."
        Task {
            do {
                let release = try await CoreUpdater.release(version: CoreUpdater.testOldVersion)
                await MainActor.run { [weak self] in
                    self?.installCoreRelease(release, reason: "测试旧版")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.serviceLabel.stringValue = "sing-box Core：获取测试旧版失败\n\(error.localizedDescription)"
                    self?.showToast("获取测试旧版 Core 失败")
                    self?.showError(error)
                }
            }
        }
    }

    private func handleCoreUpdateCheck(_ release: CoreRelease) {
        let current = runner.installedVersionNumber()
        if let current, Runner.compareVersions(current, release.version) != .orderedAscending {
            serviceLabel.stringValue = """
            sing-box Core：已是最新
            当前版本：\(current)
            最新版本：\(release.version)
            """
            showToast("Core 已是最新版：\(release.version)")
            appendLog("[Core] 已是最新版：\(release.version)\n")
            return
        }

        let currentText = current ?? "未安装"
        serviceLabel.stringValue = """
        sing-box Core：发现可更新版本
        当前版本：\(currentText)
        最新版本：\(release.version)
        """
        showToast("发现 Core 更新：\(currentText) → \(release.version)")

        let alert = NSAlert()
        alert.messageText = "发现 sing-box Core 更新"
        alert.informativeText = "当前版本：\(currentText)\n最新版本：\(release.version)\n是否现在安装？"
        alert.addButton(withTitle: "安装")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            installCoreRelease(release, reason: "更新")
        }
    }

    private func installCoreRelease(_ release: CoreRelease, reason: String) {
        guard !isProxyRuntimeRunning() else {
            showToast("请先关闭代理服务，再更新 Core")
            showError(NSError.user("请先关闭代理服务，再更新 sing-box Core。"))
            return
        }

        serviceLabel.stringValue = "sing-box Core：正在安装 \(release.version)..."
        appendLog("[Core] 开始安装 \(reason)：\(release.version)\n")
        let coreBinaryURL = store.coreBinaryURL

        Task {
            do {
                try await CoreUpdater.install(release, to: coreBinaryURL)
                await MainActor.run { [weak self] in
                    self?.appendLog("[Core] 已安装 \(release.version) 到 \(coreBinaryURL.path)\n")
                    self?.checkSingBoxInstall(showAlert: false)
                    self?.showToast("Core 已安装：\(release.version)")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.serviceLabel.stringValue = "sing-box Core：安装失败\n\(error.localizedDescription)"
                    self?.showToast("Core 安装失败")
                    self?.showError(error)
                }
            }
        }
    }

    @objc private func settingsSystemProxyChanged(_ sender: NSButton) {
        isSystemProxyEnabled = sender.state == .on
        if !isSystemProxyEnabled, isTunEnabled {
            isTunEnabled = false
            UserDefaults.standard.set(false, forKey: "tunEnabled")
            tunSwitch.isOn = false
        }
        UserDefaults.standard.set(isSystemProxyEnabled, forKey: "systemProxyEnabled")
        syncProxyPreferenceControls()
        if isProxyRuntimeRunning() {
            if isSystemProxyEnabled {
                if isTunEnabled {
                    do {
                        try applyTunPreference(restartIfRunning: false)
                    } catch {
                        showError(error)
                    }
                } else {
                    setSystemProxy(enabled: true, port: getMixedProxyPort())
                }
            } else {
                stopService()
            }
        }
        appendLog("[设置] 系统代理默认值已\(isSystemProxyEnabled ? "开启" : "关闭")\n")
        refreshStatus()
    }

    @objc private func settingsTunChanged(_ sender: NSButton) {
        guard isSystemProxyEnabled else {
            sender.state = .off
            showError(NSError.user("请先开启“默认开启系统代理”，再启用 TUN 默认开启。"))
            return
        }
        if sender.state == .on, !TunServiceManager.status(store: store).isInstalled {
            sender.state = .off
            showToast("请先安装 TUN 服务")
            showError(NSError.user("请先到 设置 > TUN 设置 安装 TUN 服务。"))
            return
        }
        isTunEnabled = sender.state == .on
        UserDefaults.standard.set(isTunEnabled, forKey: "tunEnabled")
        tunSwitch.isOn = isTunEnabled
        syncProxyPreferenceControls()
        do {
            if isProxyRuntimeRunning() {
                try applyTunPreference(restartIfRunning: false)
            }
            reconcileSystemProxyForCurrentMode()
            appendLog("[设置] 随代理开启 TUN 已\(isTunEnabled ? "开启" : "关闭")\n")
        } catch {
            isTunEnabled.toggle()
            UserDefaults.standard.set(isTunEnabled, forKey: "tunEnabled")
            sender.state = isTunEnabled ? .on : .off
            tunSwitch.isOn = isTunEnabled
            syncProxyPreferenceControls()
            showError(error)
        }
        refreshStatus()
    }

    @objc private func installTunServiceClicked() {
        do {
            try TunServiceManager.install(store: store)
            appendLog("[TUN] TUN 服务已安装\n")
            showToast("TUN 服务已安装")
            checkSingBoxInstall(showAlert: false)
            refreshTunServiceStatus()
            refreshStatus()
        } catch {
            tunServiceLogLabel.stringValue = "最近状态：安装失败\n\(error.localizedDescription)"
            showError(error)
        }
    }

    @objc private func uninstallTunServiceClicked() {
        do {
            isTunEnabled = false
            UserDefaults.standard.set(false, forKey: "tunEnabled")
            try TunServiceManager.uninstall(store: store)
            appendLog("[TUN] TUN 服务已卸载\n")
            showToast("TUN 服务已卸载")
            syncProxyPreferenceControls()
            refreshTunServiceStatus()
            refreshStatus()
        } catch {
            tunServiceLogLabel.stringValue = "最近状态：卸载失败\n\(error.localizedDescription)"
            showError(error)
        }
    }

    @objc private func openTunLogClicked() {
        if FileManager.default.fileExists(atPath: TunServiceManager.logURL.path) {
            NSWorkspace.shared.open(TunServiceManager.logURL)
        } else {
            showToast("暂无 TUN 日志")
        }
    }

    private func syncProxyPreferenceControls() {
        serviceSwitch.isOn = isProxyRuntimeRunning() && isSystemProxyEnabled
        tunSwitch.isOn = isTunEnabled
        tunSwitch.isEnabled = isSystemProxyEnabled || isProxyRuntimeRunning()
        settingsSystemProxyCheckbox.state = isSystemProxyEnabled ? .on : .off
        settingsTunCheckbox.state = isTunEnabled ? .on : .off
        settingsTunCheckbox.isEnabled = isSystemProxyEnabled
        refreshTunServiceStatus()
    }

    private func reconcileSystemProxyForCurrentMode() {
        guard isProxyRuntimeRunning() else { return }
        if isTunEnabled {
            setSystemProxy(enabled: false, port: getMixedProxyPort())
        } else {
            setSystemProxy(enabled: isSystemProxyEnabled, port: getMixedProxyPort())
        }
    }

    private func isProxyRuntimeRunning() -> Bool {
        runner.isRunning || TunServiceManager.status(store: store).isRunning
    }

    private func currentProxyPID() -> Int32? {
        runner.pid ?? TunServiceManager.activeSingBoxPID(store: store)
    }

    private func refreshTunServiceStatus() {
        let status = TunServiceManager.status(store: store)
        tunServiceStatusLabel.stringValue = "TUN 服务状态：\(status.displayText)"
        if FileManager.default.fileExists(atPath: TunServiceManager.logURL.path),
           let text = try? String(contentsOf: TunServiceManager.logURL, encoding: .utf8) {
            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            tunServiceLogLabel.stringValue = "最近状态：\(lines.suffix(3).joined(separator: "\n"))"
        } else {
            tunServiceLogLabel.stringValue = "最近状态：暂无日志"
        }
    }

    @objc private func showLogsFromHomeClicked() {
        selectPage(at: 5)
    }

    private func changeColorScheme(to index: Int) {
        MD3.currentSchemeIndex = index
        for row in colorSchemeRows {
            row.isSelected = (row.index == index)
        }
        notifyThemeChanged()
        appendLog("[TungBox] 已切换配色方案为: \(MD3.colorSchemes[index].name)\n")
    }

    @objc private func tableClicked() {
        guard table.selectedRow >= 0 else { return }
        selectProfile(at: table.selectedRow)
    }

    @objc private func subscriptionTableClicked() {
        guard subscriptionTable.selectedRow >= 0 else { return }
        selectedSubscriptionIndex = subscriptionTable.selectedRow
        let subscription = subscriptions[subscriptionTable.selectedRow]
        
        // Load associated profile
        if let profileID = subscription.profileID,
           let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) {
            selectProfile(at: profileIndex)
        } else {
            nodes = []
            nodeTable.reloadData()
        }
    }

    @objc private func newClicked() {
        let name = "配置 \(profiles.count + 1)"
        createProfile(named: name, content: defaultConfig())
    }

    @objc private func importClicked() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url) {
            createProfile(named: url.deletingPathExtension().lastPathComponent, content: text)
        }
    }

    @objc private func deleteClicked() {
        guard let index = selectedIndex else { return }
        let profile = profiles[index]
        try? FileManager.default.removeItem(at: store.configURL(for: profile))
        profiles.remove(at: index)
        store.saveProfiles(profiles)
        table.reloadData()
        selectedIndex = nil
        editor.string = ""
        if !profiles.isEmpty { selectProfile(at: min(index, profiles.count - 1)) }
    }

    @discardableResult
    @MainActor
    private func showMD3Dialog(
        title: String,
        message: String,
        customView: NSView?,
        confirmTitle: String = "确定",
        cancelTitle: String = "取消"
    ) -> MD3Dialog {
        guard let contentView = window?.contentView else { fatalError("No content view") }
        let dialog = MD3Dialog(
            title: title,
            message: message,
            customView: customView,
            confirmTitle: confirmTitle,
            cancelTitle: cancelTitle
        )
        dialog.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dialog)
        
        NSLayoutConstraint.activate([
            dialog.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dialog.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dialog.topAnchor.constraint(equalTo: contentView.topAnchor),
            dialog.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        dialog.present()
        return dialog
    }

    @objc private func addSubscriptionClicked() {
        let nameField = MD3TextField()
        nameField.placeholderString = "订阅名称 (如: Xboard)"
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 432).isActive = true
        nameField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let urlField = MD3TextField()
        urlField.placeholderString = "https://..."
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.widthAnchor.constraint(equalToConstant: 432).isActive = true
        urlField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let stack = NSStackView(views: [nameField, urlField])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 432),
            container.heightAnchor.constraint(equalToConstant: 84)
        ])

        let dialog = showMD3Dialog(
            title: "添加订阅",
            message: "请输入新订阅的名称和配置 URL。",
            customView: container
        )
        
        dialog.window?.initialFirstResponder = nameField
        
        dialog.onConfirm = { [weak self, weak nameField, weak urlField, weak dialog] in
            guard let self = self else { return }
            let name = nameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = urlField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            guard !name.isEmpty else {
                self.showError(NSError.user("订阅名称不能为空"))
                return
            }
            guard !url.isEmpty else {
                self.showError(NSError.user("订阅 URL 不能为空"))
                return
            }

            let subscription = Subscription(
                id: UUID(),
                name: name,
                url: url,
                profileID: nil,
                updatedAt: nil
            )
            self.subscriptions.append(subscription)
            self.store.saveSubscriptions(self.subscriptions)
            self.subscriptionTable.reloadData()
            self.selectedSubscriptionIndex = self.subscriptions.count - 1
            self.subscriptionTable.selectRowIndexes(IndexSet(integer: self.subscriptions.count - 1), byExtendingSelection: false)
            self.refreshSubscription(at: self.subscriptions.count - 1)
            dialog?.dismiss()
        }
        
        dialog.onCancel = { [weak dialog] in
            dialog?.dismiss()
        }
    }

    @objc private func updateSubscriptionClicked() {
        guard let index = selectedSubscriptionIndex, subscriptions.indices.contains(index) else {
            showError(NSError.user("请先选择一个订阅"))
            return
        }
        let subscription = subscriptions[index]

        let nameField = MD3TextField()
        nameField.stringValue = subscription.name
        nameField.placeholderString = "订阅名称"
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 432).isActive = true
        nameField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let urlField = MD3TextField()
        urlField.stringValue = subscription.url
        urlField.placeholderString = "https://..."
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.widthAnchor.constraint(equalToConstant: 432).isActive = true
        urlField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let stack = NSStackView(views: [nameField, urlField])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 432),
            container.heightAnchor.constraint(equalToConstant: 84)
        ])

        let dialog = showMD3Dialog(
            title: "编辑订阅",
            message: "请修改订阅的名称或配置 URL。",
            customView: container
        )
        
        dialog.window?.initialFirstResponder = nameField
        
        dialog.onConfirm = { [weak self, weak nameField, weak urlField, weak dialog] in
            guard let self = self else { return }
            let name = nameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = urlField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            guard !name.isEmpty else {
                self.showError(NSError.user("订阅名称不能为空"))
                return
            }
            guard !url.isEmpty else {
                self.showError(NSError.user("订阅 URL 不能为空"))
                return
            }

            self.subscriptions[index] = Subscription(
                id: subscription.id,
                name: name,
                url: url,
                profileID: subscription.profileID,
                updatedAt: subscription.updatedAt
            )
            self.store.saveSubscriptions(self.subscriptions)
            self.subscriptionTable.reloadData()
            self.refreshSubscription(at: index)
            dialog?.dismiss()
        }
        
        dialog.onCancel = { [weak dialog] in
            dialog?.dismiss()
        }
    }

    @objc private func deleteSubscriptionClicked() {
        guard let index = selectedSubscriptionIndex, subscriptions.indices.contains(index) else { return }
        subscriptions.remove(at: index)
        selectedSubscriptionIndex = nil
        store.saveSubscriptions(subscriptions)
        subscriptionTable.reloadData()
    }

    @objc private func refreshNodesClicked() {
        refreshNodesFromEditor()
    }

    @objc private func refreshRulesClicked() {
        refreshRulesFromEditor()
    }

    @objc private func showAddCustomRuleDialog() {
        populateRuleTypePopup()
        populateRuleStrategyPopup()
        customRuleValueField.stringValue = ""
        customRuleNoteField.stringValue = ""

        let typeLabel = settingsLabel("规则类型")
        let valueLabel = settingsLabel("值")
        let strategyLabel = settingsLabel("使用策略")
        let noteLabel = settingsLabel("备注")

        customRuleTypePopup.translatesAutoresizingMaskIntoConstraints = false
        customRuleTypePopup.heightAnchor.constraint(equalToConstant: 36).isActive = true
        customRuleStrategyPopup.translatesAutoresizingMaskIntoConstraints = false
        customRuleStrategyPopup.heightAnchor.constraint(equalToConstant: 36).isActive = true
        customRuleValueField.placeholderString = "example.com"
        customRuleValueField.translatesAutoresizingMaskIntoConstraints = false
        customRuleValueField.heightAnchor.constraint(equalToConstant: 36).isActive = true
        customRuleNoteField.placeholderString = "可选"
        customRuleNoteField.translatesAutoresizingMaskIntoConstraints = false
        customRuleNoteField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let grid = NSGridView(views: [
            [typeLabel, customRuleTypePopup],
            [valueLabel, customRuleValueField],
            [strategyLabel, customRuleStrategyPopup],
            [noteLabel, customRuleNoteField]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 340
        grid.rowSpacing = 12
        grid.columnSpacing = 12

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            grid.topAnchor.constraint(equalTo: container.topAnchor),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 432),
            container.heightAnchor.constraint(equalToConstant: 180)
        ])

        let dialog = showMD3Dialog(
            title: "新建标准规则",
            message: "自定义规则会按当前订阅单独保存，并在刷新订阅后自动合并。",
            customView: container,
            confirmTitle: "添加"
        )
        
        dialog.window?.initialFirstResponder = customRuleValueField
        
        dialog.onConfirm = { [weak self, weak dialog] in
            self?.addCustomRuleFromDialog()
            dialog?.dismiss()
        }
        
        dialog.onCancel = { [weak dialog] in
            dialog?.dismiss()
        }
    }

    private func addCustomRuleFromDialog() {
        do {
            let value = customRuleValueField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                throw NSError.user("请输入规则值")
            }
            guard let subscription = currentSubscription() else {
                throw NSError.user("请先选择一个订阅。自定义规则会按订阅单独保存。")
            }

            let type = customRuleTypePopup.titleOfSelectedItem ?? "DOMAIN"
            let strategy = customRuleStrategyPopup.titleOfSelectedItem ?? "Proxy"
            let note = customRuleNoteField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let newRule = CustomRule(
                id: UUID(),
                subscriptionID: subscription.id,
                type: type,
                value: value,
                strategy: strategy,
                note: note,
                enabled: true,
                createdAt: Date()
            )
            let previous = editor.string
            customRules.append(newRule)
            store.saveCustomRules(customRules)
            editor.string = try renderConfig(try applyCustomRules(to: previous, subscriptionID: subscription.id))
            let url = try saveCurrent()
            do {
                _ = try runner.check(config: url)
            } catch {
                customRules.removeAll { $0.id == newRule.id }
                store.saveCustomRules(customRules)
                editor.string = previous
                _ = try? saveCurrent()
                throw error
            }

            customRuleValueField.stringValue = ""
            customRuleNoteField.stringValue = ""
            appendLog("[规则] 已添加 \(type) \(value) -> \(strategy)\(note.isEmpty ? "" : "，备注：\(note)")\n")
            refreshRulesFromEditor()
        } catch {
            showError(error)
        }
    }

    @objc private func deleteCustomRuleClicked() {
        do {
            let rows = filteredRuleRows()
            let row = rulesTable.selectedRow
            guard rows.indices.contains(row), let ruleID = rows[row].customRuleID else {
                throw NSError.user("请先选中一条自定义规则")
            }
            guard let subscription = currentSubscription() else {
                throw NSError.user("请先选择一个订阅")
            }
            guard let deletedRule = customRules.first(where: { $0.id == ruleID }) else {
                throw NSError.user("没有找到选中的自定义规则")
            }
            let previousRules = customRules
            let previousConfig = editor.string
            customRules.removeAll { $0.id == ruleID }
            store.saveCustomRules(customRules)
            let configWithoutDeletedRule = try removeCustomRule(deletedRule, from: previousConfig)
            editor.string = try renderConfig(try applyCustomRules(to: configWithoutDeletedRule, subscriptionID: subscription.id))
            let url = try saveCurrent()
            do {
                _ = try runner.check(config: url)
            } catch {
                customRules = previousRules
                store.saveCustomRules(customRules)
                editor.string = previousConfig
                _ = try? saveCurrent()
                throw error
            }
            appendLog("[规则] 已删除选中的自定义规则\n")
            refreshRulesFromEditor()
        } catch {
            showError(error)
        }
    }

    private func testGroupNodes(_ group: NodeGroupInfo) {
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

    @objc private func groupTestClicked(_ sender: NSButton) {
        guard let groupTag = groupTestActions[sender.tag],
              let group = nodeGroups.first(where: { $0.tag == groupTag }) else { return }
        testGroupNodes(group)
    }

    private func testSingleNode(tag: String) {
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

    @objc private func testAllNodesClicked() {
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

    @objc private func testAllNodesTCPClicked() {
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

    @objc private func modeChanged() {
        nodesModeControl.selectedSegment = modeControl.selectedSegment
        do {
            try applySelectedMode()
        } catch {
            refreshModeFromEditor()
            showError(error)
        }
    }

    @objc private func nodesModeChanged() {
        modeControl.selectedSegment = nodesModeControl.selectedSegment
        do {
            try applySelectedMode()
        } catch {
            refreshModeFromEditor()
            showError(error)
        }
    }

    @objc private func nodeTileClicked(_ sender: NSButton) {
        guard let action = nodeTileActions[sender.tag] else { return }
        selectNode(action.node, inGroup: action.group)
    }

    @objc private func saveClicked() {
        do {
            try saveCurrent()
            appendLog("[TungBox] 已保存\n")
        } catch {
            showError(error)
        }
    }

    @objc private func saveRuleSetURLsClicked() {
        let values = [
            (TungBoxConfig.ruleSetPrivate, ruleSetPrivateURLField.stringValue),
            (TungBoxConfig.ruleSetCN, ruleSetCNURLField.stringValue),
            (TungBoxConfig.ruleSetGeoIPCN, ruleSetGeoIPCNURLField.stringValue),
            (TungBoxConfig.ruleSetGeolocationNotCN, ruleSetGeolocationNotCNURLField.stringValue)
        ]
        for (tag, value) in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty || URL(string: trimmed) != nil else {
                showError(NSError.user("\(tag) 不是有效 URL"))
                return
            }
            TungBoxConfig.setRuleSetURL(trimmed, for: tag)
        }
        setupRuleSetURLFields()
        appendLog("[规则集] 已保存规则集获取地址。留空时使用订阅地址；订阅没有时使用内置默认地址。\n")
    }



    @objc private func switchToggled(_ sender: MD3Switch) {
        if sender.isOn {
            isSystemProxyEnabled = true
            UserDefaults.standard.set(true, forKey: "systemProxyEnabled")
            syncProxyPreferenceControls()
            startService()
        } else {
            isSystemProxyEnabled = false
            if isTunEnabled {
                isTunEnabled = false
                UserDefaults.standard.set(false, forKey: "tunEnabled")
            }
            UserDefaults.standard.set(false, forKey: "systemProxyEnabled")
            syncProxyPreferenceControls()
            stopService()
        }
    }

    @objc private func tunSwitchToggled(_ sender: MD3Switch) {
        guard !sender.isOn || isSystemProxyEnabled else {
            sender.isOn = false
            showError(NSError.user("请先开启系统代理，再启用 TUN 模式。"))
            return
        }
        if sender.isOn, !TunServiceManager.status(store: store).isInstalled {
            sender.isOn = false
            showToast("请先安装 TUN 服务")
            showError(NSError.user("TUN 服务未安装。请先到 设置 > TUN 设置 安装 TUN 服务。"))
            return
        }
        isTunEnabled = sender.isOn
        UserDefaults.standard.set(isTunEnabled, forKey: "tunEnabled")
        if isTunEnabled {
            isSystemProxyEnabled = true
            UserDefaults.standard.set(true, forKey: "systemProxyEnabled")
        }
        syncProxyPreferenceControls()
        do {
            if isTunEnabled && !isProxyRuntimeRunning() {
                startService()
                return
            }
            try applyTunPreference(restartIfRunning: false)
            reconcileSystemProxyForCurrentMode()
            appendLog("[首页] TUN 模式已\(isTunEnabled ? "开启" : "关闭")\n")
        } catch {
            isTunEnabled.toggle()
            UserDefaults.standard.set(isTunEnabled, forKey: "tunEnabled")
            tunSwitch.isOn = isTunEnabled
            syncProxyPreferenceControls()
            showError(error)
        }
        refreshStatus()
    }

    @objc private func toggleSystemProxyFromTray() {
        if !isProxyRuntimeRunning() {
            isSystemProxyEnabled = true
            UserDefaults.standard.set(isSystemProxyEnabled, forKey: "systemProxyEnabled")
            syncProxyPreferenceControls()
            startService()
            appendLog("[托盘] 启动代理服务并开启系统代理\n")
        } else {
            isSystemProxyEnabled = false
            UserDefaults.standard.set(isSystemProxyEnabled, forKey: "systemProxyEnabled")
            if isTunEnabled {
                isTunEnabled = false
                UserDefaults.standard.set(isTunEnabled, forKey: "tunEnabled")
            }
            syncProxyPreferenceControls()
            stopService()
            appendLog("[托盘] 已关闭系统代理和代理服务\n")
        }
        refreshStatus()
    }

    @objc private func toggleTunFromTray() {
        if !isTunEnabled && !isSystemProxyEnabled {
            isSystemProxyEnabled = true
            UserDefaults.standard.set(true, forKey: "systemProxyEnabled")
        }
        if !isTunEnabled, !TunServiceManager.status(store: store).isInstalled {
            showToast("请先安装 TUN 服务")
            showError(NSError.user("TUN 服务未安装。请先到 设置 > TUN 设置 安装 TUN 服务。"))
            return
        }
        isTunEnabled.toggle()
        UserDefaults.standard.set(isTunEnabled, forKey: "tunEnabled")
        syncProxyPreferenceControls()
        do {
            if isTunEnabled && !isProxyRuntimeRunning() {
                startService()
                return
            }
            try applyTunPreference(restartIfRunning: false)
            reconcileSystemProxyForCurrentMode()
            appendLog("[托盘] TUN 模式已\(isTunEnabled ? "开启" : "关闭")\n")
        } catch {
            isTunEnabled.toggle()
            UserDefaults.standard.set(isTunEnabled, forKey: "tunEnabled")
            syncProxyPreferenceControls()
            showError(error)
        }
        refreshStatus()
    }

    @objc private func showConsoleFromTray() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func modeFromTray(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        syncModeControls(mode: mode)
        do {
            try applySelectedMode()
        } catch {
            refreshModeFromEditor()
            showError(error)
        }
    }

    @objc private func proxyNodeFromTray(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let group = info["group"],
              let node = info["node"] else { return }
        selectNode(node, inGroup: group)
    }

    @objc private func quitFromTray() {
        stopServiceFromDelegate()
        NSApp.terminate(nil)
    }

    @objc private func refreshConnectionsClicked() {
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

    @objc private func closeAllConnectionsClicked() {
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

    @objc private func clearLogsClicked() {
        logs.string = ""
        refreshHomeFeatureStatus()
    }

    private func startService() {
        guard ensureCoreAvailableForStart() else {
            serviceSwitch.isOn = false
            return
        }
        guard selectedIndex != nil else {
            showError(NSError.user("没有检测到有效的配置文件，请先创建或导入配置。"))
            serviceSwitch.isOn = false
            return
        }
        guard !nodes.isEmpty else {
            showError(NSError.user("当前配置中没有检测到可用的节点。请先配置节点或更新订阅。"))
            serviceSwitch.isOn = false
            return
        }

        do {
            try applyTunPreference(restartIfRunning: false)
            let url = try saveCurrent()
            
            var currentNode = "默认"
            if let config = parseConfigObject(from: editor.string),
               let outbounds = config["outbounds"] as? [[String: Any]],
               let selector = outbounds.first(where: { $0["tag"] as? String == "节点选择" }),
               let defNode = selector["default"] as? String {
                currentNode = defNode
            } else if let firstNode = nodes.first {
                currentNode = firstNode.tag
            }

            appendLog("[TungBox] 正在启动代理服务...\n")
            appendLog("[TungBox] 当前连接节点: \(currentNode)\n")

            if isTunEnabled {
                try TunServiceManager.enable(store: store, configText: editor.string)
                appendLog("[TUN] 已交给 TUN 服务启动 sing-box\n")
                setSystemProxy(enabled: false, port: getMixedProxyPort())
                refreshStatus()
                return
            }
            try runner.start(config: url, elevated: false)
            appendLog("[TungBox] 已启动\n")
            
            let port = getMixedProxyPort()
            setSystemProxy(enabled: isSystemProxyEnabled && !isTunEnabled, port: port)
            
            refreshStatus()
        } catch {
            showError(error)
            serviceSwitch.isOn = false
        }
    }

    private func ensureCoreAvailableForStart() -> Bool {
        guard runner.findSingBox() != nil else {
            checkSingBoxInstall(showAlert: false)
            showToast("未检测到 sing-box Core")
            showError(NSError.user("未检测到 sing-box Core。请先在 设置 > 基础 > Core 管理 中安装或导入 Core。"))
            return false
        }
        checkSingBoxInstall(showAlert: false)
        return true
    }

    private func stopService() {
        try? TunServiceManager.disable(store: store)
        runner.stop()
        appendLog("[TungBox] 已停止\n")
        
        setSystemProxy(enabled: false, port: 7890)
        
        refreshStatus()
    }

    private func selectProfile(at index: Int, forceReload: Bool = false) {
        guard profiles.indices.contains(index) else { return }
        if !forceReload && selectedIndex == index {
            return
        }
        selectedIndex = index
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        let url = store.configURL(for: profiles[index])
        editor.string = (try? String(contentsOf: url)) ?? ""
        refreshNodesFromEditor()
        refreshModeFromEditor()
        refreshRulesFromEditor()
        selectCurrentNodeInTable()
    }

    private func createProfile(named name: String, content: String) {
        let profile = ConfigProfile(id: UUID(), name: name, fileName: "\(UUID().uuidString).json", updatedAt: Date())
        profiles.append(profile)
        try? content.write(to: store.configURL(for: profile), atomically: true, encoding: .utf8)
        store.saveProfiles(profiles)
        table.reloadData()
        selectProfile(at: profiles.count - 1)
    }

    private func subscriptionFromFields(existing: Subscription?) throws -> Subscription {
        let name = subscriptionNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = subscriptionURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw NSError.user("请输入订阅名称") }
        guard !url.isEmpty else { throw NSError.user("请输入订阅 URL") }
        return Subscription(
            id: existing?.id ?? UUID(),
            name: name,
            url: url,
            profileID: existing?.profileID,
            updatedAt: existing?.updatedAt
        )
    }

    private func refreshSubscription(at index: Int) {
        guard subscriptions.indices.contains(index) else { return }
        let subscription = subscriptions[index]
        appendLog("[订阅] 开始刷新 \(subscription.name)\n")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let content = try SubscriptionImporter.fetch(urlString: subscription.url)
                let config = try SubscriptionImporter.singBoxConfig(from: content, profileName: subscription.name)
                DispatchQueue.main.async {
                    self?.applySubscriptionConfig(config, at: index)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.appendLog("[订阅] \(subscription.name) 刷新失败：\(error.localizedDescription)\n")
                    self?.showError(error)
                }
            }
        }
    }

    private func startSubscriptionTimer() {
        subscriptionTimer?.invalidate()
        subscriptionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.subscriptions.isEmpty else { return }
                self.appendLog("[订阅] 自动刷新开始\n")
                self.subscriptionAutoStatusLabel.stringValue = "订阅自动刷新：正在刷新 \(self.subscriptions.count) 个订阅"
                for index in self.subscriptions.indices {
                    self.refreshSubscription(at: index)
                }
            }
        }
    }

    private func applySubscriptionConfig(_ config: String, at index: Int) {
        guard subscriptions.indices.contains(index) else { return }
        var subscription = subscriptions[index]
        let profileName = "订阅 - \(subscription.name)"
        let mergedConfig: String
        do {
            mergedConfig = try renderConfig(try applyCustomRules(to: config, subscriptionID: subscription.id))
        } catch {
            showError(error)
            return
        }

        if let profileID = subscription.profileID,
           let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) {
            profiles[profileIndex].name = profileName
            profiles[profileIndex].updatedAt = Date()
            try? mergedConfig.write(to: store.configURL(for: profiles[profileIndex]), atomically: true, encoding: .utf8)
            selectedIndex = profileIndex
        } else {
            let profile = ConfigProfile(id: UUID(), name: profileName, fileName: "\(UUID().uuidString).json", updatedAt: Date())
            profiles.append(profile)
            subscription.profileID = profile.id
            try? mergedConfig.write(to: store.configURL(for: profile), atomically: true, encoding: .utf8)
            selectedIndex = profiles.count - 1
        }

        subscription.updatedAt = Date()
        subscriptions[index] = subscription
        store.saveProfiles(profiles)
        store.saveSubscriptions(subscriptions)
        table.reloadData()
        subscriptionTable.reloadData()
        if let selectedIndex {
            selectProfile(at: selectedIndex, forceReload: true)
        }
        refreshNodesFromEditor()
        refreshHomeFeatureStatus()
        appendLog("[订阅] \(subscription.name) 已刷新并写入配置\n")
    }

    @discardableResult
    private func saveCurrent() throws -> URL {
        guard let index = selectedIndex else { throw NSError.user("请先选择一个配置") }
        let data = editor.string.data(using: .utf8) ?? Data()
        _ = try JSONSerialization.jsonObject(with: data)
        profiles[index].updatedAt = Date()
        let url = store.configURL(for: profiles[index])
        try editor.string.write(to: url, atomically: true, encoding: .utf8)
        store.saveProfiles(profiles)
        table.reloadData()
        refreshNodesFromEditor()
        refreshRulesFromEditor()
        return url
    }

    private func refreshNodesFromEditor() {
        nodes = parseNodes(from: editor.string)
        nodeGroups = parseNodeGroups(from: editor.string)
        nodeTable.reloadData()
        populateRuleStrategyPopup()
        refreshNodeGroupsView()
        selectCurrentNodeInTable()
    }

    private func refreshRulesFromEditor() {
        ruleRows = buildRuleRows(from: editor.string)
        rulesTable.reloadData()
        refreshRuleSetCachesIfNeeded()
    }

    private func selectNode(at index: Int) {
        guard nodes.indices.contains(index) else { return }
        selectNode(nodes[index].tag, inGroup: TungBoxConfig.tagManual)
    }

    private func selectNode(_ nodeTag: String, inGroup groupTag: String) {
        Task {
            var switchedByAPI = false
            if isProxyRuntimeRunning() {
                do {
                    try await ClashAPI.selectProxy(group: groupTag, node: nodeTag)
                    _ = try? await ClashAPI.closeConnections()
                    switchedByAPI = true
                    appendLog("[节点] \(groupTag) 已通过运行时 API 切换到: \(nodeTag)，并已断开旧连接\n")
                } catch {
                    appendLog("[节点] 运行时 API 切换失败，改用配置重启：\(error.localizedDescription)\n")
                }
            }
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                do {
                    guard var config = self.parseConfigObject(from: self.editor.string) else { return }
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
                        let url = try self.saveCurrent()
                        self.appendLog("[节点] \(groupTag) 已选择: \(nodeTag)\n")
                        if self.isProxyRuntimeRunning() && !switchedByAPI {
                            self.runner.stop()
                            if self.isTunEnabled {
                                try TunServiceManager.enable(store: self.store, configText: self.editor.string)
                            } else {
                                try self.runner.start(config: url, elevated: false)
                            }
                            self.appendLog("[节点] 服务已按新节点重启\n")
                            self.refreshStatus()
                        } else {
                            self.refreshStatus()
                        }
                    }
                } catch {
                    self.showError(error)
                }
            }
        }
    }


    private func applyTunPreference(restartIfRunning: Bool) throws {
        let wasRunning = isProxyRuntimeRunning()
        guard var config = parseConfigObject(from: editor.string) else {
            throw NSError.user("当前配置不是有效 JSON")
        }
        config = setTunEnabled(isTunEnabled, in: config)
        let mode = selectedMode()
        config = ensureModeSupport(in: config, mode: mode)
        editor.string = try renderConfig(config)
        let url = try saveCurrent()
        if restartIfRunning, wasRunning {
            if isTunEnabled {
                try TunServiceManager.enable(store: store, configText: editor.string)
                appendLog("[TUN] 已更新 TUN 服务配置\n")
            } else {
                try TunServiceManager.disable(store: store)
                runner.stop()
                try runner.start(config: url, elevated: false)
                appendLog("[TUN] 已关闭 TUN 并用普通代理重启\n")
            }
        } else if wasRunning {
            if isTunEnabled {
                try TunServiceManager.enable(store: store, configText: editor.string)
            } else {
                try TunServiceManager.disable(store: store)
            }
        }
    }

    private func setTunEnabled(_ enabled: Bool, in config: [String: Any]) -> [String: Any] {
        var config = config
        var inbounds = config["inbounds"] as? [[String: Any]] ?? []
        inbounds.removeAll { ($0["type"] as? String)?.lowercased() == "tun" }
        if enabled {
            inbounds.insert([
                "type": "tun",
                "tag": "tun-in",
                "interface_name": "tun0",
                "address": [
                    "172.19.0.1/30",
                    "fdfe:dcba:9876::1/126"
                ],
                "auto_route": true,
                "strict_route": true,
                "sniff": true
            ], at: 0)
        }
        config["inbounds"] = inbounds
        return config
    }

    private func selectCurrentNodeInTable() {
        guard let config = parseConfigObject(from: editor.string),
              let outbounds = config["outbounds"] as? [[String: Any]],
              let selector = outbounds.first(where: { $0["tag"] as? String == "节点选择" }),
              let defNode = selector["default"] as? String else {
            return
        }
        if let row = nodes.firstIndex(where: { $0.tag == defNode }) {
            nodeTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            nodeTable.scrollRowToVisible(row)
        }
    }

    private func parseNodes(from text: String) -> [NodeInfo] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outbounds = object["outbounds"] as? [[String: Any]] else { return [] }
        let hiddenTypes = Set(["direct", "block", "dns", "selector", "urltest", "url-test"])
        return outbounds.compactMap { outbound in
            let type = (outbound["type"] as? String) ?? "unknown"
            guard !hiddenTypes.contains(type.lowercased()) else { return nil }
            let tag = (outbound["tag"] as? String) ?? type
            let server = outbound["server"].map { "\($0)" } ?? ""
            let port = outbound["server_port"].map { ":\($0)" } ?? ""
            return NodeInfo(tag: tag, type: type, server: server + port, delay: "未测试", tcp: "未测试")
        }
    }

    private func parseNodeGroups(from text: String) -> [NodeGroupInfo] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outbounds = object["outbounds"] as? [[String: Any]] else { return [] }

        let nodeTags = parseNodes(from: text).map(\.tag)
        var groups: [NodeGroupInfo] = []
        for outbound in outbounds {
            let type = ((outbound["type"] as? String) ?? "").lowercased()
            guard ["selector", "urltest", "url-test", "fallback"].contains(type),
                  let tag = outbound["tag"] as? String else { continue }
            let members = outbound["outbounds"] as? [String] ?? []
            let current = (outbound["default"] as? String) ?? members.first ?? ""
            groups.append(NodeGroupInfo(tag: tag, type: type, members: members, current: current))
        }

        if groups.isEmpty, !nodeTags.isEmpty {
            groups.append(NodeGroupInfo(tag: TungBoxConfig.tagManual, type: "selector", members: nodeTags, current: nodeTags.first ?? ""))
        }
        return groups
    }

    private func filteredRuleRows() -> [RuleInfo] {
        let query = ruleSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return ruleRows }
        return ruleRows.filter { row in
            row.isSection ||
            row.type.lowercased().contains(query) ||
            row.value.lowercased().contains(query) ||
            row.strategy.lowercased().contains(query) ||
            row.note.lowercased().contains(query)
        }
    }

    private func currentSubscription() -> Subscription? {
        if let index = selectedSubscriptionIndex, subscriptions.indices.contains(index) {
            return subscriptions[index]
        }
        guard let selectedIndex, profiles.indices.contains(selectedIndex) else { return nil }
        let profileID = profiles[selectedIndex].id
        return subscriptions.first { $0.profileID == profileID }
    }

    private func currentRouteRuleSets() -> [[String: Any]] {
        guard let config = parseConfigObject(from: editor.string),
              let route = config["route"] as? [String: Any],
              let ruleSets = route["rule_set"] as? [[String: Any]] else { return [] }
        return ruleSets
    }

    private func refreshRuleSetCachesIfNeeded() {
        let ruleSets = currentRouteRuleSets()
        guard !ruleSets.isEmpty, let binary = runner.findSingBox() else { return }
        for ruleSet in ruleSets {
            guard let tag = ruleSet["tag"] as? String,
                  let urlText = ruleSet["url"] as? String,
                  let url = URL(string: urlText),
                  !ruleSetJSONURL(for: tag).path.isEmpty,
                  !FileManager.default.fileExists(atPath: ruleSetJSONURL(for: tag).path),
                  !ruleSetDownloads.contains(tag) else { continue }
            ruleSetDownloads.insert(tag)
            let srsURL = ruleSetSRSURL(for: tag)
            let jsonURL = ruleSetJSONURL(for: tag)
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.downloadAndDecompileRuleSet(tag: tag, url: url, srsURL: srsURL, jsonURL: jsonURL, singBoxBinary: binary)
            }
        }
    }

    nonisolated private func downloadAndDecompileRuleSet(tag: String, url: URL, srsURL: URL, jsonURL: URL, singBoxBinary: String) {
        do {
            let data = try Data(contentsOf: url)
            try data.write(to: srsURL, options: .atomic)

            let process = Process()
            process.currentDirectoryURL = srsURL.deletingLastPathComponent()
            process.executableURL = URL(fileURLWithPath: singBoxBinary)
            process.arguments = ["rule-set", "decompile", srsURL.path, "-o", jsonURL.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8) ?? "规则集解包失败"
                throw NSError.user(message)
            }

            DispatchQueue.main.async { [weak self] in
                self?.ruleSetDownloads.remove(tag)
                self?.appendLog("[规则集] \(tag) 已下载并解包\n")
                self?.ruleRows = self?.buildRuleRows(from: self?.editor.string ?? "") ?? []
                self?.rulesTable.reloadData()
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.ruleSetDownloads.remove(tag)
                self?.appendLog("[规则集] \(tag) 下载或解包失败：\(error.localizedDescription)\n")
            }
        }
    }

    private func ruleSetSRSURL(for tag: String) -> URL {
        store.ruleSetsURL.appendingPathComponent(safeFileName(tag)).appendingPathExtension("srs")
    }

    private func ruleSetJSONURL(for tag: String) -> URL {
        store.ruleSetsURL.appendingPathComponent(safeFileName(tag)).appendingPathExtension("json")
    }

    private func safeFileName(_ text: String) -> String {
        text.map { char in
            char.isLetter || char.isNumber || char == "-" || char == "_" ? char : "_"
        }.map(String.init).joined()
    }

    private func customRulesForCurrentSubscription() -> [CustomRule] {
        guard let subscription = currentSubscription() else { return [] }
        return customRules
            .filter { $0.subscriptionID == subscription.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func applyCustomRules(to text: String, subscriptionID: UUID) throws -> [String: Any] {
        guard var config = parseConfigObject(from: text) else {
            throw NSError.user("当前配置不是有效 JSON")
        }
        let rulesForSubscription = customRules
            .filter { $0.subscriptionID == subscriptionID && $0.enabled }
            .sorted { $0.createdAt < $1.createdAt }
        guard !rulesForSubscription.isEmpty else { return config }

        for rule in rulesForSubscription {
            config = ensureOutboundSupport(in: config, strategy: rule.strategy)
        }

        var route = config["route"] as? [String: Any] ?? [:]
        var routeRules = route["rules"] as? [[String: Any]] ?? []
        routeRules.removeAll { existing in
            rulesForSubscription.contains { customRuleMatches($0, existing) }
        }
        let insertIndex = customRuleInsertIndex(in: routeRules)
        let generatedRules = rulesForSubscription.map {
            customRouteRule(type: $0.type, value: $0.value, strategy: $0.strategy)
        }
        routeRules.insert(contentsOf: generatedRules, at: insertIndex)
        route["rules"] = routeRules
        config["route"] = route
        return config
    }

    private func customRuleMatches(_ customRule: CustomRule, _ routeRule: [String: Any]) -> Bool {
        let expected = customRouteRule(type: customRule.type, value: customRule.value, strategy: customRule.strategy)
        return NSDictionary(dictionary: expected).isEqual(to: routeRule)
    }

    private func removeCustomRule(_ customRule: CustomRule, from text: String) throws -> String {
        guard var config = parseConfigObject(from: text) else {
            throw NSError.user("当前配置不是有效 JSON")
        }
        var route = config["route"] as? [String: Any] ?? [:]
        var routeRules = route["rules"] as? [[String: Any]] ?? []
        routeRules.removeAll { customRuleMatches(customRule, $0) }
        route["rules"] = routeRules
        config["route"] = route
        return try renderConfig(config)
    }

    private func buildRuleRows(from text: String) -> [RuleInfo] {
        guard let config = parseConfigObject(from: text) else {
            return [sectionRule("当前配置不是可读取的 JSON")]
        }

        var rows: [RuleInfo] = []
        var nextID = 1

        func append(_ type: String, _ value: String, _ strategy: String, _ note: String = "", enabled: Bool = true, count: String = "0") {
            rows.append(RuleInfo(
                customRuleID: nil,
                enabled: enabled,
                id: "\(nextID)",
                type: type,
                value: value,
                strategy: strategy,
                count: count,
                note: note,
                isSection: false
            ))
            nextID += 1
        }

        func appendCustom(_ rule: CustomRule) {
            rows.append(RuleInfo(
                customRuleID: rule.id,
                enabled: rule.enabled,
                id: "\(nextID)",
                type: rule.type,
                value: rule.value,
                strategy: displayStrategy(outboundForStrategy(rule.strategy)),
                count: "0",
                note: rule.note.isEmpty ? "自定义规则" : rule.note,
                isSection: false
            ))
            nextID += 1
        }

        let currentCustomRules = customRulesForCurrentSubscription()
        rows.append(sectionRule("自定义规则"))
        if currentCustomRules.isEmpty {
            append("CUSTOM", "当前订阅还没有自定义规则", "未设置", "通过上方输入框添加", enabled: false)
        } else {
            for rule in currentCustomRules {
                appendCustom(rule)
            }
        }

        let route = config["route"] as? [String: Any] ?? [:]
        let rules = route["rules"] as? [[String: Any]] ?? []
        rows.append(sectionRule("当前配置规则"))
        for rule in rules {
            if currentCustomRules.contains(where: { customRuleMatches($0, rule) }) {
                continue
            }
            if let action = rule["action"] as? String {
                let protocolValue = (rule["protocol"] as? String) ?? "ALL"
                append("ACTION", protocolValue, action.uppercased(), "sing-box action")
                continue
            }
            let strategy = displayStrategy((rule["outbound"] as? String) ?? (rule["server"] as? String) ?? "")
            if let clashMode = rule["clash_mode"] as? String {
                append("MODE", modeDisplayName(clashMode), strategy, "模式规则")
            }
            if let ruleSet = rule["rule_set"] {
                appendExpandedRuleSetRows(ruleSet, strategy: strategy, rows: &rows, nextID: &nextID)
            }
            if let cidr = rule["ip_cidr"] {
                append("IP-CIDR", compactDescription(cidr), strategy, "IP 段")
            }
            if let domains = rule["domain"] {
                appendEachRuleValue(type: "DOMAIN", values: domains, strategy: strategy, note: "显式域名", append: append)
            }
            if let suffixes = rule["domain_suffix"] {
                appendEachRuleValue(type: "DOMAIN-SUFFIX", values: suffixes, strategy: strategy, note: "域名后缀", append: append)
            }
            if let keywords = rule["domain_keyword"] {
                appendEachRuleValue(type: "DOMAIN-KEYWORD", values: keywords, strategy: strategy, note: "域名关键字", append: append)
            }
            if let regexes = rule["domain_regex"] {
                appendEachRuleValue(type: "DOMAIN-REGEX", values: regexes, strategy: strategy, note: "域名正则", append: append)
            }
            if let sourceCIDR = rule["source_ip_cidr"] {
                appendEachRuleValue(type: "SRC-IP", values: sourceCIDR, strategy: strategy, note: "源 IP", append: append)
            }
            if let asn = rule["ip_asn"] {
                appendEachRuleValue(type: "IP-ASN", values: asn, strategy: strategy, note: "ASN", append: append)
            }
            if let processName = rule["process_name"] {
                appendEachRuleValue(type: "PROCESS-NAME", values: processName, strategy: strategy, note: "进程", append: append)
            }
            if let userAgent = rule["user_agent"] {
                appendEachRuleValue(type: "USER-AGENT", values: userAgent, strategy: strategy, note: "User-Agent", append: append)
            }
            if let port = rule["port"] {
                appendEachRuleValue(type: "DEST-PORT", values: port, strategy: strategy, note: "端口", append: append)
            }
            if let network = rule["network"] {
                appendEachRuleValue(type: "NETWORK", values: network, strategy: strategy, note: "网络类型", append: append)
            }
        }
        if let final = route["final"] as? String {
            append("FINAL", "未命中以上规则", displayStrategy(final), "默认策略")
        }

        let dns = config["dns"] as? [String: Any] ?? [:]
        let dnsRules = dns["rules"] as? [[String: Any]] ?? []
        if !dnsRules.isEmpty {
            rows.append(sectionRule("DNS 规则"))
            for rule in dnsRules {
                let server = (rule["server"] as? String) ?? "未设置"
                if let clashMode = rule["clash_mode"] as? String {
                    append("DNS-MODE", modeDisplayName(clashMode), server, "DNS 模式规则")
                }
                if let ruleSet = rule["rule_set"] {
                    appendExpandedRuleSetRows(ruleSet, strategy: server, rows: &rows, nextID: &nextID, notePrefix: "DNS")
                }
            }
            if let final = dns["final"] as? String {
                append("DNS-FINAL", "未命中以上 DNS 规则", final, "默认 DNS")
            }
        }

        return rows
    }

    private func sectionRule(_ title: String) -> RuleInfo {
        RuleInfo(customRuleID: nil, enabled: false, id: "", type: "", value: "# \(title)", strategy: "", count: "", note: "", isSection: true)
    }

    private func appendExpandedRuleSetRows(
        _ ruleSetValue: Any,
        strategy: String,
        rows: inout [RuleInfo],
        nextID: inout Int,
        notePrefix: String = "规则集"
    ) {
        let tags: [String]
        if let values = ruleSetValue as? [String] {
            tags = values
        } else if let value = ruleSetValue as? String {
            tags = [value]
        } else {
            tags = []
        }

        for tag in tags {
            let entries = decompiledRuleSetEntries(tag: tag, strategy: strategy, notePrefix: notePrefix)
            if entries.isEmpty {
                rows.append(RuleInfo(
                    customRuleID: nil,
                    enabled: true,
                    id: "\(nextID)",
                    type: "RULE-SET",
                    value: tag,
                    strategy: strategy,
                    count: "0",
                    note: ruleSetDownloads.contains(tag) ? "下载中" : "等待下载",
                    isSection: false
                ))
                nextID += 1
            } else {
                rows.append(sectionRule("\(notePrefix)内容：\(tag)"))
                for entry in entries {
                    rows.append(RuleInfo(
                        customRuleID: nil,
                        enabled: true,
                        id: "\(nextID)",
                        type: entry.type,
                        value: entry.value,
                        strategy: strategy,
                        count: "0",
                        note: tag,
                        isSection: false
                    ))
                    nextID += 1
                }
            }
        }
    }

    private func decompiledRuleSetEntries(tag: String, strategy: String, notePrefix: String) -> [(type: String, value: String)] {
        let url = ruleSetJSONURL(for: tag)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = object["rules"] as? [[String: Any]] else { return [] }

        var entries: [(type: String, value: String)] = []
        for rule in rules {
            appendRuleSetValues(type: "DOMAIN", key: "domain", from: rule, to: &entries)
            appendRuleSetValues(type: "DOMAIN-SUFFIX", key: "domain_suffix", from: rule, to: &entries)
            appendRuleSetValues(type: "DOMAIN-KEYWORD", key: "domain_keyword", from: rule, to: &entries)
            appendRuleSetValues(type: "DOMAIN-REGEX", key: "domain_regex", from: rule, to: &entries)
            appendRuleSetValues(type: "IP-CIDR", key: "ip_cidr", from: rule, to: &entries)
            appendRuleSetValues(type: "SRC-IP", key: "source_ip_cidr", from: rule, to: &entries)
            appendRuleSetValues(type: "PROCESS-NAME", key: "process_name", from: rule, to: &entries)
            appendRuleSetValues(type: "USER-AGENT", key: "user_agent", from: rule, to: &entries)
        }
        return entries
    }

    private func appendRuleSetValues(type: String, key: String, from rule: [String: Any], to entries: inout [(type: String, value: String)]) {
        if let values = rule[key] as? [String] {
            for value in values {
                entries.append((type, value))
            }
        } else if let value = rule[key] as? String {
            entries.append((type, value))
        }
    }

    private func displayStrategy(_ strategy: String) -> String {
        switch strategy {
        case TungBoxConfig.tagDirect: return "DIRECT"
        case TungBoxConfig.tagBlock: return "REJECT"
        case TungBoxConfig.tagManual: return "Proxy"
        case TungBoxConfig.tagAuto: return "AUTO"
        default: return strategy.isEmpty ? "未设置" : strategy
        }
    }

    private func appendEachRuleValue(
        type: String,
        values: Any,
        strategy: String,
        note: String,
        append: (String, String, String, String, Bool, String) -> Void
    ) {
        if let list = values as? [String] {
            for value in list {
                append(type, value, strategy, note, true, "0")
            }
        } else if let value = values as? String {
            append(type, value, strategy, note, true, "0")
        } else {
            append(type, compactDescription(values), strategy, note, true, "0")
        }
    }

    private func customRouteRule(type: String, value: String, strategy: String) -> [String: Any] {
        let outbound = outboundForStrategy(strategy)
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case "DOMAIN":
            return ["domain": normalizedValue, "outbound": outbound]
        case "DOMAIN-SUFFIX":
            return ["domain_suffix": normalizedValue, "outbound": outbound]
        case "DOMAIN-KEYWORD":
            return ["domain_keyword": normalizedValue, "outbound": outbound]
        case "DOMAIN-WILDCARD":
            return ["domain_regex": wildcardRegex(from: normalizedValue), "outbound": outbound]
        case "DOMAIN-REGEX", "URL-REGEX":
            return ["domain_regex": normalizedValue, "outbound": outbound]
        case "RULE-SET":
            return ["rule_set": normalizedValue, "outbound": outbound]
        case "IP-CIDR":
            return ["ip_cidr": normalizedValue, "outbound": outbound]
        case "IP-CIDR6":
            return ["ip_cidr": normalizedValue, "outbound": outbound]
        case "GEOIP":
            return ["rule_set": normalizedValue.hasPrefix("geoip-") ? normalizedValue : "geoip-\(normalizedValue.lowercased())", "outbound": outbound]
        case "IP-ASN":
            if let asn = Int(normalizedValue) {
                return ["ip_asn": asn, "outbound": outbound]
            }
            return ["ip_asn": normalizedValue, "outbound": outbound]
        case "SRC-IP":
            return ["source_ip_cidr": normalizedValue, "outbound": outbound]
        case "PROCESS-NAME":
            return ["process_name": normalizedValue, "outbound": outbound]
        case "USER-AGENT":
            return ["user_agent": normalizedValue, "outbound": outbound]
        case "IN-PORT", "DEST-PORT":
            if let port = Int(normalizedValue) {
                return ["port": port, "outbound": outbound]
            }
            return ["port": normalizedValue, "outbound": outbound]
        case "PROTOCOL":
            return ["protocol": normalizedValue.lowercased(), "outbound": outbound]
        case "NETWORK":
            return ["network": normalizedValue.lowercased(), "outbound": outbound]
        default:
            return ["domain": normalizedValue, "outbound": outbound]
        }
    }

    private func outboundForStrategy(_ strategy: String) -> String {
        switch strategy {
        case "DIRECT": return TungBoxConfig.tagDirect
        case "REJECT": return TungBoxConfig.tagBlock
        case "AUTO": return TungBoxConfig.tagAuto
        case "Proxy": return TungBoxConfig.tagManual
        default: return strategy
        }
    }

    private func wildcardRegex(from value: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: value)
            .replacingOccurrences(of: "\\*", with: ".*")
        return "^\(escaped)$"
    }

    private func ensureOutboundSupport(in config: [String: Any], strategy: String) -> [String: Any] {
        var config = config
        var outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let requiredTag = outboundForStrategy(strategy)
        if !outbounds.contains(where: { ($0["tag"] as? String) == requiredTag }) {
            guard [TungBoxConfig.tagDirect, TungBoxConfig.tagBlock].contains(requiredTag) else {
                return config
            }
            let type = requiredTag == TungBoxConfig.tagBlock ? "block" : "direct"
            outbounds.append(["type": type, "tag": requiredTag])
            config["outbounds"] = outbounds
        }
        return config
    }

    private func customRuleInsertIndex(in rules: [[String: Any]]) -> Int {
        var index = 0
        while index < rules.count {
            let rule = rules[index]
            if rule["action"] != nil || rule["clash_mode"] != nil {
                index += 1
            } else {
                break
            }
        }
        return index
    }

    private func buildRulesSummary(from text: String) -> String {
        guard let config = parseConfigObject(from: text) else {
            return "当前配置不是可读取的 JSON。"
        }

        var lines: [String] = []
        let mode = readMode(from: config)
        lines.append("当前模式")
        lines.append("  \(modeDisplayName(mode))")
        lines.append("")

        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let nodeOutbounds = outbounds.filter { outbound in
            let type = ((outbound["type"] as? String) ?? "").lowercased()
            return !["direct", "block", "dns", "selector", "urltest", "url-test"].contains(type)
        }

        lines.append("节点分组")
        if let auto = firstOutbound(in: outbounds, tag: TungBoxConfig.tagAuto) {
            let autoNodes = auto["outbounds"] as? [String] ?? []
            lines.append("  自动选择")
            lines.append("    类型: \(auto["type"] ?? "urltest")")
            lines.append("    节点数: \(autoNodes.count)")
            lines.append("    检测间隔: \(auto["interval"] ?? "未设置")")
            lines.append("    容差: \(auto["tolerance"] ?? "未设置") ms")
            lines.append("    空闲超时: \(auto["idle_timeout"] ?? "未设置")")
            lines.append("    断线切换: \(boolText(auto["interrupt_exist_connections"]))")
            lines.append("    成员: \(joined(autoNodes))")
        } else {
            lines.append("  未找到 自动选择 urltest 分组")
        }

        if let manual = firstOutbound(in: outbounds, tag: TungBoxConfig.tagManual) {
            let manualNodes = manual["outbounds"] as? [String] ?? []
            lines.append("  节点选择")
            lines.append("    默认: \((manual["default"] as? String) ?? "未设置")")
            lines.append("    可选: \(joined(manualNodes))")
        } else {
            lines.append("  未找到 节点选择 selector 分组")
        }
        lines.append("  直连: direct")
        lines.append("  订阅节点: \(nodeOutbounds.count) 个")
        for outbound in nodeOutbounds {
            let tag = (outbound["tag"] as? String) ?? "未命名"
            let type = (outbound["type"] as? String) ?? "unknown"
            let server = outbound["server"].map { "\($0)" } ?? ""
            let port = outbound["server_port"].map { ":\($0)" } ?? ""
            lines.append("    - \(tag)  [\(type)] \(server)\(port)")
        }
        lines.append("")

        let route = config["route"] as? [String: Any] ?? [:]
        let ruleSets = route["rule_set"] as? [[String: Any]] ?? []
        lines.append("规则集")
        if ruleSets.isEmpty {
            lines.append("  当前配置没有 route.rule_set")
        } else {
            for ruleSet in ruleSets {
                let tag = (ruleSet["tag"] as? String) ?? "未命名"
                let format = (ruleSet["format"] as? String) ?? "unknown"
                let interval = (ruleSet["update_interval"] as? String) ?? "未设置"
                let detour = (ruleSet["download_detour"] as? String) ?? "默认"
                lines.append("  - \(tag)  \(format), 更新 \(interval), 下载出站 \(detour)")
            }
        }
        lines.append("")

        let rules = route["rules"] as? [[String: Any]] ?? []
        lines.append("分流规则")
        if rules.isEmpty {
            lines.append("  当前配置没有 route.rules")
        } else {
            for (index, rule) in rules.enumerated() {
                lines.append("  \(index + 1). \(describeRouteRule(rule))")
            }
        }
        lines.append("  final -> \((route["final"] as? String) ?? "未设置")")
        lines.append("")

        let dns = config["dns"] as? [String: Any] ?? [:]
        let dnsRules = dns["rules"] as? [[String: Any]] ?? []
        lines.append("DNS 规则")
        if dnsRules.isEmpty {
            lines.append("  当前配置没有 dns.rules")
        } else {
            for (index, rule) in dnsRules.enumerated() {
                lines.append("  \(index + 1). \(describeDNSRule(rule))")
            }
        }
        lines.append("  final -> \((dns["final"] as? String) ?? "未设置")")

        return lines.joined(separator: "\n")
    }

    private func firstOutbound(in outbounds: [[String: Any]], tag: String) -> [String: Any]? {
        outbounds.first { ($0["tag"] as? String) == tag }
    }

    private func modeDisplayName(_ mode: String) -> String {
        switch mode.lowercased() {
        case "global": return "全局"
        case "direct": return "直连"
        default: return "规则"
        }
    }

    private func boolText(_ value: Any?) -> String {
        guard let value = value as? Bool else { return "未设置" }
        return value ? "开启" : "关闭"
    }

    private func joined(_ values: [String]) -> String {
        values.isEmpty ? "无" : values.joined(separator: ", ")
    }

    private func describeRouteRule(_ rule: [String: Any]) -> String {
        if let action = rule["action"] as? String {
            if let protocolValue = rule["protocol"] as? String {
                return "\(protocolValue) -> \(action)"
            }
            return action
        }
        let outbound = (rule["outbound"] as? String) ?? "未设置出站"
        if let clashMode = rule["clash_mode"] as? String {
            return "模式 \(modeDisplayName(clashMode)) -> \(outbound)"
        }
        if let ruleSet = rule["rule_set"] {
            return "规则集 \(compactDescription(ruleSet)) -> \(outbound)"
        }
        if let cidr = rule["ip_cidr"] {
            return "IP 段 \(compactDescription(cidr)) -> \(outbound)"
        }
        return "\(compactDescription(rule)) -> \(outbound)"
    }

    private func describeDNSRule(_ rule: [String: Any]) -> String {
        let server = (rule["server"] as? String) ?? "未设置 DNS"
        if let clashMode = rule["clash_mode"] as? String {
            return "模式 \(modeDisplayName(clashMode)) -> \(server)"
        }
        if let ruleSet = rule["rule_set"] {
            return "规则集 \(compactDescription(ruleSet)) -> \(server)"
        }
        return "\(compactDescription(rule)) -> \(server)"
    }

    private func compactDescription(_ value: Any) -> String {
        if let values = value as? [String] {
            return values.joined(separator: ", ")
        }
        if let value = value as? String {
            return value
        }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "\(value)"
    }

    private func refreshModeFromEditor() {
        guard let config = parseConfigObject(from: editor.string) else {
            syncModeControls(mode: "Rule")
            modeStatusLabel.stringValue = "当前模式：无法读取配置"
            return
        }
        let mode = readMode(from: config)
        syncModeControls(mode: mode)
        updateModeStatus()
    }

    private func syncModeControls(mode: String) {
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

    private func updateModeStatus() {
        let mode = selectedMode()
        let hasClashModeRules = editor.string.contains("\"clash_mode\"")
        let suffix = hasClashModeRules
            ? "配置中已包含 clash_mode 规则。"
            : "配置中暂未看到 clash_mode 规则，切换模式时会补 direct/global 前置规则。"
        modeStatusLabel.stringValue = "当前模式：\(mode.displayName)\n\(suffix)"
    }

    private func applySelectedMode() throws {
        guard var config = parseConfigObject(from: editor.string) else {
            throw NSError.user("当前配置不是有效 JSON")
        }
        let mode = selectedMode()
        config = ensureModeSupport(in: config, mode: mode)
        editor.string = try renderConfig(config)
        let url = try saveCurrent()
        let output = try runner.check(config: url)
        appendLog("[mode] 已切换到 \(mode.displayName)：\(output)\n")
        refreshModeFromEditor()

        if isProxyRuntimeRunning() {
            runner.stop()
            if isTunEnabled {
                try TunServiceManager.enable(store: store, configText: editor.string)
            } else {
                try runner.start(config: url, elevated: false)
            }
            appendLog("[mode] sing-box 已按新模式重启\n")
            refreshStatus()
        }
    }

    private struct Mode {
        var value: String
        var displayName: String
    }

    private func selectedMode() -> Mode {
        switch modeControl.selectedSegment {
        case 0: return Mode(value: "Direct", displayName: "直接连接")
        case 1: return Mode(value: "Global", displayName: "全局代理")
        default: return Mode(value: "Rule", displayName: "规则判定")
        }
    }

    private func modeSegment(for mode: String) -> Int {
        switch mode.lowercased() {
        case "direct": return 0
        case "global": return 1
        default: return 2
        }
    }

    private func nodesModeSegment(forHomeSegment segment: Int) -> Int {
        segment
    }

    private func homeModeSegment(forNodesSegment segment: Int) -> Int {
        segment
    }

    private func readMode(from config: [String: Any]) -> String {
        let experimental = config["experimental"] as? [String: Any]
        let clashAPI = experimental?["clash_api"] as? [String: Any]
        return (clashAPI?["default_mode"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Rule"
    }

    private func ensureModeSupport(in config: [String: Any], mode: Mode) -> [String: Any] {
        var config = config
        var experimental = config["experimental"] as? [String: Any] ?? [:]
        var clashAPI = experimental["clash_api"] as? [String: Any] ?? [:]
        if clashAPI["external_controller"] == nil {
            clashAPI["external_controller"] = "127.0.0.1:9090"
        }
        clashAPI["default_mode"] = mode.value
        experimental["clash_api"] = clashAPI
        config["experimental"] = experimental

        var outbounds = config["outbounds"] as? [[String: Any]] ?? []
        if !outbounds.contains(where: { ($0["tag"] as? String) == "direct" }) {
            outbounds.append(["type": "direct", "tag": "direct"])
        }
        config["outbounds"] = outbounds

        let proxyTag = preferredProxyTag(from: outbounds)
        var route = config["route"] as? [String: Any] ?? [:]
        var rules = route["rules"] as? [[String: Any]] ?? []
        rules.removeAll { rule in
            guard let clashMode = rule["clash_mode"] as? String else { return false }
            return ["direct", "global"].contains(clashMode.lowercased())
        }
        rules.insert(["clash_mode": "direct", "outbound": "direct"], at: 0)
        rules.insert(["clash_mode": "global", "outbound": proxyTag], at: 1)
        route["rules"] = rules
        config["route"] = route

        return config
    }

    private func preferredProxyTag(from outbounds: [[String: Any]]) -> String {
        if let selector = outbounds.first(where: { ($0["type"] as? String)?.lowercased() == "selector" }),
           let tag = selector["tag"] as? String {
            return tag
        }
        if let urltest = outbounds.first(where: { ["urltest", "url-test"].contains((($0["type"] as? String) ?? "").lowercased()) }),
           let tag = urltest["tag"] as? String {
            return tag
        }
        return nodes.first?.tag ?? "direct"
    }

    private func parseConfigObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private func renderConfig(_ config: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 28)
        configureStatusButton(item.button)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        rebuildTrayMenu(menu)
    }

    private func rebuildTrayMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = isProxyRuntimeRunning() ? "运行中" : "已关闭"
        menu.addItem(NSMenuItem(title: "\(TungBoxVersion.display) \(status)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let systemProxy = NSMenuItem(title: "系统代理", action: #selector(toggleSystemProxyFromTray), keyEquivalent: "")
        systemProxy.target = self
        systemProxy.state = (isProxyRuntimeRunning() && isSystemProxyEnabled) ? .on : .off
        menu.addItem(systemProxy)

        let tun = NSMenuItem(title: "TUN 模式", action: #selector(toggleTunFromTray), keyEquivalent: "")
        tun.target = self
        tun.state = isTunEnabled ? .on : .off
        menu.addItem(tun)

        menu.addItem(.separator())
        let showConsole = NSMenuItem(title: "显示控制台", action: #selector(showConsoleFromTray), keyEquivalent: "")
        showConsole.target = self
        menu.addItem(showConsole)

        let modeMenu = NSMenu()
        for (title, mode) in [("直接连接", "Direct"), ("全局代理", "Global"), ("规则判定", "Rule")] {
            let item = NSMenuItem(title: title, action: #selector(modeFromTray(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            item.state = readMode(from: parseConfigObject(from: editor.string) ?? [:]).caseInsensitiveCompare(mode) == .orderedSame ? .on : .off
            modeMenu.addItem(item)
        }
        let modeRoot = NSMenuItem(title: "出站模式", action: nil, keyEquivalent: "")
        modeRoot.submenu = modeMenu
        menu.addItem(modeRoot)

        menu.addItem(proxyGroupMenu(title: "代理", group: TungBoxConfig.tagManual))
        menu.addItem(proxyGroupMenu(title: "自动选择", group: TungBoxConfig.tagAuto))

        menu.addItem(.separator())
        let openConfig = NSMenuItem(title: "打开配置目录", action: #selector(openFolderClicked), keyEquivalent: "")
        openConfig.target = self
        menu.addItem(openConfig)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quitFromTray), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func proxyGroupMenu(title: String, group: String) -> NSMenuItem {
        let root = NSMenuItem(title: "\(title) 快速切换", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        let groupInfo = nodeGroups.first { $0.tag == group }
        let members = groupInfo?.members ?? []
        if members.isEmpty {
            menu.addItem(NSMenuItem(title: "暂无节点", action: nil, keyEquivalent: ""))
        } else {
            for node in members {
                let item = NSMenuItem(title: node, action: #selector(proxyNodeFromTray(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ["group": group, "node": node]
                item.state = groupInfo?.current == node ? .on : .off
                menu.addItem(item)
            }
        }
        root.submenu = menu
        return root
    }

    private func trayIcon() -> NSImage? {
        let name: String
        if !isProxyRuntimeRunning() {
            name = "off"
        } else if isTunEnabled {
            name = "tun"
        } else {
            let mode = readMode(from: parseConfigObject(from: editor.string) ?? [:]).lowercased()
            switch mode {
            case "direct": name = "direct"
            case "global": name = "global"
            default: name = "rule"
            }
        }
        guard let url = AppResources.url(forResource: name, withExtension: "png", subdirectory: "Tray"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private func refreshTrayIcon() {
        configureStatusButton(statusItem?.button)
    }

    private func configureStatusButton(_ button: NSStatusBarButton?) {
        guard let button else { return }
        if let image = trayIcon() {
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "TB"
        }
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = TungBoxVersion.display
    }

    private func checkSingBoxInstall(showAlert: Bool) {
        if let binary = runner.findSingBox() {
            let result = runner.versionResult()
            let versionLine: String
            if let result, result.status == 0,
               let firstLine = result.output.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                versionLine = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                let output = result?.output.trimmingCharacters(in: .whitespacesAndNewlines)
                versionLine = output?.isEmpty == false ? "版本读取失败：\(output!)" : "版本读取失败"
            }
            detectedCoreVersion = versionLine
            serviceLabel.stringValue = "sing-box Core：已就绪 · \(versionLine)"
            serviceLabel.invalidateIntrinsicContentSize()
            appendLog("[TungBox] 检测到 \(versionLine) @ \(binary)\n")
        } else {
            detectedCoreVersion = "未找到"
            serviceLabel.stringValue = """
            sing-box Core：未找到
            可选处理：
            1. 使用 Homebrew 安装：brew install sing-box
            2. 在这里导入一个 sing-box 可执行文件
            3. 发布包时把 sing-box 放到 App 的 Resources/Core/sing-box
            """
            if showAlert {
                showError(NSError.user("未检测到 sing-box Core。请在 设置 > 基础 > Core 管理 中导入 sing-box，或安装：brew install sing-box"))
            }
        }
        serviceLabel.invalidateIntrinsicContentSize()
        refreshHomeFeatureStatus()
    }

    private func appendLog(_ text: String) {
        logs.textStorage?.append(NSAttributedString(string: text))
        logs.scrollToEndOfDocument(nil)
        logStatusLabel.stringValue = "日志：\(logs.string.components(separatedBy: .newlines).filter { !$0.isEmpty }.count) 行"
    }

    private func resolveActiveOutbound(proxiesObj: [String: Any]?) -> (name: String, isAuto: Bool) {
        return resolveActiveOutboundForGroup(groupTag: "节点选择", proxiesObj: proxiesObj)
    }

    private func resolveActiveOutboundForGroup(groupTag: String, proxiesObj: [String: Any]?) -> (name: String, isAuto: Bool) {
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

    private func syncNodeDelaysFromClashAPI(proxiesObj: [String: Any]?) {
        guard let proxiesObj = proxiesObj,
              let proxies = proxiesObj["proxies"] as? [String: Any] else { return }
        
        var updated = false
        for (name, proxyData) in proxies {
            guard let proxy = proxyData as? [String: Any] else { continue }
            var delayMs: Int? = nil
            if let history = proxy["history"] as? [[String: Any]],
               let last = history.last,
               let delay = last["delay"] as? Int {
                delayMs = delay
            }
            
            if let delayMs = delayMs {
                if let idx = nodes.firstIndex(where: { $0.tag == name }) {
                    let oldDelay = nodes[idx].delay
                    let newDelay = delayMs > 0 ? "\(delayMs) ms" : "超时"
                    if oldDelay != newDelay && oldDelay != "测试中" {
                        nodes[idx].delay = newDelay
                        updated = true
                    }
                }
            }
        }

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

    private func refreshStatus() {
        let isRunning = isProxyRuntimeRunning()
        statusChip.isActive = isRunning
        syncProxyPreferenceControls()
        refreshTrayIcon()
        refreshHomeFeatureStatus()
        
        if isRunning {
            let activeNodeInfo = resolveActiveOutbound(proxiesObj: nil)
            let formattedNode = activeNodeInfo.isAuto ? "\(activeNodeInfo.name) (自动)" : activeNodeInfo.name
            currentNodeNameLabel.stringValue = formattedNode
            let activeDelay = nodes.first(where: { $0.tag == activeNodeInfo.name })?.delay ?? "—"
            currentNodeDelayLabel.stringValue = activeDelay == "未测试" ? "—" : activeDelay
            
            if statsTimer == nil {
                startStatsTimer()
            }
        } else {
            currentNodeNameLabel.stringValue = "未连接"
            currentNodeDelayLabel.stringValue = "—"
            connections.removeAll()
            connectionsTable.reloadData()
            stopStatsTimer()
        }
    }

    private func startStatsTimer() {
        statsTimer?.invalidate()
        totalUploadBytes = 0
        totalDownloadBytes = 0
        updateTrafficLabels()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateRunningStats()
            }
        }
    }
    
    private func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
        updateConnectionsCard(value: "0", detail: "服务未运行")
        uploadValueLabel.stringValue = "0 B/s"
        downloadValueLabel.stringValue = "0 B/s"
        trafficStatsValueLabel.stringValue = "0 B"
        trafficStatsDetailLabel.stringValue = "上传: 0 B   下载: 0 B"
    }

    private func updateRunningStats() {
        guard isProxyRuntimeRunning(), let pid = currentProxyPID() else {
            stopStatsTimer()
            return
        }
        
        Task {
            let apiConnections = (try? await ClashAPI.connections()) ?? []
            let traffic = (try? await ClashAPI.traffic()) ?? (0, 0)
            let proxiesObj = (try? await ClashAPI.proxies())
            
            let rssValue = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                DispatchQueue.global(qos: .background).async {
                    let rss = self.runProcessAndGetOutput("/bin/ps", args: ["-o", "rss=", "-p", "\(pid)"])
                    let cleanRss = rss.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let kb = Double(cleanRss) {
                        if kb > 1024 {
                            continuation.resume(returning: String(format: "%.1f MB", kb / 1024.0))
                        } else {
                            continuation.resume(returning: "\(Int(kb)) KB")
                        }
                    } else {
                        continuation.resume(returning: "--")
                    }
                }
            }
            
            let connectionCount = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                DispatchQueue.global(qos: .background).async {
                    if !apiConnections.isEmpty {
                        continuation.resume(returning: apiConnections.count)
                    } else {
                        let lsof = self.runProcessAndGetOutput("/usr/sbin/lsof", args: ["-i", "-a", "-p", "\(pid)", "-n", "-P"])
                        let lines = lsof.components(separatedBy: .newlines)
                        let establishedCount = lines.filter { $0.contains("ESTABLISHED") }.count
                        continuation.resume(returning: establishedCount)
                    }
                }
            }
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                guard self.isProxyRuntimeRunning() else { return }
                
                self.connections = apiConnections
                self.connectionsTable.reloadData()
                
                // Sync delays and active node from Clash API
                self.lastProxiesObj = proxiesObj
                self.syncNodeDelaysFromClashAPI(proxiesObj: proxiesObj)
                let activeNodeInfo = self.resolveActiveOutbound(proxiesObj: proxiesObj)
                let formattedNode = activeNodeInfo.isAuto ? "\(activeNodeInfo.name) (自动)" : activeNodeInfo.name
                self.currentNodeNameLabel.stringValue = formattedNode
                let activeDelay = self.nodes.first(where: { $0.tag == activeNodeInfo.name })?.delay ?? "—"
                self.currentNodeDelayLabel.stringValue = activeDelay == "未测试" ? "—" : activeDelay
                
                // 1. Update connections card
                self.updateConnectionsCard(value: "\(connectionCount)", detail: "内存占用: \(rssValue)")
                
                // 2. Update real-time speeds
                let upSpeedStr = self.formatBytes(traffic.0)
                let downSpeedStr = self.formatBytes(traffic.1)
                self.uploadValueLabel.stringValue = "\(upSpeedStr)/s"
                self.downloadValueLabel.stringValue = "\(downSpeedStr)/s"
                
                // 3. Update session totals
                let deltaUp = traffic.0 * 2
                let deltaDown = traffic.1 * 2
                self.totalUploadBytes += deltaUp
                self.totalDownloadBytes += deltaDown
                self.recordTraffic(upload: deltaUp, download: deltaDown)
                self.updateTrafficLabels()
            }
        }
    }
    
    nonisolated private func runProcessAndGetOutput(_ binary: String, args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func updateConnectionsCard(value: String, detail: String) {
        connectionsValueLabel.stringValue = value
        connectionsDetailLabel.stringValue = detail
    }

    private func formatBytes(_ bytes: Int) -> String {
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

    @MainActor
    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    @MainActor
    private func showToast(_ message: String) {
        guard let contentView = window?.contentView else { return }
        toastView?.removeFromSuperview()

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        container.layer?.cornerRadius = 12
        container.alphaValue = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        contentView.addSubview(container)
        toastView = container

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            container.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -28),
            container.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.72)
        ])

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            container.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self, weak container] in
            guard let container, self?.toastView === container else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                container.animator().alphaValue = 0
            } completionHandler: {
                DispatchQueue.main.async {
                    container.removeFromSuperview()
                }
            }
        }
    }

    private func defaultConfig() -> String {
        """
        {
          "log": {
            "level": "info"
          },
          "inbounds": [
            {
              "type": "mixed",
              "tag": "mixed-in",
              "listen": "127.0.0.1",
              "listen_port": 7890
            }
          ],
          "outbounds": [
            {
              "type": "direct",
              "tag": "direct"
            }
          ],
          "route": {
            "final": "direct"
          }
        }
        """
    }

    func stopServiceFromDelegate() {
        stopService()
    }

    private func setSystemProxy(enabled: Bool, port: Int) {
        // Run networksetup commands in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let services = self.getActiveNetworkServices()
            for service in services {
                if enabled {
                    _ = self.runCommand("/usr/sbin/networksetup", args: ["-setwebproxy", service, "127.0.0.1", "\(port)"])
                    _ = self.runCommand("/usr/sbin/networksetup", args: ["-setsecurewebproxy", service, "127.0.0.1", "\(port)"])
                    _ = self.runCommand("/usr/sbin/networksetup", args: ["-setsocksfirewallproxy", service, "127.0.0.1", "\(port)"])
                    _ = self.runCommand("/usr/sbin/networksetup", args: ["-setwebproxystate", service, "on"])
                    _ = self.runCommand("/usr/sbin/networksetup", args: ["-setsecurewebproxystate", service, "on"])
                    _ = self.runCommand("/usr/sbin/networksetup", args: ["-setsocksfirewallproxystate", service, "on"])
                } else {
                    _ = self.runCommand("/usr/sbin/networksetup", args: ["-setwebproxystate", service, "off"])
                    _ = self.runCommand("/usr/sbin/networksetup", args: ["-setsecurewebproxystate", service, "off"])
                    _ = self.runCommand("/usr/sbin/networksetup", args: ["-setsocksfirewallproxystate", service, "off"])
                }
            }
            Task { @MainActor [weak self] in
                if enabled {
                    self?.appendLog("[TungBox] 已自动启用系统 HTTP/HTTPS 代理，端口为: \(port)\n")
                } else {
                    self?.appendLog("[TungBox] 已自动关闭系统代理\n")
                }
            }
            
            // Check if another proxy is overriding settings
            if enabled {
                Thread.sleep(forTimeInterval: 1.0)
                if let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
                   let httpEnabled = settings[kCFNetworkProxiesHTTPEnable as String] as? Int, httpEnabled == 1,
                   let activePort = settings[kCFNetworkProxiesHTTPPort as String] as? Int,
                   activePort != port {
                    Task { @MainActor [weak self] in
                        self?.appendLog("[警告] 检测到当前系统代理已被其他软件接管（当前生效端口：\(activePort)，TungBox 预期端口：\(port)）。请先关闭其他代理软件（如 Surge, ClashX, Clash Verge）以避免冲突。\n")
                    }
                }
            }
        }
    }
    
    nonisolated private func getActiveNetworkServices() -> [String] {
        let output = runCommand("/usr/sbin/networksetup", args: ["-listallnetworkservices"])
        let lines = output.components(separatedBy: .newlines)
        var services: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("An asterisk") || trimmed.hasPrefix("*") {
                continue
            }
            // Skip VPN/Proxy interfaces
            if trimmed.lowercased().contains("tailscale") || trimmed.lowercased().contains("surge") || trimmed.lowercased().contains("vpn") {
                continue
            }
            services.append(trimmed)
        }
        if services.isEmpty {
            services.append("Wi-Fi")
        }
        return services
    }
    
    nonisolated private func runCommand(_ binary: String, args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func getMixedProxyPort() -> Int {
        guard let data = editor.string.data(using: .utf8),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inbounds = config["inbounds"] as? [[String: Any]] else {
            return 7890
        }
        
        for inbound in inbounds {
            if let type = inbound["type"] as? String, type == "mixed",
               let port = inbound["listen_port"] as? Int {
                return port
            }
        }
        
        for inbound in inbounds {
            if let type = inbound["type"] as? String, type == "http",
               let port = inbound["listen_port"] as? Int {
                return port
            }
        }
        
        return 7890
    }
}

extension MainWindowController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, effectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        return .zero
    }
    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        return view != splitView.subviews.first
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        controller = MainWindowController()
        controller?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stopServiceFromDelegate()
    }

    @MainActor
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let appName = ProcessInfo.processInfo.processName
        appMenu.addItem(NSMenuItem(
            title: "退出 \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
