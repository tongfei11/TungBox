import Foundation

/// Adapts controller-owned services and presentation to the runtime flow. The
/// coordinator never reads controls, defaults, files or processes directly.
extension MainWindowController {
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
