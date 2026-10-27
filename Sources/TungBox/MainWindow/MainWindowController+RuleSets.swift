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
        RuleRouting.referenceError(for: set, config: config)
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

    func restoreCustomRuleMutation(previous: [CustomRule], attempted: [CustomRule], subscriptionID: UUID) {
        customRules = RuleConfigProjector.restoringMutation(current: customRules, previous: previous,
            attempted: attempted, subscriptionExists: subscriptions.contains { $0.id == subscriptionID })
        store.saveCustomRules(customRules)
    }

    func beginRuleChange() -> Bool {
        guard !runtimeCoordinator.state.isTransitioning, !isApplyingRuleSets, !isSyncingHosts else {
            showToast("正在应用配置，请稍后再试", style: .info)
            refreshRulesFromEditor()
            return false
        }
        isApplyingRuleSets = true
        ruleSetApplyStatus = "正在校验，尚未生效"
        showToast("正在更新规则", style: .info)
        return true
    }

    /// Validation never occupies the UI or the switch-operation queue.
    func validateRuleConfig(_ text: String) async throws {
        let checker = runner
        try await ruleConfigValidator.validate(text, directory: store.baseURL) { url in
            _ = try checker.check(config: url)
        }
    }

    func commitRuleConfig(_ candidate: String, previous: String) async throws {
        let profileID = selectedIndex.map { profiles[$0].id }
        let generation = runtimeTransitionID
        let profile = selectedIndex.map { profiles[$0] }
        let projectionURL = currentSubscription().map { store.ruleProjectionURL(for: $0.id) }
        let oldProjection = projectionURL.flatMap { try? Data(contentsOf: $0) }
        let subscriptionID = currentSubscription()?.id
        let expectedRuleFiles = try subscriptionID.map { try ruleSetFiles(for: $0) }
        do { try await validateRuleConfig(candidate) }
        catch { pendingRuleProjection = nil; throw error }
        guard runtimeCoordinator.acceptsDeferredResult(generation: generation),
              selectedIndex.map({ profiles[$0].id }) == profileID,
              editor.string == previous,
              (try subscriptionID.map { try ruleSetFiles(for: $0) }) == expectedRuleFiles else {
            pendingRuleProjection = nil
            throw NSError.user("配置或运行状态已变化，本次规则修改未应用，请重试")
        }
        editor.string = candidate
        var committed = candidate
        var committedProjection = oldProjection
        do {
            let url = try saveCurrent()
            committed = editor.string
            committedProjection = projectionURL.flatMap { try? Data(contentsOf: $0) }
            try await applyRuleSetRuntime(committed, previous: Data(previous.utf8), configURL: url)
        } catch {
            if let profile, (try? Data(contentsOf: store.configURL(for: profile))) == Data(committed.utf8) {
                try Data(previous.utf8).write(to: store.configURL(for: profile), options: .atomic)
                if let projectionURL, (try? Data(contentsOf: projectionURL)) == committedProjection {
                    if let oldProjection { try oldProjection.write(to: projectionURL, options: .atomic) }
                    else { try? FileManager.default.removeItem(at: projectionURL) }
                }
            }
            if selectedIndex.map({ profiles[$0].id }) == profileID, editor.string == committed {
                editor.string = previous
            }
            pendingRuleProjection = nil
            throw error
        }
    }

    /// Import configurations created before the independent rule-source file was
    /// introduced. The current editor is the only available baseline; remove the
    /// known generated rule-set entries and persist the resulting snapshot once.
    func ensureRuleBase(for subscription: Subscription) throws {
        do {
            _ = try store.baseRouteRules(for: subscription.id)
            return
        } catch { }
        guard let config = parseConfigObject(from: editor.string) else {
            throw NSError.user("当前配置不是有效 JSON，无法迁移旧规则")
        }
        let baseline = try renderConfig(RuleConfigProjector.legacyBase(
            in: config, ruleSets: store.loadRuleSets(for: subscription.id).valid
        ))
        try store.saveRuleBase(baseline, for: subscription.id)
        appendLog("[规则集] 已将旧配置迁移为独立规则来源\n")
    }

    /// File operations and core validation share a rollback boundary. A failed write
    /// or check never becomes a successful UI operation.
    private func changeRuleSetFile(at file: URL, mutation: () throws -> Void) async throws {
        guard !runtimeCoordinator.state.isTransitioning, !isApplyingRuleSets, !isSyncingHosts else { throw NSError.user("规则正在应用，请稍后重试") }
        isApplyingRuleSets = true
        defer { isApplyingRuleSets = false }
        guard let sub = currentSubscription(), let index = selectedIndex,
              profiles.indices.contains(index), sub.profileID == profiles[index].id else {
            throw NSError.user("请先选择该订阅的配置")
        }
        try ensureRuleBase(for: sub)
        let oldFile = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
        let oldEditor = editor.string
        var attemptedFile = oldFile
        do {
            try mutation()
            attemptedFile = try? Data(contentsOf: file)
            let candidate = try renderConfig(try applyCustomRules(to: oldEditor, subscriptionID: sub.id))
            let attemptedFiles = try ruleSetFiles(for: sub.id)
            try await commitRuleConfig(candidate, previous: oldEditor)
            ruleSetFileSignature = attemptedFiles
        } catch {
            do {
                if subscriptions.contains(where: { $0.id == sub.id }), (try? Data(contentsOf: file)) == attemptedFile {
                    if let oldFile { try oldFile.write(to: file, options: .atomic) }
                    else if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                }
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

    /// Apply both independent runtimes. Every blocking Core/OS operation uses
    /// the serialized runtime queue; a newer switch generation cancels late work.
    func applyRuleSetRuntime(_ text: String, previous: Data, configURL: URL) async throws {
        let coordinator = runtimeCoordinator
        guard let request = coordinator.state.request else {
            ruleSetApplyStatus = "已保存，待启动应用"
            return
        }
        let storeCopy = store
        let profileID = selectedIndex.map { profiles[$0].id }
        let runnerRef = runner
        let wantTun = isTunEnabled
        let wantProxy = isSystemProxyEnabled && runner.isRunning
        let port = getMixedProxyPort()
        let runningSnapshot = runner.runningConfigData ?? previous
        let oldTunRequest = wantTun ? try Data(contentsOf: store.tunRequestConfigURL) : nil
        let log: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor [weak self] in self?.appendLog(line) }
        }
        ruleSetApplyStatus = "已保存，正在应用"
        let updated = try await RuntimeConfigurationUpdate.apply(tun: wantTun, proxy: wantProxy, services: .init(
            current: { coordinator.isCurrent(request) },
            updateTun: { [self] in
                let oldPID = try await coordinator.performBlocking(for: request) {
                    TunServiceManager.activeSingBoxPID(store: storeCopy)
                }
                guard await reloadTunConfigInPlace(configText: text) else {
                    if !coordinator.isCurrent(request) { throw RuntimeCoordinator.OperationError.superseded }
                    throw NSError.user("TUN 配置重载请求失败")
                }
                let submitted = try Data(contentsOf: storeCopy.tunRequestConfigURL)
                if submitted == oldTunRequest, oldPID != nil { return }
                // Check process replacement and interface readiness off MainActor.
                // Two consecutive observations avoid calling a failed startup active.
                var confirmedPID: Int32?
                for _ in 0..<30 {
                    try await Task.sleep(for: .milliseconds(500))
                    let snapshot = try await coordinator.performBlocking(for: request) {
                        (try Data(contentsOf: storeCopy.tunRequestConfigURL),
                         TunServiceManager.activeSingBoxPID(store: storeCopy),
                         TunServiceManager.tunInterfaceIsActive())
                    }
                    guard snapshot.0 == submitted else { throw RuntimeCoordinator.OperationError.superseded }
                    if let pid = snapshot.1, pid != oldPID, snapshot.2 {
                        if confirmedPID == pid { return }
                        confirmedPID = pid
                    } else { confirmedPID = nil }
                }
                throw NSError.user("TUN 重载未确认成功，正在恢复旧配置")
            },
            updateProxy: { [self] in
                try await coordinator.performBlocking(for: request) {
                    runnerRef.stop()
                    do {
                        try self.startNormalProxyBlocking(runner: runnerRef, config: configURL, port: port, reason: "规则更新", log: log)
                    } catch {
                        let applyError = error
                        runnerRef.stop()
                        let recoveryURL = storeCopy.baseURL.appendingPathComponent("rules-recovery-\(UUID().uuidString).json")
                        defer { try? FileManager.default.removeItem(at: recoveryURL) }
                        try runningSnapshot.write(to: recoveryURL, options: .atomic)
                        try self.startNormalProxyBlocking(runner: runnerRef, config: recoveryURL, port: port, reason: "规则应用失败后恢复", log: log)
                        throw applyError
                    }
                }
            },
            restoreTun: {
                guard let oldTunRequest else { return }
                try await coordinator.performBlocking(for: request) {
                    try TunServiceManager.writeRequestConfig(oldTunRequest, store: storeCopy)
                    TunServiceManager.refreshRequestHeartbeat(store: storeCopy)
                }
            }
        ))
        guard updated, coordinator.isCurrent(request) else {
            ruleSetApplyStatus = "已保存，运行状态已变化"
            return
        }
        if wantProxy {
            await reconcileSelectorSelectionsToConfigAsync(configText: text, profileID: profileID)
            guard coordinator.isCurrent(request) else { return }
            let mode = parseConfigObject(from: text).map { ProxyModeConfig.readMode(from: $0) } ?? "Rule"
            applyRuntimeMode(mode, refreshNodeDelays: false, onlyIfNeeded: true)
        }
        ruleSetApplyStatus = (wantTun || wantProxy) ? "已生效（现有连接已重建）" : "已保存，待启动应用"
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
        Task { @MainActor [weak self] in await self?.applyExternalRuleSetChanges() }
    }

    private func applyExternalRuleSetChanges() async {
        guard !runtimeCoordinator.state.isTransitioning, !isApplyingRuleSets, !isSyncingHosts, let sub = currentSubscription(), let index = selectedIndex,
              profiles.indices.contains(index), sub.profileID == profiles[index].id else { return }
        isApplyingRuleSets = true
        defer { isApplyingRuleSets = false }
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
            guard Data(editor.string.utf8) == saved else {
                ruleSetApplyStatus = "文件已变化，请先保存配置编辑内容"
                return
            }
            let candidate = try renderConfig(try applyCustomRules(to: editor.string, subscriptionID: sub.id))
            if candidate != editor.string {
                do {
                    try await commitRuleConfig(candidate, previous: editor.string)
                    showToast("规则已刷新：\(ruleSetApplyStatus)", style: ruleSetApplyStatus.hasPrefix("已生效") ? .success : .info)
                } catch {
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
            showToast("规则刷新失败：\(error.localizedDescription)", style: .error)
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
        Task { @MainActor in
            do {
                try await changeRuleSetFile(at: store.ruleSetFileURL(for: set)) { try store.deleteRuleSet(set) }
                appendLog("[规则集] 已删除「\(set.name)」\n")
            } catch { showError(error) }
        }
    }

    func setRuleSetEnabled(_ set: CustomRuleSet, to enabled: Bool) {
        if enabled, let error = RuleRouting.enableError(for: set, config: parseConfigObject(from: editor.string)) {
            showError(NSError.user("启用失败：\(error)"))
            refreshRulesFromEditor()
            return
        }
        var updated = set
        updated.enabled = enabled
        Task { @MainActor [updated] in
            do {
                try await changeRuleSetFile(at: store.ruleSetFileURL(for: set)) { try store.saveRuleSet(updated) }
            } catch { showError(error) }
        }
    }

    func deleteInvalidRuleSet(_ invalid: InvalidRuleSet) {
        Task { @MainActor in
            do {
                try await changeRuleSetFile(at: invalid.fileURL) { try store.deleteRuleSetFile(at: invalid.fileURL) }
                showToast("已删除无效规则集文件")
            } catch { showError(error) }
        }
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
        presetButton.heightAnchor.constraint(equalToConstant: ConsoleControlLayout.actionHeight).isActive = true

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
            let name = nameField?.stringValue ?? ""
            let outbound = outboundPopup?.titleOfSelectedItem ?? "Proxy"
            let rules = textView?.string ?? ""
            Task { @MainActor in
                let ok = await self.saveRuleSetFromDialog(name: name, outbound: outbound, rulesText: rules, editing: existing)
                if ok { dialog?.dismiss() }
            }
        }
        dialog.onCancel = { [weak dialog] in dialog?.dismiss() }
    }

    /// Returns true on success (dialog should close), false if validation failed
    /// (dialog stays open so the user keeps their input).
    private func saveRuleSetFromDialog(name: String, outbound: String, rulesText: String, editing: CustomRuleSet?) async -> Bool {
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
            try await changeRuleSetFile(at: store.ruleSetFileURL(for: set)) { try store.saveRuleSet(set) }
            appendLog("[规则集] 已保存「\(set.name)」：\(ruleSetApplyStatus)\n")
        } catch {
            showError(error)
            return false
        }
        refreshRulesFromEditor()
        return true
    }
}
