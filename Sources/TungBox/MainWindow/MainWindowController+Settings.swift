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
        tabControl.items = ["常规", "Core", "TUN 设置", "规则集", "外观"]
        tabControl.selectedSegment = 0
        tabControl.target = self
        tabControl.action = #selector(settingsTabChanged(_:))
        tabControl.translatesAutoresizingMaskIntoConstraints = false
        tabControl.widthAnchor.constraint(equalToConstant: 380).isActive = true
        tabControl.heightAnchor.constraint(equalToConstant: 36).isActive = true

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
        let detailsText = NSTextField(labelWithString: """
        应用版本: \(TungBoxVersion.current)
        配置目录: \(store.baseURL.path)
        Clash API: \(TungBoxConfig.clashAPIListen)
        """)
        detailsText.textColor = MD3.onSurfaceVariant
        detailsText.font = .systemFont(ofSize: 13)
        detailsText.lineBreakMode = .byWordWrapping
        detailsText.maximumNumberOfLines = 0
        detailsText.usesSingleLineMode = false
        detailsText.cell?.wraps = true
        detailsText.cell?.isScrollable = false
        detailsText.translatesAutoresizingMaskIntoConstraints = false
        detailsText.setContentHuggingPriority(.required, for: .vertical)
        detailsText.setContentCompressionResistancePriority(.required, for: .vertical)
        detailsText.heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true

        let openFolderButton = settingsButton(title: "打开配置目录", action: #selector(openFolderClicked), style: .outlined)

        settingsSystemProxyCheckbox.title = "默认开启代理服务"
        settingsSystemProxyCheckbox.target = self
        settingsSystemProxyCheckbox.action = #selector(settingsSystemProxyChanged(_:))
        settingsSystemProxyCheckbox.state = isSystemProxyDefaultEnabled ? .on : .off

        configureCaptureRadio(settingsSystemProxyRadio, tag: 0, action: #selector(settingsCaptureModeChanged(_:)))
        configureCaptureRadio(settingsTunRadio, tag: 1, action: #selector(settingsCaptureModeChanged(_:)))
        settingsSystemProxyRadio.state = isTunEnabled ? .off : .on
        settingsTunRadio.state = isTunEnabled ? .on : .off
        let defaultCaptureLabel = settingsLabel("默认接管方式")
        let defaultCaptureStack = NSStackView(views: [settingsSystemProxyRadio, settingsTunRadio])
        defaultCaptureStack.orientation = .vertical
        defaultCaptureStack.spacing = 6
        defaultCaptureStack.alignment = .leading
        defaultCaptureStack.translatesAutoresizingMaskIntoConstraints = false

        settingsLaunchAtLoginCheckbox.title = "开机自启动"
        settingsLaunchAtLoginCheckbox.target = self
        settingsLaunchAtLoginCheckbox.action = #selector(settingsLaunchAtLoginChanged(_:))
        settingsLaunchAtLoginCheckbox.state = isLaunchAtLoginEnabled ? .on : .off

        settingsStartSilentlyCheckbox.title = "静默启动 (只启动状态栏，不打开控制台UI)"
        settingsStartSilentlyCheckbox.target = self
        settingsStartSilentlyCheckbox.action = #selector(settingsStartSilentlyChanged(_:))
        settingsStartSilentlyCheckbox.state = UserDefaults.standard.bool(forKey: "startSilently") ? .on : .off


        let proxyHint = NSTextField(labelWithString: "代理服务开启后会按接管方式启动；系统代理和 TUN 模式互斥。")
        proxyHint.textColor = MD3.onSurfaceVariant
        proxyHint.font = .systemFont(ofSize: 13)
        proxyHint.lineBreakMode = .byWordWrapping
        proxyHint.maximumNumberOfLines = 0
        proxyHint.translatesAutoresizingMaskIntoConstraints = false

        // Subscription auto-refresh interval
        let refreshLabel = settingsLabel("订阅自动刷新间隔")
        let refreshPopup = MD3PopUpButton()
        let intervals: [(String, Int)] = [("关闭", 0), ("30 分钟", 30), ("1 小时", 60), ("2 小时", 120), ("4 小时", 240), ("6 小时", 360), ("12 小时", 720), ("24 小时", 1440)]
        refreshPopup.removeAllItems()
        for (title, _) in intervals { refreshPopup.addItem(withTitle: title) }
        let savedInterval = UserDefaults.standard.integer(forKey: "subscriptionRefreshMinutes")
        let savedMinutes = savedInterval > 0 ? savedInterval : 60
        if let idx = intervals.firstIndex(where: { $0.1 == savedMinutes }) {
            refreshPopup.selectItem(at: idx)
        } else {
            refreshPopup.selectItem(at: 2) // default 1h
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

        return settingsPageStack([
            settingsPanel(title: "代理启动配置", views: [
                settingsSystemProxyCheckbox,
                defaultCaptureLabel,
                defaultCaptureStack,
                proxyHint
            ]),
            settingsPanel(title: "软件启动配置", views: [
                settingsLaunchAtLoginCheckbox,
                settingsStartSilentlyCheckbox
            ]),
            settingsPanel(title: "订阅", views: [refreshRow]),
            settingsPanel(title: "软件信息", views: [detailsText, openFolderButton])
        ])
    }

    func makeSettingsCorePage() -> NSView {
        serviceLabel.font = .systemFont(ofSize: 14, weight: .bold)
        serviceLabel.textColor = MD3.onSurface
        serviceLabel.lineBreakMode = .byWordWrapping
        serviceLabel.maximumNumberOfLines = 0
        serviceLabel.usesSingleLineMode = false
        serviceLabel.cell?.wraps = true
        serviceLabel.translatesAutoresizingMaskIntoConstraints = false

        let checkUpdateButton = settingsButton(title: "检查 Core 更新", action: #selector(checkCoreUpdateClicked), style: .tonal)
        let installLatestButton = settingsButton(title: "安装最新 Core", action: #selector(installLatestCoreClicked), style: .filled)
        let importCoreButton = settingsButton(title: "导入 sing-box Core", action: #selector(importCoreClicked), style: .filled)
        let installOldCoreButton = settingsButton(title: "安装旧版 Core（测试）", action: #selector(installOldCoreForTestClicked), style: .outlined)
        let openCoreFolderButton = settingsButton(title: "打开 Core 目录", action: #selector(openCoreFolderClicked), style: .outlined)
        let coreButtonGrid = settingsButtonGrid([
            checkUpdateButton,
            installLatestButton,
            importCoreButton,
            installOldCoreButton,
            openCoreFolderButton
        ])

        return settingsPageStack([
            settingsPanel(title: "Core 管理", views: [
                serviceLabel,
                coreButtonGrid
            ])
        ])
    }

    func makeSettingsTunPage() -> NSView {
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

        configureSettingsButton(tunServiceToggleButton, title: "安装 TUN 服务", action: #selector(toggleTunServiceInstallClicked), style: .filled)
        configureSettingsButton(tunServiceReinstallButton, title: "重新安装 TUN 服务", action: #selector(reinstallTunServiceClicked), style: .outlined)
        configureSettingsButton(tunServiceReloadButton, title: "重载 TUN 服务", action: #selector(reloadTunServiceClicked), style: .tonal)
        let openLogButton = settingsButton(title: "打开 TUN 日志", action: #selector(openTunLogClicked), style: .outlined)
        let tunButtonGrid = settingsButtonGrid([
            tunServiceToggleButton,
            tunServiceReinstallButton,
            tunServiceReloadButton,
            openLogButton
        ])

        let hint = NSTextField(labelWithString: "安装、卸载、重装和重载 TUN 服务会请求管理员授权。首页 TUN 开关只负责启用或关闭本用户的控制请求；TUN 服务校验配置后使用 /Library/Application Support/TungBox 下的 root-owned 运行配置。")
        hint.textColor = MD3.onSurfaceVariant
        hint.font = .systemFont(ofSize: 13)
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false

        refreshTunServiceStatus()
        return settingsPageStack([
            settingsPanel(title: "TUN 设置", views: [
                tunServiceStatusLabel,
                tunButtonGrid,
                tunServiceLogLabel,
                hint
            ])
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
        ruleSetForm.column(at: 1).width = 560
        ruleSetForm.rowSpacing = 10
        ruleSetForm.columnSpacing = 10
        let saveRuleSetButton = settingsButton(title: "保存规则集地址", action: #selector(saveRuleSetURLsClicked))
        let refreshRuleSetsButton = settingsButton(title: "刷新规则集", action: #selector(refreshRuleSetsManuallyClicked), style: .filled)
        let clearRuleSetsButton = settingsButton(title: "清空规则集缓存", action: #selector(clearRuleSetCacheClicked), style: .outlined)
        let cacheButtonGrid = settingsButtonGrid([
            refreshRuleSetsButton,
            clearRuleSetsButton
        ])

        return settingsPageStack([
            settingsPanel(title: "规则集地址", views: [ruleSetForm, saveRuleSetButton]),
            settingsPanel(title: "规则集缓存", views: [cacheButtonGrid])
        ])
    }

    func makeSettingsAppearancePage() -> NSView {
        let trayIconStyleLabel = settingsLabel("图标样式")
        trayIconStylePopup.removeAllItems()
        let trayIconStyles: [TrayIconStyle] = [.iconOnly, .iconAndSpeed, .speedOnly]
        for style in trayIconStyles {
            trayIconStylePopup.addItem(withTitle: style.title)
        }
        trayIconStylePopup.selectItem(at: TrayIconStyle.current.rawValue)
        trayIconStylePopup.target = self
        trayIconStylePopup.action = #selector(trayIconStyleChanged(_:))
        trayIconStylePopup.translatesAutoresizingMaskIntoConstraints = false
        trayIconStylePopup.heightAnchor.constraint(equalToConstant: 36).isActive = true
        trayIconStylePopup.widthAnchor.constraint(equalToConstant: 190).isActive = true

        let trayIconStyleRow = NSStackView(views: [trayIconStyleLabel, trayIconStylePopup])
        trayIconStyleRow.orientation = .horizontal
        trayIconStyleRow.alignment = .centerY
        trayIconStyleRow.spacing = 12
        trayIconStyleRow.translatesAutoresizingMaskIntoConstraints = false

        let statusBarPanel = settingsPanel(title: "状态栏", views: [trayIconStyleRow])

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
        
        let appearancePanel = settingsPanel(title: "外观", views: [themeButton, columnsStack])

        return settingsPageStack([statusBarPanel, appearancePanel])
    }

    private func settingsPageStack(_ cards: [NSView]) -> NSView {
        let view = MD3SettingsPageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        let scroll = NSScrollView()
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

    private func settingsPanel(title: String, views: [NSView]) -> NSView {
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

    private func settingsButton(title: String, action: Selector, style: MD3Button.ButtonStyle = .filled) -> MD3Button {
        let button = MD3Button()
        configureSettingsButton(button, title: title, action: action, style: style)
        return button
    }

    @discardableResult
    private func configureSettingsButton(_ button: MD3Button, title: String, action: Selector, style: MD3Button.ButtonStyle = .filled) -> MD3Button {
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

    @objc func checkCoreUpdateClicked() {
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

    @objc func installLatestCoreClicked() {
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

    @objc func installOldCoreForTestClicked() {
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

        let dialog = showMD3Dialog(
            title: "发现 sing-box Core 更新",
            message: "当前版本：\(currentText)\n最新版本：\(release.version)\n是否现在安装？",
            customView: nil,
            confirmTitle: "安装",
            cancelTitle: "稍后"
        )
        dialog.onConfirm = { [weak self, weak dialog] in
            self?.installCoreRelease(release, reason: "更新")
            dialog?.dismiss()
        }
        dialog.onCancel = { [weak dialog] in
            dialog?.dismiss()
        }
    }

    func installCoreRelease(_ release: CoreRelease, reason: String) {
        let wasRunning = isProxyRuntimeRunning()
        if wasRunning {
            stopService()
            showToast("已暂停代理服务以安装 Core")
            appendLog("[Core] 暂停代理服务以便安装 \(release.version)\n")
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
                    self?.showToast(wasRunning
                        ? "Core 已更新至 \(release.version)，请手动重启代理"
                        : "Core 已安装：\(release.version)")
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

    @objc func trayIconStyleChanged(_ sender: MD3PopUpButton) {
        let index = max(0, min(sender.indexOfSelectedItem, TrayIconStyle.speedOnly.rawValue))
        let style = TrayIconStyle(rawValue: index) ?? .iconOnly
        UserDefaults.standard.set(style.rawValue, forKey: TrayIconStyle.defaultsKey)
        refreshTrayIcon()
        appendLog("[设置] 状态栏图标样式已设为 \(style.title)\n")
    }

    @objc func toggleTunServiceInstallClicked() {
        let status = TunServiceManager.status(store: store)
        if status.shouldReinstall {
            installTunServiceClicked()
        } else if status.isInstalled {
            uninstallTunServiceClicked()
        } else {
            installTunServiceClicked()
        }
    }

    @objc func installTunServiceClicked() {
        runTunServiceOperation(
            progressText: "最近状态：正在安装 TUN 服务...",
            successLog: "[TUN] TUN 服务已安装\n",
            successToast: "TUN 服务已安装",
            failurePrefix: "安装失败",
            operation: { store in
                try TunServiceManager.install(store: store)
            },
            completion: { [weak self] in
                self?.checkSingBoxInstall(showAlert: false)
            }
        )
    }

    @objc func uninstallTunServiceClicked() {
        isTunEnabled = false
        UserDefaults.standard.set(false, forKey: "tunEnabled")
        runTunServiceOperation(
            progressText: "最近状态：正在卸载 TUN 服务...",
            successLog: "[TUN] TUN 服务已卸载\n",
            successToast: "TUN 服务已卸载",
            failurePrefix: "卸载失败",
            operation: { store in
                try TunServiceManager.uninstall(store: store)
            },
            completion: { [weak self] in
                self?.syncProxyPreferenceControls()
            }
        )
    }

    @objc func reinstallTunServiceClicked() {
        let shouldRestoreTun = isTunEnabled
        runTunServiceOperation(
            progressText: "最近状态：正在重新安装 TUN 服务...",
            successLog: "[TUN] TUN 服务已重新安装\n",
            successToast: "TUN 服务已重新安装",
            failurePrefix: "重新安装失败",
            operation: { store in
                try TunServiceManager.install(store: store)
            },
            completion: { [weak self] in
                guard let self else { return }
                if shouldRestoreTun {
                    try self.applyTunPreference(restartIfRunning: false)
                    try self.enableTunServiceSafely(configText: self.editor.string)
                    self.scheduleTunHealthCheck()
                }
                self.checkSingBoxInstall(showAlert: false)
                self.syncProxyPreferenceControls()
            }
        )
    }

    @objc func reloadTunServiceClicked() {
        do {
            if isTunEnabled {
                try applyTunPreference(restartIfRunning: false)
                try enableTunServiceSafely(configText: editor.string)
            }
        } catch {
            tunServiceLogLabel.stringValue = "最近状态：重载失败\n\(error.localizedDescription)"
            showError(error)
            return
        }

        runTunServiceOperation(
            progressText: "最近状态：正在重载 TUN 服务...",
            successLog: "[TUN] TUN 服务已重载\n",
            successToast: "TUN 服务已重载",
            failurePrefix: "重载失败",
            operation: { store in
                try TunServiceManager.reload(store: store)
            }
        )
    }

    func runTunServiceOperation(
        progressText: String,
        successLog: String,
        successToast: String,
        failurePrefix: String,
        operation: @escaping @Sendable (Store) throws -> Void,
        completion: (@MainActor @Sendable () throws -> Void)? = nil
    ) {
        setTunServiceControlsBusy(true, progressText: progressText)
        let store = store
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try operation(store)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.setTunServiceControlsBusy(false, progressText: nil)
                do {
                    try result.get()
                    try completion?()
                    self.appendLog(successLog)
                    self.showToast(successToast)
                    self.refreshTunServiceStatus()
                    self.refreshStatus()
                } catch {
                    self.tunServiceLogLabel.stringValue = "最近状态：\(failurePrefix)\n\(error.localizedDescription)"
                    self.showError(error)
                    self.refreshTunServiceStatus()
                    self.refreshStatus()
                }
            }
        }
    }

    func setTunServiceControlsBusy(_ busy: Bool, progressText: String?) {
        tunServiceOperationInProgress = busy
        tunServiceToggleButton.isEnabled = !busy
        tunServiceReinstallButton.isEnabled = !busy
        tunServiceReloadButton.isEnabled = !busy
        if let progressText {
            tunServiceLogLabel.stringValue = progressText
        }
    }

    @objc func subscriptionRefreshIntervalChanged(_ sender: MD3PopUpButton) {
        let intervals = [0, 30, 60, 120, 240, 360, 720, 1440]
        let minutes = intervals[sender.indexOfSelectedItem]
        UserDefaults.standard.set(minutes, forKey: "subscriptionRefreshMinutes")
        startSubscriptionTimer()
        appendLog("[设置] 订阅自动刷新间隔已设为 \(sender.titleOfSelectedItem ?? "关闭")\n")
    }

    @objc func openTunLogClicked() {
        if FileManager.default.fileExists(atPath: TunServiceManager.logURL.path) {
            NSWorkspace.shared.open(TunServiceManager.logURL)
        } else {
            showToast("暂无 TUN 日志")
        }
    }

    func syncProxyPreferenceControls() {
        serviceSwitch.isOn = isProxyServiceActiveOrRequested()
        homeSystemProxyRadio.state = isTunEnabled ? .off : .on
        homeTunRadio.state = isTunEnabled ? .on : .off
        settingsSystemProxyCheckbox.state = isSystemProxyDefaultEnabled ? .on : .off
        settingsSystemProxyRadio.state = isTunEnabled ? .off : .on
        settingsTunRadio.state = isTunEnabled ? .on : .off
        settingsLaunchAtLoginCheckbox.state = isLaunchAtLoginEnabled ? .on : .off
        settingsStartSilentlyCheckbox.state = UserDefaults.standard.bool(forKey: "startSilently") ? .on : .off
        if trayIconStylePopup.numberOfItems > TrayIconStyle.current.rawValue {
            trayIconStylePopup.selectItem(at: TrayIconStyle.current.rawValue)
        }
    }

    func reconcileSystemProxyForCurrentMode() {
        guard isProxyRuntimeRunning() else { return }
        if isTunEnabled {
            setSystemProxy(enabled: false, port: getMixedProxyPort())
        } else {
            setSystemProxy(enabled: isSystemProxyEnabled, port: getMixedProxyPort())
        }
    }

    func isProxyRuntimeRunning() -> Bool {
        runner.isRunning || isTunRuntimeRunning()
    }

    func isProxyServiceActiveOrRequested() -> Bool {
        isProxyServiceTransitioning
            || runner.isRunning
            || isTunRuntimeRunning()
            || (isTunEnabled && (isSystemProxyEnabled || TunServiceManager.hasEnableRequest(store: store)))
    }

    func isTunRuntimeRunning() -> Bool {
        isTunEnabled && TunServiceManager.activeSingBoxPID(store: store) != nil
    }

    func enableTunServiceSafely(configText: String) throws {
        try ensureTunRouteIsSafeToStart()
        let preparedConfig = try preparedTunConfigText(from: configText)
        setSystemProxy(enabled: false, port: getMixedProxyPort())

        // 调试：保存 tun-request 副本
        let debugRequestPath = NSHomeDirectory() + "/Library/Application Support/TungBox/tun-request-debug.json"
        try? preparedConfig.write(toFile: debugRequestPath, atomically: true, encoding: .utf8)

        try TunServiceManager.enable(store: store, configText: preparedConfig)
        startTunRequestHeartbeat()
    }

    func startTunRequestHeartbeat() {
        TunServiceManager.refreshRequestHeartbeat(store: store)
        tunRequestHeartbeatTimer?.invalidate()
        tunRequestHeartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isTunEnabled, TunServiceManager.hasEnableRequest(store: self.store) else {
                    self.stopTunRequestHeartbeat()
                    return
                }
                TunServiceManager.refreshRequestHeartbeat(store: self.store)
            }
        }
    }

    func stopTunRequestHeartbeat() {
        tunRequestHeartbeatTimer?.invalidate()
        tunRequestHeartbeatTimer = nil
    }

    func ensureTunRouteIsSafeToStart() throws {
        guard let conflict = externalTunDefaultRouteDescription() else { return }
        appendLog("[TUN] 已阻止启动：检测到系统默认网络仍在 \(conflict)\n")
        throw NSError.user("检测到系统默认路由在 TUN/VPN 上（\(conflict)），且没有找到可用的物理出口接口。TungBox 暂不启动 TUN。请检查 Wi-Fi/有线网络，或改用系统代理模式。")
    }

    func externalTunDefaultRouteDescription() -> String? {
        if isTunRuntimeRunning() { return nil }
        let route = runProcessAndGetOutput("/sbin/route", args: ["-n", "get", "default"])
        guard let interface = route
            .components(separatedBy: .newlines)
            .compactMap({ line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("interface:") else { return nil }
                return trimmed
                    .replacingOccurrences(of: "interface:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            })
            .first,
            interface.hasPrefix("utun")
        else {
            return nil
        }
        if let egress = TunServiceManager.defaultNetworkInterface(), !egress.hasPrefix("utun") {
            return nil
        }

        let ifconfig = runProcessAndGetOutput("/sbin/ifconfig", args: [interface])
        var detail = "\(interface)"
        if let address = firstIPv4Address(in: ifconfig) {
            detail += " \(address)"
        }
        if let dns = firstFakeTunDNSServer() {
            detail += "，DNS \(dns)"
        }
        return detail
    }

    private func firstIPv4Address(in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
            if let index = parts.firstIndex(of: "inet"), parts.indices.contains(index + 1) {
                return parts[index + 1]
            }
        }
        return nil
    }

    private func firstFakeTunDNSServer() -> String? {
        let dns = runProcessAndGetOutput("/usr/sbin/scutil", args: ["--dns"])
        for line in dns.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("nameserver"), trimmed.contains("198.18.") else { continue }
            return trimmed.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    func currentProxyPID() -> Int32? {
        if runner.isRunning {
            return runner.pid
        }
        if isTunRuntimeRunning() {
            return TunServiceManager.activeSingBoxPID(store: store)
        }
        return nil
    }

    func refreshTunServiceStatus() {
        tunServiceStatusLabel.stringValue = "TUN 服务状态：正在检查..."
        let store = store
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = TunServiceManager.status(store: store)
            let recentLog: String
            if let text = TunServiceManager.recentLogText(maxBytes: 16 * 1024) {
                recentLog = text
            } else {
                recentLog = ""
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.applyTunServiceStatus(status, recentLogText: recentLog)
            }
        }
    }

    func applyTunServiceStatus(_ status: TunServiceStatus, recentLogText: String) {
        tunServiceStatusLabel.stringValue = "TUN 服务状态：\(status.displayText)"
        if status.shouldReinstall {
            tunServiceToggleButton.title = "安装 TUN 服务"
            tunServiceToggleButton.style = .filled
        } else {
            tunServiceToggleButton.title = status.isInstalled ? "卸载 TUN 服务" : "安装 TUN 服务"
            tunServiceToggleButton.style = status.isInstalled ? .destructive : .filled
        }
        if tunServiceOperationInProgress {
            return
        }
        tunServiceToggleButton.isEnabled = true
        tunServiceReinstallButton.isEnabled = status.isInstalled
        tunServiceReloadButton.isEnabled = status.isUsable
        if !recentLogText.isEmpty {
            let text = recentLogText
            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            tunServiceLogLabel.stringValue = "最近状态：\(lines.suffix(3).joined(separator: "\n"))"
        } else {
            tunServiceLogLabel.stringValue = "最近状态：暂无日志"
        }
    }

    @objc func showLogsFromHomeClicked() {
        selectPage(at: 5)
    }

    func changeColorScheme(to index: Int) {
        MD3.currentSchemeIndex = index
        for row in colorSchemeRows {
            row.isSelected = (row.index == index)
        }
        notifyThemeChanged()
        appendLog("[TungBox] 已切换配色方案为: \(MD3.colorSchemes[index].name)\n")
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
        try? FileManager.default.removeItem(at: store.configURL(for: profile))
        profiles.remove(at: index)
        store.saveProfiles(profiles)
        table.reloadData()
        selectedIndex = nil
        editor.string = ""
        if !profiles.isEmpty { selectProfile(at: min(index, profiles.count - 1)) }
    }

    func checkSingBoxInstall(showAlert: Bool) {
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

    func setupRuleSetURLFields() {
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
            guard trimmed.isEmpty || URL(string: trimmed) != nil else {
                showError(NSError.user("\(tag) 不是有效 URL"))
                return
            }
            TungBoxConfig.setRuleSetURL(trimmed, for: tag)
        }
        setupRuleSetURLFields()
        appendLog("[规则集] 已保存规则集获取地址。留空时使用订阅地址；订阅没有时使用内置默认地址。\n")
    }

    @objc func toggleThemeClicked() {
        MD3.isDark.toggle()
        UserDefaults.standard.set(MD3.isDark, forKey: "appearanceIsDark")
        NSApp.appearance = NSAppearance(named: MD3.isDark ? .darkAqua : .aqua)
        notifyThemeChanged()
        appendLog("[TungBox] 已切换到\(MD3.isDark ? "深色" : "浅色")外观\n")
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

    @objc func openCoreFolderClicked() {
        NSWorkspace.shared.open(store.coreURL)
    }

    @objc func importCoreClicked() {
        let panel = NSOpenPanel()
        panel.title = "选择 sing-box Core"
        panel.message = "请选择 sing-box 或 singbox 可执行文件。TungBox 会复制一份到自己的 Core 目录。"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let source = panel.url {
            do {
                guard FileManager.default.isExecutableFile(atPath: source.path) else {
                    showError(NSError.user("所选文件不是可执行的 sing-box 程序。请确保选择了正确的二进制文件。"))
                    return
                }
                // Quick sanity check: try running version
                let test = Process()
                test.executableURL = source
                test.arguments = ["version"]
                let pipe = Pipe()
                test.standardOutput = pipe
                test.standardError = pipe
                try test.run()
                test.waitUntilExit()
                guard test.terminationStatus == 0 else {
                    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    showError(NSError.user("所选文件无法执行 sing-box version：\(output.prefix(200))"))
                    return
                }

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
}

final class MD3SettingsPageView: NSView, MD3Themeable {
    func themeChanged() {
        self.needsDisplay = true
    }
}

final class MD3SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
