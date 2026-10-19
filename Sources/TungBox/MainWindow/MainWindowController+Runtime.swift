import Darwin
import Foundation

/// Adapts controller-owned services and presentation to the runtime flow. The
/// coordinator never reads controls, defaults, files or processes directly.
extension MainWindowController {
    func reloadTunConfigInPlace(configText: String) async -> Bool {
        guard let request = runtimeCoordinator.state.request,
              runtimeCoordinator.isCurrent(request), isTunEnabled else { return false }
        nodeDelayTestID = UUID()
        let services = runtimeServices(for: request)
        let storeCopy = store
        let coordinator = runtimeCoordinator
        let success = await coordinator.reloadTun(source: configText, services: .init(
            discover: services.discoverTunNetwork, prepare: services.prepareTunConfig,
            write: { prepared in
                try TunServiceManager.writeRequestConfig(prepared, store: storeCopy)
                if !FileManager.default.fileExists(atPath: storeCopy.tunRequestFlagURL.path) {
                    FileManager.default.createFile(atPath: storeCopy.tunRequestFlagURL.path, contents: Data())
                }
                TunServiceManager.refreshRequestHeartbeat(store: storeCopy)
            }, tunEnabled: { [weak self] in self?.isTunEnabled == true }
        )) { self.handleRuntimeLifecycleEvent($0) }
        if success {
            coordinator.schedule(after: 3) { [weak self] in
                guard let self, self.isTunEnabled else { return }
                self.reconcileSelectorSelectionsToConfig()
            }
        }
        return success
    }

    @discardableResult
    func stopService(clearSystemProxySynchronously: Bool = false, isTerminating: Bool = false) -> Task<Void, Never> {
        let coordinator = runtimeCoordinator
        let plan = RuntimeCoordinator.ShutdownPlan(
            disableTun: wasTunActiveInThisSession || coordinator.state.hasRequestedTun,
            stopUserProxy: runner.isRunning || coordinator.state.hasRequestedProxy,
            clearSystemProxy: (wasProxyActiveInThisSession || coordinator.state.hasRequestedProxy)
                && (isSystemProxyEnabled || runner.isRunning || coordinator.state.hasRequestedProxy),
            synchronously: clearSystemProxySynchronously, isTerminating: isTerminating
        )
        let storeCopy = store
        let runnerRef = runner
        let manager = systemProxyManager
        let port = getMixedProxyPort()
        return coordinator.shutdown(plan, services: .init(
            cancelTasks: { [self] in
                nodeDelayTestID = UUID()
                selectorSelectionTask?.cancel()
                selectorSelectionID = UUID()
                modeChangeTask?.cancel()
                modeChangeID = UUID()
                tunCaptureIntentID = UUID()
                subscriptionTimer?.invalidate()
                ruleSetWatchTimer?.invalidate()
                stopStatsTimer()
                stopConnectionsRefreshTimer()
                stopTunRequestHeartbeat()
                // Keep saved preferences for the next launch; only the current
                // in-memory intent is off so late callbacks cannot restore TUN.
                isTunEnabled = false
                isSystemProxyEnabled = false
            },
            disableTun: { try TunServiceManager.disable(store: storeCopy) },
            waitForTunStop: { timeout in
                let success = TunServiceManager.waitUntilStopped(store: storeCopy, timeout: timeout)
                return .init(success: success, residue: success ? "" : (TunServiceManager.networkResidueDescription() ?? "未知残留"))
            },
            stopUserProxy: { runnerRef.stop() },
            clearSystemProxy: { manager.apply(enabled: false, port: port) }
        )) { [weak self] in self?.handleRuntimeLifecycleEvent($0) }
    }

    func handleRuntimeLifecycleEvent(_ event: RuntimeCoordinator.LifecycleEvent) {
        switch event {
        case .log(let text): appendLog(text)
        case .tunReloaded: startTunRequestHeartbeat()
        case .tunStopWarning: showToast("TUN 未确认回收，请重新安装 TUN 服务")
        case .shutdownFinished(let refresh):
            wasTunActiveInThisSession = false
            wasProxyActiveInThisSession = false
            clearFeatureTransitions()
            if refresh { refreshStatus() }
        }
    }

