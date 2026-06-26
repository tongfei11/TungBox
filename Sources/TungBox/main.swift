import AppKit
import Darwin
import Foundation
import ServiceManagement

enum TrayIconStyle: Int {
    case iconOnly = 0
    case iconAndSpeed = 1
    case speedOnly = 2

    static let defaultsKey = "trayIconStyle"

    static var current: TrayIconStyle {
        TrayIconStyle(rawValue: UserDefaults.standard.integer(forKey: defaultsKey)) ?? .iconOnly
    }

    var title: String {
        switch self {
        case .iconOnly: return "仅显示图标"
        case .iconAndSpeed: return "显示图标和实时速度"
        case .speedOnly: return "仅显示实时速度"
        }
    }
}

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
    let currentNodeAutoBadge = NSTextField(labelWithString: "自动")
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
    let tunStatusChip = MD3StatusChip()
    let subscriptionNameField = MD3TextField()
    let subscriptionURLField = MD3TextField()
    let serviceLabel = NSTextField(labelWithString: "sing-box：检测中")
    let nodeTestURLField = MD3TextField(string: TungBoxConfig.urlTestURL)
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
    /// Per-feature transition direction — drives the "启动中 / 关闭中" status chip and
    /// the loading spinner next to each switch while a runtime change is in flight.
    enum FeatureTransition { case none, starting, stopping }
    var systemProxyTransition: FeatureTransition = .none
    var tunTransition: FeatureTransition = .none
    var systemProxyOperationID = 0
    // Runtime convergence runs its blocking work (TUN daemon teardown waits, port
    // waits, user sing-box start) on this serial queue so the main thread (and the
    // UI) never freezes. `runtimeTransitionID` is bumped on every reconcile so a
    // stale background transition can detect it has been superseded and skip its
    // final UI refresh.
    let runtimeQueue = DispatchQueue(label: "com.tungbox.runtime")
    var runtimeTransitionID = 0
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
    let tunSwitch = MD3Switch()
    let homeSystemProxyRadio = MD3RadioButton(radioButtonWithTitle: "系统代理", target: nil, action: nil)
    let homeTunRadio = MD3RadioButton(radioButtonWithTitle: "TUN 模式", target: nil, action: nil)
    let settingsSystemProxyRadio = MD3RadioButton(radioButtonWithTitle: "系统代理", target: nil, action: nil)
    let settingsTunRadio = MD3RadioButton(radioButtonWithTitle: "TUN 模式", target: nil, action: nil)
    let settingsSystemProxyCheckbox = MD3Checkbox(checkboxWithTitle: "默认开启代理服务", target: nil, action: nil)
    let settingsLaunchAtLoginCheckbox = MD3Checkbox(checkboxWithTitle: "开机自启动", target: nil, action: nil)
    let settingsStartSilentlyCheckbox = MD3Checkbox(checkboxWithTitle: "静默启动", target: nil, action: nil)
    let trayIconStylePopup = MD3PopUpButton()
    let dnsLocalServerField = MD3TextField()
    let dnsProxyServerField = MD3TextField()
    let dnsStrategyPopup = MD3PopUpButton()
    let dnsFakeIPCheckbox = MD3Checkbox(checkboxWithTitle: "启用 Fake-IP", target: nil, action: nil)
    let dnsFakeIPRangeField = MD3TextField()
    let dnsFakeIPExcludesTextView = NSTextView()
    let dnsReadSystemHostsCheckbox = MD3Checkbox(checkboxWithTitle: "读取系统 /etc/hosts", target: nil, action: nil)
    let dnsCustomHostsTextView = NSTextView()
    var dnsApplyWorkItem: DispatchWorkItem?
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
    var currentUploadSpeed = 0
    var currentDownloadSpeed = 0
    var wasTunActiveInThisSession = false
    var wasProxyActiveInThisSession = false
    var lastTrayActiveState: Bool? = nil
    var trayImageView: NSImageView?
    var traySpeedLabel: NSTextField?
    var statsTimer: Timer?
    var runningStatsMissCount = 0
    var lastProxiesObj: [String: Any]? = nil
    var prevConnections: [ConnectionInfo] = []
    /// 上一次拉到的 sing-box 进程级累计字节数（按端口分别记，因为用户代理 9090 和
    /// TUN 守护 9091 是独立进程）。流量累计用这两个数字相减得 delta，能算上 UDP /
    /// IPv6 / 已关闭的短连接（per-connection delta 会漏算 YouTube 那种 QUIC 短流）。
    var prevTrafficTotals: [Int: (upload: Int64, download: Int64)] = [:]
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
        registerSystemWakeObserver()
    }

    func normalizeProxyPreferences() {
        if UserDefaults.standard.object(forKey: "systemProxyDefaultEnabled") == nil {
            UserDefaults.standard.set(isSystemProxyDefaultEnabled, forKey: "systemProxyDefaultEnabled")
        }
        // TUN was on last session but its service is gone → drop the flag and clean up.
        if isTunEnabled && !TunServiceManager.hasInstalledServiceFiles {
            isTunEnabled = false
            UserDefaults.standard.set(false, forKey: "tunEnabled")
            try? TunServiceManager.disable(store: store)
            appendLog("[TUN] 检测到 TUN 服务不可用，已关闭 TUN 模式。请到 设置 > TUN 设置 重新安装。\n")
        }
        runner.stopStaleUserProcesses()
    }

    func applyStartupProxyPreference() {
        // Restore the last exit state for both independent switches (persisted on
        // every toggle). reconcileRuntime converges the runtime to match, doing all
        // blocking work off the main thread — so the console window / tray icon are
        // already painted and the (slow) TUN bring-up happens in the background.
        isSystemProxyEnabled = UserDefaults.standard.bool(forKey: "systemProxyEnabled")
        if isSystemProxyEnabled || isTunEnabled {
            // Show the "启动中" state + spinner up front so the home cards reflect the
            // pending bring-up immediately rather than flashing "未连接" first.
            beginFeatureTransition(
                systemProxy: isSystemProxyEnabled ? .starting : FeatureTransition.none,
                tun: isTunEnabled ? .starting : FeatureTransition.none
            )
            appendLog("[启动] 恢复状态：系统代理=\(isSystemProxyEnabled ? "开" : "关")，TUN=\(isTunEnabled ? "开" : "关")\n")
        } else {
            appendLog("[启动] 本次启动不自动开启代理。\n")
        }
        syncProxyPreferenceControls()
        refreshStatus()
        // Defer convergence by one run-loop cycle so the window/tray paint first.
        DispatchQueue.main.async { [weak self] in
            self?.reconcileRuntime(reason: "启动")
        }
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
    // The "代理服务" entry now means "turn the system proxy on". The runtime is
    // converged by reconcileRuntime() based on the two independent switches.
    func startService() {
        isSystemProxyEnabled = true
        UserDefaults.standard.set(true, forKey: "systemProxyEnabled")
        reconcileRuntime(reason: "启动代理服务")
    }

    func markProxyStartupFailed() {
        clearFeatureTransitions()
        syncProxyPreferenceControls()
    }

    /// Mark a feature as transitioning (drives the chip text + spinner). Pass nil to
    /// leave a feature's current transition untouched.
    func beginFeatureTransition(systemProxy: FeatureTransition? = nil, tun: FeatureTransition? = nil) {
        if let systemProxy { systemProxyTransition = systemProxy }
        if let tun { tunTransition = tun }
        isProxyServiceTransitioning = systemProxyTransition != .none || tunTransition != .none
    }

    /// Clear all transition indicators (chips fall back to their on/off state).
    func clearFeatureTransitions() {
        systemProxyTransition = .none
        tunTransition = .none
        isProxyServiceTransitioning = false
    }

    /// Single source of truth that converges the runtime to the two independent
    /// switches `isSystemProxyEnabled` and `isTunEnabled` (they can be on together):
    ///   • TUN on  → run the root daemon (it also serves 7890); stop the user runner.
    ///   • TUN off → stop the daemon; if system proxy is on, run the user runner on
    ///               7890, otherwise stop it.
    ///   • The OS system-proxy setting points at 7890 whenever system proxy is on,
    ///     regardless of which sing-box currently serves that port.
    /// Converges the runtime to the two INDEPENDENT switches. The TUN daemon (root,
    /// utun29 + clash 9091) and the user proxy (user, 7890 + clash 9090) are now
    /// separate processes that never share a port — so each switch only ever
    /// starts/stops its own thing, and toggling TUN never disturbs the user proxy
    /// (no hand-off, no race, no "关闭TUN把代理也关了").
    func reconcileRuntime(reason: String, forceRestart: Bool = false) {
        let port = getMixedProxyPort()
        runtimeTransitionID += 1
        let token = runtimeTransitionID
        let wantSystemProxy = isSystemProxyEnabled
        let wantTun = isTunEnabled
        let runnerRef = runner
        let storeCopy = store
        let log: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor [weak self] in self?.appendLog(text) }
        }

        // Build the configs on the main thread (touches the editor). The user proxy
        // config is a plain NON-TUN local proxy (7890); the TUN daemon config is
        // derived from it inside enableTunServiceSafely (utun29, no 7890/9090).
        var userProxyURL: URL? = nil
        var userConfigText: String? = nil
        if wantSystemProxy || wantTun {
            guard ensureCoreAvailableForStart() else { markProxyStartupFailed(); return }
            guard selectedIndex != nil, !nodes.isEmpty else {
                showError(NSError.user("没有可用的配置或节点，请先导入订阅。"))
                markProxyStartupFailed()
                return
            }
            do {
                guard var config = parseConfigObject(from: editor.string) else {
                    throw NSError.user("当前配置不是有效 JSON")
                }
                config = setTunEnabled(false, in: config)   // user proxy is never TUN
                config = ensureModeSupport(in: config, mode: selectedMode())
                editor.string = try renderConfig(config)
                userProxyURL = try saveCurrent()
                userConfigText = editor.string
            } catch {
                showError(error)
                markProxyStartupFailed()
                return
            }
        }

        if wantSystemProxy { wasProxyActiveInThisSession = true }
        appendLog("[TungBox] 正在切换运行状态（\(reason)）...\n")
        Task { @MainActor [weak self] in
            guard let self, token == self.runtimeTransitionID else { return }

            // ===== 1) Converge the TUN daemon (utun29) — independent of the proxy =====
            if wantTun {
                do {
                    let status = try await self.runSerializedOffMain { TunServiceManager.status(store: storeCopy) }
                    guard token == self.runtimeTransitionID else { return }
                    guard status.isUsable else {
                        throw NSError.user("TUN 服务不可用：\(status.displayText)。请到 设置 > TUN 设置处理。")
                    }
                    try self.enableTunServiceSafely(configText: userConfigText!)
                    self.appendLog("[TungBox] TUN 已启用（\(reason)）\n")
                } catch {
                    guard token == self.runtimeTransitionID else { return }
                    self.appendLog("[TungBox] TUN 启用失败（\(reason)）：\(error.localizedDescription)\n")
                    self.isTunEnabled = false
                    UserDefaults.standard.set(false, forKey: "tunEnabled")
                    self.tunTransition = .none
                    self.syncProxyPreferenceControls()
                    self.showError(error)
                }
            } else {
                // Closing TUN is INSTANT: just drop the request file. The daemon
                // reclaims utun29 and restores the system DNS on its own in the
                // background. We do NOT block the UI on that, and we NEVER touch the
                // user proxy — so the proxy keeps running and the switch feels
                // immediate, exactly like a competitor's transparent-proxy toggle.
                self.stopTunRequestHeartbeat()
                try? TunServiceManager.disable(store: storeCopy)
                self.wasTunActiveInThisSession = false
                self.appendLog("[TungBox] TUN 已关闭（守护进程后台回收 utun29 与 DNS）\n")
                let bgStore = storeCopy
                Task.detached { _ = TunServiceManager.waitUntilStopped(store: bgStore, timeout: 8) }
            }
            guard token == self.runtimeTransitionID else { return }

            // ===== 2) Converge the user proxy (7890) — independent of TUN =====
            if wantSystemProxy {
                do {
                    if forceRestart {
                        try await self.runSerializedOffMain { if runnerRef.isRunning { runnerRef.stop() } }
                    }
                    if !runnerRef.isRunning, let url = userProxyURL {
                        try await self.runSerializedOffMain {
                            try self.startNormalProxyBlocking(runner: runnerRef, config: url, port: port, reason: reason, log: log)
                        }
                    }
                    guard token == self.runtimeTransitionID else { return }
                    try await self.runSerializedOffMain { self.applySystemProxyBlocking(enabled: true, port: port) }
                } catch {
                    guard token == self.runtimeTransitionID else { return }
                    self.appendLog("[TungBox] 系统代理启动失败（\(reason)）：\(error.localizedDescription)\n")
                    self.isSystemProxyEnabled = false
                    UserDefaults.standard.set(false, forKey: "systemProxyEnabled")
                    self.systemProxyTransition = .none
                    try? await self.runSerializedOffMain { self.applySystemProxyBlocking(enabled: false, port: port) }
                    self.syncProxyPreferenceControls()
                    self.showError(error)
                }
            } else {
                try await self.runSerializedOffMain {
                    if runnerRef.isRunning { runnerRef.stop() }
                    self.applySystemProxyBlocking(enabled: false, port: port)
                }
            }

            guard token == self.runtimeTransitionID else { return }
            self.clearFeatureTransitions()
            self.refreshStatus()
            self.scheduleConnectionsRefreshAfterStart()
        }
    }

    /// Run blocking runtime work on the serial `runtimeQueue` (off the main thread)
    /// and await the result without blocking the main actor. Serializing here means
    /// two rapid toggles can never manipulate the runner/ports concurrently.
    @discardableResult
    private func runSerializedOffMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            runtimeQueue.async {
                do { cont.resume(returning: try work()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    /// Drop the TUN request flag and block until the root sing-box has released its
    /// port + interface, so a follow-on user proxy can safely bind 7890. No-op when
    /// TUN is not active. `nonisolated` — MUST run off the main thread (it sleeps).
    nonisolated func tearDownTunDaemonBlocking(store: Store, wasTunActive: Bool, log: @Sendable (String) -> Void) {
        let active = wasTunActive
            || TunServiceManager.status(store: store).isRunning
            || TunServiceManager.hasRequestFiles(store: store)
            || TunServiceManager.hasNetworkResidue()
        guard active else { return }
        try? TunServiceManager.disable(store: store)
        log("[TungBox] TUN 标记已关闭，等待守护进程回收端口...\n")
        if TunServiceManager.waitUntilStopped(store: store, timeout: 8) {
            log("[TungBox] TUN 已确认回收\n")
        } else {
            let residue = TunServiceManager.networkResidueDescription() ?? "未知残留"
            log("[警告] TUN 未确认回收：\(residue)。请到设置重新安装 TUN 服务。\n")
        }
    }

    /// Apply the OS system-proxy setting for every active service, off the main
    /// thread (networksetup spawns a subprocess per call). `nonisolated`.
    nonisolated func applySystemProxyBlocking(enabled: Bool, port: Int) {
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
                disableSystemProxyIfOwned(service: service, port: port)
            }
        }
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
        wasTunActiveInThisSession = false
    }

    /// Main-thread convenience wrapper around `startNormalProxyBlocking` (used by
    /// legacy callers). Runs the blocking port waits on the calling thread.
    func startNormalProxy(config: URL, port: Int, reason: String) throws {
        try startNormalProxyBlocking(runner: runner, config: config, port: port, reason: reason) { [weak self] text in
            Task { @MainActor [weak self] in self?.appendLog(text) }
        }
    }

    /// Start the user sing-box on `port`, off the main thread.
    ///
    /// During a TUN→system-proxy handoff the mixed (7890) and clash (9090) ports are
    /// still owned by the TUN daemon's *root* sing-box, which keeps listening for a
    /// few seconds after we drop the request while it drains. `reapStrayUserProcesses`
    /// only kills *user*-owned strays — it cannot touch the root daemon — and the
    /// daemon-PID check in `waitUntilStopped` is throttled and can report "gone" a
    /// beat too early. So the real, authoritative gate is the ports themselves:
    /// block until BOTH are actually free before binding, otherwise sing-box FATALs
    /// with "address already in use" and 7890 never comes up. `nonisolated` so it can
    /// run inside the serial runtime queue.
    nonisolated func startNormalProxyBlocking(runner: Runner, config: URL, port: Int, reason: String, log: @Sendable (String) -> Void) throws {
        log("[TungBox] 正在检查普通代理配置...\n")
        _ = try runner.check(config: config)
        let clashPort = 9090
        // Clear our own strays, then give the ports a SHORT chance to free. We do NOT
        // hard-fail on the bind probe anymore — sing-box binds with SO_REUSEADDR and
        // is the real authority on whether the port is usable; the probe was vetoing
        // startup even when the port was actually bindable. If it doesn't clear fast,
        // SIGKILL any sing-box still holding it and just proceed to start.
        runner.reapStrayUserProcesses()
        // Proactively SIGKILL any sing-box still holding 7890/9090 in ANY state
        // (e.g. bound-but-not-listening after a FATAL/mid-exit — the real cause of
        // the EADDRINUSE we kept hitting). Then a short settle wait.
        killSingBoxHoldersOfPorts([port, clashPort])
        if !waitForLocalTCPPortsFree([port, clashPort], timeout: 3.0) {
            runner.reapStrayUserProcesses()
            killSingBoxHoldersOfPorts([port, clashPort])
            _ = waitForLocalTCPPortsFree([port, clashPort], timeout: 2.0)
            log("[TungBox] 端口探测：\(portHoldersDescription([port, clashPort]))\n")
        }
        try runner.start(config: config, elevated: false)
        if waitForLocalTCPPort(port, timeout: 6.0) {
            log("[TungBox] \(reason)完成，本地代理端口 \(port) 已监听\n")
            return
        }
        log("[TungBox] 端口 \(port) 未在首次启动内监听，重试一次...\n")
        runner.stop()
        runner.reapStrayUserProcesses()
        killSingBoxHoldersOfPorts([port, clashPort])
        _ = waitForLocalTCPPortsFree([port, clashPort], timeout: 3.0)
        try runner.start(config: config, elevated: false)
        guard waitForLocalTCPPort(port, timeout: 6.0) else {
            runner.stop()
            throw NSError.user("普通代理启动失败：本地端口 \(port) 未开始监听。请查看日志中的 sing-box 退出原因。端口探测：\(portHoldersDescription([port, clashPort]))")
        }
        log("[TungBox] \(reason)完成（重试后），本地代理端口 \(port) 已监听\n")
    }

    nonisolated func waitForLocalTCPPortFree(_ port: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !canConnectLocalTCPPort(port) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return !canConnectLocalTCPPort(port)
    }

    /// Wait until every port in `ports` can actually be BOUND. Authoritative gate
    /// for the TUN→system-proxy handoff. A connect test is NOT enough: while the
    /// TUN daemon's sing-box drains on shutdown it closes its listener (so connect
    /// is already refused — port looks "free") yet the process still holds the bound
    /// socket until it fully exits a couple seconds later, so a fresh `bind` fails
    /// with "address already in use". Only an explicit bind test reflects what
    /// sing-box's own bind will see.
    nonisolated func waitForLocalTCPPortsFree(_ ports: [Int], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if ports.allSatisfy({ canBindLocalTCPPort($0) }) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return ports.allSatisfy { canBindLocalTCPPort($0) }
    }

    /// Whether 127.0.0.1:`port` can be bound right now by sing-box.
    ///
    /// MUST mirror sing-box's own bind options or the gate is wrong. sing-box is Go,
    /// and Go's net listener sets SO_REUSEADDR — so it can bind a port whose old
    /// connections are still in TIME_WAIT. Testing WITHOUT SO_REUSEADDR (as an
    /// earlier version did) made this fail with EADDRINUSE for the full ~15s
    /// TIME_WAIT window after the TUN daemon's sing-box (which had served live
    /// connections on 7890) exited — even though sing-box could have bound
    /// immediately. That stalled and then failed every TUN→system-proxy handoff.
    /// Verified: a plain bind fails errno 48 in TIME_WAIT; with SO_REUSEADDR it
    /// succeeds the instant the listener is gone.
    nonisolated func canBindLocalTCPPort(_ port: Int) -> Bool {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    /// Diagnostic: actually attempt the bind and report the exact failure (errno +
    /// strerror), so we can tell EADDRINUSE (something holds it) from EMFILE (we ran
    /// out of file descriptors) from anything else — instead of guessing.
    nonisolated func bindFailureReason(_ port: Int) -> String {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 {
            let e = errno
            return "\(port): socket() 失败 errno=\(e)(\(String(cString: strerror(e))))"
        }
        defer { Darwin.close(fd) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let rc = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc == 0 { return "\(port): 可 bind" }
        let e = errno
        return "\(port): bind 失败 errno=\(e)(\(String(cString: strerror(e))))"
    }

    /// SIGKILL any *sing-box* process currently LISTENING on the given local ports.
    /// This is the decisive way to reclaim 7890/9090 from a lingering instance — our
    /// own user sing-box that was SIGTERM'd and is still draining keeps the listener
    /// open, and SO_REUSEADDR can't bind past a live listener. We only kill processes
    /// whose command line contains "sing-box" so we never touch an unrelated app.
    nonisolated func killSingBoxHoldersOfPorts(_ ports: [Int]) {
        for port in ports {
            // NO `-sTCP:LISTEN` filter: a sing-box that bound the port but FATAL'd
            // before listen() (or is mid-exit) still HOLDS the bound socket and
            // causes EADDRINUSE, yet shows no LISTEN state. Match any TCP socket on
            // the port; we only kill processes whose command is sing-box.
            let pidList = runCommand("/usr/sbin/lsof", args: ["-nP", "-iTCP:\(port)", "-t"], timeoutSeconds: 2)
            for token in pidList.split(whereSeparator: { $0 == "\n" || $0 == " " || $0 == "\t" }) {
                guard let pid = Int32(token) else { continue }
                let cmd = runCommand("/bin/ps", args: ["-p", "\(pid)", "-o", "command="], timeoutSeconds: 2)
                guard cmd.contains("sing-box") else { continue }
                Darwin.kill(pid, SIGKILL)
            }
        }
    }

    /// Human-readable description of who holds the given ports + the precise bind
    /// failure (errno) + our own open-fd count, so a failure is fully self-diagnosing.
    nonisolated func portHoldersDescription(_ ports: [Int]) -> String {
        var holders: [String] = []
        for port in ports {
            let out = runCommand("/usr/sbin/lsof", args: ["-nP", "-iTCP:\(port)"], timeoutSeconds: 2)
            for line in out.split(separator: "\n").dropFirst().prefix(3) {
                let cols = line.split(separator: " ", omittingEmptySubsequences: true)
                if cols.count >= 3 {
                    holders.append("\(port):\(cols[0])(pid \(cols[1]),uid \(cols[2]))")
                }
            }
        }
        let reasons = ports.map { bindFailureReason($0) }.joined(separator: ", ")
        // Our own open file-descriptor count — to catch fd exhaustion (EMFILE).
        let myFD = runCommand("/usr/sbin/lsof", args: ["-p", "\(getpid())"], timeoutSeconds: 2)
            .split(separator: "\n").count
        let who = holders.isEmpty ? "无监听者" : holders.joined(separator: "; ")
        return "\(who)；bind 探测=[\(reasons)]；本进程fd=\(myFD)"
    }

    nonisolated func waitForLocalTCPPort(_ port: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if canConnectLocalTCPPort(port) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    nonisolated func canConnectLocalTCPPort(_ port: Int) -> Bool {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
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
            let proxyOK = self.runHTTPHealthCheck(url: TungBoxConfig.urlTestURL, timeout: 8)
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
                // Diagnostic only: this HTTP probe can fail transiently right after
                // start (DNS cache still settling, node not yet selected) even when
                // the TUN is healthy, so keep it in the log without alarming the user
                // with a toast. Hard startup failures are surfaced by
                // verifyTunStartupAsync (process + interface check) instead.
                self.appendLog("[TUN] 连通性检查未通过：\(failed)（可能为启动初期的瞬时结果，仅记录用于诊断）\n")
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
            "--http1.1",
            "--noproxy", "*",
            "--max-time", "\(Int(timeout))",
            "--output", "/dev/null",
            url
        ]
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "http_proxy": "",
            "https_proxy": "",
            "all_proxy": "",
            "HTTP_PROXY": "",
            "HTTPS_PROXY": "",
            "ALL_PROXY": "",
            "NO_PROXY": "*",
            "no_proxy": "*"
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

    func stopService(clearSystemProxySynchronously: Bool = false, isTerminating: Bool = false) {
        let shouldDisableTun = wasTunActiveInThisSession && (
            isTunEnabled
            || TunServiceManager.status(store: store).isRunning
            || TunServiceManager.hasRequestFiles(store: store)
            || TunServiceManager.hasNetworkResidue()
        )
        let shouldStopNormalProxy = runner.isRunning
        let shouldClearSystemProxy = wasProxyActiveInThisSession && (isSystemProxyEnabled || shouldStopNormalProxy)

        // 1. Tell TUN daemon to stop (removes enabled flag; daemon cleanly kills TUN child, keeps daemon alive)
        if shouldDisableTun {
            stopTunRequestHeartbeat()
            try? TunServiceManager.disable(store: store)
            appendLog("[TungBox] TUN 标记已关闭\n")
            if isTerminating {
                // App is quitting: removing the request files is all we owe the
                // persistent root daemon — it reclaims utun29 and restores the
                // system DNS on its own within ~1s. Never block the main thread
                // (and the app's exit) waiting for that reclaim to finish.
                appendLog("[TungBox] 退出：已交由后台守护进程回收 TUN\n")
                wasTunActiveInThisSession = false
            } else if clearSystemProxySynchronously {
                let timeout: TimeInterval = 8
                if TunServiceManager.waitUntilStopped(store: store, timeout: timeout) {
                    appendLog("[TungBox] TUN 已确认回收\n")
                } else {
                    let residue = TunServiceManager.networkResidueDescription() ?? "未知残留"
                    appendLog("[警告] TUN 未在 \(Int(timeout)) 秒内确认回收：\(residue)。请到设置重新安装 TUN 服务以更新安全停机脚本。\n")
                    showToast("TUN 未确认回收，请重新安装 TUN 服务")
                }
                wasTunActiveInThisSession = false
            } else {
                let storeCopy = self.store
                appendLog("[TungBox] 正在后台等待回收 TUN 网卡...\n")
                Task.detached { [weak self] in
                    let success = TunServiceManager.waitUntilStopped(store: storeCopy, timeout: 6)
                    let residue = success ? nil : (TunServiceManager.networkResidueDescription() ?? "未知残留")
                    
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        if success {
                            self.appendLog("[TungBox] TUN 已确认回收\n")
                        } else {
                            self.appendLog("[警告] TUN 未能在后台确认回收：\(residue ?? "")。请到设置重新安装 TUN 服务以更新安全停机脚本。\n")
                            self.showToast("TUN 未确认回收，请重新安装 TUN 服务")
                        }
                        self.wasTunActiveInThisSession = false
                    }
                }
            }
        } else {
            wasTunActiveInThisSession = false
        }

        // 2. Stop sing-box processes (normal + elevated)
        if shouldStopNormalProxy {
            runner.stop()
            appendLog("[TungBox] sing-box 已停止\n")
        }

        // 3. Turn off system proxy synchronously — must complete before app exits
        if shouldClearSystemProxy {
            let port = getMixedProxyPort()
            if clearSystemProxySynchronously {
                setSystemProxySync(enabled: false, port: port)
            } else {
                setSystemProxy(enabled: false, port: port)
            }
            appendLog("[TungBox] 系统代理已关闭\n")
        }
        wasProxyActiveInThisSession = false

        isSystemProxyEnabled = false
        clearFeatureTransitions()

        // No UI refresh on the exit path — the app is tearing down and a status
        // sweep here only adds work (and timers) to a process that is going away.
        if !isTerminating {
            refreshStatus()
        }
    }

    func setSystemProxySync(enabled: Bool, port: Int) {
        if enabled {
            wasProxyActiveInThisSession = true
        }
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
                disableSystemProxyIfOwned(service: service, port: port)
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
        let rawConfig = (try? String(contentsOf: url)) ?? ""
        editor.string = normalizeLatencyTestURLs(inConfigText: rawConfig) ?? rawConfig
        refreshNodesFromEditor()
        refreshModeFromEditor()
        refreshRulesFromEditor()
        selectCurrentNodeInTable()
    }

    

    

    

    

    

    

    @discardableResult
    func saveCurrent() throws -> URL {
        guard let index = selectedIndex else { throw NSError.user("请先选择一个配置") }
        if let normalized = normalizeLatencyTestURLs(inConfigText: editor.string) {
            editor.string = normalized
        }
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

    func normalizeLatencyTestURLs(inConfigText text: String) -> String? {
        guard var config = parseConfigObject(from: text),
              var outbounds = config["outbounds"] as? [[String: Any]] else {
            return nil
        }

        var changed = false
        for index in outbounds.indices {
            let type = (outbounds[index]["type"] as? String ?? "").lowercased()
            guard ["urltest", "url-test", "fallback"].contains(type),
                  let url = outbounds[index]["url"] as? String,
                  url == "https://www.google.com/generate_204" else {
                continue
            }
            outbounds[index]["url"] = TungBoxConfig.urlTestURL
            changed = true
        }

        guard changed else { return nil }
        config["outbounds"] = outbounds
        return try? renderConfig(config)
    }

    func refreshNodesFromEditor() {
        // Re-parsing the editor rebuilds NodeInfo with delay "未测试", which would
        // wipe latencies already measured this session (e.g. when switching the
        // selected node from auto to a manual one). Carry the measured delay over
        // for nodes that are still the same (matched by tag + server).
        let previousDelays = Dictionary(
            nodes.map { ("\($0.tag)\u{1}\($0.server)", $0.delay) },
            uniquingKeysWith: { first, _ in first }
        )
        var parsed = parseNodes(from: editor.string)
        for index in parsed.indices {
            let key = "\(parsed[index].tag)\u{1}\(parsed[index].server)"
            if let previous = previousDelays[key], previous != "未测试", previous != "测试中" {
                parsed[index].delay = previous
            }
        }
        nodes = parsed
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
                        if nodeTag == TungBoxConfig.tagAuto {
                            if let autoGroup = self.nodeGroups.first(where: { $0.tag == TungBoxConfig.tagAuto }) {
                                self.testGroupNodes(autoGroup)
                            }
                        }
                        if self.isProxyRuntimeRunning() && !switchedByAPI {
                            if self.isTunEnabled {
                                // TUN is already running; hot-reload the config in
                                // place. A full restart here re-runs start-time
                                // checks that can throw and tear the live TUN down
                                // (the reported "switching node killed the proxy").
                                self.reloadTunConfigInPlace(configText: self.editor.string)
                                self.appendLog("[节点] 已按新节点热重载 TUN\n")
                            } else {
                                self.runner.stop()
                                try self.startNormalProxy(config: url, port: self.getMixedProxyPort(), reason: "节点切换后重启")
                                self.appendLog("[节点] 服务已按新节点重启\n")
                            }
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
        if restartIfRunning {
            if isTunEnabled {
                runner.stop()
                try enableTunServiceSafely(configText: editor.string)
                appendLog("[TUN] 已更新 TUN 服务配置\n")
            } else {
                runner.stop()
                try stopTunBeforeStartingNormalProxy(timeout: 8)
                try startNormalProxy(config: url, port: getMixedProxyPort(), reason: "从 TUN 切回系统代理")
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

        // 确保配置中有 direct outbound（即使原始配置没有）
        var outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let hadDirect = outbounds.contains(where: { ($0["tag"] as? String) == "direct" })
        if !hadDirect {
            outbounds.append(["type": "direct", "tag": "direct"])
            config["outbounds"] = outbounds
            appendLog("[TUN] 原始配置缺少 direct outbound，已添加\n")
        } else {
            appendLog("[TUN] 原始配置已有 direct outbound\n")
        }

        let modeValue = readMode(from: config)
        config = setTunEnabled(true, in: config)
        config = ensureModeSupport(in: config, mode: Mode(value: modeValue, displayName: modeDisplayName(modeValue)))
        config = stripLocalListenersForTunDaemon(in: config)
        config = applyTunAutomaticEgressRouting(in: config)
        config = applyTunPhysicalEgressBinding(in: config)
        config = applyTunRuntimeRouteExclusions(in: config)
        config = setTunCacheFile(enabled: true, in: config)
        try validateTunRuntimeRouting(in: config)

        // 最终检查
        let finalOutbounds = config["outbounds"] as? [[String: Any]] ?? []
        let finalHasDirect = finalOutbounds.contains(where: { ($0["tag"] as? String) == "direct" })
        appendLog("[TUN] 最终配置 direct outbound 状态: \(finalHasDirect ? "存在" : "缺失")\n")

        // 打印所有 outbound tags 用于调试
        let tags = finalOutbounds.compactMap { $0["tag"] as? String }
        appendLog("[TUN] 最终配置中的所有 outbound tags: \(tags.joined(separator: ", "))\n")

        let finalConfigText = try renderConfig(config)

        // 调试：保存最终配置副本用于诊断
        let debugPath = NSHomeDirectory() + "/Library/Application Support/TungBox/tun-config-debug.json"
        try? finalConfigText.write(toFile: debugPath, atomically: true, encoding: .utf8)
        appendLog("[TUN] 已保存调试配置到: \(debugPath)\n")

        return finalConfigText
    }

    func validateTunRuntimeRouting(in config: [String: Any]) throws {
        let inbounds = config["inbounds"] as? [[String: Any]] ?? []
        let hasAutoRouteTun = inbounds.contains { inbound in
            (inbound["type"] as? String)?.lowercased() == "tun"
                && (inbound["auto_route"] as? Bool) == true
        }
        guard hasAutoRouteTun else { return }

        let route = config["route"] as? [String: Any] ?? [:]
        let autoDetect = route["auto_detect_interface"] as? Bool == true
        let hasDefaultInterface = (route["default_interface"] as? String)?.isEmpty == false
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let hasBoundOutbound = outbounds.contains { outbound in
            (outbound["bind_interface"] as? String)?.isEmpty == false
                || (outbound["inet4_bind_address"] as? String)?.isEmpty == false
                || (outbound["inet6_bind_address"] as? String)?.isEmpty == false
        }

        guard autoDetect || hasDefaultInterface || hasBoundOutbound else {
            throw NSError.user("TUN 配置缺少出口防回环设置：auto_route=true 时必须启用 auto_detect_interface、default_interface 或 outbound 绑定。")
        }
    }

    /// The TUN daemon and the user proxy are now fully independent processes. The
    /// daemon must NOT bind the user proxy's ports (7890 mixed + 9090 clash) — that
    /// shared-port design forced a fragile hand-off on every TUN toggle. Here we
    /// strip ALL local proxy inbounds from the daemon config (it only needs the TUN
    /// inbound + utun29) and move its clash_api to a dedicated port so it never
    /// collides with the user runner's 9090.
    func stripLocalListenersForTunDaemon(in config: [String: Any]) -> [String: Any] {
        var config = config

        var inbounds = config["inbounds"] as? [[String: Any]] ?? []
        let localTypes: Set<String> = ["mixed", "http", "socks"]
        let before = inbounds.count
        inbounds = inbounds.filter { inbound in
            guard let type = (inbound["type"] as? String)?.lowercased() else { return true }
            return !localTypes.contains(type)
        }
        config["inbounds"] = inbounds
        if inbounds.count < before {
            appendLog("[TUN] 守护进程不绑定本地代理端口（7890 由用户代理独占）\n")
        }

        // Keep clash_api (the clash_mode route rules depend on it) but on a dedicated
        // port so it never collides with the user runner's 9090.
        if var experimental = config["experimental"] as? [String: Any],
           var clashAPI = experimental["clash_api"] as? [String: Any] {
            clashAPI["external_controller"] = "127.0.0.1:\(TungBoxConfig.tunDaemonClashPort)"
            experimental["clash_api"] = clashAPI
            config["experimental"] = experimental
        }
        return config
    }

    func applyTunAutomaticEgressRouting(in config: [String: Any]) -> [String: Any] {
        var config = config
        var changed = false

        var route = config["route"] as? [String: Any] ?? [:]
        if route.removeValue(forKey: "default_interface") != nil {
            changed = true
        }
        if route["auto_detect_interface"] as? Bool != true {
            route["auto_detect_interface"] = true
            changed = true
        }
        if !route.isEmpty {
            config["route"] = route
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

        if var dns = config["dns"] as? [String: Any],
           var servers = dns["servers"] as? [[String: Any]] {
            var dnsChanged = false
            for index in servers.indices where servers[index]["detour"] as? String == "direct" {
                servers[index].removeValue(forKey: "detour")
                dnsChanged = true
            }
            if dnsChanged {
                dns["servers"] = servers
                config["dns"] = dns
                changed = true
            }
        }

        if changed {
            appendLog("[TUN] 已启用 auto_detect_interface，并清理固定出口绑定和 DNS direct detour\n")
        } else {
            appendLog("[TUN] 运行时出口：auto_detect_interface 已启用\n")
        }

        return config
    }

    func applyTunPhysicalEgressBinding(in config: [String: Any]) -> [String: Any] {
        var config = config
        guard let interface = TunServiceManager.defaultNetworkInterface() else {
            appendLog("[TUN] 未找到可用物理出口接口，保留 auto_detect_interface\n")
            return config
        }

        var route = config["route"] as? [String: Any] ?? [:]
        route["default_interface"] = interface
        route.removeValue(forKey: "auto_detect_interface")
        config["route"] = route

        var outbounds = config["outbounds"] as? [[String: Any]] ?? []
        var changedOutbounds = false
        let virtualTypes: Set<String> = ["selector", "urltest", "url-test", "direct", "block", "dns"]
        for index in outbounds.indices {
            let type = (outbounds[index]["type"] as? String ?? "").lowercased()
            guard !virtualTypes.contains(type) else { continue }
            outbounds[index]["bind_interface"] = interface
            changedOutbounds = true
        }
        if changedOutbounds {
            config["outbounds"] = outbounds
        }

        appendLog("[TUN] 已绑定 direct/节点出站到物理接口 \(interface)，避免 direct 出口无路由\n")
        return config
    }

    func applyTunRuntimeRouteExclusions(in config: [String: Any]) -> [String: Any] {
        var config = config
        var bypassCIDRs: [String] = []
        var seen = Set<String>()

        func add(_ cidr: String) {
            if seen.insert(cidr).inserted {
                bypassCIDRs.append(cidr)
            }
        }

        let alwaysBypass = [
            "1.0.0.1",
            "1.1.1.1",
            "8.8.4.4",
            "8.8.8.8",
            "114.114.114.114",
            "119.29.29.29",
            "120.53.53.53",
            "180.76.76.76",
            "223.5.5.5",
            "223.6.6.6"
        ]
        for ip in alwaysBypass {
            if let cidr = routeExcludeCIDR(for: ip) {
                add(cidr)
            }
        }

        if let dns = config["dns"] as? [String: Any],
           let servers = dns["servers"] as? [[String: Any]] {
            for server in servers {
                if let address = server["server"] as? String,
                   let cidr = routeExcludeCIDR(for: address) {
                    add(cidr)
                }
            }
        }

        let virtualTypes: Set<String> = ["selector", "urltest", "url-test", "direct", "block", "dns"]
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        // Collect the proxy-server hostnames that still need DNS resolution. Literal
        // IPs are excluded immediately; only real hostnames go to the resolver.
        var hostsToResolve: [String] = []
        var seenHosts = Set<String>()
        for outbound in outbounds {
            let type = (outbound["type"] as? String ?? "").lowercased()
            guard !virtualTypes.contains(type),
                  let server = outbound["server"] as? String,
                  !server.isEmpty else {
                continue
            }
            if let cidr = routeExcludeCIDR(for: server) {
                add(cidr)
                continue
            }
            if seenHosts.insert(server).inserted {
                hostsToResolve.append(server)
            }
        }
        // Resolve concurrently instead of serially: dscacheutil can block up to
        // ~1.5s per host, so 16 hostnames serially stalled the TUN switch for many
        // seconds on the main thread. Concurrency caps the wait at ~one lookup.
        let cappedHosts = Array(hostsToResolve.prefix(16))
        let resolvedByHost = resolvePublicIPv4Addresses(forHosts: cappedHosts)
        for host in cappedHosts {
            for ip in (resolvedByHost[host] ?? []).prefix(4) {
                if let cidr = routeExcludeCIDR(for: ip) {
                    add(cidr)
                }
            }
        }

        guard !bypassCIDRs.isEmpty else {
            return config
        }

        var inbounds = config["inbounds"] as? [[String: Any]] ?? []
        var updatedTun = false
        for index in inbounds.indices {
            guard (inbounds[index]["type"] as? String)?.lowercased() == "tun" else {
                continue
            }
            var excludes = inbounds[index]["route_exclude_address"] as? [String] ?? []
            var excludeSet = Set(excludes)
            var added = 0
            for cidr in bypassCIDRs where excludeSet.insert(cidr).inserted {
                excludes.append(cidr)
                added += 1
            }
            if added > 0 {
                inbounds[index]["route_exclude_address"] = excludes
                updatedTun = true
            }
        }
        if updatedTun {
            config["inbounds"] = inbounds
            appendLog("[TUN] 已排除 DNS/节点上游地址 \(bypassCIDRs.count) 个，避免代理握手被 TUN 捕获\n")
        }

        // 不再硬覆盖 dns.strategy —— 由 DNSConfig 用户设置主导。仅在调试日志里记一笔，
        // 方便排查"明明没 IPv6 路由怎么还在查 AAAA"的问题。
        if let dns = config["dns"] as? [String: Any],
           let strategy = dns["strategy"] as? String {
            appendLog("[TUN] DNS 策略：\(strategy)\n")
        }

        return config
    }

    func routeExcludeCIDR(for address: String) -> String? {
        let trimmed = address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard isPublicIPv4Address(trimmed) else { return nil }
        return "\(trimmed)/32"
    }

    nonisolated func isPublicIPv4Address(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return false
        }
        let first = octets[0]
        let second = octets[1]
        switch first {
        case 0, 10, 127:
            return false
        case 100 where (64...127).contains(second):
            return false
        case 169 where second == 254:
            return false
        case 172 where (16...31).contains(second):
            return false
        case 192 where second == 168:
            return false
        case 198 where second == 18 || second == 19:
            return false
        case 224...255:
            return false
        default:
            return true
        }
    }

    /// Resolve several hostnames concurrently. Returns host -> public IPv4 list.
    /// nonisolated so it can fan out over background threads without blocking the
    /// main actor (the TUN switch was stalling on serial dscacheutil lookups).
    nonisolated func resolvePublicIPv4Addresses(forHosts hosts: [String]) -> [String: [String]] {
        guard !hosts.isEmpty else { return [:] }
        let box = LockedValue<[String: [String]]>([:])
        DispatchQueue.concurrentPerform(iterations: hosts.count) { index in
            let ips = self.resolvePublicIPv4Addresses(for: hosts[index])
            box.mutate { $0[hosts[index]] = ips }
        }
        return box.get()
    }

    nonisolated func resolvePublicIPv4Addresses(for host: String) -> [String] {
        let output = runProcessAndGetOutput("/usr/bin/dscacheutil", args: ["-q", "host", "-a", "name", host])
        var addresses: [String] = []
        var seen = Set<String>()
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("ip_address:") else { continue }
            let address = trimmed
                .replacingOccurrences(of: "ip_address:", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard isPublicIPv4Address(address), seen.insert(address).inserted else {
                continue
            }
            addresses.append(address)
        }
        return addresses
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
                    "\(TunServiceManager.tunIPv4Address)/30"
                ],
                "interface_name": TunServiceManager.tunInterfaceName,
                "auto_route": true,
                "strict_route": false,
                "route_exclude_address": [
                    "10.0.0.0/8",
                    "100.64.0.0/10",
                    "127.0.0.0/8",
                    "169.254.0.0/16",
                    "172.16.0.0/12",
                    "192.168.0.0/16",
                    "::1/128",
                    "fc00::/7",
                    "fe80::/10"
                ]
            ], at: 0)

            var outbounds = config["outbounds"] as? [[String: Any]] ?? []

            // 确保 direct outbound 存在
            if !outbounds.contains(where: { ($0["tag"] as? String) == "direct" }) {
                outbounds.append(["type": "direct", "tag": "direct"])
            }

            let proxyTag = preferredProxyTag(from: outbounds)
            var route = config["route"] as? [String: Any] ?? [:]
            if proxyTag != "direct" {
                if (route["final"] as? String).map({ $0 == "direct" }) ?? true {
                    route["final"] = proxyTag
                }
            }
            config["route"] = route
            config["outbounds"] = outbounds
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
            let transport = (outbound["transport"] as? [String: Any])?["type"] as? String ?? ""
            let network = (outbound["network"] as? String)?.lowercased() ?? ""
            // QUIC-based protocols are inherently UDP; others relay UDP unless the
            // outbound restricts `network` to tcp only.
            let quicTypes = Set(["hysteria", "hysteria2", "tuic"])
            let supportsUDP = quicTypes.contains(type.lowercased()) || network != "tcp"
            let tls = (outbound["tls"] as? [String: Any])?["enabled"] as? Bool ?? false
            return NodeInfo(tag: tag, type: type, server: server + port, delay: "未测试",
                            transport: transport, supportsUDP: supportsUDP, tls: tls)
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
        refreshNodeGroupsView()   // re-filter shown groups for the new mode

        if isProxyRuntimeRunning() {
            reconcileRuntime(reason: "模式切换", forceRestart: true)
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
        outbounds = ensureGlobalSelector(in: outbounds)
        config["outbounds"] = outbounds

        let proxyTag = preferredProxyTag(from: outbounds)
        // Global clash mode routes through the dedicated 全局 selector (manual node
        // pick) when present; otherwise fall back to the main proxy group.
        let globalTag = outbounds.contains { ($0["tag"] as? String) == TungBoxConfig.tagGlobal }
            ? TungBoxConfig.tagGlobal
            : proxyTag
        var route = config["route"] as? [String: Any] ?? [:]
        var rules = route["rules"] as? [[String: Any]] ?? []
        rules.removeAll { isManagedRuntimeRule($0) }
        rules = [
            ["action": "sniff"],
            ["protocol": "dns", "action": "hijack-dns"],
            ["clash_mode": "direct", "outbound": "direct"],
            ["clash_mode": "global", "outbound": globalTag]
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

    /// Ensure a dedicated 全局 (Global) selector exists for clash global mode.
    /// Members are [自动选择] + all subscription nodes, defaulting to 自动选择, so the
    /// user can either ride auto-select or manually pin a node for global mode. Kept
    /// in sync (members refreshed) so newly added nodes show up; never reorders the
    /// existing groups, so `preferredProxyTag` still resolves to 节点选择.
    func ensureGlobalSelector(in outbounds: [[String: Any]]) -> [[String: Any]] {
        let virtualTypes: Set<String> = ["selector", "urltest", "url-test", "fallback", "direct", "block", "dns"]
        let nodeTags = outbounds.compactMap { outbound -> String? in
            let type = (outbound["type"] as? String ?? "").lowercased()
            guard !virtualTypes.contains(type), let tag = outbound["tag"] as? String else { return nil }
            return tag
        }
        guard !nodeTags.isEmpty else { return outbounds }

        let hasAuto = outbounds.contains { ($0["tag"] as? String) == TungBoxConfig.tagAuto }
        let members = (hasAuto ? [TungBoxConfig.tagAuto] : []) + nodeTags
        let defaultMember = hasAuto ? TungBoxConfig.tagAuto : (nodeTags.first ?? "")

        var outbounds = outbounds
        if let index = outbounds.firstIndex(where: { ($0["tag"] as? String) == TungBoxConfig.tagGlobal }) {
            // Refresh members but preserve the user's current manual pick.
            outbounds[index]["outbounds"] = members
            if let current = outbounds[index]["default"] as? String, members.contains(current) {
                outbounds[index]["default"] = current
            } else {
                outbounds[index]["default"] = defaultMember
            }
        } else {
            outbounds.append([
                "type": "selector",
                "tag": TungBoxConfig.tagGlobal,
                "outbounds": members,
                "default": defaultMember,
                "interrupt_exist_connections": true
            ])
        }
        return outbounds
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

    /// Drive a status chip (label + built-in spinner) from a feature's transition.
    private func applyChipState(chip: MD3StatusChip, transition: FeatureTransition, isOn: Bool) {
        switch transition {
        case .starting:
            chip.transitioningText = "启动中"
            chip.status = .transitioning
        case .stopping:
            chip.transitioningText = "关闭中"
            chip.status = .transitioning
        case .none:
            chip.status = isOn ? .active : .inactive
        }
    }

    func refreshStatus() {
        let isRunning = isProxyRuntimeRunning()
        let isActiveOrRequested = isProxyServiceActiveOrRequested()
        // 系统代理卡片：过渡中显示 启动中/关闭中（内置转圈），否则显示运行态。
        applyChipState(chip: statusChip, transition: systemProxyTransition, isOn: isSystemProxyEnabled)
        // TUN 卡片
        applyChipState(chip: tunStatusChip, transition: tunTransition, isOn: isTunEnabled)
        syncProxyPreferenceControls()
        refreshTrayIcon()
        refreshHomeFeatureStatus()
        
        if isActiveOrRequested {
            let activeNodeInfo = resolveActiveOutbound(proxiesObj: lastProxiesObj)
            // 自动模式刚启动 / 切换订阅那一刻，clash API 的 "now" 可能还没填好 →
            // resolved name 是空字符串。给个明确的占位避免节点名行整个空白。
            currentNodeNameLabel.stringValue = activeNodeInfo.name.isEmpty ? "（选择中…）" : activeNodeInfo.name
            currentNodeAutoBadge.isHidden = !activeNodeInfo.isAuto
            let activeDelay = nodes.first(where: { $0.tag == activeNodeInfo.name })?.delay ?? "—"
            currentNodeDelayLabel.stringValue = activeDelay == "未测试" ? "—" : activeDelay
            currentNodeDelayLabel.textColor = MD3.latencyTextColor(currentNodeDelayLabel.stringValue)

            if isRunning {
                if statsTimer == nil {
                    startStatsTimer()
                }
            } else {
                currentUploadSpeed = 0
                currentDownloadSpeed = 0
                clearConnections()
                stopConnectionsRefreshTimer()
                stopStatsTimer()
                refreshTrayIcon()
            }
        } else {
            currentNodeNameLabel.stringValue = "未连接"
            currentNodeAutoBadge.isHidden = true
            currentNodeDelayLabel.stringValue = "—"
            currentUploadSpeed = 0
            currentDownloadSpeed = 0
            clearConnections()
            stopConnectionsRefreshTimer()
            stopStatsTimer()
            refreshTrayIcon()
        }
    }

    func startStatsTimer() {
        statsTimer?.invalidate()
        runningStatsMissCount = 0
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
        // 流量统计是按天累计的历史值（代理流量），停止/切换时不应清零——显示累计值。
        updateTrafficLabels()
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

    enum ToastStyle {
        case info, success, warning, error
        var iconName: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }
        @MainActor
        var accentColor: NSColor {
            switch self {
            case .info: return MD3.primary
            case .success: return MD3.success
            case .warning: return MD3.warning
            case .error: return MD3.error
            }
        }
    }

    @MainActor
    func showToast(_ message: String, style: ToastStyle = .info, duration: TimeInterval = 3.0) {
        guard let contentView = window?.contentView else { return }
        toastView?.removeFromSuperview()

        // 卡片容器 (右上角 / 阴影 / 圆角 / MD3 surface)
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = MD3.surface.cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = MD3.outlineVariant.cgColor
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.18
        card.layer?.shadowRadius = 14
        card.layer?.shadowOffset = CGSize(width: 0, height: -3)
        card.alphaValue = 0
        card.translatesAutoresizingMaskIntoConstraints = false

        // 左侧强调色条
        let accent = NSView()
        accent.wantsLayer = true
        accent.layer?.backgroundColor = style.accentColor.cgColor
        accent.layer?.cornerRadius = 2
        accent.translatesAutoresizingMaskIntoConstraints = false

        // 图标
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: style.iconName, accessibilityDescription: nil)
        iconView.contentTintColor = style.accentColor
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // 消息
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = MD3.onSurface
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        label.preferredMaxLayoutWidth = 280
        label.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(accent)
        card.addSubview(iconView)
        card.addSubview(label)
        contentView.addSubview(card)
        toastView = card

        NSLayoutConstraint.activate([
            accent.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            accent.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            accent.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            accent.widthAnchor.constraint(equalToConstant: 3),

            iconView.leadingAnchor.constraint(equalTo: accent.trailingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            // 右上角，从顶部下来一点不挡标题栏
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])

        // 滑入：alpha 0→1 + 从右滑入约 12pt
        card.layer?.transform = CATransform3DMakeTranslation(12, 0, 0)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            card.animator().alphaValue = 1
            card.layer?.transform = CATransform3DIdentity
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak card] in
            guard let card, self?.toastView === card else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                card.animator().alphaValue = 0
                card.layer?.transform = CATransform3DMakeTranslation(12, 0, 0)
            } completionHandler: {
                DispatchQueue.main.async { card.removeFromSuperview() }
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
        stopService(clearSystemProxySynchronously: true, isTerminating: true)
    }

    func setSystemProxy(enabled: Bool, port: Int, rollbackOnMismatch: Bool = false) {
        systemProxyOperationID += 1
        let operationID = systemProxyOperationID
        if enabled {
            wasProxyActiveInThisSession = true
        }
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
                    self.disableSystemProxyIfOwned(service: service, port: port)
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
                        self.showToast("系统代理被其他软件覆盖")
                    }
                }
            }
        }
    }

    nonisolated func disableSystemProxyIfOwned(service: String, port: Int) {
        if proxySettingMatches(service: service, getter: "-getwebproxy", port: port) {
            _ = runCommand("/usr/sbin/networksetup", args: ["-setwebproxystate", service, "off"])
        }
        if proxySettingMatches(service: service, getter: "-getsecurewebproxy", port: port) {
            _ = runCommand("/usr/sbin/networksetup", args: ["-setsecurewebproxystate", service, "off"])
        }
        if proxySettingMatches(service: service, getter: "-getsocksfirewallproxy", port: port) {
            _ = runCommand("/usr/sbin/networksetup", args: ["-setsocksfirewallproxystate", service, "off"])
        }
    }

    nonisolated func proxySettingMatches(service: String, getter: String, port: Int) -> Bool {
        let output = runCommand("/usr/sbin/networksetup", args: [getter, service])
        let lines = output.components(separatedBy: .newlines)
        let enabled = lines.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Enabled: Yes") == .orderedSame }
        let server = lines.first { $0.hasPrefix("Server:") }?
            .replacingOccurrences(of: "Server:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentPort = lines.first { $0.hasPrefix("Port:") }?
            .replacingOccurrences(of: "Port:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return enabled && isLocalProxyHost(server) && currentPort == "\(port)"
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
