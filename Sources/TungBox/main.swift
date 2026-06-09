import AppKit
import Foundation
import ServiceManagement


final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSWindowDelegate {
    let store = Store()
    lazy var runner = Runner(store: store)
    var profiles: [ConfigProfile] = []
    var subscriptions: [Subscription] = []
    var customRules: [CustomRule] = []
    var nodes: [NodeInfo] = []
    var nodeGroups: [NodeGroupInfo] = []
    var ruleRows: [RuleInfo] = []
    var connections: [ConnectionInfo] = []
    var ruleSetDownloads = Set<String>()
    var nodeTileActions: [Int: (group: String, node: String)] = [:]
    var groupTestActions: [Int: String] = [:]
    var nextNodeTileTag = 1
    var selectedIndex: Int?
    var selectedSubscriptionIndex: Int? {
        didSet {
            if let index = selectedSubscriptionIndex {
                UserDefaults.standard.set(index, forKey: "selectedSubscriptionIndex")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedSubscriptionIndex")
            }
        }
    }

    let split = MD3SplitView()
    let currentNodeNameLabel = NSTextField(labelWithString: "未连接")
    let currentNodeDelayLabel = NSTextField(labelWithString: "—")
    var totalUploadBytes = 0
    var totalDownloadBytes = 0
    let trafficStatsValueLabel = NSTextField(labelWithString: "0 B")
    let trafficStatsDetailLabel = NSTextField(labelWithString: "上传: 0 B   下载: 0 B")



    let trafficPeriodControl = MD3SegmentedControl()
    


    let table = NSTableView()
    let subscriptionTable = NSTableView()
    let nodeTable = NSTableView()
    let rulesTable = NSTableView()
    let connectionsTable = NSTableView()
    let nodeGroupsStack = NSStackView()
    let pages = NSTabView()
    var navButtons: [MD3SidebarItem] = []
    let editor = NSTextView()
    let logs = NSTextView()
    let ruleSearchField = MD3TextField()
    let customRuleTypePopup = MD3PopUpButton()
    let customRuleStrategyPopup = MD3PopUpButton()
    let customRuleValueField = MD3TextField()
    let customRuleNoteField = MD3TextField()
    let ruleSetPrivateURLField = MD3TextField()
    let ruleSetCNURLField = MD3TextField()
    let ruleSetGeoIPCNURLField = MD3TextField()
    let ruleSetGeolocationNotCNURLField = MD3TextField()
    let statusChip = MD3StatusChip()
    let subscriptionNameField = MD3TextField()
    let subscriptionURLField = MD3TextField()
    let serviceLabel = NSTextField(labelWithString: "sing-box：检测中")
    let nodeTestURLField = MD3TextField(string: "https://www.gstatic.com/generate_204")
    let tcpAddressField = MD3TextField(string: "www.google.com:443")
    let modeControl = MD3SegmentedControl()
    let nodesModeControl = MD3SegmentedControl()
    let modeStatusLabel = NSTextField(labelWithString: "当前模式：规则")
    let apiStatusLabel = NSTextField(labelWithString: "运行态 API：服务未启动")
    let subscriptionAutoStatusLabel = NSTextField(labelWithString: "订阅自动刷新：每 60 分钟，尚未执行")
    let nodeTestStatusLabel = NSTextField(labelWithString: "节点 URLTest：尚未测试")
    let coreStatusLabel = NSTextField(labelWithString: "sing-box Core：检测中")
    let logStatusLabel = NSTextField(labelWithString: "日志：0 行")
    let tunRuntimeStatusLabel = NSTextField(labelWithString: "TUN 权限：未启用")
    var colorSchemeRows: [MD3ColorSchemeRow] = []
    var themeObservers: [() -> Void] = []
    var statusItem: NSStatusItem?
    var isSystemProxyDefaultEnabled = UserDefaults.standard.object(forKey: "systemProxyDefaultEnabled") as? Bool ?? false
    var isSystemProxyEnabled = false
    var isTunEnabled = UserDefaults.standard.object(forKey: "tunEnabled") as? Bool ?? false
    var isProxyServiceTransitioning = false
    var systemProxyOperationID = 0
    var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return UserDefaults.standard.bool(forKey: "launchAtLoginEnabled")
        }
    }
    var detectedCoreVersion = "检测中"
    var subscriptionTimer: Timer?
    var connectionsRefreshTimer: Timer?
    var tunRequestHeartbeatTimer: Timer?
    var tunHealthCheckID = 0
    var isRefreshingConnections = false
    weak var zeroStateView: NSView?
    let connectionFilterField = MD3TextField()
    var editingRuleID: UUID?
    var logLevelButtons: [MD3Checkbox]?
    var logBuffer = ""
    
    let serviceSwitch = MD3Switch()
    let homeSystemProxyRadio = MD3RadioButton(radioButtonWithTitle: "系统代理", target: nil, action: nil)
    let homeTunRadio = MD3RadioButton(radioButtonWithTitle: "TUN 模式", target: nil, action: nil)
    let settingsSystemProxyRadio = MD3RadioButton(radioButtonWithTitle: "系统代理", target: nil, action: nil)
    let settingsTunRadio = MD3RadioButton(radioButtonWithTitle: "TUN 模式", target: nil, action: nil)
    let settingsSystemProxyCheckbox = MD3Checkbox(checkboxWithTitle: "默认开启代理服务", target: nil, action: nil)
    let settingsLaunchAtLoginCheckbox = MD3Checkbox(checkboxWithTitle: "开机自启动", target: nil, action: nil)
    let settingsStartSilentlyCheckbox = MD3Checkbox(checkboxWithTitle: "静默启动", target: nil, action: nil)
    let tunServiceStatusLabel = NSTextField(labelWithString: "TUN 服务状态：未检测")
    let tunServiceLogLabel = NSTextField(labelWithString: "最近状态：暂无")
    let tunServiceToggleButton = MD3Button()
    let tunServiceReinstallButton = MD3Button()
    let tunServiceReloadButton = MD3Button()
    var tunServiceOperationInProgress = false
    let activeNodeLabel = NSTextField(labelWithString: "")
    let connectionsValueLabel = NSTextField(labelWithString: "0")
    let connectionsDetailLabel = NSTextField(labelWithString: "服务未运行")
    let uploadValueLabel = NSTextField(labelWithString: "0 KB/s")
    let downloadValueLabel = NSTextField(labelWithString: "0 KB/s")
    var statsTimer: Timer?
    var lastProxiesObj: [String: Any]? = nil
    var prevConnections: [ConnectionInfo] = []
    var connectionRefreshTime: Date = .distantPast
    var settingsPages: [NSView] = []
    let settingsTabView = NSView()
    let appVersionFooter = MD3AppVersionFooter()
    var latestAppRelease: AppRelease?
    var appUpdateCheckState: AppUpdateCheckState = .notChecked
    private weak var toastView: NSView?
    private var pendingStatusRefresh: DispatchWorkItem?
    private var pendingLogRefresh: DispatchWorkItem?
    var logLineCount = 0

    func registerThemeObserver(_ observer: @escaping () -> Void) {
        themeObservers.append(observer)
    }

    func notifyThemeChanged() {
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
        window.title = "TungBox"
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.delegate = self
        setup()
    }

    func setup() {
        profiles = store.loadProfiles()
        subscriptions = store.loadSubscriptions()
        customRules = store.loadCustomRules()
        runner.onOutput = { [weak self] text in
            self?.appendLog(text)
            self?.scheduleStatusRefreshFromOutput()
        }

        // Apply persisted theme
        NSApp.appearance = NSAppearance(named: MD3.isDark ? .darkAqua : .aqua)
        configureCenteredWindowTitle()

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
            subscriptionTable.reloadData()
            
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

        normalizeProxyPreferences()
        
        refreshStatus()
        
        // Apply logo as Application Dock Icon
        if let logoUrl = AppResources.url(forResource: "logo", withExtension: "png", subdirectory: "Tray"),
           let logoImage = NSImage(contentsOf: logoUrl) {
            NSApplication.shared.applicationIconImage = logoImage

            // One-time: force Finder to show our icon (CFBundleIconFile may be stale)
            if !UserDefaults.standard.bool(forKey: "finderIconApplied") {
                let iconApplied = NSWorkspace.shared.setIcon(logoImage, forFile: Bundle.main.bundlePath, options: [])
                if iconApplied {
                    UserDefaults.standard.set(true, forKey: "finderIconApplied")
                }
            }
        }

        checkSingBoxInstall(showAlert: true)
        refreshSubscriptionBadge()
    }

    func normalizeProxyPreferences() {
        if UserDefaults.standard.object(forKey: "systemProxyDefaultEnabled") == nil {
            UserDefaults.standard.set(isSystemProxyDefaultEnabled, forKey: "systemProxyDefaultEnabled")
        }

        if isTunEnabled && !TunServiceManager.hasInstalledServiceFiles {
            isTunEnabled = false
            UserDefaults.standard.set(false, forKey: "tunEnabled")
            try? TunServiceManager.disable(store: store)
            appendLog("[TUN] 检测到 TUN 服务不可用，已关闭 TUN 模式。请到 设置 > TUN 设置 重新安装。\n")
            return
        }

        guard isSystemProxyDefaultEnabled else {
            isSystemProxyEnabled = false
            runner.stopStaleUserProcesses()
            if TunServiceManager.hasEnableRequest(store: store) {
                try? TunServiceManager.disable(store: store)
                appendLog("[启动] 默认开启代理服务未启用，已清理残留 TUN 请求。\n")
            }
            return
        }

        let isTunRunning = TunServiceManager.activeSingBoxPID(store: store) != nil
        if isTunRunning && !isTunEnabled {
            try? TunServiceManager.disable(store: store)
            isSystemProxyEnabled = false
            appendLog("[启动] 当前接管方式为系统代理，已清理残留 TUN 请求。\n")
            return
        }

        if isTunRunning && isTunEnabled {
            isSystemProxyEnabled = true
        }
    }

    func applyStartupProxyPreference() {
        guard isSystemProxyDefaultEnabled else {
            isSystemProxyEnabled = false
            try? TunServiceManager.disable(store: store)
            syncProxyPreferenceControls()
            appendLog("[启动] 默认开启代理服务未启用，本次启动不自动打开代理。\n")
            return
        }

        isSystemProxyEnabled = true
        syncProxyPreferenceControls()

        if isProxyRuntimeRunning() {
            reconcileSystemProxyForCurrentMode()
            appendLog("[启动] 检测到代理已在运行，已同步系统代理状态。\n")
            refreshStatus()
            return
        }

        appendLog("[启动] 按设置自动开启代理服务。\n")
        startService()
    }

    func scheduleStatusRefreshFromOutput() {
        guard pendingStatusRefresh == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingStatusRefresh = nil
            self?.refreshStatus()
        }
        pendingStatusRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    func scheduleLogRefresh() {
        guard pendingLogRefresh == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingLogRefresh = nil
            self.refreshLogDisplay()
            self.logs.scrollToEndOfDocument(nil)
            self.logStatusLabel.stringValue = "日志：\(self.logLineCount) 行"
        }
        pendingLogRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    func setupSidebar(_ view: NSView) {
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

        appVersionFooter.versionText = "TungBox v\(TungBoxVersion.release)"
        appVersionFooter.target = self
        appVersionFooter.action = #selector(appVersionFooterClicked)
        appVersionFooter.translatesAutoresizingMaskIntoConstraints = false
        appVersionFooter.heightAnchor.constraint(equalToConstant: 28).isActive = true
        registerThemeObserver { [weak self] in
            self?.appVersionFooter.themeChanged()
        }

        view.addSubview(title)
        view.addSubview(nav)
        view.addSubview(appVersionFooter)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 34),

            nav.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            nav.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            nav.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 30),

            appVersionFooter.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            appVersionFooter.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            appVersionFooter.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24)
        ])
    }

    func setupMain(_ view: NSView) {
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
    func populateRuleTypePopup() {
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
                customRuleTypePopup.menu?.addItem(NSMenuItem.separator())
            }
            customRuleTypePopup.addItems(withTitles: section)
        }
        if let current, popup(customRuleTypePopup, contains: current) {
            customRuleTypePopup.selectItem(withTitle: current)
        }
    }

    func populateRuleStrategyPopup() {
        let current = customRuleStrategyPopup.titleOfSelectedItem
        customRuleStrategyPopup.removeAllItems()
        customRuleStrategyPopup.addItems(withTitles: ["DIRECT", "REJECT"])
        customRuleStrategyPopup.menu?.addItem(NSMenuItem.separator())
        customRuleStrategyPopup.addItems(withTitles: ["Proxy", "AUTO"])
        let nodeTags = nodes.map(\.tag).filter { !$0.isEmpty }
        if !nodeTags.isEmpty {
            customRuleStrategyPopup.menu?.addItem(NSMenuItem.separator())
            customRuleStrategyPopup.addItems(withTitles: nodeTags)
        }
        if let current, popup(customRuleStrategyPopup, contains: current) {
            customRuleStrategyPopup.selectItem(withTitle: current)
        } else {
            customRuleStrategyPopup.selectItem(withTitle: "Proxy")
        }
    }

    func popup(_ popup: NSPopUpButton, contains title: String) -> Bool {
        popup.itemArray.contains { $0.title == title }
    }

    

    

    

    

    

    func makeRuleCell(for rule: RuleInfo, columnID: String) -> NSView {
        if columnID == "enabled" && !rule.isSection {
            let button = MD3Checkbox(checkboxWithTitle: "", target: nil, action: nil)
            button.state = rule.enabled ? .on : .off
            button.isEnabled = rule.customRuleID != nil
            if rule.customRuleID != nil {
                button.tag = ruleRows.firstIndex(where: { $0.customRuleID == rule.customRuleID }) ?? -1
                button.target = self
                button.action = #selector(toggleRuleEnabled(_:))
            }
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
    @objc func navClicked(_ sender: MD3SidebarItem) {
        selectPage(at: sender.tag)
    }

    private func configureCenteredWindowTitle() {
        guard let window,
              let closeButton = window.standardWindowButton(.closeButton),
              let titlebarView = closeButton.superview else { return }

        window.title = "TungBox"
        window.titleVisibility = .hidden

        let titleIdentifier = NSUserInterfaceItemIdentifier("TungBoxCenteredWindowTitle")
        titlebarView.subviews
            .filter { $0.identifier == titleIdentifier }
            .forEach { $0.removeFromSuperview() }

        let titleLabel = NSTextField(labelWithString: "TungBox")
        titleLabel.identifier = titleIdentifier
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titlebarView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: titlebarView.widthAnchor, constant: -240),
            titleLabel.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    func selectPage(at index: Int) {
        guard index >= 0, index < pages.numberOfTabViewItems else { return }
        pages.selectTabViewItem(at: index)
        for button in navButtons {
            button.isSelected = (button.tag == index)
        }
        if index == 6 {
            checkSingBoxInstall(showAlert: false)
        }
        if index == 4 {
            startConnectionsRefreshTimer()
            refreshConnections(showErrors: false)
        } else {
            stopConnectionsRefreshTimer()
        }
        window?.contentView?.refreshSubviews()
    }
    func startService() {
        guard ensureCoreAvailableForStart() else {
            markProxyStartupFailed()
            return
        }
        guard selectedIndex != nil else {
            showError(NSError.user("没有检测到有效的配置文件，请先创建或导入配置。"))
            markProxyStartupFailed()
            return
        }
        guard !nodes.isEmpty else {
            showError(NSError.user("当前配置中没有检测到可用的节点。请先配置节点或更新订阅。"))
            markProxyStartupFailed()
            return
        }

        do {
            try applyTunPreference(restartIfRunning: false)
            try ensureRuntimeAPISupport()
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
            if let config = parseConfigObject(from: editor.string),
               readMode(from: config).caseInsensitiveCompare("Direct") == .orderedSame {
                appendLog("[警告] 当前出站模式为直连/绕过代理，流量不会走代理。请切换到规则判定或全局代理。\n")
                showToast("当前为直连/绕过代理模式")
            }

            if isTunEnabled {
                let tunStatus = TunServiceManager.status(store: store)
                guard tunStatus.isUsable else {
                    isTunEnabled = false
                    UserDefaults.standard.set(false, forKey: "tunEnabled")
                    syncProxyPreferenceControls()
                    throw NSError.user("TUN 服务不可用：\(tunStatus.displayText)。请到 设置 > TUN 设置处理。")
                }
                runner.stop()
                try enableTunServiceSafely(configText: editor.string)
                appendLog("[TUN] 已交给 TUN 服务启动 sing-box\n")
                isProxyServiceTransitioning = false
                // TUN daemon needs a moment to start sing-box; delay status refresh
                // so the switch doesn't flip off before the daemon picks up the flag
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.refreshStatus()
                }
                scheduleTunHealthCheck()
                scheduleConnectionsRefreshAfterStart()
                return
            }
            try stopTunBeforeStartingNormalProxy(timeout: 8)
            try runner.start(config: url, elevated: false)
            appendLog("[TungBox] 已启动\n")
            isProxyServiceTransitioning = false
            
            let port = getMixedProxyPort()
            setSystemProxy(enabled: isSystemProxyEnabled && !isTunEnabled, port: port, rollbackOnMismatch: true)
            
            refreshStatus()
            scheduleConnectionsRefreshAfterStart()
        } catch {
            showError(error)
            markProxyStartupFailed()
        }
    }

    func markProxyStartupFailed() {
        isSystemProxyEnabled = false
        isProxyServiceTransitioning = false
        stopTunRequestHeartbeat()
        try? TunServiceManager.disable(store: store)
        _ = TunServiceManager.waitUntilStopped(store: store, timeout: 3)
        serviceSwitch.isOn = false
        syncProxyPreferenceControls()
    }

    func stopTunBeforeStartingNormalProxy(timeout: TimeInterval) throws {
        let shouldStopTun = TunServiceManager.status(store: store).isRunning
            || TunServiceManager.hasRequestFiles(store: store)
            || TunServiceManager.hasNetworkResidue()
        guard shouldStopTun else { return }

        stopTunRequestHeartbeat()
        try TunServiceManager.disable(store: store)
        appendLog("[TUN] 正在等待 TUN 完全停止后再启动系统代理...\n")
        guard TunServiceManager.waitUntilStopped(store: store, timeout: timeout) else {
            let residue = TunServiceManager.networkResidueDescription() ?? "TUN 服务仍在停止中"
            throw NSError.user("TUN 尚未完全停止，暂不启动系统代理，避免进入断网状态。请稍等后重试。\(residue)")
        }
        appendLog("[TUN] 已停止，继续启动系统代理\n")
    }

    func ensureRuntimeAPISupport() throws {
        guard var config = parseConfigObject(from: editor.string) else { return }
        let currentMode = readMode(from: config)
        config = ensureModeSupport(in: config, mode: Mode(value: currentMode, displayName: modeDisplayName(currentMode)))
        editor.string = try renderConfig(config)
    }

    func scheduleConnectionsRefreshAfterStart() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.isProxyRuntimeRunning() else { return }
            if self.isConnectionsPageSelected() {
                self.startConnectionsRefreshTimer()
            }
            self.updateRunningStats()
            self.refreshConnections(showErrors: false)
        }
    }

    func scheduleTunHealthCheck() {
        tunHealthCheckID += 1
        let checkID = tunHealthCheckID
        appendLog("[TUN] 正在进行连通性检查...\n")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self else { return }
            let directOK = self.runHTTPHealthCheck(url: "http://www.baidu.com", timeout: 6)
            let proxyOK = self.runHTTPHealthCheck(url: "https://www.gstatic.com/generate_204", timeout: 8)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      checkID == self.tunHealthCheckID,
                      self.isTunEnabled,
                      TunServiceManager.hasEnableRequest(store: self.store) else {
                    return
                }
                if directOK && proxyOK {
                    self.appendLog("[TUN] 连通性检查通过：国内与代理站点均可访问\n")
                    return
                }
                let failed = [
                    directOK ? nil : "国内站点不可达",
                    proxyOK ? nil : "代理站点不可达"
                ].compactMap { $0 }.joined(separator: "，")
                self.appendLog("[TUN] 连通性检查异常：\(failed)，已保留 TUN 现场用于诊断\n")
                self.showToast("TUN 连通性异常，已保留现场")
            }
        }
    }

    nonisolated func runHTTPHealthCheck(url: String, timeout: TimeInterval) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "--silent",
            "--show-error",
            "--fail",
            "--location",
            "--max-time", "\(Int(timeout))",
            "--output", "/dev/null",
            url
        ]
        do {
            try process.run()
        } catch {
            return false
        }
        let deadline = Date().addingTimeInterval(timeout + 1)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
            }
            return false
        }
        return process.terminationStatus == 0
    }

    func isConnectionsPageSelected() -> Bool {
        guard let item = pages.selectedTabViewItem else { return false }
        return pages.indexOfTabViewItem(item) == 4
    }

    func ensureCoreAvailableForStart() -> Bool {
        guard runner.findSingBox() != nil else {
            checkSingBoxInstall(showAlert: false)
            showToast("未检测到 sing-box Core")
            showError(NSError.user("未检测到 sing-box Core。请先在 设置 > 基础 > Core 管理 中安装或导入 Core。"))
            return false
        }
        return true
    }

    func stopService(clearSystemProxySynchronously: Bool = false) {
        let shouldDisableTun = isTunEnabled
            || TunServiceManager.status(store: store).isRunning
            || TunServiceManager.hasRequestFiles(store: store)
            || TunServiceManager.hasNetworkResidue()
        let shouldStopNormalProxy = runner.isRunning
        let shouldClearSystemProxy = isSystemProxyEnabled || shouldStopNormalProxy

        // 1. Tell TUN daemon to stop (removes enabled flag; daemon cleanly kills TUN child, keeps daemon alive)
        if shouldDisableTun {
            stopTunRequestHeartbeat()
            try? TunServiceManager.disable(store: store)
            appendLog("[TungBox] TUN 标记已关闭\n")
            let timeout: TimeInterval = clearSystemProxySynchronously ? 8 : 6
            if TunServiceManager.waitUntilStopped(store: store, timeout: timeout) {
                appendLog("[TungBox] TUN 已确认回收\n")
            } else {
                let residue = TunServiceManager.networkResidueDescription() ?? "未知残留"
                appendLog("[警告] TUN 未在 \(Int(timeout)) 秒内确认回收：\(residue)。请到设置重新安装 TUN 服务以更新安全停机脚本。\n")
                showToast("TUN 未确认回收，请重新安装 TUN 服务")
            }
        }

        // 2. Stop sing-box processes (normal + elevated)
        if shouldStopNormalProxy {
            runner.stop()
            appendLog("[TungBox] sing-box 已停止\n")
        }

        // 3. Turn off system proxy synchronously — must complete before app exits
        if shouldClearSystemProxy {
            if clearSystemProxySynchronously {
                setSystemProxySync(enabled: false, port: 7890)
            } else {
                setSystemProxy(enabled: false, port: 7890)
            }
            appendLog("[TungBox] 系统代理已关闭\n")
        }

        isSystemProxyEnabled = false
        isProxyServiceTransitioning = false

        refreshStatus()
    }

    /// Synchronous system proxy toggle — used during app quit/crash where async dispatch might not complete.
    func setSystemProxySync(enabled: Bool, port: Int) {
        let services = getActiveNetworkServices()
        for service in services {
            if enabled {
                _ = runCommand("/usr/sbin/networksetup", args: ["-setwebproxy", service, "127.0.0.1", "\(port)"])
                _ = runCommand("/usr/sbin/networksetup", args: ["-setsecurewebproxy", service, "127.0.0.1", "\(port)"])
                _ = runCommand("/usr/sbin/networksetup", args: ["-setsocksfirewallproxy", service, "127.0.0.1", "\(port)"])
                _ = runCommand("/usr/sbin/networksetup", args: ["-setwebproxystate", service, "on"])
                _ = runCommand("/usr/sbin/networksetup", args: ["-setsecurewebproxystate", service, "on"])
                _ = runCommand("/usr/sbin/networksetup", args: ["-setsocksfirewallproxystate", service, "on"])
            } else {
                _ = runCommand("/usr/sbin/networksetup", args: ["-setwebproxystate", service, "off"])
                _ = runCommand("/usr/sbin/networksetup", args: ["-setsecurewebproxystate", service, "off"])
                _ = runCommand("/usr/sbin/networksetup", args: ["-setsocksfirewallproxystate", service, "off"])
            }
        }
        if !enabled {
            // Clear proxy bypass domains that may have been set
            if !services.isEmpty {
                _ = runCommand("/usr/sbin/networksetup", args: ["-setproxybypassdomains", services[0], "Empty"])
            }
        }
    }

    func selectProfile(at index: Int, forceReload: Bool = false) {
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

    

    

    

    

    

    

    @discardableResult
    func saveCurrent() throws -> URL {
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

    func refreshNodesFromEditor() {
        nodes = parseNodes(from: editor.string)
        nodeGroups = parseNodeGroups(from: editor.string)
        nodeTable.reloadData()
        populateRuleStrategyPopup()
        refreshNodeGroupsView()
        selectCurrentNodeInTable()
    }

    

    func selectNode(at index: Int) {
        guard nodes.indices.contains(index) else { return }
        selectNode(nodes[index].tag, inGroup: TungBoxConfig.tagManual)
    }

    func selectNode(_ nodeTag: String, inGroup groupTag: String) {
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
                        self.refreshNodesFromEditor()
                        if self.isProxyRuntimeRunning() && !switchedByAPI {
                            self.runner.stop()
                            if self.isTunEnabled {
                                try self.enableTunServiceSafely(configText: self.editor.string)
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


    func applyTunPreference(restartIfRunning: Bool) throws {
        let wasRunning = runner.isRunning || TunServiceManager.status(store: store).isRunning
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
                runner.stop()
                try enableTunServiceSafely(configText: editor.string)
                appendLog("[TUN] 已更新 TUN 服务配置\n")
            } else {
                runner.stop()
                try stopTunBeforeStartingNormalProxy(timeout: 8)
                try runner.start(config: url, elevated: false)
                appendLog("[TUN] 已关闭 TUN 并用普通代理重启\n")
            }
        } else if wasRunning {
            if isTunEnabled {
                runner.stop()
                try enableTunServiceSafely(configText: editor.string)
            } else {
                try stopTunBeforeStartingNormalProxy(timeout: 8)
            }
        } else if !isTunEnabled {
            try stopTunBeforeStartingNormalProxy(timeout: 8)
        }
    }

    func preparedTunConfigText(from configText: String) throws -> String {
        guard var config = parseConfigObject(from: configText) else {
            throw NSError.user("当前配置不是有效 JSON")
        }
        let modeValue = readMode(from: config)
        config = setTunEnabled(true, in: config)
        config = ensureModeSupport(in: config, mode: Mode(value: modeValue, displayName: modeDisplayName(modeValue)))
        config = keepLoopbackLocalProxyInboundForTunRuntime(in: config)
        config = bindTunEgressToPhysicalInterface(in: config)
        return try renderConfig(config)
    }

    func bindTunEgressToPhysicalInterface(in config: [String: Any]) -> [String: Any] {
        var config = config
        guard let interface = TunServiceManager.defaultNetworkInterface() else {
            appendLog("[TUN] 警告：未找到物理网络接口，TUN 出站流量可能形成递归\n")
            return config
        }

        appendLog("[TUN] 绑定 sing-box 出站流量到物理接口: \(interface)\n")

        // 设置全局默认接口
        var route = config["route"] as? [String: Any] ?? [:]
        route["default_interface"] = interface
        config["route"] = route

        // 为真实节点 outbound 绑定物理接口
        if var outbounds = config["outbounds"] as? [[String: Any]] {
            let virtualTypes: Set<String> = ["selector", "urltest", "url-test", "direct", "block", "dns"]
            for i in outbounds.indices {
                let type = (outbounds[i]["type"] as? String ?? "").lowercased()
                guard !virtualTypes.contains(type) else { continue }
                outbounds[i]["bind_interface"] = interface
            }
            config["outbounds"] = outbounds
        }

        // 确保 DNS 服务器走正确的出口
        if var dns = config["dns"] as? [String: Any],
           var servers = dns["servers"] as? [[String: Any]] {
            for i in servers.indices {
                if servers[i]["detour"] == nil {
                    servers[i]["detour"] = "direct"
                }
            }
            dns["servers"] = servers
            config["dns"] = dns
        }

        return config
    }

    func keepLoopbackLocalProxyInboundForTunRuntime(in config: [String: Any]) -> [String: Any] {
        var config = config
        var inbounds = config["inbounds"] as? [[String: Any]] ?? []
        let localTypes: Set<String> = ["mixed", "http", "socks"]
        var keptLoopbackProxy = false
        var droppedExternalProxy = false

        inbounds = inbounds.compactMap { inbound in
            guard let type = (inbound["type"] as? String)?.lowercased(),
                  localTypes.contains(type) else {
                return inbound
            }

            var inbound = inbound
            let listen = (inbound["listen"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if listen == nil || listen?.isEmpty == true {
                inbound["listen"] = "127.0.0.1"
                keptLoopbackProxy = true
                return inbound
            }
            if let listen, ["127.0.0.1", "localhost", "::1"].contains(listen) {
                keptLoopbackProxy = true
                return inbound
            }

            droppedExternalProxy = true
            return nil
        }
        config["inbounds"] = inbounds
        if keptLoopbackProxy {
            appendLog("[TUN] 调试：保留本地回环代理入口用于对照测试\n")
        }
        if droppedExternalProxy {
            appendLog("[TUN] 已移除非回环本地代理入口，避免 root TUN 服务暴露端口\n")
        }
        return config
    }

    func clearTunRuntimeEgressBindings(in config: [String: Any]) -> [String: Any] {
        var config = config
        var changed = false

        if var route = config["route"] as? [String: Any],
           route.removeValue(forKey: "default_interface") != nil {
            config["route"] = route
            changed = true
        }

        if var outbounds = config["outbounds"] as? [[String: Any]] {
            var outboundsChanged = false
            for index in outbounds.indices {
                if outbounds[index].removeValue(forKey: "bind_interface") != nil {
                    outboundsChanged = true
                }
                if outbounds[index].removeValue(forKey: "inet4_bind_address") != nil {
                    outboundsChanged = true
                }
                if outbounds[index].removeValue(forKey: "inet6_bind_address") != nil {
                    outboundsChanged = true
                }
            }
            if outboundsChanged {
                config["outbounds"] = outbounds
                changed = true
            }
        }

        if changed {
            appendLog("[TUN] 已清理运行时出口绑定，交由 sing-box/macOS 自动选择上游接口\n")
        } else {
            appendLog("[TUN] 运行时出口：未强制绑定物理接口\n")
        }

        return config
    }

    func setTunEnabled(_ enabled: Bool, in config: [String: Any]) -> [String: Any] {
        var config = config
        var inbounds = config["inbounds"] as? [[String: Any]] ?? []
        inbounds.removeAll { ($0["type"] as? String)?.lowercased() == "tun" }
        if enabled {
            var log = config["log"] as? [String: Any] ?? [:]
            log["level"] = "warn"
            config["log"] = log

            inbounds.insert([
                "type": "tun",
                "tag": "tun-in",
                "stack": "mixed",
                "mtu": 1500,
                "address": [
                    "172.19.0.1/30",
                    "fdfe:dcba:9876::1/126"
                ],
                "auto_route": true,
                "strict_route": false,
                "route_address": [
                    "0.0.0.0/1",
                    "128.0.0.0/1",
                    "::/1",
                    "8000::/1"
                ],
                "route_exclude_address": [
                    "10.0.0.0/8",
                    "172.16.0.0/12",
                    "192.168.0.0/16",
                    "169.254.0.0/16",
                    "224.0.0.0/4",
                    "240.0.0.0/4",
                    "fe80::/10",
                    "fec0::/10",
                    "fc00::/7",
                    "ff00::/8"
                ]
            ], at: 0)

            let outbounds = config["outbounds"] as? [[String: Any]] ?? []
            let proxyTag = preferredProxyTag(from: outbounds)
            var route = config["route"] as? [String: Any] ?? [:]
            if proxyTag != "direct" {
                if (route["final"] as? String).map({ $0 == "direct" }) ?? true {
                    route["final"] = proxyTag
                }
            }
            config["route"] = route
        } else {
            if var route = config["route"] as? [String: Any] {
                route.removeValue(forKey: "default_interface")
                route.removeValue(forKey: "auto_detect_interface")
                if route.isEmpty {
                    config.removeValue(forKey: "route")
                } else {
                    config["route"] = route
                }
            }
        }
        config["inbounds"] = inbounds
        config = setTunCacheFile(enabled: enabled, in: config)
        return config
    }

    func setTunCacheFile(enabled: Bool, in config: [String: Any]) -> [String: Any] {
        var config = config
        var experimental = config["experimental"] as? [String: Any] ?? [:]
        var cacheFile = experimental["cache_file"] as? [String: Any] ?? [:]

        if enabled {
            cacheFile["enabled"] = true
            cacheFile["path"] = TunServiceManager.cachePath
            experimental["cache_file"] = cacheFile
            config["experimental"] = experimental
            return config
        }

        if cacheFile["path"] as? String == TunServiceManager.cachePath {
            cacheFile.removeValue(forKey: "path")
            experimental["cache_file"] = cacheFile
            config["experimental"] = experimental
        }
        return config
    }

    

    func parseNodes(from text: String) -> [NodeInfo] {
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

    func parseNodeGroups(from text: String) -> [NodeGroupInfo] {
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

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    func buildRulesSummary(from text: String) -> String {
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

    func firstOutbound(in outbounds: [[String: Any]], tag: String) -> [String: Any]? {
        outbounds.first { ($0["tag"] as? String) == tag }
    }

    func modeDisplayName(_ mode: String) -> String {
        switch mode.lowercased() {
        case "global": return "全局"
        case "direct": return "直连"
        default: return "规则"
        }
    }

    func boolText(_ value: Any?) -> String {
        guard let value = value as? Bool else { return "未设置" }
        return value ? "开启" : "关闭"
    }

    func joined(_ values: [String]) -> String {
        values.isEmpty ? "无" : values.joined(separator: ", ")
    }

    func describeRouteRule(_ rule: [String: Any]) -> String {
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

    func describeDNSRule(_ rule: [String: Any]) -> String {
        let server = (rule["server"] as? String) ?? "未设置 DNS"
        if let clashMode = rule["clash_mode"] as? String {
            return "模式 \(modeDisplayName(clashMode)) -> \(server)"
        }
        if let ruleSet = rule["rule_set"] {
            return "规则集 \(compactDescription(ruleSet)) -> \(server)"
        }
        return "\(compactDescription(rule)) -> \(server)"
    }

    func compactDescription(_ value: Any) -> String {
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
                try enableTunServiceSafely(configText: editor.string)
            } else {
                try runner.start(config: url, elevated: false)
            }
            appendLog("[mode] sing-box 已按新模式重启\n")
            refreshStatus()
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

    func readMode(from config: [String: Any]) -> String {
        let experimental = config["experimental"] as? [String: Any]
        let clashAPI = experimental?["clash_api"] as? [String: Any]
        return (clashAPI?["default_mode"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Rule"
    }

    func ensureModeSupport(in config: [String: Any], mode: Mode) -> [String: Any] {
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
        rules.removeAll { isManagedRuntimeRule($0) }
        rules = [
            ["action": "sniff"],
            ["protocol": "dns", "action": "hijack-dns"],
            ["clash_mode": "direct", "outbound": "direct"],
            ["clash_mode": "global", "outbound": proxyTag]
        ] + rules
        route["rules"] = rules
        // sing-box 1.12+: outbound dials that chain to domain-based routing require a
        // default domain resolver. Without this, sing-box warns now and will FATAL in 1.14.
        if route["default_domain_resolver"] == nil {
            if let dns = config["dns"] as? [String: Any],
               let servers = dns["servers"] as? [[String: Any]],
               let firstTag = servers.first?["tag"] as? String {
                route["default_domain_resolver"] = firstTag
            }
        }
        config["route"] = route

        return config
    }

    func isManagedRuntimeRule(_ rule: [String: Any]) -> Bool {
        if let action = (rule["action"] as? String)?.lowercased() {
            if action == "sniff" { return true }
            if action == "hijack-dns",
               (rule["protocol"] as? String)?.lowercased() == "dns" {
                return true
            }
        }
        guard let clashMode = (rule["clash_mode"] as? String)?.lowercased() else { return false }
        return clashMode == "direct" || clashMode == "global"
    }

    func preferredProxyTag(from outbounds: [[String: Any]]) -> String {
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

    func parseConfigObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    func renderConfig(_ config: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? ""
    }

    

    

    

    

    

    

    

    

    

    func resolveActiveOutbound(proxiesObj: [String: Any]?) -> (name: String, isAuto: Bool) {
        return resolveActiveOutboundForGroup(groupTag: "节点选择", proxiesObj: proxiesObj)
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

    func refreshSubscriptionBadge() {
        // Index 3 = 订阅 in the sidebar nav
        if navButtons.indices.contains(3) {
            navButtons[3].hasBadge = subscriptions.isEmpty
        }
        refreshSubscriptionEmptyState()
    }

    func refreshStatus() {
        let isRunning = isProxyRuntimeRunning()
        let isActiveOrRequested = isProxyServiceActiveOrRequested()
        statusChip.isActive = isActiveOrRequested
        syncProxyPreferenceControls()
        refreshTrayIcon()
        refreshHomeFeatureStatus()
        
        if isActiveOrRequested {
            let activeNodeInfo = resolveActiveOutbound(proxiesObj: lastProxiesObj)
            let formattedNode = activeNodeInfo.isAuto ? "\(activeNodeInfo.name) (自动)" : activeNodeInfo.name
            currentNodeNameLabel.stringValue = formattedNode
            let activeDelay = nodes.first(where: { $0.tag == activeNodeInfo.name })?.delay ?? "—"
            currentNodeDelayLabel.stringValue = activeDelay == "未测试" ? "—" : activeDelay
            
            if isRunning {
                if statsTimer == nil {
                    startStatsTimer()
                }
            } else {
                clearConnections()
                stopConnectionsRefreshTimer()
                stopStatsTimer()
            }
        } else {
            currentNodeNameLabel.stringValue = "未连接"
            currentNodeDelayLabel.stringValue = "—"
            clearConnections()
            stopConnectionsRefreshTimer()
            stopStatsTimer()
        }
    }

    func startStatsTimer() {
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
    
    func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
        updateConnectionsCard(value: "0", detail: "服务未运行")
        uploadValueLabel.stringValue = "0 B/s"
        downloadValueLabel.stringValue = "0 B/s"
        trafficStatsValueLabel.stringValue = "0 B"
        trafficStatsDetailLabel.stringValue = "上传: 0 B   下载: 0 B"
    }

    
    
    

    

    

    @MainActor
    func showError(_ error: Error) {
        let dialog = showMD3Dialog(
            title: "错误提示",
            message: error.localizedDescription,
            customView: nil,
            confirmTitle: "确定",
            cancelTitle: ""
        )
        dialog.onConfirm = { [weak dialog] in
            dialog?.dismiss()
        }
        dialog.onCancel = { [weak dialog] in
            dialog?.dismiss()
        }
    }

    @MainActor
    func showToast(_ message: String) {
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

    func defaultConfig() -> String {
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
        stopService(clearSystemProxySynchronously: true)
    }

    func setSystemProxy(enabled: Bool, port: Int, rollbackOnMismatch: Bool = false) {
        systemProxyOperationID += 1
        let operationID = systemProxyOperationID
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
            
            if enabled {
                Thread.sleep(forTimeInterval: 1.0)
                Task { @MainActor [weak self] in
                    guard let self,
                          operationID == self.systemProxyOperationID,
                          self.isSystemProxyEnabled,
                          !self.isTunEnabled else { return }
                    let status = self.currentSystemProxyStatus(expectedPort: port)
                    guard status.hasExternalProxy else { return }
                    self.appendLog("[警告] 检测到系统代理指向非 TungBox 地址（\(status.message)）。如代理不可用，请检查其他代理软件设置。\n")
                    if rollbackOnMismatch {
                        if self.runner.isRunning {
                            self.runner.stop()
                            self.appendLog("[TungBox] 已停止普通代理服务，避免后台空跑\n")
                        }
                        self.isSystemProxyEnabled = false
                        self.serviceSwitch.isOn = false
                        self.syncProxyPreferenceControls()
                        self.showToast("系统代理未指向 TungBox，已停止代理")
                        self.refreshStatus()
                    }
                }
            }
        }
    }

    nonisolated func currentSystemProxyStatus(expectedPort port: Int) -> (matches: Bool, hasExternalProxy: Bool, message: String) {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return (false, false, "无法读取系统代理")
        }
        let httpEnabled = settings[kCFNetworkProxiesHTTPEnable as String] as? Int ?? 0
        let httpHost = settings[kCFNetworkProxiesHTTPProxy as String] as? String ?? "-"
        let httpPort = settings[kCFNetworkProxiesHTTPPort as String] as? Int ?? 0
        let httpsEnabled = settings[kCFNetworkProxiesHTTPSEnable as String] as? Int ?? 0
        let httpsHost = settings[kCFNetworkProxiesHTTPSProxy as String] as? String ?? "-"
        let httpsPort = settings[kCFNetworkProxiesHTTPSPort as String] as? Int ?? 0
        let httpMatches = httpEnabled == 1 && isLocalProxyHost(httpHost) && httpPort == port
        let httpsMatches = httpsEnabled == 1 && isLocalProxyHost(httpsHost) && httpsPort == port
        if httpMatches && httpsMatches {
            return (true, false, "HTTP/HTTPS 已指向 127.0.0.1:\(port)")
        }
        let httpExternal = httpEnabled == 1 && !(isLocalProxyHost(httpHost) && httpPort == port)
        let httpsExternal = httpsEnabled == 1 && !(isLocalProxyHost(httpsHost) && httpsPort == port)
        return (false, httpExternal || httpsExternal, "HTTP \(httpHost):\(httpPort) \(httpEnabled == 1 ? "开启" : "关闭")，HTTPS \(httpsHost):\(httpsPort) \(httpsEnabled == 1 ? "开启" : "关闭")，预期 127.0.0.1:\(port)")
    }

    nonisolated func isLocalProxyHost(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
    
    nonisolated func getActiveNetworkServices() -> [String] {
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
    
    nonisolated func runCommand(_ binary: String, args: [String], timeoutSeconds: TimeInterval = 3) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
        } catch {
            return error.localizedDescription
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            proc.waitUntilExit()
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            if proc.isRunning {
                proc.terminate()
                Thread.sleep(forTimeInterval: 0.2)
                if proc.isRunning {
                    _ = Darwin.kill(proc.processIdentifier, SIGKILL)
                }
            }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func getMixedProxyPort() -> Int {
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

extension MainWindowController {
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appendLog("[窗口] 控制台已关闭，TungBox 保留在状态栏后台运行。\n")
    }

    func showConsoleWindow() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        checkAppUpdateInBackground()
        appendLog("[窗口] 已从状态栏恢复控制台。\n")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        controller = MainWindowController()
        
        let startSilently = UserDefaults.standard.bool(forKey: "startSilently")
        if isLaunchedAtLogin() && startSilently {
            NSApp.setActivationPolicy(.accessory)
            controller?.appendLog("[启动] 检测到开机自启动且已勾选“静默启动”，只在状态栏运行，已隐藏控制台窗口。\n")
        } else {
            controller?.showConsoleWindow()
        }
        controller?.applyStartupProxyPreference()
    }

    func isLaunchedAtLogin() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getppid()]
        let junk = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        if junk == 0 {
            let name = withUnsafeBytes(of: &info.kp_proc.p_comm) { bytes -> String in
                if let baseAddress = bytes.baseAddress {
                    return String(cString: baseAddress.assumingMemoryBound(to: CChar.self))
                }
                return ""
            }
            return name == "launchd"
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showConsoleWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stopServiceFromDelegate()
    }

    @MainActor
    func setupMainMenu() {
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
