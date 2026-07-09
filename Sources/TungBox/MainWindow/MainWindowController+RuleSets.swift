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
        customRuleSets.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Config regeneration

    /// Remove every route rule that a rule set (in its current on-disk form) would
    /// generate, so a change can be re-applied cleanly. Returns rendered config text.
    func removeRuleSetRules(_ set: CustomRuleSet, from text: String) throws -> String {
        guard var config = parseConfigObject(from: text) else {
            throw NSError.user("当前配置不是有效 JSON")
        }
        var route = config["route"] as? [String: Any] ?? [:]
        var routeRules = route["rules"] as? [[String: Any]] ?? []
        let generated = set.rules.map { customRouteRule(type: $0.type, value: $0.value, strategy: set.outbound) }
        routeRules.removeAll { existing in
            generated.contains { NSDictionary(dictionary: $0).isEqual(to: existing) }
        }
        route["rules"] = routeRules
        config["route"] = route
        return try renderConfig(config)
    }

    /// Re-apply all custom rules + rule sets onto a base config and persist.
    private func regenerate(from base: String, subscription: Subscription) throws {
        editor.string = try renderConfig(try applyCustomRules(to: base, subscriptionID: subscription.id))
        _ = try saveCurrent()
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
        guard let sub = currentSubscription() else { return }
        do {
            let base = try removeRuleSetRules(set, from: editor.string)
            store.deleteRuleSet(set)
            loadRuleSetsForCurrentSubscription()
            try regenerate(from: base, subscription: sub)
            appendLog("[规则集] 已删除「\(set.name)」\n")
        } catch {
            store.saveRuleSet(set)   // rollback file if regen failed
            loadRuleSetsForCurrentSubscription()
            showError(error)
        }
        refreshRulesFromEditor()
    }

    func setRuleSetEnabled(_ set: CustomRuleSet, to enabled: Bool) {
        guard let sub = currentSubscription() else { return }
        var updated = set
        updated.enabled = enabled
        do {
            let base = try removeRuleSetRules(set, from: editor.string)
            store.saveRuleSet(updated)
            loadRuleSetsForCurrentSubscription()
            try regenerate(from: base, subscription: sub)
            appendLog("[规则集]「\(set.name)」已\(enabled ? "启用" : "停用")\n")
        } catch {
            store.saveRuleSet(set)
            loadRuleSetsForCurrentSubscription()
            showError(error)
        }
        refreshRulesFromEditor()
    }

    func deleteInvalidRuleSet(_ invalid: InvalidRuleSet) {
        store.deleteRuleSetFile(at: invalid.fileURL)
        loadRuleSetsForCurrentSubscription()
        refreshRulesFromEditor()
        showToast("已删除无效规则集文件")
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
            let base: String
            if let editing {
                base = try removeRuleSetRules(editing, from: editor.string)
            } else {
                base = editor.string
            }
            store.saveRuleSet(set)
            loadRuleSetsForCurrentSubscription()
            try regenerate(from: base, subscription: sub)
            appendLog("[规则集] 已保存「\(set.name)」→ \(set.outbound)（\(entries.count) 条）\n")
        } catch {
            showError(error)
            // Leave the file as-is; reload to reflect actual state.
            loadRuleSetsForCurrentSubscription()
            return false
        }
        refreshRulesFromEditor()
        return true
    }
}
