import AppKit
import Foundation

/// Core 管理页面、更新检查、安装与本地导入。
extension MainWindowController {
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
                        ? "Core 已更新至 \(release.version)，当前代理保持运行"
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

    @MainActor
    func downgradeCoreForCompatibility() async {
        let oldVersion = "1.11.10"
        serviceLabel.stringValue = "sing-box Core：正在安装兼容版本 \(oldVersion)..."
        appendLog("[Core] 订阅兼容性要求降级 Core 至 \(oldVersion)\n")
        do {
            let release = try await CoreUpdater.release(version: oldVersion)
            installCoreRelease(release, reason: "兼容旧订阅")
        } catch {
            serviceLabel.stringValue = "sing-box Core：安装 \(oldVersion) 失败\n\(error.localizedDescription)"
            showError(error)
        }
    }
}
