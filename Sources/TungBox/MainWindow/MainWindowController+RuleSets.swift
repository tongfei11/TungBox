import AppKit
import Foundation

extension MainWindowController {

    /// Built-in "主流 AI" preset filled into the rules text on demand.
    static let aiPresetRules = """
    DOMAIN-SUFFIX, openai.com
    DOMAIN-SUFFIX, chatgpt.com
    DOMAIN-SUFFIX, oaistatic.com
    DOMAIN-SUFFIX, oaiusercontent.com
    DOMAIN-SUFFIX, anthropic.com
    DOMAIN-SUFFIX, claude.ai
    DOMAIN-SUFFIX, gemini.google.com
    DOMAIN-SUFFIX, generativelanguage.googleapis.com
    DOMAIN-SUFFIX, ai.google.dev
    DOMAIN-SUFFIX, x.ai
    DOMAIN-SUFFIX, grok.com
    DOMAIN-SUFFIX, perplexity.ai
    DOMAIN-SUFFIX, poe.com
    DOMAIN-SUFFIX, copilot.microsoft.com
    """

    // MARK: - Loading

    func loadRuleSetsForCurrentSubscription() {
        guard let sub = currentSubscription() else {
            customRuleSets = []
            invalidRuleSets = []
            return
        }
        let result = store.loadRuleSets(for: sub.id)
        customRuleSets = result.valid
        invalidRuleSets = result.invalid
    }

    func ruleSetsForCurrentSubscription() -> [CustomRuleSet] {
        customRuleSets.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
    }

    // MARK: - Config regeneration

    func ruleSetReferenceError(_ set: CustomRuleSet, config: [String: Any]) -> String? {
        if let error = RuleRouting.referenceError(type: "LAN", value: "", strategy: set.outbound, config: config) { return error }
        return set.rules.compactMap { RuleRouting.referenceError(type: $0.type, value: $0.value, strategy: set.outbound, config: config) }.first
    }

    func checkRuleSetConfig(_ text: String) throws {
        let url = store.baseURL.appendingPathComponent("rules-check-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appendingPathComponent("run_" + url.lastPathComponent))
        }
        try Data(text.utf8).write(to: url, options: .atomic)
        _ = try runner.check(config: url)
    }

    /// Import configurations created before the independent rule-source file was
    /// introduced. The current editor is the only available baseline; remove the
    /// known generated rule-set entries and persist the resulting snapshot once.
    private func ensureRuleBase(for subscription: Subscription) throws {
        do {
            _ = try store.baseRouteRules(for: subscription.id)
            return
        } catch { }
        guard var config = parseConfigObject(from: editor.string) else {
            throw NSError.user("当前配置不是有效 JSON，无法迁移旧规则")
        }
        var route = config["route"] as? [String: Any] ?? [:]
        var routeRules = route["rules"] as? [[String: Any]] ?? []
        for set in store.loadRuleSets(for: subscription.id).valid {
            let generated = set.rules.map { RuleRouting.customRouteRule(type: $0.type, value: $0.value, strategy: set.outbound) }
            routeRules.removeAll { existing in generated.contains { NSDictionary(dictionary: $0).isEqual(to: existing) } }
        }
        route["rules"] = routeRules
        config["route"] = route
        let baseline = try renderConfig(config)
        try store.saveRuleBase(baseline, for: subscription.id)
        appendLog("[规则集] 已将旧配置迁移为独立规则来源\n")
    }

    /// File operations and core validation share a rollback boundary. A failed write
    /// or check never becomes a successful UI operation.
    private func changeRuleSetFile(at file: URL, mutation: () throws -> Void) throws {
        guard !isApplyingRuleSets else { throw NSError.user("规则正在应用，请稍后重试") }
        guard let sub = currentSubscription(), let index = selectedIndex,
              profiles.indices.contains(index), sub.profileID == profiles[index].id else {
            throw NSError.user("请先选择该订阅的配置")
        }
        try ensureRuleBase(for: sub)
        let oldFile = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
        let oldEditor = editor.string
        let configURL = store.configURL(for: profiles[index])
        let oldConfig = try Data(contentsOf: configURL)
        let projectionURL = store.ruleProjectionURL(for: sub.id)
        let oldProjection = FileManager.default.fileExists(atPath: projectionURL.path) ? try Data(contentsOf: projectionURL) : nil
        do {
            try mutation()
            let candidate = try renderConfig(try applyCustomRules(to: oldEditor, subscriptionID: sub.id))
            try checkRuleSetConfig(candidate)
            editor.string = candidate
            _ = try saveCurrent()
            try applyRuleSetRuntime(candidate, previous: oldConfig, configURL: configURL)
            ruleSetFileSignature = try? ruleSetFiles(for: sub.id)
        } catch {
            editor.string = oldEditor
            do {
                if let oldFile { try oldFile.write(to: file, options: .atomic) }
                else if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                try oldConfig.write(to: configURL, options: .atomic)
                if let oldProjection { try oldProjection.write(to: projectionURL, options: .atomic) }
                else if FileManager.default.fileExists(atPath: projectionURL.path) { try FileManager.default.removeItem(at: projectionURL) }
                pendingRuleProjection = nil
            } catch let restoreError {
                throw NSError.user("操作失败：\(error.localizedDescription)；恢复文件失败：\(restoreError.localizedDescription)")
            }
            loadRuleSetsForCurrentSubscription()
            throw error
        }
        refreshRulesFromEditor()
        showToast(ruleSetApplyStatus)
    }

