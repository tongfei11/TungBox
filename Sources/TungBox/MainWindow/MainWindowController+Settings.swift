import AppKit
import Foundation
import ServiceManagement

extension MainWindowController {
    
    func makeSettingsView() -> NSView {
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
        tabControl.items = SettingsPageNavigation.titles
        tabControl.selectedSegment = 0
        tabControl.target = self
        tabControl.action = #selector(settingsTabChanged(_:))
        tabControl.translatesAutoresizingMaskIntoConstraints = false
        tabControl.widthAnchor.constraint(equalToConstant: SettingsPageNavigation.width).isActive = true
        ConsoleControlLayout.configurePageTabs(tabControl)

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
            makeSettingsCorePage(),
            makeSettingsTunPage(),
            makeSettingsDNSPage(),
            makeSettingsRuleSetPage(),
            makeSettingsAppearancePage(),
            makeSettingsAboutPage()
        ]
        
        settingsPages.forEach { ConsoleControlLayout.equalizePageActions(in: $0) }
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

    @objc func settingsTabChanged(_ sender: MD3SegmentedControl) {
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

    func makeSettingsGeneralPage() -> NSView {
        settingsLaunchAtLoginCheckbox.title = "开机自启动"
        settingsLaunchAtLoginCheckbox.target = self
        settingsLaunchAtLoginCheckbox.action = #selector(settingsLaunchAtLoginChanged(_:))
        settingsLaunchAtLoginCheckbox.state = isLaunchAtLoginEnabled ? .on : .off

        settingsStartSilentlyCheckbox.title = "静默启动 (只启动状态栏，不打开控制台UI)"
        settingsStartSilentlyCheckbox.target = self
        settingsStartSilentlyCheckbox.action = #selector(settingsStartSilentlyChanged(_:))
        settingsStartSilentlyCheckbox.state = UserDefaults.standard.bool(forKey: "startSilently") ? .on : .off


        // Subscription auto-refresh interval
        let refreshLabel = settingsLabel("订阅自动刷新间隔")
        let refreshPopup = MD3PopUpButton()
        let intervals = SubscriptionRefreshSchedule.options
        refreshPopup.removeAllItems()
        for (title, _) in intervals { refreshPopup.addItem(withTitle: title) }
        let savedMinutes = SubscriptionRefreshSchedule.minutes()
        if let idx = intervals.firstIndex(where: { $0.1 == savedMinutes }) {
            refreshPopup.selectItem(at: idx)
        } else {
            refreshPopup.selectItem(at: 0) // default 关闭
        }
        refreshPopup.target = self
        refreshPopup.action = #selector(subscriptionRefreshIntervalChanged(_:))
        refreshPopup.translatesAutoresizingMaskIntoConstraints = false
        refreshPopup.heightAnchor.constraint(equalToConstant: 36).isActive = true
        refreshPopup.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let refreshRow = NSStackView(views: [refreshLabel, refreshPopup])
        refreshRow.orientation = .horizontal
        refreshRow.alignment = .centerY
        refreshRow.spacing = 12
        refreshRow.translatesAutoresizingMaskIntoConstraints = false

        // 自动测速 interval / tolerance（写进 urltest outbound）
        let urlTestIntervalLabel = settingsLabel("自动测速间隔")
        let urlTestIntervalPopup = MD3PopUpButton()
        urlTestIntervalPopup.removeAllItems()
        for minutes in TungBoxConfig.urlTestIntervalOptionsMinutes {
            urlTestIntervalPopup.addItem(withTitle: "\(minutes) 分钟")
        }
        let currentInterval = TungBoxConfig.urlTestIntervalMinutes
        if let idx = TungBoxConfig.urlTestIntervalOptionsMinutes.firstIndex(of: currentInterval) {
            urlTestIntervalPopup.selectItem(at: idx)
        }
        urlTestIntervalPopup.target = self
        urlTestIntervalPopup.action = #selector(urlTestIntervalChanged(_:))
        urlTestIntervalPopup.translatesAutoresizingMaskIntoConstraints = false
        urlTestIntervalPopup.heightAnchor.constraint(equalToConstant: 36).isActive = true
        urlTestIntervalPopup.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let urlTestIntervalRow = NSStackView(views: [urlTestIntervalLabel, urlTestIntervalPopup])
        urlTestIntervalRow.orientation = .horizontal
        urlTestIntervalRow.alignment = .centerY
        urlTestIntervalRow.spacing = 12
        urlTestIntervalRow.translatesAutoresizingMaskIntoConstraints = false

        let urlTestToleranceLabel = settingsLabel("自动测速容差 (ms)")
        let urlTestTolerancePopup = MD3PopUpButton()
        urlTestTolerancePopup.removeAllItems()
        for ms in TungBoxConfig.urlTestToleranceOptionsMs {
            urlTestTolerancePopup.addItem(withTitle: "\(ms) ms")
        }
        let currentTolerance = TungBoxConfig.urlTestTolerance
        if let idx = TungBoxConfig.urlTestToleranceOptionsMs.firstIndex(of: currentTolerance) {
            urlTestTolerancePopup.selectItem(at: idx)
        }
        urlTestTolerancePopup.target = self
        urlTestTolerancePopup.action = #selector(urlTestToleranceChanged(_:))
        urlTestTolerancePopup.translatesAutoresizingMaskIntoConstraints = false
        urlTestTolerancePopup.heightAnchor.constraint(equalToConstant: 36).isActive = true
        urlTestTolerancePopup.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let urlTestToleranceRow = NSStackView(views: [urlTestToleranceLabel, urlTestTolerancePopup])
        urlTestToleranceRow.orientation = .horizontal
        urlTestToleranceRow.alignment = .centerY
        urlTestToleranceRow.spacing = 12
        urlTestToleranceRow.translatesAutoresizingMaskIntoConstraints = false

        let urlTestHint = NSTextField(labelWithString: "「自动选择」组的 sing-box urltest 参数。间隔决定多久重新拨测一次；容差是当前节点比最快节点慢多少毫秒之内不切换，避免来回抖动。改动在下次刷新订阅后生效。")
        urlTestHint.textColor = MD3.onSurfaceVariant
        urlTestHint.font = .systemFont(ofSize: 12)
        urlTestHint.lineBreakMode = .byWordWrapping
        urlTestHint.maximumNumberOfLines = 0
        urlTestHint.usesSingleLineMode = false
        urlTestHint.cell?.wraps = true
        urlTestHint.cell?.isScrollable = false
        urlTestHint.translatesAutoresizingMaskIntoConstraints = false
        urlTestHint.preferredMaxLayoutWidth = 520
        registerThemeObserver { [weak urlTestHint] in
            urlTestHint?.textColor = MD3.onSurfaceVariant
        }

        return settingsPageStack([
            settingsPanel(title: "软件启动配置", views: [
                settingsLaunchAtLoginCheckbox,
                settingsStartSilentlyCheckbox
            ]),
            settingsPanel(title: "订阅", views: [refreshRow]),
            settingsPanel(title: "自动测速", views: [urlTestIntervalRow, urlTestToleranceRow, urlTestHint])
        ])
    }

    func makeSettingsRuleSetPage() -> NSView {
        setupRuleSetURLFields()
        let ruleSetForm = NSGridView(views: [
            [settingsLabel("geosite-private"), ruleSetPrivateURLField],
            [settingsLabel("geosite-cn"), ruleSetCNURLField],
            [settingsLabel("geoip-cn"), ruleSetGeoIPCNURLField],
            [settingsLabel("geosite-geolocation-!cn"), ruleSetGeolocationNotCNURLField]
        ])
        ruleSetForm.translatesAutoresizingMaskIntoConstraints = false
        ruleSetForm.column(at: 0).xPlacement = .trailing
        ruleSetForm.column(at: 1).width = 480
        ruleSetForm.rowSpacing = 10
        ruleSetForm.columnSpacing = 10
        let saveRuleSetButton = settingsButton(title: "保存规则集地址", action: #selector(saveRuleSetURLsClicked))
        let refreshRuleSetsButton = settingsButton(title: "刷新规则集", action: #selector(refreshRuleSetsManuallyClicked), style: .filled)
        let clearRuleSetsButton = settingsButton(title: "清空规则集缓存", action: #selector(clearRuleSetCacheClicked), style: .outlined)
        let cacheButtonGrid = settingsButtonGrid([
            refreshRuleSetsButton,
            clearRuleSetsButton
        ])
        let addressHint = settingsLabel("修改地址后，刷新订阅即可将新地址应用到配置。留空时优先使用订阅地址。")

        return settingsPageStack([
            settingsPanel(title: "规则集地址", views: [ruleSetForm, addressHint, saveRuleSetButton]),
            settingsPanel(title: "规则集缓存", views: [cacheButtonGrid])
        ])
    }

    func settingsPageStack(_ cards: [NSView]) -> NSView {
        let view = MD3SettingsPageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        let scroll = MD3ScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let content = MD3SettingsDocumentView()
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = content
        
        let stack = NSStackView(views: cards)
        stack.orientation = .vertical
        stack.spacing = 16
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentHuggingPriority(.required, for: .vertical)
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        content.addSubview(stack)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
        
        cards.forEach { card in
            card.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            card.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }

        DispatchQueue.main.async { [weak scroll] in
            guard let scroll else { return }
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        
        return view
    }

    func settingsPanel(title: String, views: [NSView]) -> NSView {
        let panel = MD3Panel()
        panel.type = .filled
        panel.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = MD3.onSurface
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        registerThemeObserver { [weak titleLabel] in
            titleLabel?.textColor = MD3.onSurface
        }
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
            titleLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -18)
        ])
        return panel
    }

    func settingsButton(title: String, action: Selector, style: MD3Button.ButtonStyle = .filled) -> MD3Button {
        let button = MD3Button()
        configureSettingsButton(button, title: title, action: action, style: style)
        return button
    }

    @discardableResult
    func configureSettingsButton(_ button: MD3Button, title: String, action: Selector, style: MD3Button.ButtonStyle = .filled) -> MD3Button {
        button.title = title
        button.style = style
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: ConsoleControlLayout.actionHeight).isActive = true
        return button
    }

    func settingsButtonGrid(_ buttons: [NSView]) -> NSView {
        ConsoleControlLayout.settingsButtonGrid(buttons)
    }

    @objc func settingsSystemProxyChanged(_ sender: MD3Checkbox) {
        isSystemProxyDefaultEnabled = sender.state == .on
        UserDefaults.standard.set(isSystemProxyDefaultEnabled, forKey: "systemProxyDefaultEnabled")
        syncProxyPreferenceControls()
        appendLog("[设置] 默认开启代理服务已\(isSystemProxyDefaultEnabled ? "开启" : "关闭")\n")
        refreshStatus()
    }

    @objc func settingsCaptureModeChanged(_ sender: MD3RadioButton) {
        setCaptureMode(tunEnabled: sender.tag == 1, source: "设置")
    }

    @objc func settingsLaunchAtLoginChanged(_ sender: MD3Checkbox) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "launchAtLoginEnabled")
        
