import AppKit
import Darwin
import Foundation
import ServiceManagement

final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSWindowDelegate {
    let store = Store()
    nonisolated let systemProxyManager = SystemProxyManager()
    nonisolated let runtimePortProbe = RuntimePortProbe()
    let runtimeCoordinator = RuntimeCoordinator()
    lazy var runner = Runner(store: store)
    var profiles: [ConfigProfile] = []
    var subscriptions: [Subscription] = []
    var subscriptionRefreshTracker = SubscriptionRefreshTracker()
    var customRules: [CustomRule] = []
    /// Valid rule sets for the current subscription (loaded from disk).
    var customRuleSets: [CustomRuleSet] = []
    var pendingRuleProjection: (UUID, [[String: Any]])?
    var ruleSetApplyStatus = "已保存，待应用"
    var isApplyingRuleSets = false
    var ruleSetWatchTimer: Timer?
    var ruleSetFileSignature: [String: Data]?
    var ruleSetWatchSubscriptionID: UUID?

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
        } else if !isTunEnabled && TunServiceManager.hasRequestFiles(store: store) {
            // A crash or forced quit can leave the request files behind even
            // though the persisted switch is off. Clear them before restoring
            // any other runtime state, otherwise the root daemon can resurrect
            // TUN during the next proxy transition.
            try? TunServiceManager.disable(store: store)
            appendLog("[TUN] 清理了开关已关闭但残留的 TUN 请求\n")
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
            guard let self else { return }
            self.reconcileRuntime(reason: "启动", refreshNodeDelays: self.isSystemProxyEnabled || self.isTunEnabled)
        }
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
        runtimeCoordinator.beginFeatureTransition(systemProxy: systemProxy, tun: tun)
    }

    /// Clear all transition indicators (chips fall back to their on/off state).
    func clearFeatureTransitions() {
        runtimeCoordinator.clearFeatureTransitions()
    }

    /// Converges the independent TUN and system-proxy switches. The root TUN
    /// daemon serves 9091; the user runner serves 7890/9090. Each switch manages
    /// its own process, using the coordinator's request snapshot and generation.
    func reconcileRuntime(reason: String, forceRestart: Bool = false, refreshNodeDelays: Bool = true) {
        guard !runtimeCoordinator.state.isTerminating else { return }
        let request = runtimeCoordinator.begin(.init(
            systemProxyEnabled: isSystemProxyEnabled, tunEnabled: isTunEnabled,
            mixedProxyPort: getMixedProxyPort(), reason: reason, forceRestart: forceRestart,
            refreshNodeDelays: refreshNodeDelays
        ))
        modeChangeTask?.cancel()
        modeChangeNeedsDelayRefresh = false
        nodeDelayTestID = UUID()
        let wantSystemProxy = request.input.systemProxyEnabled
        let wantTun = request.input.tunEnabled
        let tunNeedsReconcile = wantTun && !TunServiceManager.hasEnableRequest(store: store)

        // Snapshot the editor only when a process needs configuration. Network
        // discovery is awaited off the main actor below; toggling the OS proxy
        // never rebuilds subscription/rules views or reconfigures a live TUN.
        var userProxyURL: URL? = nil
        var userConfigText: String? = nil
        let needsUserProxyStart = wantSystemProxy && (!runner.isRunning || request.input.forceRestart)
        let transitionStarted = Date()
        if needsUserProxyStart || tunNeedsReconcile {
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
                // Runtime convergence does not rebuild the rules and nodes UI.
                guard let index = selectedIndex else { throw NSError.user("请先选择一个配置") }
                userProxyURL = store.configURL(for: profiles[index])
                try editor.string.write(to: userProxyURL!, atomically: true, encoding: .utf8)
                userConfigText = editor.string

            } catch {
                showError(error)
                markProxyStartupFailed()
                return
            }
        }

        appendLog("[性能] 主线程配置准备：\(Int(Date().timeIntervalSince(transitionStarted) * 1000)) ms\n")
        if wantSystemProxy { wasProxyActiveInThisSession = true }
        appendLog("[TungBox] 正在切换运行状态（\(reason)）...\n")
        let plan = RuntimeCoordinator.Plan(tunNeedsReconcile: tunNeedsReconcile,
                                           userProxyURL: userProxyURL, userConfigText: userConfigText,
                                           startedAt: transitionStarted)
        Task { @MainActor [weak self] in
            guard let self, self.runtimeCoordinator.isCurrent(request) else { return }
            await self.runtimeCoordinator.converge(request, plan: plan, services: self.runtimeServices(for: request)) {
                self.handleRuntimeEvent($0)
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

    /// Blocking system operation; runtime scheduling remains in the controller.
    nonisolated func applySystemProxyBlocking(enabled: Bool, port: Int) {
        systemProxyManager.apply(enabled: enabled, port: port)
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
        runtimePortProbe.killSingBoxHoldersOfPorts([port, clashPort])
        if !runtimePortProbe.waitForLocalTCPPortsFree([port, clashPort], timeout: 3.0) {
            runner.reapStrayUserProcesses()
            runtimePortProbe.killSingBoxHoldersOfPorts([port, clashPort])
            _ = runtimePortProbe.waitForLocalTCPPortsFree([port, clashPort], timeout: 2.0)
            log("[TungBox] 端口探测：\(runtimePortProbe.portHoldersDescription([port, clashPort]))\n")
        }
        try runner.start(config: config, elevated: false)
        if runtimePortProbe.waitForLocalTCPPort(port, timeout: 6.0) {
            log("[TungBox] \(reason)完成，本地代理端口 \(port) 已监听\n")
            return
        }
        log("[TungBox] 端口 \(port) 未在首次启动内监听，重试一次...\n")
        runner.stop()
        runner.reapStrayUserProcesses()
        runtimePortProbe.killSingBoxHoldersOfPorts([port, clashPort])
        _ = runtimePortProbe.waitForLocalTCPPortsFree([port, clashPort], timeout: 3.0)
        try runner.start(config: config, elevated: false)
        guard runtimePortProbe.waitForLocalTCPPort(port, timeout: 6.0) else {
            runner.stop()
            throw NSError.user("普通代理启动失败：本地端口 \(port) 未开始监听。请查看日志中的 sing-box 退出原因。端口探测：\(runtimePortProbe.portHoldersDescription([port, clashPort]))")
        }
        log("[TungBox] \(reason)完成（重试后），本地代理端口 \(port) 已监听\n")
    }

    func ensureRuntimeAPISupport() throws {
        guard var config = parseConfigObject(from: editor.string) else { return }
        let currentMode = readMode(from: config)
        config = ensureModeSupport(in: config, mode: Mode(value: currentMode, displayName: modeDisplayName(currentMode)))
        editor.string = try renderConfig(config)
    }

    func scheduleConnectionsRefreshAfterStart() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, !self.runtimeCoordinator.state.isTerminating, self.isProxyRuntimeRunning() else { return }
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

    func isLogsPageSelected() -> Bool {
        guard let item = pages.selectedTabViewItem else { return false }
        return pages.indexOfTabViewItem(item) == 5
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

    func selectProfile(at index: Int, forceReload: Bool = false) {
        guard profiles.indices.contains(index) else { return }
        if !forceReload && selectedIndex == index {
            return
        }
        selectedIndex = index
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        let url = store.configURL(for: profiles[index])
        let rawConfig = (try? String(contentsOf: url)) ?? ""
        var loaded = normalizeLatencyTestURLs(inConfigText: rawConfig) ?? rawConfig
        // Some subscription generators have briefly returned Trojan outbounds
        // without their TLS block. Heal persisted profiles on load as well as at
        // runtime so an older app-created broken profile does not keep failing.
        if let parsed = parseConfigObject(from: loaded) {
            let containedSecret = LocalAPIConfiguration.containsSecret(in: parsed)
            let sanitized = LocalAPIConfiguration.removingSecret(from: parsed)
            let repaired = ConfigCompatibilityChecker.autoFix(config: sanitized)
            if (containedSecret || !repaired.fixed.isEmpty), let rendered = try? renderConfig(repaired.config) {
                loaded = rendered
                try? loaded.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        // Repair a stale/dangling default_domain_resolver (e.g. an old "dns-cn" no
        // longer defined) so the profile passes sing-box check, and persist the fix.
        if let repaired = repairDefaultDomainResolver(inConfigText: loaded) {
            loaded = repaired
            try? loaded.write(to: url, atomically: true, encoding: .utf8)
        }
        editor.string = loaded
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
        if let parsed = parseConfigObject(from: editor.string),
           LocalAPIConfiguration.containsSecret(in: parsed) {
            editor.string = try renderConfig(LocalAPIConfiguration.removingSecret(from: parsed))
        }
        let data = editor.string.data(using: .utf8) ?? Data()
        _ = try JSONSerialization.jsonObject(with: data)
        profiles[index].updatedAt = Date()
        let url = store.configURL(for: profiles[index])
        try editor.string.write(to: url, atomically: true, encoding: .utf8)
        if let (id, rules) = pendingRuleProjection,
           let obj = parseConfigObject(from: editor.string),
           NSArray(array: (obj["route"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []).isEqual(to: rules) {
            try store.saveRuleProjection(editor.string, for: id)
            pendingRuleProjection = nil
        }
        store.saveProfiles(profiles)
        // Saving the profile does not change the watched rule-set files. Keep the
        // last observed revision; subscription changes reset it in the watcher.
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

    func tunUpstreamHosts(in text: String) -> [String] {
        TUNRuntimeConfigBuilder.upstreamHosts(in: text)
    }

    func preparedTunConfigText(from configText: String, networkSnapshot: TUNRuntimeConfigBuilder.NetworkSnapshot? = nil) throws -> String {
        guard var config = parseConfigObject(from: configText) else {
            throw NSError.user("当前配置不是有效 JSON")
        }
        config = ConfigCompatibilityChecker.autoFix(config: config).config
        config = RuleSetRuntime.localizeBuiltInRuleSets(
            in: config,
            ruleSetDirectory: store.ruleSetsURL
        ).config

        let builder = TUNRuntimeConfigBuilder(
            settings: TUNConfig.snapshot(),
            device: currentTunDevice(),
            fallbackProxyTag: nodes.first?.tag ?? "direct",
            cachePath: TunServiceManager.cachePath,
            clashAPIPort: TungBoxConfig.tunDaemonClashPort,
            clashAPISecret: TungBoxConfig.tunClashAPISecret
        )
        let prepared = builder.prepare(config)
        prepared.diagnostics.forEach { appendLog($0) }

        // 快照中的 nil 表示已探测但没有物理接口，不能再次探测。
        let interface: String?
        if let networkSnapshot {
            interface = networkSnapshot.physicalInterface
        } else {
            interface = TunServiceManager.defaultNetworkInterface()
        }
        let bound = builder.bindPhysicalInterface(interface, in: prepared.config)
        bound.diagnostics.forEach { appendLog($0) }
        let hosts = TUNRuntimeConfigBuilder.hostsNeedingResolution(in: bound.config)
        let addresses = networkSnapshot?.resolvedAddressesByHost ?? resolvePublicIPv4Addresses(forHosts: hosts)
        let output = builder.finish(bound.config, resolvedAddresses: addresses)
        output.diagnostics.forEach { appendLog($0) }
        return try output.text.get()
    }

    nonisolated func isPublicIPv4Address(_ value: String) -> Bool {
        TUNRuntimeConfigBuilder.isPublicIPv4Address(value)
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

    func currentTunDevice() -> TUNRuntimeConfigBuilder.Device {
        .init(ipv4Address: TunServiceManager.tunIPv4Address, interfaceName: TunServiceManager.tunInterfaceName)
    }

    func setTunEnabled(_ enabled: Bool, in config: [String: Any]) -> [String: Any] {
        TUNRuntimeConfigBuilder.setTunEnabled(
            enabled, in: config,
            settings: enabled ? TUNConfig.snapshot() : .init(),
            device: currentTunDevice(),
            fallbackProxyTag: nodes.first?.tag ?? "direct",
            cachePath: TunServiceManager.cachePath
        )
    }

    func modeDisplayName(_ mode: String) -> String {
        ConfigInspection.modeDisplayName(mode)
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
        guard !runtimeCoordinator.state.isTerminating else { return }
        guard var config = parseConfigObject(from: editor.string) else {
            throw NSError.user("当前配置不是有效 JSON")
        }
        let previousMode = readMode(from: config)
        let mode = selectedMode()
        let refreshDelays = NodeDelayTestPolicy.refreshAfterModeChange(
            from: previousMode, to: mode.value,
            pendingRefresh: modeChangeNeedsDelayRefresh
        )
        config = ensureModeSupport(in: config, mode: mode)
        editor.string = try renderConfig(config)
        let url = try saveCurrent()
        let output = try runner.check(config: url)
        appendLog("[mode] 已切换到 \(mode.displayName)：\(output)\n")
        refreshModeFromEditor()
        refreshNodeGroupsView()   // re-filter shown groups for the new mode

        if isProxyServiceActiveOrRequested() {
            applyRuntimeMode(mode.value, refreshNodeDelays: refreshDelays)
        } else if refreshDelays {
            testAllNodesClicked()
        }
    }

    func applyRuntimeMode(_ mode: String, refreshNodeDelays: Bool) {
        guard !runtimeCoordinator.state.isTerminating else { return }
        let previousTask = modeChangeTask
        previousTask?.cancel()
        modeChangeID = UUID()
        let id = modeChangeID
        let transitionID = runtimeTransitionID
        modeChangeNeedsDelayRefresh = refreshNodeDelays
        modeChangeTask = Task { @MainActor [weak self] in
            // Wait for cancelled work to settle before applying the latest mode,
            // so rapid mode clicks cannot leave a late older PATCH as the winner.
            await previousTask?.value
            guard let self else { return }
            defer {
                if self.modeChangeID == id {
                    self.modeChangeTask = nil
                }
            }
            @MainActor func isCurrent() -> Bool {
                !Task.isCancelled && self.modeChangeID == id && self.runtimeTransitionID == transitionID
            }
            guard isCurrent() else { return }
            do {
                // If a switch is still starting a Core, apply the saved mode once
                // its startup has finished instead of restarting it again.
                while self.isProxyServiceTransitioning {
                    try await Task.sleep(for: .milliseconds(100))
                    guard isCurrent() else { return }
                }
                let ports = self.activeSelectorAPIPorts()
                for port in ports {
                    guard isCurrent() else { return }
                    try await ClashAPI.setModeAndCloseConnections(mode, port: port)
                }
                guard isCurrent() else { return }
                self.appendLog(ports.isEmpty ? "[模式] 运行态已关闭，模式已保存\n" : "[模式] 已同步到运行中的 Core：\(mode)\n")
                if refreshNodeDelays, !self.nodeDelayTestState.covers(self.nodes.map(\.tag)) {
                    while self.nodeDelayTestState.isActive {
                        try await Task.sleep(for: .milliseconds(100))
                        guard isCurrent() else { return }
                    }
                    self.testAllNodesClicked()
                }
                self.modeChangeNeedsDelayRefresh = false
            } catch {
                guard isCurrent() else { return }
                self.appendLog("[模式] 运行态模式同步失败：\(error.localizedDescription)\n")
                self.showError(NSError.user("模式未能同步到运行中的 Core，请重试：\(error.localizedDescription)"))
            }
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
        ProxyModeConfig.readMode(from: config)
    }

    func repairDefaultDomainResolver(inConfigText text: String) -> String? {
        ProxyModeConfig.repairDefaultDomainResolver(inConfigText: text)
    }

    func ensureModeSupport(in config: [String: Any], mode: Mode) -> [String: Any] {
        ProxyModeConfig.ensureModeSupport(
            in: config,
            mode: mode.value,
            fallbackProxyTag: nodes.first?.tag ?? "direct"
        )
    }

    func parseConfigObject(from text: String) -> [String: Any]? {
        ConfigCodec.parseObject(from: text)
    }

    func renderConfig(_ config: [String: Any]) throws -> String {
        try ConfigCodec.render(config)
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

    @discardableResult
    func stopServiceFromDelegate() -> Task<Void, Never> {
        stopService(clearSystemProxySynchronously: true, isTerminating: true)
    }

    nonisolated func runCommand(_ binary: String, args: [String], timeoutSeconds: TimeInterval = 3) -> String {
        SystemCommand.run(binary, args: args, timeoutSeconds: timeoutSeconds)
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
}
