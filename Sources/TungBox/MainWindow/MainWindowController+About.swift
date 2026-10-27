import AppKit
import Foundation

enum SettingsPageNavigation {
    static let titles = ["常规", "Core", "TUN 设置", "DNS", "规则集", "外观", "关于"]
    static let width: CGFloat = 560
}

enum TungBoxLinks {
    static let project = URL(string: "https://github.com/tongfei11/TungBox")!
    static let feedback = URL(string: "https://github.com/tongfei11/TungBox/issues/new")!
}

extension MainWindowController {
    func makeSettingsAboutPage() -> NSView {
        let version = settingsLabel("软件版本：\(TungBoxVersion.current)")
        aboutCoreVersionLabel.stringValue = "sing-box Core：\(detectedCoreVersion)"
        aboutCoreVersionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        aboutCoreVersionLabel.textColor = MD3.onSurfaceVariant
        aboutCoreVersionLabel.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak self] in
            self?.aboutCoreVersionLabel.textColor = MD3.onSurfaceVariant
        }
        let repository = settingsLabel("GitHub：\(TungBoxLinks.project.absoluteString)")
        repository.isSelectable = true
        let configDirectory = settingsLabel("配置目录：\(store.baseURL.path)")
        configDirectory.isSelectable = true
        configDirectory.lineBreakMode = .byTruncatingMiddle
        let clashAPI = settingsLabel("Clash API：\(TungBoxConfig.clashAPIListen)")

        let buttons = settingsButtonGrid([
            settingsButton(title: "打开 GitHub 项目", action: #selector(openTungBoxProject), style: .outlined),
            settingsButton(title: "提交反馈", action: #selector(openTungBoxFeedback), style: .filled),
            settingsButton(title: "查看版本发布", action: #selector(openTungBoxReleases), style: .outlined),
            settingsButton(title: "打开配置目录", action: #selector(openFolderClicked), style: .outlined)
        ])

        return settingsPageStack([
            settingsPanel(title: "软件信息", views: [version, aboutCoreVersionLabel, configDirectory, clashAPI]),
            settingsPanel(title: "项目与反馈", views: [repository, buttons])
        ])
    }

    @objc private func openTungBoxProject() { NSWorkspace.shared.open(TungBoxLinks.project) }
    @objc private func openTungBoxFeedback() { NSWorkspace.shared.open(TungBoxLinks.feedback) }
    @objc private func openTungBoxReleases() { NSWorkspace.shared.open(AppUpdater.latestReleaseURL) }
}
