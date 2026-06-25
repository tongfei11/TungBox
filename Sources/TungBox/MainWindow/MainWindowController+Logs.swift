import AppKit
import Foundation

extension MainWindowController {

    func makeLogsView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        let logTitle = NSTextField(labelWithString: "日志")
        logTitle.font = .systemFont(ofSize: 30, weight: .bold)
        logTitle.textColor = MD3.onSurface
        logTitle.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak logTitle] in
            logTitle?.textColor = MD3.onSurface
        }

        // Filter toolbar
        let searchField = MD3TextField()
        searchField.placeholderString = "搜索日志关键词..."
        searchField.target = self
        searchField.action = #selector(refreshLogDisplay)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.heightAnchor.constraint(equalToConstant: 32).isActive = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshLogDisplay),
            name: NSControl.textDidChangeNotification, object: searchField
        )

        let levels: [(String, String)] = [("INFO", "INFO"), ("WARN", "WARN"), ("ERROR", "ERROR"), ("DEBUG", "DEBUG")]
        var levelButtons: [MD3Checkbox] = []
        for (title, _) in levels {
            let btn = MD3Checkbox(checkboxWithTitle: title, target: self, action: #selector(refreshLogDisplay))
            btn.state = .on
            btn.translatesAutoresizingMaskIntoConstraints = false
            levelButtons.append(btn)
        }

        let clearButton = MD3Button()
        clearButton.title = "清空"
        clearButton.style = .outlined
        clearButton.target = self
        clearButton.action = #selector(clearLogsClicked)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        clearButton.widthAnchor.constraint(equalToConstant: 80).isActive = true

        let copyButton = MD3Button()
        copyButton.title = "复制"
        copyButton.style = .outlined
        copyButton.target = self
        copyButton.action = #selector(copyLogsClicked)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        copyButton.widthAnchor.constraint(equalToConstant: 80).isActive = true

        let levelStack = NSStackView(views: levelButtons)
        levelStack.orientation = .horizontal; levelStack.spacing = 4; levelStack.alignment = .centerY
        levelStack.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let toolbar = NSStackView(views: [searchField, levelStack, spacer, copyButton, clearButton])
        toolbar.orientation = .horizontal; toolbar.spacing = 12; toolbar.alignment = .centerY
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 200).isActive = true

        // Store level buttons for later querying
        logLevelButtons = levelButtons

        let logScroll = NSScrollView()
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        logScroll.hasVerticalScroller = true
        logScroll.applyThinOverlayScroller()
        logScroll.documentView = logs

        logs.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logs.isEditable = false
        logs.backgroundColor = .clear
        logs.textColor = MD3.onSurface
        registerThemeObserver { [weak self] in
            self?.logs.textColor = MD3.onSurface
        }

        let countLabel = logCountLabel
        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = MD3.onSurfaceVariant
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak countLabel] in
            countLabel?.textColor = MD3.onSurfaceVariant
        }

        let panel = MD3Panel()
        panel.type = .filled
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(logScroll)
        panel.addSubview(countLabel)

        view.addSubview(logTitle)
        view.addSubview(toolbar)
        view.addSubview(panel)

        NSLayoutConstraint.activate([
            logTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            logTitle.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),

            toolbar.leadingAnchor.constraint(equalTo: logTitle.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            toolbar.topAnchor.constraint(equalTo: logTitle.bottomAnchor, constant: 16),

            panel.leadingAnchor.constraint(equalTo: logTitle.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            panel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),

            logScroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            logScroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            logScroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            logScroll.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -8),

            countLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            countLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            countLabel.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8)
        ])

        return view
    }

    // MARK: - Log storage & filtering

    private func enabledLogLevels() -> Set<String> {
        guard let buttons = logLevelButtons else { return ["INFO", "WARN", "ERROR", "DEBUG"] }
        var levels = Set<String>()
        for btn in buttons {
            if btn.state == .on, let title = btn.title.components(separatedBy: " ").first {
                levels.insert(title)
            }
        }
        return levels.isEmpty ? ["INFO", "WARN", "ERROR", "DEBUG"] : levels
    }

    @objc func refreshLogDisplay() {
        let lines = logBuffer.components(separatedBy: .newlines)
        let levels = enabledLogLevels()
        let allLevelsOn = levels.count >= 4

        let filtered = lines.filter { line in
            let upper = line.uppercased()
            // Level match: if all levels on, skip level filter
            if !allLevelsOn {
                var matched = false
                for level in levels {
                    if upper.contains("[\(level)]") || upper.hasPrefix("\(level) ") || upper.contains(" \(level) ") {
                        matched = true; break
                    }
                }
                guard matched else { return false }
            }
            // Keyword match from search field
            let query = logSearchFieldText()
            guard query.isEmpty || upper.contains(query) else { return false }
            return true
        }

        logs.string = filtered.isEmpty ? "" : filtered.joined(separator: "\n")
        logCountLabel.stringValue = filtered.count == lines.count && allLevelsOn
            ? "共 \(lines.filter { !$0.isEmpty }.count) 条"
            : "显示 \(filtered.count) / \(lines.filter { !$0.isEmpty }.count) 条"
    }

    private func logSearchFieldText() -> String {
        // Find the first MD3TextField in the toolbar that isn't a level button
        // The search field is the first child of the toolbar stack
        guard let content = window?.contentView else { return "" }
        return findLogSearchText(in: content).lowercased()
    }

    private func findLogSearchText(in root: NSView) -> String {
        if let field = root as? NSTextField, field.placeholderString?.contains("搜索日志") == true {
            return field.stringValue
        }
        for sub in root.subviews {
            let result = findLogSearchText(in: sub)
            if !result.isEmpty { return result }
        }
        return ""
    }

    var logCountLabel: NSTextField {
        if let existing = logs.superview?.subviews.first(where: { $0.tag == 9902 }) as? NSTextField {
            return existing
        }
        let label = NSTextField(labelWithString: "")
        label.tag = 9902
        return label
    }

    // MARK: - Actions

    @objc func clearLogsClicked() {
        logBuffer = ""
        logLineCount = 0
        logs.string = ""
        logCountLabel.stringValue = "显示 0 条"
        refreshHomeFeatureStatus()
        showToast("日志已清空", style: .info)
    }

    @objc func copyLogsClicked() {
        let text = logs.string
        guard !text.isEmpty else {
            showToast("日志为空", style: .warning)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast("日志已复制到剪贴板（\(text.components(separatedBy: .newlines).filter { !$0.isEmpty }.count) 行）", style: .success)
    }

    func appendLog(_ text: String) {
        logBuffer += text
        logLineCount += text.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
        logStatusLabel.stringValue = "日志：\(logLineCount) 行"
        appendPersistentLog(text)
        scheduleLogRefresh()
    }

    func appendPersistentLog(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: store.appLogURL.path) {
            FileManager.default.createFile(atPath: store.appLogURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: store.appLogURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        handle.write(data)
    }
}