    func runtimeServices(for request: RuntimeCoordinator.Request) -> RuntimeCoordinator.Services {
        let coordinator = runtimeCoordinator
        let storeCopy = store
        let runnerRef = runner
        let input = request.input
        let log: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor [weak self] in self?.appendLog(text) }
        }
        return .init(
            tunStatus: { try await coordinator.performBlocking(for: request) { TunServiceManager.status(store: storeCopy) } },
            discoverTunNetwork: { [self] source in
                let hosts = tunUpstreamHosts(in: source)
                return try await coordinator.performBlocking(for: request) {
                    TUNRuntimeConfigBuilder.NetworkSnapshot(
                        physicalInterface: TunServiceManager.defaultNetworkInterface(),
                        resolvedAddressesByHost: self.resolvePublicIPv4Addresses(forHosts: hosts)
                    )
                }
            },
            prepareTunConfig: { [self] source, network in try preparedTunConfigText(from: source, networkSnapshot: network) },
            enableTun: { text in try await coordinator.performBlocking(for: request) { try TunServiceManager.enable(store: storeCopy, configText: text) } },
            disableTun: { try TunServiceManager.disable(store: storeCopy) },
            waitForTunStop: { _ = TunServiceManager.waitUntilStopped(store: storeCopy, timeout: 8) },
            verifyTunStartup: { [self] in verifyTunStartupAsync() },
            userProxyIsRunning: { runnerRef.isRunning },
            stopUserProxy: {
                try await coordinator.performBlocking(for: request) { if runnerRef.isRunning { runnerRef.stop() } }
            },
            startUserProxy: { [self] url in
                try await coordinator.performBlocking(for: request) {
                    try self.startNormalProxyBlocking(runner: runnerRef, config: url, port: input.mixedProxyPort, reason: input.reason, log: log)
                }
            },
            verifyUserAPI: { try await ClashAPI.verifyAuthentication(port: 9090) },
            applySystemProxy: { [self] enabled in
                try await coordinator.performBlocking(for: request) { self.applySystemProxyBlocking(enabled: enabled, port: input.mixedProxyPort) }
            },
            stopUserProxyAndClearSystemProxy: { [self] in
                try await coordinator.performBlocking(for: request) {
                    if runnerRef.isRunning { runnerRef.stop() }
                    self.applySystemProxyBlocking(enabled: false, port: input.mixedProxyPort)
                }
            },
            restoreSelectors: { [self] in
                await self.reconcileSelectorSelectionsToConfigAsync()
            },
            currentSwitches: { [self] in .init(systemProxyEnabled: isSystemProxyEnabled, tunEnabled: isTunEnabled) }
        )
    }

    func handleRuntimeEvent(_ event: RuntimeCoordinator.Event) {
        switch event {
        case .log(let text): appendLog(text)
        case .tunResumed: startTunRequestHeartbeat()
        case .tunStarted:
            startTunRequestHeartbeat()
            wasTunActiveInThisSession = true
        case .tunWillStop: stopTunRequestHeartbeat()
        case .tunStopped: wasTunActiveInThisSession = false
        case .tunFailed(let error):
            isTunEnabled = false
            UserDefaults.standard.set(false, forKey: "tunEnabled")
            tunTransition = .none
            syncProxyPreferenceControls()
            reportRuntimeFailure(error, operation: .tunStart)
        case .userProxyFailed:
            isSystemProxyEnabled = false
            UserDefaults.standard.set(false, forKey: "systemProxyEnabled")
            systemProxyTransition = .none
        case .reportStartupError(let error):
            syncProxyPreferenceControls()
            reportRuntimeFailure(error, operation: .systemProxyStart)
        case .userProxyClosing:
            systemProxyTransition = .none
            refreshStatus()
        case .shutdownFailed(let error):
            refreshStatus()
            reportRuntimeFailure(error, operation: .systemProxyStop)
        case .userProxyReady(let port): runDeferredNetworkChecksAfterConnection(proxyPort: port)
        case .finished(let refreshNodeDelays):
            refreshStatus()
            scheduleConnectionsRefreshAfterStart()
            if isSystemProxyEnabled || isTunEnabled {
                applyRuntimeMode(selectedMode().value, refreshNodeDelays: modeChangeNeedsDelayRefresh, onlyIfNeeded: true)
            }
            if refreshNodeDelays { testAllNodesClicked() }
        }
    }

    func reportRuntimeFailure(_ error: Error, operation: ErrorPresentation.RuntimeOperation, allowDialog: Bool = true) {
        let failure = ErrorPresentation.runtimeFailure(error, operation: operation, allowDialog: allowDialog)
        appendLog("[运行错误] \(failure.message)\n")
        RecentStatusTracker.shared.record(failure.message, level: .warning)
        if failure.presentsDialog {
            showError(NSError.user(failure.message))
        } else {
            showToast(failure.message, style: .warning)
        }
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
        // Legacy rule updates also restart Core outside runtime convergence.
        applyRuntimeMode(selectedMode().value, refreshNodeDelays: false, onlyIfNeeded: true)
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
    func ensureCoreAvailableForStart() -> Bool {
        guard runner.findSingBox() != nil else {
            checkSingBoxInstall(showAlert: false)
            showToast("未检测到 sing-box Core")
            showError(NSError.user("未检测到 sing-box Core。请先在 设置 > 基础 > Core 管理 中安装或导入 Core。"))
            return false
        }
        return true
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
    func applyRuntimeMode(_ mode: String, refreshNodeDelays: Bool, onlyIfNeeded: Bool = false) {
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
                    if onlyIfNeeded {
                        try await ClashAPI.reconcileMode(mode, port: port)
                    } else {
                        try await ClashAPI.setModeAndCloseConnections(mode, port: port)
                    }
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
                self.reportRuntimeFailure(error, operation: .modeSynchronization)
            }
        }
    }
    @discardableResult
    func stopServiceFromDelegate() -> Task<Void, Never> {
        stopService(clearSystemProxySynchronously: true, isTerminating: true)
    }

    nonisolated func runCommand(_ binary: String, args: [String], timeoutSeconds: TimeInterval = 3) -> String {
        SystemCommand.run(binary, args: args, timeoutSeconds: timeoutSeconds)
    }

    func isProxyRuntimeRunning() -> Bool {
        runner.isRunning || isTunRuntimeRunning()
    }

    /// 测速时应打的 sing-box ClashAPI 端口。
    /// 用户代理在跑用 9090；仅 TUN 守护在跑用 9091；否则返回 nil（走 sing-box URLTest）。
    func delayAPIPort() -> Int? {
        if runner.isRunning { return nil }           // nil → ClashAPI 默认 9090
        if isTunRuntimeRunning() { return TungBoxConfig.tunDaemonClashPort }
        return nil
    }

    func isProxyServiceActiveOrRequested() -> Bool {
        isProxyServiceTransitioning
            || runner.isRunning
            || isTunRuntimeRunning()
            || (isTunEnabled && (isSystemProxyEnabled || TunServiceManager.hasEnableRequest(store: store)))
    }

    func currentProxyPID() -> Int32? {
        if runner.isRunning {
            return runner.pid
        }
        if isTunRuntimeRunning() {
            return TunServiceManager.activeSingBoxPID(store: store, allowScan: false)
        }
        return nil
    }

    /// Re-assert each selector group's configured `default` selection via the clash
    /// API. sing-box's cache_file remembers the previously selected outbound and
    /// restores it on (re)start, which otherwise overrides the user's last explicit
    /// choice when sing-box is restarted (e.g. switching capture mode into TUN).
    func reconcileSelectorSelectionsToConfigAsync() async {
        guard let config = parseConfigObject(from: editor.string),
              let outbounds = config["outbounds"] as? [[String: Any]] else { return }
        var targets: [(group: String, node: String)] = []
        for outbound in outbounds {
            guard (outbound["type"] as? String)?.lowercased() == "selector",
                  let tag = outbound["tag"] as? String,
                  let def = (outbound["default"] as? String), !def.isEmpty else { continue }
            targets.append((tag, def))
        }
        guard !targets.isEmpty else { return }
        let apiPorts = activeSelectorAPIPorts()
        let selectionID = selectorSelectionID
        let transitionID = runtimeTransitionID
        for target in targets {
            for apiPort in apiPorts {
                guard selectionID == selectorSelectionID, transitionID == runtimeTransitionID else { return }
                try? await ClashAPI.selectProxy(group: target.group, node: target.node, port: apiPort)
            }
        }
    }

    func reconcileSelectorSelectionsToConfig() {
        Task { [weak self] in
            await self?.reconcileSelectorSelectionsToConfigAsync()
        }
    }
}
