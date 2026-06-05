import AppKit
import Foundation

extension MainWindowController {
    
    func makeHomeView() -> NSView {
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

        let captureLabel = NSTextField(labelWithString: "接管方式")
        captureLabel.font = .systemFont(ofSize: 13, weight: .bold)
        captureLabel.textColor = MD3.onSurfaceVariant
        captureLabel.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak captureLabel] in
            captureLabel?.textColor = MD3.onSurfaceVariant
        }

        configureCaptureRadio(homeSystemProxyRadio, tag: 0, action: #selector(homeCaptureModeChanged(_:)))
        configureCaptureRadio(homeTunRadio, tag: 1, action: #selector(homeCaptureModeChanged(_:)))
        homeSystemProxyRadio.state = isTunEnabled ? .off : .on
        homeTunRadio.state = isTunEnabled ? .on : .off

        let systemProxyOption = makeOptionWithHint(radio: homeSystemProxyRadio, hint: "设置系统 HTTP/Socks5 代理，接管常规软件流量")
        let tunOption = makeOptionWithHint(radio: homeTunRadio, hint: "创建虚拟网卡接管全局 IP 流量，支持终端和游戏")

        let captureOptionsStack = NSStackView(views: [systemProxyOption, tunOption])
        captureOptionsStack.orientation = .vertical
        captureOptionsStack.spacing = 8
        captureOptionsStack.alignment = .leading
        captureOptionsStack.translatesAutoresizingMaskIntoConstraints = false
        
        systemProxyOption.leadingAnchor.constraint(equalTo: captureOptionsStack.leadingAnchor).isActive = true
        systemProxyOption.trailingAnchor.constraint(equalTo: captureOptionsStack.trailingAnchor).isActive = true
        tunOption.leadingAnchor.constraint(equalTo: captureOptionsStack.leadingAnchor).isActive = true
        tunOption.trailingAnchor.constraint(equalTo: captureOptionsStack.trailingAnchor).isActive = true

        captureLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        captureOptionsStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let captureRow = NSStackView(views: [captureLabel, captureOptionsStack])
        captureRow.orientation = .horizontal
        captureRow.spacing = 16
        captureRow.alignment = .top
        captureRow.translatesAutoresizingMaskIntoConstraints = false
        
        captureOptionsStack.trailingAnchor.constraint(equalTo: captureRow.trailingAnchor).isActive = true

        let serviceCard = homeCard(title: "代理服务", titleInlineView: statusChip, titleAccessoryView: serviceSwitch, views: [captureRow])

        modeControl.items = ["直连/绕过代理", "全局代理", "规则判定"]
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
        trafficPeriodControl.heightAnchor.constraint(equalToConstant: 36).isActive = true

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
        syncProxyPreferenceControls()

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(serviceCard)
        container.addSubview(outboundCard)
        container.addSubview(nodeLatencyCard)
        container.addSubview(uploadCard)
        container.addSubview(downloadCard)
        container.addSubview(activeConnectionsCard)
        container.addSubview(trafficStatsCard)

        NSLayoutConstraint.activate([
            // --- Width Constraints ---
            uploadCard.widthAnchor.constraint(equalTo: serviceCard.widthAnchor, multiplier: 0.5, constant: -8),
            downloadCard.widthAnchor.constraint(equalTo: uploadCard.widthAnchor),
            
            // Span 2 cards width: 2 * size-1 width + 16 (gap)
            serviceCard.widthAnchor.constraint(equalTo: outboundCard.widthAnchor),
            nodeLatencyCard.widthAnchor.constraint(equalTo: outboundCard.widthAnchor),
            activeConnectionsCard.widthAnchor.constraint(equalTo: outboundCard.widthAnchor),
            trafficStatsCard.widthAnchor.constraint(equalTo: outboundCard.widthAnchor),
            
            // --- Height Constraints ---
            serviceCard.heightAnchor.constraint(equalToConstant: 180),
            outboundCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            nodeLatencyCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            uploadCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            downloadCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            activeConnectionsCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            trafficStatsCard.heightAnchor.constraint(equalTo: serviceCard.heightAnchor),
            
            // --- Row 1 Layout (top) ---
            serviceCard.topAnchor.constraint(equalTo: container.topAnchor),
            serviceCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            
            outboundCard.topAnchor.constraint(equalTo: container.topAnchor),
            outboundCard.leadingAnchor.constraint(equalTo: serviceCard.trailingAnchor, constant: 16),
            outboundCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            // --- Row 2 Layout (middle) ---
            nodeLatencyCard.topAnchor.constraint(equalTo: serviceCard.bottomAnchor, constant: 16),
            nodeLatencyCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            
            uploadCard.topAnchor.constraint(equalTo: serviceCard.bottomAnchor, constant: 16),
            uploadCard.leadingAnchor.constraint(equalTo: nodeLatencyCard.trailingAnchor, constant: 16),
            
            downloadCard.topAnchor.constraint(equalTo: serviceCard.bottomAnchor, constant: 16),
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
        let refreshMinutes = UserDefaults.standard.integer(forKey: "subscriptionRefreshMinutes")
        let effectiveMinutes = refreshMinutes > 0 ? refreshMinutes : 60
        let intervalText: String
        if refreshMinutes == 0 {
            intervalText = "已关闭"
        } else if effectiveMinutes < 60 {
            intervalText = "每 \(effectiveMinutes) 分钟"
        } else {
            intervalText = "每 \(effectiveMinutes / 60) 小时"
        }
        subscriptionAutoStatusLabel.stringValue = "订阅自动刷新：\(intervalText)；上次刷新 \(latestSubscription)"
        coreStatusLabel.stringValue = "sing-box Core：\(detectedCoreVersion)"
        logStatusLabel.stringValue = "日志：\(logs.string.components(separatedBy: .newlines).filter { !$0.isEmpty }.count) 行"
        tunRuntimeStatusLabel.stringValue = isTunEnabled
            ? (TunServiceManager.status(store: store).isUsable ? "TUN 服务：已安装，随代理开启" : "TUN 服务：不可用，请重新安装")
            : "TUN 权限：未启用"
    }

    func detailsTextConfig(_ label: NSTextField) {
        label.textColor = MD3.onSurfaceVariant
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
    }

    func homeCard(title: String, titleInlineView: NSView? = nil, titleAccessoryView: NSView? = nil, views: [NSView]) -> NSView {
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
        
        if let inline = titleInlineView {
            titleStack.addArrangedSubview(inline)
        }
        
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

    func getTodayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    func recordTraffic(upload: Int, download: Int) {
        let today = getTodayKey()
        var history = UserDefaults.standard.dictionary(forKey: "tungbox_traffic_history") as? [String: [String: Int]] ?? [:]
        var todayTraffic = history[today] ?? ["upload": 0, "download": 0]
        todayTraffic["upload"] = (todayTraffic["upload"] ?? 0) + upload
        todayTraffic["download"] = (todayTraffic["download"] ?? 0) + download
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
                    totalUp += dayData["upload"] ?? 0
                    totalDown += dayData["download"] ?? 0
                }
            }
        }
        return (totalUp, totalDown)
    }

    func updateTrafficLabels() {
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

    @objc func trafficPeriodChanged() {
        updateTrafficLabels()
    }

    func updateRunningStats() {
        guard isProxyRuntimeRunning(), let pid = currentProxyPID() else {
            stopStatsTimer()
            return
        }
        
        Task {
            let apiConnections = try? await ClashAPI.connections()
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
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                guard self.isProxyRuntimeRunning() else { return }
                
                if let apiConnections {
                    self.applyConnections(apiConnections, detail: "实时刷新")
                }
                
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
                
                if apiConnections == nil {
                    self.uploadValueLabel.stringValue = "—"
                    self.downloadValueLabel.stringValue = "—"
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
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
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

    @objc func switchToggled(_ sender: MD3Switch) {
        if sender.isOn {
            isSystemProxyEnabled = true
            syncProxyPreferenceControls()
            startService()
        } else {
            isSystemProxyEnabled = false
            syncProxyPreferenceControls()
            stopService()
        }
    }

    @objc func homeCaptureModeChanged(_ sender: MD3RadioButton) {
        setCaptureMode(tunEnabled: sender.tag == 1, source: "首页")
    }

    func configureCaptureRadio(_ radio: MD3RadioButton, tag: Int, action: Selector) {
        radio.tag = tag
        radio.target = self
        radio.action = action
    }

    func setCaptureMode(tunEnabled: Bool, source: String) {
        let previous = isTunEnabled
        guard previous != tunEnabled else {
            syncProxyPreferenceControls()
            return
        }
        if tunEnabled, !TunServiceManager.status(store: store).isUsable {
            syncProxyPreferenceControls()
            showToast("请先安装 TUN 服务")
            showError(NSError.user("TUN 服务不可用。请先到 设置 > TUN 设置 重新安装 TUN 服务。"))
            return
        }

        isTunEnabled = tunEnabled
        if tunEnabled {
            isSystemProxyEnabled = true
        }
        UserDefaults.standard.set(isTunEnabled, forKey: "tunEnabled")
        syncProxyPreferenceControls()
        do {
            if isProxyRuntimeRunning() {
                try applyTunPreference(restartIfRunning: false)
                reconcileSystemProxyForCurrentMode()
            } else if tunEnabled {
                try applyTunPreference(restartIfRunning: false)
                try TunServiceManager.enable(store: store, configText: editor.string)
                appendLog("[\(source)] 已启动 TUN 模式\n")
                appendLog("[TUN] 已交给 TUN 服务启动 sing-box\n")
                // Delay status refresh so daemon has time to pick up the flag
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.refreshStatus()
                }
            }
            appendLog("[\(source)] 接管方式已切换为 \(isTunEnabled ? "TUN 模式" : "系统代理")\n")
        } catch {
            isTunEnabled = previous
            UserDefaults.standard.set(isTunEnabled, forKey: "tunEnabled")
            syncProxyPreferenceControls()
            showError(error)
        }
        refreshStatus()
    }

    @objc func saveClicked() {
        do {
            try saveCurrent()
            appendLog("[TungBox] 已保存\n")
        } catch {
            showError(error)
        }
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
