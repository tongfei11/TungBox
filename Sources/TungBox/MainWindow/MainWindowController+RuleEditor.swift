import AppKit
import Foundation

/// Single-rule editor, input metadata, pickers and add/edit persistence callbacks.
extension MainWindowController {
    /// Per-rule-type field label, input placeholder, a short description shown under
    /// the type popup, and whether it's a process rule (offers the running-app picker).
    func ruleTypeMeta(_ type: String) -> (label: String, placeholder: String, desc: String, isProcess: Bool) {
        switch type {
        case "DOMAIN": return ("域名", "example.com", "如果请求的域名完全匹配，执行该规则。", false)
        case "DOMAIN-SUFFIX": return ("域名后缀", "example.com", "如果请求的域名以此后缀结尾（含子域名），执行该规则。", false)
        case "DOMAIN-KEYWORD": return ("域名关键字", "google", "如果请求的域名包含该关键字，执行该规则。", false)
        case "DOMAIN-WILDCARD": return ("通配域名", "*.example.com", "使用通配符匹配域名，* 匹配任意字符。", false)
        case "DOMAIN-REGEX": return ("域名正则", "^.*\\.example\\.com$", "使用正则表达式匹配请求的域名。", false)
        case "RULE-SET": return ("规则集标签", "geosite-cn", "引用当前配置中已定义的规则集（geosite / geoip / 自定义 SRS）。可点下方按钮从已有规则集中选择，避免手输错标签。", false)
        case "IP-CIDR": return ("IP 范围", "IP CIDR 地址块（例如 192.168.1.0/24）", "当请求的目标 IP 属于指定段时匹配（IPv4）。默认不执行 DNS 解析（no-resolve），仅按已知 IP 匹配。", false)
        case "IP-CIDR6": return ("IP 范围", "IPv6 CIDR（例如 2001:db8::/32）", "当请求的目标 IP 属于指定段时匹配（IPv6）。默认不执行 DNS 解析（no-resolve），仅按已知 IP 匹配。", false)
        case "GEOIP": return ("国家/地区码", "cn", "当请求的目标 IP 属于指定国家 / 地区时匹配。默认不执行 DNS 解析（no-resolve），仅按已知 IP 匹配。", false)
        case "LAN": return ("匹配值（可留空）", "无需填写", "匹配所有目标为内网 / 私有地址的流量（10./172.16./192.168./fc00 等），一条顶多条 IP-CIDR。此类型无需填写匹配值。", false)
        case "SRC-IP": return ("来源 IP 范围", "192.168.1.0/24", "当请求的来源 IP 属于指定段时匹配。", false)
        case "PROCESS-NAME": return ("进程名", "WeChat", "当发起请求的进程名匹配时执行该规则。可从运行中的应用选择。", true)
        case "PROCESS-PATH": return ("进程路径", "/Applications/WeChat.app/Contents/MacOS/WeChat", "按发起请求进程的可执行文件完整路径匹配，比进程名更精确（可区分同名进程）。", false)
        case "URL-REGEX": return ("URL 正则", "^.*\\.example\\.com$", "按域名正则近似匹配（sing-box 无完整 URL 匹配能力）。", false)
        case "DEST-PORT": return ("目标端口", "443", "当请求的目标端口匹配时执行该规则。", false)
        case "PROTOCOL": return ("协议", "tls", "当嗅探到的应用层协议匹配时执行（如 tls、http、quic）。", false)
        case "NETWORK": return ("网络", "tcp", "按传输层网络匹配，仅可填 tcp 或 udp。", false)
        default: return ("规则值", "example.com", "", false)
        }
    }

    /// Short Chinese name shown next to the English key in the type dropdown.
    func ruleTypeChineseName(_ type: String) -> String {
        switch type {
        case "DOMAIN": return "域名"
        case "DOMAIN-SUFFIX": return "域名后缀"
        case "DOMAIN-KEYWORD": return "域名关键字"
        case "DOMAIN-WILDCARD": return "通配域名"
        case "DOMAIN-REGEX": return "域名正则"
        case "RULE-SET": return "规则集"
        case "IP-CIDR": return "IP 段"
        case "IP-CIDR6": return "IPv6 段"
        case "GEOIP": return "地区"
        case "LAN": return "内网"
        case "SRC-IP": return "来源 IP"
        case "PROCESS-NAME": return "进程名"
        case "PROCESS-PATH": return "进程路径"
        case "URL-REGEX": return "URL 正则"
        case "DEST-PORT": return "目标端口"
        case "PROTOCOL": return "协议"
        case "NETWORK": return "网络"
        default: return ""
        }
    }