    private func applyRuleSetRuntime(_ text: String, previous: Data, configURL: URL) throws {
        if isTunEnabled && TunServiceManager.activeSingBoxPID(store: store) != nil {
            let prepared = try preparedTunConfigText(from: text)
            let oldRequest = try Data(contentsOf: store.tunRequestConfigURL)
            let oldPID = TunServiceManager.activeSingBoxPID(store: store)
            try Data(prepared.utf8).write(to: store.tunRequestConfigURL, options: .atomic)
            TunServiceManager.refreshRequestHeartbeat(store: store)
            isApplyingRuleSets = true
            ruleSetApplyStatus = "已保存，正在应用"
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.isApplyingRuleSets = false; self.refreshRulesFromEditor() }
                for _ in 0..<30 {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard self.isTunEnabled else {
                        self.ruleSetApplyStatus = "已保存，待启动应用"
                        return
                    }
                    if let latest = try? Data(contentsOf: self.store.tunRequestConfigURL), latest != Data(prepared.utf8) {
                        self.ruleSetApplyStatus = "应用请求已被新的配置替换"
                        return
                    }
                    if let pid = TunServiceManager.activeSingBoxPID(store: self.store), pid != oldPID,
                       TunServiceManager.tunInterfaceIsActive() {
                        try? await Task.sleep(for: .seconds(1))
                        if self.isTunEnabled, TunServiceManager.activeSingBoxPID(store: self.store) == pid,
                           TunServiceManager.tunInterfaceIsActive() {
                            self.ruleSetApplyStatus = "已生效"
                            return
                        }
                    }
                }
                do {
                    guard self.isTunEnabled else { return }
                    try oldRequest.write(to: self.store.tunRequestConfigURL, options: .atomic)
                    try Data().write(to: self.store.tunRequestFlagURL, options: .atomic)
                    self.startTunRequestHeartbeat()
                    TunServiceManager.refreshRequestHeartbeat(store: self.store)
                    self.ruleSetApplyStatus = "已保存，应用失败；已请求恢复旧配置"
                } catch {
                    self.ruleSetApplyStatus = "应用失败，恢复失败：\(error.localizedDescription)"
                }
                self.showError(NSError.user(self.ruleSetApplyStatus))
            }
        } else if runner.isRunning {
            let runningSnapshot = runner.runningConfigData ?? previous
            runner.stop()
            do {
                try startNormalProxy(config: configURL, port: getMixedProxyPort(), reason: "规则更新")
                ruleSetApplyStatus = "已生效（现有连接已重建）"
            } catch {
                let applyError = error
                runner.stop()
                do {
                    try runningSnapshot.write(to: configURL, options: .atomic)
                    try startNormalProxy(config: configURL, port: getMixedProxyPort(), reason: "规则应用失败后恢复")
                } catch {
                    ruleSetApplyStatus = "应用及恢复失败"
                    throw NSError.user("规则应用失败：\(applyError.localizedDescription)；恢复失败：\(error.localizedDescription)")
                }
                ruleSetApplyStatus = "应用失败，已恢复旧配置"
                throw applyError
            }
        } else { ruleSetApplyStatus = "已保存，待启动应用" }
    }

    private func ruleSetFiles(for id: UUID) throws -> [String: Data] {
        let folder = store.ruleSetsFolder(for: id)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [:] }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return try Dictionary(uniqueKeysWithValues: files.filter { $0.pathExtension == "yml" }.map { ($0.path, try Data(contentsOf: $0)) })
    }

    func startRuleSetWatching() {
        guard ruleSetWatchTimer == nil else { return }
        ruleSetWatchTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshExternalRuleSetChanges() }
        }
    }

    func refreshExternalRuleSetChanges() {
        guard !isApplyingRuleSets, let sub = currentSubscription(), let index = selectedIndex,
              profiles.indices.contains(index), sub.profileID == profiles[index].id else { return }
        do {
            let files = try ruleSetFiles(for: sub.id)
            if ruleSetWatchSubscriptionID != sub.id {
                ruleSetWatchSubscriptionID = sub.id
                ruleSetFileSignature = nil
            }
            guard files != ruleSetFileSignature else { return }
            // Do not overwrite an open dialog or unsaved config edits.
            guard ruleSetRulesTextView?.window?.isVisible != true else { return }
            let url = store.configURL(for: profiles[index])
            let saved = try Data(contentsOf: url)
            let projectionURL = store.ruleProjectionURL(for: sub.id)
            let projection = FileManager.default.fileExists(atPath: projectionURL.path) ? try Data(contentsOf: projectionURL) : nil
            guard Data(editor.string.utf8) == saved else {
                ruleSetApplyStatus = "文件已变化，请先保存配置编辑内容"
                return
            }
            let candidate = try renderConfig(try applyCustomRules(to: editor.string, subscriptionID: sub.id))
            if candidate != editor.string {
                try checkRuleSetConfig(candidate)
                editor.string = candidate
                do {
                    _ = try saveCurrent()
                    try applyRuleSetRuntime(candidate, previous: saved, configURL: url)
                } catch {
                    editor.string = String(decoding: saved, as: UTF8.self)
                    try saved.write(to: url, options: .atomic)
                    if let projection { try projection.write(to: projectionURL, options: .atomic) }
                    pendingRuleProjection = nil
                    throw error
                }
            }
            ruleSetFileSignature = files
            refreshRulesFromEditor()
        } catch {
            // Report once per revision instead of continuously attempting a bad update.
            ruleSetFileSignature = try? ruleSetFiles(for: sub.id)
            ruleSetApplyStatus = "未应用：\(error.localizedDescription)"
            appendLog("[规则集] \(ruleSetApplyStatus)\n")
            refreshRulesFromEditor()
        }
    }

    // MARK: - Actions

    @objc func showAddRuleSetDialog() {
        editingRuleSetID = nil
        presentRuleSetDialog(existing: nil)
    }

    func editRuleSet(_ set: CustomRuleSet) {
        editingRuleSetID = set.id
        presentRuleSetDialog(existing: set)
    }

    func deleteRuleSet(_ set: CustomRuleSet) {
        do {
            try changeRuleSetFile(at: store.ruleSetFileURL(for: set)) { try store.deleteRuleSet(set) }
            appendLog("[规则集] 已删除「\(set.name)」\n")
        } catch { showError(error) }
    }

    func setRuleSetEnabled(_ set: CustomRuleSet, to enabled: Bool) {
        var updated = set
        updated.enabled = enabled
        do {
            if enabled, let config = parseConfigObject(from: editor.string), let error = ruleSetReferenceError(updated, config: config) {
                throw NSError.user(error)
            }
            try changeRuleSetFile(at: store.ruleSetFileURL(for: set)) { try store.saveRuleSet(updated) }
        } catch { showError(error) }
    }

    func deleteInvalidRuleSet(_ invalid: InvalidRuleSet) {
        do {
            try changeRuleSetFile(at: invalid.fileURL) { try store.deleteRuleSetFile(at: invalid.fileURL) }
            showToast("已删除无效规则集文件")
        } catch { showError(error) }
    }

    @objc func openRuleSetWiki() {
        if let url = URL(string: TungBoxConfig.customRuleSetWikiURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Append the built-in AI preset to the open rule-set dialog's rules editor, de-duped.
    @objc func fillAIPresetClicked() {
        guard let textView = ruleSetRulesTextView else { return }
        var seen = Set(textView.string.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) })
        var lines: [String] = textView.string.isEmpty ? [] : [textView.string]
        for line in MainWindowController.aiPresetRules.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, !seen.contains(t) {
                lines.append(t)
                seen.insert(t)
            }
        }
        textView.string = lines.joined(separator: "\n")
    }

    // MARK: - Dialog

    private func fillRuleSetOutboundPopup(_ popup: MD3PopUpButton, selected: String?) {
        popup.removeAllItems()
        popup.addItems(withTitles: ["DIRECT", "REJECT"])
        popup.menu?.addItem(NSMenuItem.separator())
        popup.addItems(withTitles: ["Proxy", "AUTO"])
        let nodeTags = nodes.map(\.tag).filter { !$0.isEmpty }
        if !nodeTags.isEmpty {
            popup.menu?.addItem(NSMenuItem.separator())
            popup.addItems(withTitles: nodeTags)
        }
        if let selected, popup.itemArray.contains(where: { $0.title == selected }) {
            popup.selectItem(withTitle: selected)
        } else if let selected {
            popup.addItem(withTitle: selected)
            popup.selectItem(withTitle: selected)
        } else {
            popup.selectItem(withTitle: "Proxy")
        }
    }

    private func presentRuleSetDialog(existing: CustomRuleSet?) {
        let isEditing = existing != nil

        let nameField = MD3TextField()
        nameField.stringValue = existing?.name ?? ""
        nameField.placeholderString = "如 AI"
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let outboundPopup = MD3PopUpButton()
        outboundPopup.translatesAutoresizingMaskIntoConstraints = false
        outboundPopup.heightAnchor.constraint(equalToConstant: 36).isActive = true
        fillRuleSetOutboundPopup(outboundPopup, selected: existing?.outbound)

        // Multi-line rules editor.
        let textView = NSTextView()
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = existing.map { RuleSetFormat.rulesText(for: $0.rules) } ?? ""
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = textView
        scroll.heightAnchor.constraint(equalToConstant: 170).isActive = true

        ruleSetRulesTextView = textView

        let presetButton = MD3Button()
        presetButton.title = "填入「主流 AI」预设"
        presetButton.style = .outlined
        presetButton.target = self
        presetButton.action = #selector(fillAIPresetClicked)
        presetButton.translatesAutoresizingMaskIntoConstraints = false
        presetButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let wikiButton = MD3Button()
        wikiButton.title = "规则格式说明 →"
        wikiButton.style = .text
        wikiButton.target = self
        wikiButton.action = #selector(openRuleSetWiki)
        wikiButton.translatesAutoresizingMaskIntoConstraints = false

        let helperRow = NSStackView(views: [presetButton, wikiButton])
        helperRow.orientation = .horizontal
        helperRow.spacing = 12
        helperRow.alignment = .centerY
        helperRow.translatesAutoresizingMaskIntoConstraints = false

        func section(_ title: String) -> NSTextField {
            let l = NSTextField(labelWithString: title)
            l.font = .systemFont(ofSize: 13, weight: .bold)
            l.textColor = MD3.primary
            l.translatesAutoresizingMaskIntoConstraints = false
            registerThemeObserver { [weak l] in l?.textColor = MD3.primary }
            return l
        }

        let stack = NSStackView(views: [
            section("名称"), nameField,
            section("出站规则"), outboundPopup,
            section("规则清单"),
            NSTextField(labelWithString: "每行一条：TYPE, VALUE，例如  DOMAIN-SUFFIX, openai.com"),
            scroll,
            helperRow
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 460),
            nameField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            outboundPopup.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        let dialog = showMD3Dialog(
            title: isEditing ? "编辑规则集" : "新建规则集",
            message: isEditing ? "修改后点击保存即可更新。" : "把一批域名 / IP 统一指向一个出站，按订阅单独保存。",
            customView: container,
            confirmTitle: isEditing ? "保存" : "添加"
        )
        dialog.window?.initialFirstResponder = nameField

        dialog.onConfirm = { [weak self, weak dialog, weak nameField, weak outboundPopup, weak textView] in
            guard let self else { return }
            let ok = self.saveRuleSetFromDialog(
                name: nameField?.stringValue ?? "",
                outbound: outboundPopup?.titleOfSelectedItem ?? "Proxy",
                rulesText: textView?.string ?? "",
                editing: existing
            )
            if ok { dialog?.dismiss() }
        }
        dialog.onCancel = { [weak dialog] in dialog?.dismiss() }
    }

    /// Returns true on success (dialog should close), false if validation failed
    /// (dialog stays open so the user keeps their input).
    private func saveRuleSetFromDialog(name: String, outbound: String, rulesText: String, editing: CustomRuleSet?) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            showError(NSError.user("请填写规则集名称"))
            return false
        }
        guard let sub = currentSubscription() else {
            showError(NSError.user("请先选择一个订阅"))
            return false
        }
        // Name must be unique within this subscription.
        let clash = customRuleSets.contains { $0.name == trimmedName && $0.id != editing?.id }
        if clash {
            showError(NSError.user("已存在同名规则集「\(trimmedName)」"))
            return false
        }
        // Strict: every line must parse.
        let (entries, errors) = RuleSetFormat.parseRules(rulesText)
        if let first = errors.first {
            showError(NSError.user("第 \(first.line) 行「\(first.text)」无效：\(first.reason)"))
            return false
        }

        let set = CustomRuleSet(
            id: editing?.id ?? UUID(),
            subscriptionID: sub.id,
            name: trimmedName,
            outbound: outbound,
            rules: entries,
            enabled: editing?.enabled ?? true,
            createdAt: editing?.createdAt ?? Date()
        )

        do {
            guard let config = parseConfigObject(from: editor.string) else { throw NSError.user("配置 JSON 无效") }
            if let error = ruleSetReferenceError(set, config: config) { throw NSError.user(error) }
            try changeRuleSetFile(at: store.ruleSetFileURL(for: set)) { try store.saveRuleSet(set) }
            appendLog("[规则集] 已保存「\(set.name)」：\(ruleSetApplyStatus)\n")
        } catch {
            showError(error)
            return false
        }
        refreshRulesFromEditor()
        return true
    }
}
