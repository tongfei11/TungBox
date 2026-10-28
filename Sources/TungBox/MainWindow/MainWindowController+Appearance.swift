import AppKit
import Foundation

/// 外观页面、配色方案、深浅色主题与状态栏图标样式。
extension MainWindowController {
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

    @objc func trayIconStyleChanged(_ sender: MD3PopUpButton) {
        let index = max(0, min(sender.indexOfSelectedItem, TrayIconStyle.speedOnly.rawValue))
        let style = TrayIconStyle(rawValue: index) ?? .iconOnly
        UserDefaults.standard.set(style.rawValue, forKey: TrayIconStyle.defaultsKey)
        refreshTrayIcon()
        appendLog("[设置] 状态栏图标样式已设为 \(style.title)\n")
    }

    func changeColorScheme(to index: Int) {
        MD3.currentSchemeIndex = index
        for row in colorSchemeRows {
            row.isSelected = (row.index == index)
        }
        notifyThemeChanged()
        appendLog("[TungBox] 已切换配色方案为: \(MD3.colorSchemes[index].name)\n")
    }

    @objc func toggleThemeClicked() {
        MD3.isDark.toggle()
        UserDefaults.standard.set(MD3.isDark, forKey: "appearanceIsDark")
        NSApp.appearance = NSAppearance(named: MD3.isDark ? .darkAqua : .aqua)
        notifyThemeChanged()
        appendLog("[TungBox] 已切换到\(MD3.isDark ? "深色" : "浅色")外观\n")
        showToast("已切换到\(MD3.isDark ? "深色" : "浅色")外观", style: .info)
    }
}