    /// English key of the selected rule type. Each menu item stores its key in
    /// representedObject so the visible title can carry Chinese without breaking
    /// the type switches elsewhere.
    var selectedRuleType: String {
        (customRuleTypePopup.selectedItem?.representedObject as? String) ?? "DOMAIN"
    }

    /// Select the type item whose English key matches (used when editing a rule).
    func selectRuleType(_ key: String) {
        if let item = customRuleTypePopup.itemArray.first(where: { ($0.representedObject as? String) == key }) {
            customRuleTypePopup.select(item)
        }
    }

    /// "ENGLISH 中文" for the type dropdown, with the Chinese half greyed out so it
    /// reads like a secondary hint rather than part of the identifier.
    func ruleTypeAttributedTitle(_ key: String) -> NSAttributedString {
        let name = ruleTypeChineseName(key)
        let full = name.isEmpty ? key : "\(key)   \(name)"
        let attr = NSMutableAttributedString(string: full, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: MD3.onSurface
        ])
        if !name.isEmpty, let range = full.range(of: name) {
            attr.addAttribute(.foregroundColor, value: MD3.onSurfaceVariant.withAlphaComponent(0.55), range: NSRange(range, in: full))
        }
        return attr
    }

    /// Friendly pre-save validation per rule type (the final config is still checked
    /// by sing-box, but this catches obvious mistakes with a clear message).
    func validateRuleValue(type: String, value: String) throws {
        do { try RuleSetFormat.validate(type: type, value: value) }
        catch { throw NSError.user((error as? RuleSetFormat.FormatError)?.message ?? error.localizedDescription) }
    }

    @objc func customRuleTypeChanged() {
        let type = selectedRuleType
        let meta = ruleTypeMeta(type)
        customRuleValueLabel?.stringValue = meta.label
        customRuleValueField.placeholderString = meta.placeholder
        customRuleDescLabel?.stringValue = meta.desc
        // Show a "pick from existing" button for the types that have a source to
        // pick from (running apps for PROCESS-NAME, defined rule sets for RULE-SET).
        // Add/remove it from the stack rather than toggling isHidden — a hidden
        // arranged subview is not collapsed on macOS 26 and would overlap the value
        // field, blocking clicks on its left half.
        if let button = customRuleAppPickerButton, let stack = customRuleValueStack {
            let picker: (title: String, action: Selector)?
            switch type {
            case "PROCESS-NAME": picker = ("从运行中的应用选择…", #selector(pickRunningAppForRule(_:)))
            case "RULE-SET": picker = ("从已有规则集选择…", #selector(pickRuleSetForRule(_:)))
            default: picker = nil
            }
            if let picker {
                button.title = picker.title
                button.action = picker.action
                if button.superview == nil { stack.addArrangedSubview(button) }
            } else if button.superview != nil {
                stack.removeArrangedSubview(button)
                button.removeFromSuperview()
            }
        }
    }

    @objc func pickRunningAppForRule(_ sender: NSButton) {
        // Only meaningful for PROCESS-NAME; ignore for any other type.
        guard selectedRuleType == "PROCESS-NAME" else { return }
        let menu = NSMenu()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (name: String, process: String)? in
                guard let process = app.executableURL?.lastPathComponent else { return nil }
                return (app.localizedName ?? process, process)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if apps.isEmpty {
            menu.addItem(withTitle: "没有检测到运行中的应用", action: nil, keyEquivalent: "")
        }
        for app in apps {
            let item = NSMenuItem(title: "\(app.name)  ·  \(app.process)", action: #selector(runningAppPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.process
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc func runningAppPicked(_ sender: NSMenuItem) {
        guard let process = sender.representedObject as? String else { return }
        customRuleValueField.stringValue = process
    }

    @objc func pickRuleSetForRule(_ sender: NSButton) {
        // Only meaningful for RULE-SET; list the rule sets actually defined in the
        // current config so the user can't reference a non-existent tag.
        guard selectedRuleType == "RULE-SET" else { return }
        let tags = currentRouteRuleSets().compactMap { $0["tag"] as? String }
        let menu = NSMenu()
        if tags.isEmpty {
            menu.addItem(withTitle: "当前配置没有规则集", action: nil, keyEquivalent: "")
        }
        for tag in tags {
            let item = NSMenuItem(title: tag, action: #selector(ruleSetPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tag
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc func ruleSetPicked(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? String else { return }
        customRuleValueField.stringValue = tag
    }

    @objc func showAddCustomRuleDialog() {
        populateRuleTypePopup()
        populateRuleStrategyPopup()
        customRuleValueField.stringValue = ""
        customRuleNoteField.stringValue = ""
        customRuleTypePopup.target = self
        customRuleTypePopup.action = #selector(customRuleTypeChanged)

        let typeLabel = settingsLabel("规则类型")
        let valueLabel = settingsLabel("域名")
        customRuleValueLabel = valueLabel
        let strategyLabel = settingsLabel("使用策略")
        let noteLabel = settingsLabel("备注")

        typeLabel.alignment = .left
        valueLabel.alignment = .left
        strategyLabel.alignment = .left
        noteLabel.alignment = .left

        customRuleTypePopup.translatesAutoresizingMaskIntoConstraints = false
        customRuleTypePopup.heightAnchor.constraint(equalToConstant: 36).isActive = true
        customRuleStrategyPopup.translatesAutoresizingMaskIntoConstraints = false
        customRuleStrategyPopup.heightAnchor.constraint(equalToConstant: 36).isActive = true
        customRuleValueField.placeholderString = "example.com"
        customRuleValueField.translatesAutoresizingMaskIntoConstraints = false
        customRuleValueField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        // 仅 PROCESS-NAME 类型显示：从运行中的应用选择进程名
        let appPickerButton = MD3Button()
        appPickerButton.title = "从运行中的应用选择…"
        appPickerButton.style = .outlined
        appPickerButton.target = self
        appPickerButton.action = #selector(pickRunningAppForRule(_:))
        appPickerButton.translatesAutoresizingMaskIntoConstraints = false
        appPickerButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        customRuleAppPickerButton = appPickerButton
        // The picker button is added to / removed from the stack on demand in
        // customRuleTypeChanged(). We must NOT rely on isHidden here: on macOS 26
        // NSStackView no longer collapses a hidden arranged subview, so the hidden
        // button stays laid out on top of the value field's left half and swallows
        // its clicks (they fall through to the table behind the dialog).
        let valueStack = NSStackView(views: [customRuleValueField])
        valueStack.orientation = .vertical
        valueStack.spacing = 8
        valueStack.alignment = .leading
        valueStack.translatesAutoresizingMaskIntoConstraints = false
        customRuleValueStack = valueStack
        customRuleValueField.leadingAnchor.constraint(equalTo: valueStack.leadingAnchor).isActive = true
        customRuleValueField.trailingAnchor.constraint(equalTo: valueStack.trailingAnchor).isActive = true

        customRuleNoteField.placeholderString = "可选"
        customRuleNoteField.translatesAutoresizingMaskIntoConstraints = false
        customRuleNoteField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let sectionHeadingLabel = { (title: String) -> NSTextField in
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 13, weight: .bold)
            label.textColor = MD3.primary
            label.translatesAutoresizingMaskIntoConstraints = false
            self.registerThemeObserver { [weak label] in
                label?.textColor = MD3.primary
            }
            return label
        }

        let dividerLine = { () -> NSView in
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = MD3.outlineVariant.cgColor
            view.translatesAutoresizingMaskIntoConstraints = false
            view.heightAnchor.constraint(equalToConstant: 1).isActive = true
            self.registerThemeObserver { [weak view] in
                view?.layer?.backgroundColor = MD3.outlineVariant.cgColor
            }
            return view
        }

        let fieldStack = { (label: NSTextField, control: NSView) -> NSStackView in
            let stack = NSStackView(views: [label, control])
            stack.orientation = .vertical
            stack.spacing = 6
            stack.alignment = .leading
            stack.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                control.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
                control.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
            ])
            return stack
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let sec1 = sectionHeadingLabel("规则")
        let f1 = fieldStack(typeLabel, customRuleTypePopup)
        let descLabel = NSTextField(labelWithString: "")
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = MD3.onSurfaceVariant
        descLabel.lineBreakMode = .byWordWrapping
        descLabel.maximumNumberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak descLabel] in descLabel?.textColor = MD3.onSurfaceVariant }
        customRuleDescLabel = descLabel
        let f2 = fieldStack(valueLabel, valueStack)
        let div1 = dividerLine()

        let sec2 = sectionHeadingLabel("动作")
        let f3 = fieldStack(strategyLabel, customRuleStrategyPopup)
        let div2 = dividerLine()

        let sec3 = sectionHeadingLabel("备注")
        let f4 = fieldStack(noteLabel, customRuleNoteField)

        stack.addArrangedSubview(sec1)
        stack.addArrangedSubview(f1)
        stack.addArrangedSubview(descLabel)
        stack.addArrangedSubview(f2)
        stack.addArrangedSubview(div1)
        stack.addArrangedSubview(sec2)
        stack.addArrangedSubview(f3)
        stack.addArrangedSubview(div2)
        stack.addArrangedSubview(sec3)
        stack.addArrangedSubview(f4)

        NSLayoutConstraint.activate([
            f1.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            f1.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            descLabel.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            descLabel.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            f2.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            f2.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            div1.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            div1.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            f3.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            f3.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            div2.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            div2.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            f4.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            f4.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])

        stack.setCustomSpacing(8, after: sec1)
        stack.setCustomSpacing(6, after: f1)
        stack.setCustomSpacing(12, after: descLabel)
        stack.setCustomSpacing(16, after: f2)
        stack.setCustomSpacing(16, after: div1)
        stack.setCustomSpacing(8, after: sec2)
        stack.setCustomSpacing(16, after: f3)
        stack.setCustomSpacing(16, after: div2)
        stack.setCustomSpacing(8, after: sec3)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 432)
        ])

        let isEditing = editingRuleID != nil
        let dialog = showMD3Dialog(
            title: isEditing ? "编辑自定义规则" : "新建标准规则",
            message: isEditing ? "修改后点击保存即可更新。" : "自定义规则会按当前订阅单独保存，并在刷新订阅后自动合并。",
            customView: container,
            confirmTitle: isEditing ? "保存" : "添加"
        )

        dialog.window?.initialFirstResponder = customRuleValueField
        customRuleTypeChanged()   // sync label / placeholder / app-picker to current type

        dialog.onConfirm = { [weak self, weak dialog] in
            self?.addCustomRuleFromDialog()
            dialog?.dismiss()
        }

        dialog.onCancel = { [weak dialog] in
            dialog?.dismiss()
        }
    }

    private func addCustomRuleFromDialog() {
        do {
            let value = customRuleValueField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let type = selectedRuleType
            try validateRuleValue(type: type, value: value)
            guard let subscription = currentSubscription() else {
                throw NSError.user("请先选择一个订阅。自定义规则会按订阅单独保存。")
            }
            try ensureRuleBase(for: subscription)

            let strategy = customRuleStrategyPopup.titleOfSelectedItem ?? "Proxy"
            let note = customRuleNoteField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let previous = editor.string
            let previousRules = customRules

            if let editID = editingRuleID, let idx = customRules.firstIndex(where: { $0.id == editID }) {
                // Edit existing rule
                customRules[idx].type = type
                customRules[idx].value = value
                customRules[idx].strategy = strategy
                customRules[idx].note = note
                store.saveCustomRules(customRules)
                editor.string = try renderConfig(try applyCustomRules(to: previous, subscriptionID: subscription.id))
                let url = try saveCurrent()
                do {
                    _ = try runner.check(config: url)
                    try applyRuleSetRuntime(editor.string, previous: Data(previous.utf8), configURL: url)
                }
                catch {
                    customRules = previousRules; store.saveCustomRules(customRules)
                    editor.string = previous; _ = try? saveCurrent()
                    throw error
                }
                editingRuleID = nil
                appendLog("[规则] 已更新自定义规则\n")
                showToast("已更新自定义规则", style: .success)
            } else {
                // Add new rule
                let newRule = CustomRule(id: UUID(), subscriptionID: subscription.id, type: type, value: value, strategy: strategy, note: note, enabled: true, createdAt: Date())
                customRules.append(newRule)
                store.saveCustomRules(customRules)
                editor.string = try renderConfig(try applyCustomRules(to: previous, subscriptionID: subscription.id))
                let url = try saveCurrent()
                do {
                    _ = try runner.check(config: url)
                    try applyRuleSetRuntime(editor.string, previous: Data(previous.utf8), configURL: url)
                }
                catch {
                    customRules.removeAll { $0.id == newRule.id }; store.saveCustomRules(customRules)
                    editor.string = previous; _ = try? saveCurrent()
                    throw error
                }
                appendLog("[规则] 已添加 \(type) \(value) -> \(strategy)\(note.isEmpty ? "" : "，备注：\(note)")\n")
                showToast("已添加自定义规则", style: .success)
            }

            customRuleValueField.stringValue = ""
            customRuleNoteField.stringValue = ""
            refreshRulesFromEditor()
        } catch {
            showError(error)
        }
    }

    @objc func editCustomRuleClicked() {
        let rows = filteredRuleRows()
        guard rows.indices.contains(rulesTable.selectedRow),
              let ruleID = rows[rulesTable.selectedRow].customRuleID,
              let rule = customRules.first(where: { $0.id == ruleID }) else {
            showError(NSError.user("请先选中一条自定义规则"))
            return
        }
        // Pre-fill dialog with existing values
        showAddCustomRuleDialog()
        selectRuleType(rule.type)
        customRuleStrategyPopup.selectItem(withTitle: rule.strategy)
        customRuleValueField.stringValue = rule.value
        customRuleNoteField.stringValue = rule.note
        customRuleTypeChanged()   // refresh label / placeholder / app-picker for the edited type

        editingRuleID = rule.id
    }

    func populateRuleTypePopup() {
        let currentKey = customRuleTypePopup.selectedItem?.representedObject as? String
        customRuleTypePopup.removeAllItems()
        let sections = [
            ["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-WILDCARD", "DOMAIN-REGEX"],
            ["IP-CIDR", "IP-CIDR6", "GEOIP", "SRC-IP"],
            ["PROCESS-NAME", "PROCESS-PATH", "URL-REGEX"],
            ["DEST-PORT", "PROTOCOL", "NETWORK"],
            ["RULE-SET", "LAN"]
        ]
        for (index, section) in sections.enumerated() {
            if index > 0 {
                customRuleTypePopup.menu?.addItem(NSMenuItem.separator())
            }
            for key in section {
                // Show "ENGLISH 中文" (Chinese greyed) but keep the English key in
                // representedObject so the type switches elsewhere read a stable
                // identifier, not the label. The per-item action fires the type-change
                // handler reliably (the popup-level action was inconsistent through
                // the custom cell).
                let item = NSMenuItem(
                    title: key,
                    action: #selector(customRuleTypeChanged),
                    keyEquivalent: ""
                )
                item.attributedTitle = ruleTypeAttributedTitle(key)
                item.target = self
                item.representedObject = key
                customRuleTypePopup.menu?.addItem(item)
            }
        }
        if let currentKey {
            selectRuleType(currentKey)
        }
    }

    func populateRuleStrategyPopup() {
        let current = customRuleStrategyPopup.titleOfSelectedItem
        customRuleStrategyPopup.removeAllItems()
        customRuleStrategyPopup.addItems(withTitles: ["DIRECT", "REJECT"])
        customRuleStrategyPopup.menu?.addItem(NSMenuItem.separator())
        customRuleStrategyPopup.addItems(withTitles: ["Proxy", "AUTO"])
        let nodeTags = nodes.map(\.tag).filter { !$0.isEmpty }
        if !nodeTags.isEmpty {
            customRuleStrategyPopup.menu?.addItem(NSMenuItem.separator())
            customRuleStrategyPopup.addItems(withTitles: nodeTags)
        }
        if let current, popup(customRuleStrategyPopup, contains: current) {
            customRuleStrategyPopup.selectItem(withTitle: current)
        } else {
            customRuleStrategyPopup.selectItem(withTitle: "Proxy")
        }
    }

    func popup(_ popup: NSPopUpButton, contains title: String) -> Bool {
        popup.itemArray.contains { $0.title == title }
    }

}
