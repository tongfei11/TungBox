import AppKit
import Foundation

extension MainWindowController {
    
    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusButton(item.button)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.isVisible = true
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        rebuildTrayMenu(menu)
        refreshTrayRuntimeState(for: menu)
    }

    func rebuildTrayMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = isProxyServiceActiveOrRequested() ? "运行中" : "已关闭"
        menu.addItem(NSMenuItem(title: "\(TungBoxVersion.display) \(status)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let proxyService = NSMenuItem(title: "代理服务", action: #selector(toggleProxyServiceFromTray), keyEquivalent: "")
        proxyService.target = self
        proxyService.state = isProxyServiceActiveOrRequested() ? .on : .off
        menu.addItem(proxyService)

        let captureMenu = NSMenu()
        for (title, useTun) in [("系统代理", false), ("TUN 模式", true)] {
            let item = NSMenuItem(title: title, action: #selector(captureModeFromTray(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = useTun
            item.state = isTunEnabled == useTun ? .on : .off
            captureMenu.addItem(item)
        }
        let captureRoot = NSMenuItem(title: "接管方式", action: nil, keyEquivalent: "")
        captureRoot.submenu = captureMenu
        menu.addItem(captureRoot)

        menu.addItem(.separator())

        let modeMenu = NSMenu()
        for (title, mode) in [("直连/绕过代理", "Direct"), ("全局代理", "Global"), ("规则判定", "Rule")] {
            let item = NSMenuItem(title: title, action: #selector(modeFromTray(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            item.state = readMode(from: parseConfigObject(from: editor.string) ?? [:]).caseInsensitiveCompare(mode) == .orderedSame ? .on : .off
            modeMenu.addItem(item)
        }
        let modeRoot = NSMenuItem(title: "出站模式", action: nil, keyEquivalent: "")
        modeRoot.submenu = modeMenu
        menu.addItem(modeRoot)

        menu.addItem(.separator())

        menu.addItem(proxyGroupMenu(title: "代理", group: TungBoxConfig.tagManual))
        menu.addItem(proxyGroupMenu(title: "自动选择", group: TungBoxConfig.tagAuto))

        menu.addItem(.separator())
        
        let showConsole = NSMenuItem(title: "显示控制台", action: #selector(showConsoleFromTray), keyEquivalent: "")
        showConsole.target = self
        menu.addItem(showConsole)

        let openConfig = NSMenuItem(title: "打开配置目录", action: #selector(openFolderClicked), keyEquivalent: "")
        openConfig.target = self
        menu.addItem(openConfig)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quitFromTray), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func proxyGroupMenu(title: String, group: String) -> NSMenuItem {
        let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        let groupInfo = nodeGroups.first { $0.tag == group }
        let members = groupInfo?.members ?? []
        let isAuto = (group == TungBoxConfig.tagAuto)
        
        let testItem = NSMenuItem(title: "延迟测试", action: #selector(testAllNodesClicked), keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)
        menu.addItem(.separator())
        
        if members.isEmpty {
            menu.addItem(NSMenuItem(title: "暂无节点", action: nil, keyEquivalent: ""))
        } else {
            for node in members {
                let displayTitle = trayProxyNodeTitle(for: node)
                let item = NSMenuItem(title: displayTitle, action: isAuto ? nil : #selector(proxyNodeFromTray(_:)), keyEquivalent: "")
                if !isAuto {
                    item.target = self
                    item.representedObject = ["group": group, "node": node]
                } else {
                    item.isEnabled = false
                }
                item.state = groupInfo?.current == node ? .on : .off
                menu.addItem(item)
            }
        }
        root.submenu = menu
        return root
    }

    private func refreshTrayRuntimeState(for menu: NSMenu) {
        guard isProxyRuntimeRunning() else { return }
        Task { [weak self, weak menu] in
            guard let proxiesObj = try? await ClashAPI.proxies() else { return }
            await MainActor.run { [weak self, weak menu] in
                guard let self, let menu, menu === self.statusItem?.menu else { return }
                self.lastProxiesObj = proxiesObj
                self.syncNodeDelaysFromClashAPI(proxiesObj: proxiesObj)
                self.rebuildTrayMenu(menu)
            }
        }
    }

    private func trayProxyNodeTitle(for node: String) -> String {
        if let group = nodeGroups.first(where: { $0.tag == node }),
           ["urltest", "url-test", "fallback"].contains(group.type.lowercased()) {
            let resolved = resolveActiveOutboundForGroup(groupTag: group.tag, proxiesObj: lastProxiesObj)
            let resolvedNode = resolved.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !resolvedNode.isEmpty, resolvedNode != node {
                let delay = nodes.first(where: { $0.tag == resolvedNode })?.delay
                if let delay, !delay.isEmpty, delay != "未测试" {
                    return "\(node) - \(resolvedNode) (\(delay))"
                }
                return "\(node) - \(resolvedNode)"
            }
        }

        let delay = nodes.first(where: { $0.tag == node })?.delay ?? "未测试"
        return "\(node) (\(delay))"
    }

    func trayIcon() -> NSImage? {
        let name = isProxyServiceActiveOrRequested() ? "on" : "off"
        guard let url = AppResources.url(forResource: name, withExtension: "png", subdirectory: "Tray"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 20, height: 20)
        return image
    }

    func refreshTrayIcon() {
        configureStatusButton(statusItem?.button)
    }

    func configureStatusButton(_ button: NSStatusBarButton?) {
        guard let button else { return }
        if let image = trayIcon() {
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "TB"
        }
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = TungBoxVersion.display
    }

    @objc func toggleProxyServiceFromTray() {
        if !isProxyServiceActiveOrRequested() {
            isSystemProxyEnabled = true
            syncProxyPreferenceControls()
            startService()
            appendLog("[托盘] 启动代理服务\n")
        } else {
            isSystemProxyEnabled = false
            syncProxyPreferenceControls()
            stopService()
            appendLog("[托盘] 已关闭代理服务\n")
        }
        refreshStatus()
    }

    @objc func captureModeFromTray(_ sender: NSMenuItem) {
        guard let useTun = sender.representedObject as? Bool else { return }
        setCaptureMode(tunEnabled: useTun, source: "托盘")
    }

    @objc func showConsoleFromTray() {
        showConsoleWindow()
    }

    @objc func modeFromTray(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        syncModeControls(mode: mode)
        do {
            try applySelectedMode()
        } catch {
            refreshModeFromEditor()
            showError(error)
        }
    }

    @objc func proxyNodeFromTray(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let group = info["group"],
              let node = info["node"] else { return }
        selectNode(node, inGroup: group)
    }

    @objc func quitFromTray() {
        stopServiceFromDelegate()
        NSApp.terminate(nil)
    }
}