        if #available(macOS 13.0, *) {
            let appService = SMAppService.mainApp
            do {
                if enabled {
                    if appService.status != .enabled {
                        try appService.register()
                    }
                } else {
                    if appService.status == .enabled {
                        try appService.unregister()
                    }
                }
                appendLog("[设置] 开机自启动已\(enabled ? "开启" : "关闭")\n")
            } catch {
                showError(error)
                sender.state = enabled ? .off : .on
                UserDefaults.standard.set(!enabled, forKey: "launchAtLoginEnabled")
            }
        } else {
            let appPath = Bundle.main.bundlePath
            let script = enabled 
                ? "tell application \"System Events\" to make new login item at end with properties {path:\"\(appPath)\", hidden:false}"
                : "tell application \"System Events\" to delete (every login item whose path is \"\(appPath)\")"
            
            let appleScript = NSAppleScript(source: script)
            var errorInfo: NSDictionary?
            appleScript?.executeAndReturnError(&errorInfo)
            if let err = errorInfo {
                let msg = err[NSAppleScript.errorMessage] as? String ?? "AppleScript execution failed"
                showError(NSError.user(msg))
                sender.state = enabled ? .off : .on
                UserDefaults.standard.set(!enabled, forKey: "launchAtLoginEnabled")
            } else {
                appendLog("[设置] 开机自启动已\(enabled ? "开启" : "关闭")\n")
            }
        }
        
        refreshStatus()
    }

    @objc func settingsStartSilentlyChanged(_ sender: MD3Checkbox) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "startSilently")
        appendLog("[设置] 静默启动已\(enabled ? "开启" : "关闭")\n")
        refreshStatus()
    }

    @objc func subscriptionRefreshIntervalChanged(_ sender: MD3PopUpButton) {
        let intervals = SubscriptionRefreshSchedule.options
        guard intervals.indices.contains(sender.indexOfSelectedItem) else { return }
        let minutes = intervals[sender.indexOfSelectedItem].minutes
        UserDefaults.standard.set(minutes, forKey: SubscriptionRefreshSchedule.defaultsKey)
        startSubscriptionTimer()
        refreshHomeFeatureStatus()
        appendLog("[设置] 订阅自动刷新间隔已设为 \(sender.titleOfSelectedItem ?? "关闭")\n")
    }

    @objc func urlTestIntervalChanged(_ sender: MD3PopUpButton) {
        let options = TungBoxConfig.urlTestIntervalOptionsMinutes
        let index = max(0, min(sender.indexOfSelectedItem, options.count - 1))
        let minutes = options[index]
        UserDefaults.standard.set(minutes, forKey: "urlTestIntervalMinutes")
        appendLog("[设置] 自动测速间隔已设为 \(minutes) 分钟（下次刷新订阅生效）\n")
        showToast("自动测速间隔：\(minutes) 分钟（下次刷新订阅生效）", style: .info)
    }

    @objc func urlTestToleranceChanged(_ sender: MD3PopUpButton) {
        let options = TungBoxConfig.urlTestToleranceOptionsMs
        let index = max(0, min(sender.indexOfSelectedItem, options.count - 1))
        let ms = options[index]
        UserDefaults.standard.set(ms, forKey: "urlTestToleranceMs")
        appendLog("[设置] 自动测速容差已设为 \(ms) ms（下次刷新订阅生效）\n")
        showToast("自动测速容差：\(ms) ms（下次刷新订阅生效）", style: .info)
    }

    func syncProxyPreferenceControls() {
        // Two independent switches (system proxy + TUN, can both be on).
        serviceSwitch.isOn = isSystemProxyEnabled
        tunSwitch.isOn = isTunEnabled
        settingsLaunchAtLoginCheckbox.state = isLaunchAtLoginEnabled ? .on : .off
        settingsStartSilentlyCheckbox.state = UserDefaults.standard.bool(forKey: "startSilently") ? .on : .off
        if trayIconStylePopup.numberOfItems > TrayIconStyle.current.rawValue {
            trayIconStylePopup.selectItem(at: TrayIconStyle.current.rawValue)
        }
    }

    @objc func showLogsFromHomeClicked() {
        selectPage(at: 5)
    }

    @objc func tableClicked() {
        guard table.selectedRow >= 0 else { return }
        selectProfile(at: table.selectedRow)
    }

    @objc func newClicked() {
        let name = "配置 \(profiles.count + 1)"
        createProfile(named: name, content: defaultConfig())
    }

    @objc func importClicked() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url) {
            createProfile(named: url.deletingPathExtension().lastPathComponent, content: text)
        }
    }

    @objc func deleteClicked() {
        guard let index = selectedIndex else { return }
        let profile = profiles[index]
        store.deleteConfig(for: profile)
        profiles.remove(at: index)
        store.saveProfiles(profiles)
        table.reloadData()
        selectedIndex = nil
        editor.string = ""
        if !profiles.isEmpty { selectProfile(at: min(index, profiles.count - 1)) }
    }

    func setupRuleSetURLFields() {
        let fields = [
            (ruleSetPrivateURLField, TungBoxConfig.ruleSetPrivate),
            (ruleSetCNURLField, TungBoxConfig.ruleSetCN),
            (ruleSetGeoIPCNURLField, TungBoxConfig.ruleSetGeoIPCN),
            (ruleSetGeolocationNotCNURLField, TungBoxConfig.ruleSetGeolocationNotCN)
        ]
        for (field, tag) in fields {
            field.stringValue = TungBoxConfig.ruleSetURLOverride(for: tag)
            field.placeholderString = TungBoxConfig.defaultRuleSetURLs[tag]
            field.translatesAutoresizingMaskIntoConstraints = false
            field.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }
    }

    /// 标题在左、checkbox 在右、灰色提示文案在下的设置行。统一 4 处 DNS/TUN 的开关
    /// 视觉，避免 "[✓] 标题（长括号说明）" 那种把说明塞到 checkbox title 里的拥挤写法。
    /// - checkbox 的 title 会被清空，所以传进来时不用关心 title 字段。
    func settingsToggleRow(title: String, hint: String? = nil, checkbox: MD3Checkbox) -> NSView {
        checkbox.title = ""
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = MD3.onSurface
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        registerThemeObserver { [weak titleLabel] in
            titleLabel?.textColor = MD3.onSurface
        }

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)

        let row = NSStackView(views: [titleLabel, spacer, checkbox])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 560).isActive = true

        guard let hint, !hint.isEmpty else { return row }

        let hintLabel = NSTextField(labelWithString: hint)
        hintLabel.textColor = MD3.onSurfaceVariant
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 0
        hintLabel.usesSingleLineMode = false
        hintLabel.cell?.wraps = true
        hintLabel.cell?.isScrollable = false
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.preferredMaxLayoutWidth = 560
        registerThemeObserver { [weak hintLabel] in
            hintLabel?.textColor = MD3.onSurfaceVariant
        }

        let stack = NSStackView(views: [row, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 560).isActive = true
        return stack
    }

    /// 一条横向分隔线，宽度跟 panel 内容一致。用在同一 panel 里区分两组不相关的内容。
    func settingsDivider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 560).isActive = true
        return box
    }

    func settingsLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = MD3.onSurfaceVariant
        label.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak label] in
            label?.textColor = MD3.onSurfaceVariant
        }
        return label
    }

    @objc func saveRuleSetURLsClicked() {
        let values = [
            (TungBoxConfig.ruleSetPrivate, ruleSetPrivateURLField.stringValue),
            (TungBoxConfig.ruleSetCN, ruleSetCNURLField.stringValue),
            (TungBoxConfig.ruleSetGeoIPCN, ruleSetGeoIPCNURLField.stringValue),
            (TungBoxConfig.ruleSetGeolocationNotCN, ruleSetGeolocationNotCNURLField.stringValue)
        ]
        for (tag, value) in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty || (URL(string: trimmed).map {
                ["http", "https"].contains($0.scheme?.lowercased() ?? "") && !($0.host ?? "").isEmpty
            } ?? false) else {
                showError(NSError.user("\(tag) 请输入有效的 HTTP 或 HTTPS 地址"))
                return
            }
        }
        for (tag, value) in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            TungBoxConfig.setRuleSetURL(trimmed, for: tag)
        }
        setupRuleSetURLFields()
        appendLog("[规则集] 已保存规则集获取地址。留空时使用订阅地址；订阅没有时使用内置默认地址。\n")
        showToast("规则集地址已保存，刷新订阅后生效", style: .success)
    }

    @discardableResult
    @MainActor
    func showMD3Dialog(
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

    @objc func openFolderClicked() {
        NSWorkspace.shared.open(store.baseURL)
    }

}

final class MD3SettingsPageView: NSView, MD3Themeable {
    func themeChanged() {
        self.needsDisplay = true
    }
}

final class MD3SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
