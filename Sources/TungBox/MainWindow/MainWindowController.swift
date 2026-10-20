import AppKit
import Foundation
import ServiceManagement

final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSWindowDelegate {
    let store: Store
    nonisolated let systemProxyManager: SystemProxyManager
    nonisolated let runtimePortProbe: RuntimePortProbe
    let runtimeCoordinator: RuntimeCoordinator
    let consoleWindowDelegate = ConsoleWindowDelegate()
    private let makeRunner: (Store) -> Runner
    lazy var runner = makeRunner(store)
    var profiles: [ConfigProfile] = []
    var subscriptions: [Subscription] = []
    var subscriptionRefreshTracker = SubscriptionRefreshTracker()
    var subscriptionRefreshBatch = SubscriptionRefreshBatch()
    var customRules: [CustomRule] = []
    /// Valid rule sets for the current subscription (loaded from disk).
    var customRuleSets: [CustomRuleSet] = []
    var pendingRuleProjection: (UUID, [[String: Any]])?
    var ruleSetApplyStatus = "已保存，待应用"
    var isApplyingRuleSets = false
    var ruleSetWatchTimer: Timer?
    var ruleSetFileSignature: [String: Data]?
    var ruleSetWatchSubscriptionID: UUID?
    var systemHostsWatchTimer: Timer?
    var lastKnownSystemHostsFingerprint: String?
    var isSyncingHosts = false

    /// Rule-set files for the current subscription that failed to load/validate.
    var invalidRuleSets: [InvalidRuleSet] = []
    /// Rule set being edited (nil when adding a new one).
    var editingRuleSetID: UUID?
    /// The open rule-set dialog's multi-line rules editor, for the AI-preset button.
    weak var ruleSetRulesTextView: NSTextView?
    var nodes: [NodeInfo] = []
    var nodeGroups: [NodeGroupInfo] = []
    var ruleRows: [RuleInfo] = []
    var cachedFilteredRuleRows: [RuleInfo]?
    var cachedRuleSearchQuery: String?
    var connections: [ConnectionInfo] = []
    var displayedConnections: [ConnectionInfo] = []
    var ruleSetDownloads = Set<String>()
    var nodeTileActions: [Int: (group: String, node: String)] = [:]
    var groupTestActions: [Int: String] = [:]
    var nextNodeTileTag = 1
    var selectedIndex: Int? {
        didSet {
            if oldValue != selectedIndex {
                nodeDelayTestID = UUID()
                selectorSelectionID = UUID()
                modeChangeTask?.cancel()
                modeChangeID = UUID()
                modeChangeNeedsDelayRefresh = false
            }
        }
    }
    var selectedSubscriptionIndex: Int? {
        didSet {
            if let index = selectedSubscriptionIndex {
                UserDefaults.standard.set(index, forKey: "selectedSubscriptionIndex")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedSubscriptionIndex")
            }
        }
    }

    let split = FixedSidebarLayout()
    let currentNodeNameLabel = NSTextField(labelWithString: "未连接")
    let currentNodeAutoBadge = CenteredPillLabel(labelWithString: "自动")
    let currentNodeDelayLabel = NSTextField(labelWithString: "—")
    var lastRecordedActiveNode: String?
    var totalUploadBytes = 0
    var totalDownloadBytes = 0
    let trafficStatsValueLabel = NSTextField(labelWithString: "0 B")
    let trafficStatsDetailLabel = NSTextField(labelWithString: "上传: 0 B   下载: 0 B")

    let trafficPeriodControl = MD3SegmentedControl()

    // Home Dashboard widgets
    let wifiStatusLabel = NSTextField(labelWithString: "Wi-Fi")
    let homeProfileSelectorPopup = MD3PopUpButton()
    let externalIPLabel = NSTextField(labelWithString: "检测中…")
    let externalIPRefreshButton = NSButton()
    let trafficTrendChartView = TrafficTrendChartView()
    let trafficTotalValueLabel = NSTextField(labelWithString: "0 B")
    let trafficUploadStatLabel = NSTextField(labelWithString: "2.1 GB")
    let trafficDownloadStatLabel = NSTextField(labelWithString: "1.2 GB")
    let uploadWaveChartView = SpeedWaveChartView()
    let downloadWaveChartView = SpeedWaveChartView()
    let trafficDonutChartView = TrafficDonutChartView()
    let donutProxyLabel = NSTextField(labelWithString: "代理 0 B  0%")
    let donutDirectLabel = NSTextField(labelWithString: "直连 0 B  0%")
    let donutOtherLabel = NSTextField(labelWithString: "其他 0 B  0%")
    let donutProxyAmountLabel = NSTextField(labelWithString: "0 B")
    let donutProxyRatioLabel = NSTextField(labelWithString: "0%")
    let donutDirectAmountLabel = NSTextField(labelWithString: "0 B")
    let donutDirectRatioLabel = NSTextField(labelWithString: "0%")
    let donutOtherAmountLabel = NSTextField(labelWithString: "0 B")
    let donutOtherRatioLabel = NSTextField(labelWithString: "0%")
    let memoryValueLabel = NSTextField(labelWithString: "65.3 MB")
    let memoryRingView = MemoryRingView()
    let equalizerBarsView = EqualizerBarsView()
    let recentStatusStack = NSStackView()
    let recentStatusPill = MD3StatusBadgeView()

    let table = NSTableView()
    let subscriptionTable = NSTableView()
    let nodeTable = NSTableView()
    let rulesTable = ControlFriendlyTableView()
    let connectionsTable = NSTableView()
    let nodeGroupsStack = NSStackView()
    let pages = ConsoleTabView()
    var navButtons: [MD3SidebarItem] = []
    let editor = NSTextView()
    let logs = NSTextView()
    let ruleSearchField = MD3TextField()
    let customRuleTypePopup = MD3PopUpButton()
    let customRuleStrategyPopup = MD3PopUpButton()
    let customRuleValueField = MD3TextField()
    let customRuleNoteField = MD3TextField()
    weak var customRuleValueLabel: NSTextField?
    weak var customRuleDescLabel: NSTextField?
    // Strong: this button is detached from the view hierarchy for non-PROCESS types,
    // so nothing else retains it while it's out of the stack.
    var customRuleAppPickerButton: NSButton?
    weak var customRuleValueStack: NSStackView?
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
    var isProxyServiceTransitioning: Bool { runtimeCoordinator.state.isTransitioning }
    /// Per-feature transition direction — drives the "启动中 / 关闭中" status chip and
    /// the loading spinner next to each switch while a runtime change is in flight.
    typealias FeatureTransition = RuntimeCoordinator.FeatureTransition
    var systemProxyTransition: FeatureTransition {
        get { runtimeCoordinator.state.systemProxyTransition }
        set { runtimeCoordinator.updateFeaturePresentation(systemProxy: newValue) }
    }
    var tunTransition: FeatureTransition {
        get { runtimeCoordinator.state.tunTransition }
        set { runtimeCoordinator.updateFeaturePresentation(tun: newValue) }
    }
    // Every reconcile submits an immutable request to the coordinator. Existing
    // callbacks read its generation to reject obsolete results.
    var runtimeTransitionID: Int { runtimeCoordinator.generation }
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
    let connectionCountLabel = NSTextField(labelWithString: "共 0 条连接")
    var editingRuleID: UUID?
    var logLevelButtons: [MD3Checkbox]?
    weak var logSearchField: NSTextField?
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
    let tunStackPopup = MD3PopUpButton()
    let tunMTUField = MD3TextField()
    let tunStrictRouteCheckbox = MD3Checkbox(checkboxWithTitle: "严格路由（防泄漏，可能影响局域网共享）", target: nil, action: nil)
    let tunEINCheckbox = MD3Checkbox(checkboxWithTitle: "端点独立 NAT（对 P2P / 游戏 / 语音友好）", target: nil, action: nil)
    let tunRouteExcludeTextView = NSTextView()
    let tunIncludeIfaceField = MD3TextField()
    let tunExcludeIfaceField = MD3TextField()
    var tunApplyWorkItem: DispatchWorkItem?
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
    var lastTrayPresentation: String?
    var wasTunActiveInThisSession = false
    var wasProxyActiveInThisSession = false
    var lastTrayActiveState: Bool? = nil
    var trayImageView: NSImageView?
    var traySpeedLabel: NSTextField?
    var statsTimer: Timer?
    var isUpdatingRunningStats = false
    var runningStatsMissCount = 0
    var nodeDelayTestState = NodeDelayTestState()
    var nodeDelayTestTask: Task<Void, Never>?
    var modeChangeID = UUID()
    var modeChangeTask: Task<Void, Never>?
    var modeChangeNeedsDelayRefresh = false
    var nodeDelayTestID = UUID() {
        didSet {
            guard oldValue != nodeDelayTestID else { return }
            if let requestID = nodeDelayTestState.requestID {
                nodeDelayTestTask?.cancel()
                finishNodeDelayTest(id: requestID, succeeded: false)
            }
            nodeDelayTestState.clearResultProtection()
        }
    }
    var selectorSelectionID = UUID()
    var selectorSelectionTask: Task<Void, Never>?
    var tunCaptureIntentID = UUID()
    var lastProxiesObj: [String: Any]? = nil
    var lastAutomaticNodeByAPIPort: [Int: String] = [:]
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
    var firstConnectionGate = FirstConnectionGate()
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
        for item in pages.tabViewItems {
            item.view?.refreshSubviews()
        }
        window?.contentView?.refreshSubviews()
    }

    init(store: Store, systemProxyManager: SystemProxyManager,
         runtimePortProbe: RuntimePortProbe, runtimeCoordinator: RuntimeCoordinator,
         makeRunner: @escaping (Store) -> Runner) {
        self.store = store
        self.systemProxyManager = systemProxyManager
        self.runtimePortProbe = runtimePortProbe
        self.runtimeCoordinator = runtimeCoordinator
        self.makeRunner = makeRunner
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: ConsoleLayout.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TungBox"
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        consoleWindowDelegate.configure(window)
        consoleWindowDelegate.onClose = { [weak self] notification in self?.windowWillClose(notification) }
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("TungBox constructs its window programmatically")
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

        split.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split)
        let sidebar = split.sidebar
        let main = split.mainContent

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
        }

        checkSingBoxInstall(showAlert: true)
        refreshSubscriptionBadge()
        registerSystemWakeObserver()
        startSystemHostsWatching()
    }

    func scheduleStatusRefreshFromOutput() {
        guard pendingStatusRefresh == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingStatusRefresh = nil
            self?.refreshStatus()
        }
        pendingStatusRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    func scheduleLogRefresh() {
        guard pendingLogRefresh == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingLogRefresh = nil
            guard self.isLogsPageSelected(), self.window?.isVisible == true else { return }
            self.refreshLogDisplay()
            self.logs.scrollToEndOfDocument(nil)
            self.logStatusLabel.stringValue = "日志：\(self.logLineCount) 行"
        }
        pendingLogRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    func setupSidebar(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.surface.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.surface.cgColor
        }

        let title = NSTextField(labelWithString: "TungBox")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak title] in
            title?.textColor = MD3.onSurface
        }

        let nav = NSStackView()
        nav.orientation = .vertical
        nav.spacing = 6
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
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
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
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 26),

            nav.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            nav.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            nav.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 24),

            appVersionFooter.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            appVersionFooter.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            appVersionFooter.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18)
        ])
    }

    func setupMain(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

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

        split.installPages(pages)
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
            refreshConnectionsTable()
            startConnectionsRefreshTimer()
            refreshConnections(showErrors: false)
        } else {
            stopConnectionsRefreshTimer()
        }
        if index == 5 {
            refreshLogDisplay()
        }
        window?.contentView?.refreshSubviews()
    }
    func isConnectionsPageSelected() -> Bool {
        guard let item = pages.selectedTabViewItem else { return false }
        return pages.indexOfTabViewItem(item) == 4
    }

    func isLogsPageSelected() -> Bool {
        guard let item = pages.selectedTabViewItem else { return false }
        return pages.indexOfTabViewItem(item) == 5
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
        guard !runtimeCoordinator.state.isTerminating else { return }
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
                if externalIPLabel.stringValue == "未获取到公网 IP" {
                    refreshExternalIP(force: false)
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
        lastAutomaticNodeByAPIPort.removeAll()
        updateConnectionsCard(value: "0", detail: "服务未运行")
        uploadValueLabel.stringValue = "0 B/s"
        downloadValueLabel.stringValue = "0 B/s"
        // 流量统计是按天累计的历史值（代理流量），停止/切换时不应清零——显示累计值。
        updateTrafficLabels()
    }

    @MainActor
    func showError(_ error: Error) {
        // A delayed request timeout must never leave a modal over the console.
        guard !ErrorPresentation.isTimeout(error) else {
            appendLog("[请求] 请求超时：\(error.localizedDescription)\n")
            return
        }
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
        refreshConnectionsTable()
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        appendLog("[窗口] 已从状态栏恢复控制台。\n")
    }

    func startSystemHostsWatching() {
        guard systemHostsWatchTimer == nil else { return }
        lastKnownSystemHostsFingerprint = DNSConfig.systemHostsFingerprint()
        systemHostsWatchTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkSystemHostsChanges()
            }
        }
    }

    func stopSystemHostsWatching() {
        systemHostsWatchTimer?.invalidate()
        systemHostsWatchTimer = nil
    }

    func checkSystemHostsChanges() {
        guard DNSConfig.readSystemHosts, !isSyncingHosts else { return }
        guard let current = DNSConfig.systemHostsFingerprint() else { return }
        if lastKnownSystemHostsFingerprint == nil {
            lastKnownSystemHostsFingerprint = current
            return
        }
        if current != lastKnownSystemHostsFingerprint {
            lastKnownSystemHostsFingerprint = current
            syncHostsToRunningConfig(reason: "检测到系统 /etc/hosts 文件变更")
        }
    }

    func syncHostsToRunningConfig(reason: String) {
        guard !isSyncingHosts else { return }
        isSyncingHosts = true
        defer { isSyncingHosts = false }

        var targetIndex = selectedIndex
        if targetIndex == nil && !profiles.isEmpty {
            targetIndex = 0
            selectProfile(at: 0)
        }
        guard let index = targetIndex, profiles.indices.contains(index) else { return }

        let url = store.configURL(for: profiles[index])
        guard var config = parseConfigObject(from: editor.string) ?? (try? String(contentsOf: url, encoding: .utf8)).flatMap({ parseConfigObject(from: $0) }) else {
            return
        }

        let newDNS = DNSConfig.buildSingBoxDNS()
        let oldDNS = config["dns"] as? [String: Any] ?? [:]
        if canonicalJSON(newDNS) == canonicalJSON(oldDNS) {
            return
        }

        config["dns"] = newDNS
        config = ensureModeSupport(in: config, mode: selectedMode())

        do {
            let rendered = try renderConfig(config)
            editor.string = rendered
            _ = try saveCurrent()
        } catch {
            appendLog("[Hosts] 更新配置失败：\(error.localizedDescription)\n")
            return
        }

        appendLog("[Hosts] \(reason)，已更新当前配置中的 hosts 条目\n")

        if isTunEnabled {
            do {
                let prepared = try preparedTunConfigText(from: editor.string)
                try TunServiceManager.writeRequestConfig(prepared, store: store)
                appendLog("[Hosts] TUN 运行中，已写入新配置触发守护进程热重载\n")
                RecentStatusTracker.shared.record("系统 hosts 已自动刷新", level: .info)
            } catch {
                appendLog("[Hosts] 热更新 TUN 配置失败：\(error.localizedDescription)\n")
            }
        } else if isSystemProxyEnabled && runner.isRunning {
            reconcileRuntime(reason: reason, forceRestart: true)
            RecentStatusTracker.shared.record("系统 hosts 已自动刷新", level: .info)
        }
    }
}
