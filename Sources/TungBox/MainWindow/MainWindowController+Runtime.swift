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
            showError(error)
        case .userProxyFailed:
            isSystemProxyEnabled = false
            UserDefaults.standard.set(false, forKey: "systemProxyEnabled")
            systemProxyTransition = .none
        case .reportStartupError(let error):
            syncProxyPreferenceControls()
            showError(error)
        case .userProxyClosing:
            systemProxyTransition = .none
            refreshStatus()
        case .shutdownFailed(let error):
            refreshStatus()
            showError(error)
        case .userProxyReady(let port): runDeferredNetworkChecksAfterConnection(proxyPort: port)
        case .restoreSelectors: reconcileSelectorSelectionsToConfig()
        case .finished(let refreshNodeDelays):
            refreshStatus()
            scheduleConnectionsRefreshAfterStart()
            if refreshNodeDelays { testAllNodesClicked() }
        }
    }
}
