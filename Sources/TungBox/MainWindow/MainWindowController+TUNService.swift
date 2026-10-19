import AppKit
import Foundation

/// TUN 服务设置，以及启动、唤醒和心跳的控制器回调。
extension MainWindowController {
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
        var cards: [NSView] = [
            settingsPanel(title: "服务管理", views: [
                tunServiceStatusLabel,
                tunButtonGrid,
                tunServiceLogLabel,
                hint
            ])
        ]
        cards.append(contentsOf: makeTunConfigPanels())
        return settingsPageStack(cards)
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
                    self.reconcileRuntime(reason: "重装后恢复 TUN")
                }
                self.checkSingBoxInstall(showAlert: false)
                self.syncProxyPreferenceControls()
            }
        )
    }

    @objc func reloadTunServiceClicked() {
        if isTunEnabled {
            reconcileRuntime(reason: "重载 TUN")
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

    @objc func openTunLogClicked() {
        if FileManager.default.fileExists(atPath: TunServiceManager.logURL.path) {
            NSWorkspace.shared.open(TunServiceManager.logURL)
        } else {
            showToast("暂无 TUN 日志")
        }
    }

    /// 监听系统唤醒：睡醒后 TUN 守护进程的 DNS 缓存 / UDP NAT 会话 / utun 路由可能失效，
    /// 但 sing-box 没有 wake-poke 机制，浏览器再访问也激不活 UDP 通道。表现就是
    /// "TUN 开关亮着但全网无响应，得手动切一下系统代理才恢复"——切代理顺带
    /// 触发了 reconcileRuntime → enableTunServiceSafely，把守护进程的配置重新下发
    /// 一遍，UDP/DNS 链路才重建。这里就把"切一下"自动化：只在 TUN 在跑时动它，
    /// 用户代理依赖 inbound 触发，会自愈，不碰。
    func registerSystemWakeObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // 网络接口（en*）的 IP / 默认路由 / DNS resolver 在 didWake 那一刻
            // 可能还没回来，立刻 reconcile 会建在错的接口上。等 2s 再动手。
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.runtimeCoordinator.schedule(after: 2) { [weak self] in
                    guard let self, self.isTunEnabled else { return }
                    self.appendLog("[TungBox] 系统已唤醒，自动重新下发 TUN 配置以恢复守护进程\n")
                    self.reconcileRuntime(reason: "唤醒", forceRestart: false)
                }
            }
        }
    }

    func isTunRuntimeRunning() -> Bool {
        // Non-blocking (cache/pidfile only) — called from refreshStatus on the main
        // thread, so it must never trigger the ~2s `ps` scan or the UI freezes.
        isTunEnabled && TunServiceManager.activeSingBoxPID(store: store, allowScan: false) != nil
    }

    func enableTunServiceSafely(configText: String) throws {
        try ensureTunRouteIsSafeToStart()
        let preparedConfig = try preparedTunConfigText(from: configText)
        // Note: the OS system-proxy setting is managed independently by
        // reconcileRuntime() now (system proxy and TUN can be enabled together), so
        // enabling TUN must not force the system proxy off here.

        try TunServiceManager.enable(store: store, configText: preparedConfig)
        startTunRequestHeartbeat()
        wasTunActiveInThisSession = true
        verifyTunStartupAsync()
    }

    /// After requesting TUN, confirm in the background that sing-box actually came
    /// up (process alive + utun29 carrying its address). The root daemon validates
    /// the config with `sing-box check`, which passes for some configs that then
    /// FATAL at `run` (e.g. the dns-detour case) — leaving the UI showing "on"
    /// while nothing works. If the TUN does not come online in time, surface the
    /// last error from the daemon log instead of failing silently. Runs entirely
    /// off the main thread, so it adds no switch latency.
    @discardableResult
    func verifyTunStartupAsync() -> Task<Bool, Never> {
        let store = self.store
        let transitionID = runtimeTransitionID
        return Task.detached { [weak self] in
            let deadline = Date().addingTimeInterval(8)
            var online = false
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let stillWanted = await MainActor.run { [weak self] in
                    guard let self else { return false }
                    return self.isTunEnabled && self.runtimeTransitionID == transitionID
                }
                guard stillWanted else { return false }
                if TunServiceManager.activeSingBoxPID(store: store, allowScan: false) != nil,
                   TunServiceManager.tunInterfaceIsActive() {
                    online = true
                    break
                }
            }
            if online {
                do {
                    try await ClashAPI.verifyAuthentication(port: TungBoxConfig.tunDaemonClashPort)
                } catch {
                    let stillWanted = await MainActor.run { [weak self] in
                        guard let self else { return false }
                        return self.isTunEnabled && self.runtimeTransitionID == transitionID
                    }
                    guard stillWanted else { return false }
                    await MainActor.run { [weak self] in
                        guard let self, self.isTunEnabled, self.runtimeTransitionID == transitionID else { return }
                        self.stopTunRequestHeartbeat()
                        try? TunServiceManager.disable(store: self.store)
                        self.isTunEnabled = false
                        UserDefaults.standard.set(false, forKey: "tunEnabled")
                        self.wasTunActiveInThisSession = false
                        self.tunTransition = .none
                        self.syncProxyPreferenceControls()
                        self.refreshStatus()
                        self.reportRuntimeFailure(error, operation: .tunControlVerification, allowDialog: false)
                    }
                    return false
                }
                // sing-box restores the last selector selection from cache.db,
                // which can override the config's `default` (e.g. a manual node
                // reverting to auto after switching into TUN). Re-assert the
                // config's selection via the clash API so manual stays manual and
                // auto stays auto.
                return await MainActor.run { [weak self] in
                    guard let self, self.isTunEnabled, self.runtimeTransitionID == transitionID else { return false }
                    RecentStatusTracker.shared.record("TUN 模式已开启", level: .success)
                    self.reconcileSelectorSelectionsToConfig()
                    self.runDeferredNetworkChecksAfterConnection(proxyPort: nil)
                    return true
                }
            }
            let stillWanted = await MainActor.run { [weak self] in
                guard let self else { return false }
                return self.isTunEnabled && self.runtimeTransitionID == transitionID
            }
            guard stillWanted else { return false }
            let recentError = TunServiceManager.lastDaemonErrorLine()
            await MainActor.run { [weak self] in
                guard let self, self.isTunEnabled, self.runtimeTransitionID == transitionID else { return }
                if let recentError {
                    self.appendLog("[TUN] 守护进程最近错误（可能与本次启动无关）：\(recentError)\n")
                }
                self.stopTunRequestHeartbeat()
                try? TunServiceManager.disable(store: self.store)
                self.isTunEnabled = false
                UserDefaults.standard.set(false, forKey: "tunEnabled")
                self.wasTunActiveInThisSession = false
                self.tunTransition = .none
                self.syncProxyPreferenceControls()
                self.refreshStatus()
                self.reportRuntimeFailure(
                    NSError.user("等待 8 秒后仍未检测到 Core 进程及 TUN 网卡就绪，已停止本次启动。请查看 TUN 日志。"),
                    operation: .tunStart, allowDialog: false
                )
            }
            return false
        }
    }

    func startTunRequestHeartbeat() {
        TunServiceManager.refreshRequestHeartbeat(store: store)
        tunRequestHeartbeatTimer?.invalidate()
        tunRequestHeartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch TunServiceManager.heartbeatAction(isTunEnabled: self.isTunEnabled, store: self.store) {
                case .refresh:
                    TunServiceManager.refreshRequestHeartbeat(store: self.store)
                case .recover:
                    self.appendLog("[TUN] 请求文件意外丢失，正在恢复 TUN\n")
                    self.stopTunRequestHeartbeat()
                    self.reconcileRuntime(reason: "恢复 TUN 请求")
                case .stop:
                    self.stopTunRequestHeartbeat()
                }
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
            tunServiceToggleButton.title = "更新 TUN 服务"
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
}
