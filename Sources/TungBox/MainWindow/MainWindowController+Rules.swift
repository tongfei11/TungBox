import AppKit
import Foundation

extension MainWindowController {
    
    func makeRulesView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        let title = NSTextField(labelWithString: "规则")
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak title] in
            title?.textColor = MD3.onSurface
        }

        let subtitle = NSTextField(labelWithString: "规则将按照从上到下的顺序匹配")
        subtitle.textColor = MD3.onSurfaceVariant
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak subtitle] in
            subtitle?.textColor = MD3.onSurfaceVariant
        }

        ruleSearchField.placeholderString = "搜索规则"
        ruleSearchField.target = self
        ruleSearchField.action = #selector(refreshRulesClicked)
        ruleSearchField.translatesAutoresizingMaskIntoConstraints = false
        ruleSearchField.heightAnchor.constraint(equalToConstant: 36).isActive = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshRulesClicked),
            name: NSControl.textDidChangeNotification,
            object: ruleSearchField
        )

        let addRuleButton = MD3Button()
        addRuleButton.title = "添加规则"
        addRuleButton.style = .filled
        addRuleButton.target = self
        addRuleButton.action = #selector(showAddCustomRuleDialog)
        addRuleButton.translatesAutoresizingMaskIntoConstraints = false
        addRuleButton.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let ruleToolbar = NSStackView(views: [ruleSearchField, addRuleButton])
        ruleToolbar.orientation = .horizontal
        ruleToolbar.spacing = 12
        ruleToolbar.alignment = .centerY
        ruleToolbar.translatesAutoresizingMaskIntoConstraints = false
        ruleSearchField.widthAnchor.constraint(equalToConstant: 320).isActive = true

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = rulesTable

        rulesTable.backgroundColor = .clear
        rulesTable.usesAlternatingRowBackgroundColors = false
        rulesTable.headerView = NSTableHeaderView()
        rulesTable.delegate = self
        rulesTable.dataSource = self
        rulesTable.rowHeight = 54
        rulesTable.gridStyleMask = [.solidHorizontalGridLineMask]
        rulesTable.gridColor = MD3.outlineVariant
        rulesTable.menu = ruleContextMenu()
        rulesTable.target = self
        rulesTable.action = #selector(rulesTableClicked(_:))
        rulesTable.registerForDraggedTypes([.string])
        rulesTable.draggingDestinationFeedbackStyle = .gap
        rulesTable.addTableColumn(ruleColumn("enabled", title: "", width: 48))
        rulesTable.addTableColumn(ruleColumn("id", title: "#", width: 56))
        rulesTable.addTableColumn(ruleColumn("type", title: "类型", width: 150))
        rulesTable.addTableColumn(ruleColumn("value", title: "匹配值", width: 360))
        rulesTable.addTableColumn(ruleColumn("strategy", title: "策略", width: 120))
        rulesTable.addTableColumn(ruleColumn("count", title: "命中", width: 80))
        rulesTable.addTableColumn(ruleColumn("note", title: "备注", width: 240))

        let panel = MD3Panel()
        panel.type = .filled
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(scroll)

        view.addSubview(title)
        view.addSubview(subtitle)
        view.addSubview(ruleToolbar)
        view.addSubview(panel)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),

            ruleToolbar.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            ruleToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            ruleToolbar.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 20),

            panel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            panel.topAnchor.constraint(equalTo: ruleToolbar.bottomAnchor, constant: 14),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),

            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8)
        ])

        refreshRulesFromEditor()
        return view
    }

    private func ruleColumn(_ id: String, title: String, width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = width
        column.resizingMask = .autoresizingMask
        return column
    }

    private func ruleContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "编辑自定义规则", action: #selector(editCustomRuleClicked), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "删除自定义规则", action: #selector(deleteCustomRuleClicked), keyEquivalent: ""))
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu == rulesTable.menu else { return }
        let row = rulesTable.clickedRow
        if row >= 0 {
            rulesTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        let rows = filteredRuleRows()
        let isCustom = rows.indices.contains(rulesTable.selectedRow) && rows[rulesTable.selectedRow].customRuleID != nil
        menu.items.forEach { $0.isEnabled = isCustom }
    }

    @objc func refreshRulesClicked() {
        refreshRulesFromEditor()
    }

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
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // LAN matches all private-address traffic and takes no value.
        if type == "LAN" { return }
        guard !v.isEmpty else { throw NSError.user("请输入规则值") }
        switch type {
        case "DEST-PORT":
            guard let p = Int(v), (1...65535).contains(p) else {
                throw NSError.user("端口需为 1-65535 之间的数字")
            }
        case "IP-CIDR", "IP-CIDR6", "SRC-IP":
            guard v.contains("/") else {
                throw NSError.user("请使用 CIDR 写法，例如 192.168.0.0/16（单个 IP 用 /32 或 /128）")
            }
        case "GEOIP":
            guard v.range(of: "^[A-Za-z][A-Za-z-]*$", options: .regularExpression) != nil else {
                throw NSError.user("国家/地区码示例：cn、us、hk")
            }
        case "NETWORK":
            guard ["tcp", "udp"].contains(v.lowercased()) else {
                throw NSError.user("网络只能填 tcp 或 udp")
            }
        default:
            break
        }
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
                do { _ = try runner.check(config: url) }
                catch {
                    customRules = previousRules; store.saveCustomRules(customRules)
                    editor.string = previous; _ = try? saveCurrent()
                    throw error
                }
                editingRuleID = nil
                appendLog("[规则] 已更新自定义规则\n")
            } else {
                // Add new rule
                let newRule = CustomRule(id: UUID(), subscriptionID: subscription.id, type: type, value: value, strategy: strategy, note: note, enabled: true, createdAt: Date())
                customRules.append(newRule)
                store.saveCustomRules(customRules)
                editor.string = try renderConfig(try applyCustomRules(to: previous, subscriptionID: subscription.id))
                let url = try saveCurrent()
                do { _ = try runner.check(config: url) }
                catch {
                    customRules.removeAll { $0.id == newRule.id }; store.saveCustomRules(customRules)
                    editor.string = previous; _ = try? saveCurrent()
                    throw error
                }
                appendLog("[规则] 已添加 \(type) \(value) -> \(strategy)\(note.isEmpty ? "" : "，备注：\(note)")\n")
            }

            customRuleValueField.stringValue = ""
            customRuleNoteField.stringValue = ""
            refreshRulesFromEditor()
        } catch {
            showError(error)
        }
    }

    @objc func deleteCustomRuleClicked() {
        do {
            let rows = filteredRuleRows()
            let row = rulesTable.selectedRow
            guard rows.indices.contains(row), let ruleID = rows[row].customRuleID else {
                throw NSError.user("请先选中一条自定义规则")
            }
            guard let subscription = currentSubscription() else {
                throw NSError.user("请先选择一个订阅")
            }
            guard let deletedRule = customRules.first(where: { $0.id == ruleID }) else {
                throw NSError.user("没有找到选中的自定义规则")
            }
            let previousRules = customRules
            let previousConfig = editor.string
            customRules.removeAll { $0.id == ruleID }
            store.saveCustomRules(customRules)
            let configWithoutDeletedRule = try removeCustomRule(deletedRule, from: previousConfig)
            editor.string = try renderConfig(try applyCustomRules(to: configWithoutDeletedRule, subscriptionID: subscription.id))
            let url = try saveCurrent()
            do {
                _ = try runner.check(config: url)
            } catch {
                customRules = previousRules
                store.saveCustomRules(customRules)
                editor.string = previousConfig
                _ = try? saveCurrent()
                throw error
            }
            appendLog("[规则] 已删除选中的自定义规则\n")
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

    @objc func toggleRuleEnabled(_ sender: MD3Checkbox) {
        setCustomRuleEnabled(at: sender.tag, to: sender.state == .on)
    }

    /// Table-level fallback: a click landing in the 启用 column toggles that rule.
    /// On selected rows the drag-tracking machinery can swallow the checkbox's own
    /// mouseDown, so the click falls through to the table — this action catches it.
    /// The two paths are mutually exclusive (the checkbox consumes its event when it
    /// does receive it), so a single click never toggles twice.
    @objc func rulesTableClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        let column = sender.clickedColumn
        guard row >= 0, column >= 0,
              sender.tableColumns[column].identifier.rawValue == "enabled" else { return }
        let rows = filteredRuleRows()
        guard rows.indices.contains(row),
              let ruleID = rows[row].customRuleID,
              let idx = customRules.firstIndex(where: { $0.id == ruleID }) else { return }
        setCustomRuleEnabled(at: idx, to: !customRules[idx].enabled)
    }

    func setCustomRuleEnabled(at idx: Int, to enabled: Bool) {
        guard customRules.indices.contains(idx) else { return }
        customRules[idx].enabled = enabled
        store.saveCustomRules(customRules)
        appendLog("[规则] \(customRules[idx].type) \(customRules[idx].value) 已\(customRules[idx].enabled ? "启用" : "禁用")\n")

        // Regenerate config to apply the toggle
        if let sub = currentSubscription() {
            do {
                let baseConfig = try removeCustomRule(customRules[idx], from: editor.string)
                editor.string = try renderConfig(try applyCustomRules(to: baseConfig, subscriptionID: sub.id))
                _ = try saveCurrent()
            } catch {
                // Rollback
                customRules[idx].enabled.toggle()
                store.saveCustomRules(customRules)
                showError(error)
            }
        }
        refreshRulesFromEditor()
    }

    func refreshRulesFromEditor() {
        ruleRows = buildRuleRows(from: editor.string)
        rulesTable.reloadData()
        refreshRuleSetCachesIfNeeded()
    }

    @objc func refreshRuleSetsManuallyClicked() {
        let sets = currentRouteRuleSets()
        guard !sets.isEmpty else { showToast("当前配置没有规则集"); return }
        ruleSetDownloads.removeAll()
        appendLog("[规则集] 手动刷新 \(sets.count) 个规则集\n")
        refreshRuleSetCachesIfNeeded()
        showToast("正在刷新 \(sets.count) 个规则集")
    }

    @objc func clearRuleSetCacheClicked() {
        let dir = store.ruleSetsURL
        guard FileManager.default.fileExists(atPath: dir.path) else { showToast("缓存为空"); return }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var n = 0
        for f in files { try? FileManager.default.removeItem(at: f); n += 1 }
        ruleSetDownloads.removeAll()
        appendLog("[规则集] 已清空缓存（\(n) 个文件）\n")
        showToast("已清空 \(n) 个规则集缓存")
    }

    func filteredRuleRows() -> [RuleInfo] {
        let query = ruleSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return ruleRows }
        return ruleRows.filter { row in
            row.isSection ||
            row.type.lowercased().contains(query) ||
            row.value.lowercased().contains(query) ||
            row.strategy.lowercased().contains(query) ||
            row.note.lowercased().contains(query)
        }
    }

    func customRulesForCurrentSubscription() -> [CustomRule] {
        guard let subscription = currentSubscription() else { return [] }
        return customRules
            .filter { $0.subscriptionID == subscription.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func applyCustomRules(to text: String, subscriptionID: UUID) throws -> [String: Any] {
        guard var config = parseConfigObject(from: text) else {
            throw NSError.user("当前配置不是有效 JSON")
        }
        let rulesForSubscription = customRules
            .filter { $0.subscriptionID == subscriptionID && $0.enabled }
            .sorted { $0.createdAt < $1.createdAt }
        guard !rulesForSubscription.isEmpty else { return config }

        for rule in rulesForSubscription {
            config = ensureOutboundSupport(in: config, strategy: rule.strategy)
        }

        var route = config["route"] as? [String: Any] ?? [:]
        var routeRules = route["rules"] as? [[String: Any]] ?? []
        routeRules.removeAll { existing in
            rulesForSubscription.contains { customRuleMatches($0, existing) }
        }
        let insertIndex = customRuleInsertIndex(in: routeRules)
        let generatedRules = rulesForSubscription.map {
            customRouteRule(type: $0.type, value: $0.value, strategy: $0.strategy)
        }
        routeRules.insert(contentsOf: generatedRules, at: insertIndex)
        route["rules"] = routeRules
        config["route"] = route
        return config
    }

    private func customRuleMatches(_ customRule: CustomRule, _ routeRule: [String: Any]) -> Bool {
        let expected = customRouteRule(type: customRule.type, value: customRule.value, strategy: customRule.strategy)
        return NSDictionary(dictionary: expected).isEqual(to: routeRule)
    }

    func removeCustomRule(_ customRule: CustomRule, from text: String) throws -> String {
        guard var config = parseConfigObject(from: text) else {
            throw NSError.user("当前配置不是有效 JSON")
        }
        var route = config["route"] as? [String: Any] ?? [:]
        var routeRules = route["rules"] as? [[String: Any]] ?? []
        routeRules.removeAll { customRuleMatches(customRule, $0) }
        route["rules"] = routeRules
        config["route"] = route
        return try renderConfig(config)
    }

    func buildRuleRows(from text: String) -> [RuleInfo] {
        guard let config = parseConfigObject(from: text) else {
            return [sectionRule("当前配置不是可读取的 JSON")]
        }

        var rows: [RuleInfo] = []
        var nextID = 1

        func append(_ type: String, _ value: String, _ strategy: String, _ note: String = "", enabled: Bool = true, count: String = "0") {
            rows.append(RuleInfo(
                customRuleID: nil,
                enabled: enabled,
                id: "\(nextID)",
                type: type,
                value: value,
                strategy: strategy,
                count: count,
                note: note,
                isSection: false
            ))
            nextID += 1
        }

        func appendCustom(_ rule: CustomRule) {
            rows.append(RuleInfo(
                customRuleID: rule.id,
                enabled: rule.enabled,
                id: "\(nextID)",
                type: rule.type,
                value: rule.value,
                strategy: displayStrategy(outboundForStrategy(rule.strategy)),
                count: "0",
                note: rule.note.isEmpty ? "自定义规则" : rule.note,
                isSection: false
            ))
            nextID += 1
        }

        let currentCustomRules = customRulesForCurrentSubscription()
        rows.append(sectionRule("自定义规则"))
        if currentCustomRules.isEmpty {
            append("CUSTOM", "当前订阅还没有自定义规则", "未设置", "通过上方输入框添加", enabled: false)
        } else {
            for rule in currentCustomRules {
                appendCustom(rule)
            }
        }

        let route = config["route"] as? [String: Any] ?? [:]
        let rules = route["rules"] as? [[String: Any]] ?? []
        rows.append(sectionRule("当前配置规则"))
        for rule in rules {
            if currentCustomRules.contains(where: { customRuleMatches($0, rule) }) {
                continue
            }
            if let action = rule["action"] as? String {
                let protocolValue = (rule["protocol"] as? String) ?? "ALL"
                append("ACTION", protocolValue, action.uppercased(), "sing-box action")
                continue
            }
            let strategy = displayStrategy((rule["outbound"] as? String) ?? (rule["server"] as? String) ?? "")
            if let clashMode = rule["clash_mode"] as? String {
                append("MODE", modeDisplayName(clashMode), strategy, "模式规则")
            }
            if let ruleSet = rule["rule_set"] {
                appendExpandedRuleSetRows(ruleSet, strategy: strategy, rows: &rows, nextID: &nextID)
            }
            if let cidr = rule["ip_cidr"] {
                append("IP-CIDR", compactDescription(cidr), strategy, "IP 段")
            }
            if let priv = rule["ip_is_private"] as? Bool, priv {
                append("LAN", "内网 / 私有地址", strategy, "内网")
            }
            if let domains = rule["domain"] {
                appendEachRuleValue(type: "DOMAIN", values: domains, strategy: strategy, note: "显式域名", append: append)
            }
            if let suffixes = rule["domain_suffix"] {
                appendEachRuleValue(type: "DOMAIN-SUFFIX", values: suffixes, strategy: strategy, note: "域名后缀", append: append)
            }
            if let keywords = rule["domain_keyword"] {
                appendEachRuleValue(type: "DOMAIN-KEYWORD", values: keywords, strategy: strategy, note: "域名关键字", append: append)
            }
            if let regexes = rule["domain_regex"] {
                appendEachRuleValue(type: "DOMAIN-REGEX", values: regexes, strategy: strategy, note: "域名正则", append: append)
            }
            if let sourceCIDR = rule["source_ip_cidr"] {
                appendEachRuleValue(type: "SRC-IP", values: sourceCIDR, strategy: strategy, note: "源 IP", append: append)
            }
            if let processName = rule["process_name"] {
                appendEachRuleValue(type: "PROCESS-NAME", values: processName, strategy: strategy, note: "进程", append: append)
            }
            if let processPath = rule["process_path"] {
                appendEachRuleValue(type: "PROCESS-PATH", values: processPath, strategy: strategy, note: "进程路径", append: append)
            }
            if let port = rule["port"] {
                appendEachRuleValue(type: "DEST-PORT", values: port, strategy: strategy, note: "端口", append: append)
            }
            if let network = rule["network"] {
                appendEachRuleValue(type: "NETWORK", values: network, strategy: strategy, note: "网络类型", append: append)
            }
        }

        if let final = route["final"] as? String {
            append("FINAL", "未命中以上规则", displayStrategy(final), "默认策略")
        }

        let dns = config["dns"] as? [String: Any] ?? [:]
        let dnsRules = dns["rules"] as? [[String: Any]] ?? []
        if !dnsRules.isEmpty {
            rows.append(sectionRule("DNS 规则"))
            for rule in dnsRules {
                let server = (rule["server"] as? String) ?? "未设置"
                if let clashMode = rule["clash_mode"] as? String {
                    append("DNS-MODE", modeDisplayName(clashMode), server, "DNS 模式规则")
                }
                if let ruleSet = rule["rule_set"] {
                    appendExpandedRuleSetRows(ruleSet, strategy: server, rows: &rows, nextID: &nextID, notePrefix: "DNS")
                }
            }
            if let final = dns["final"] as? String {
                append("DNS-FINAL", "未命中以上 DNS 规则", final, "默认 DNS")
            }
        }

        return rows
    }

    private func sectionRule(_ title: String) -> RuleInfo {
        RuleInfo(customRuleID: nil, enabled: false, id: "", type: "", value: "# \(title)", strategy: "", count: "", note: "", isSection: true)
    }

    private func appendExpandedRuleSetRows(
        _ ruleSetValue: Any,
        strategy: String,
        rows: inout [RuleInfo],
        nextID: inout Int,
        notePrefix: String = "规则集"
    ) {
        let tags: [String]
        if let values = ruleSetValue as? [String] {
            tags = values
        } else if let value = ruleSetValue as? String {
            tags = [value]
        } else {
            tags = []
        }

        for tag in tags {
            let entries = decompiledRuleSetEntries(tag: tag, strategy: strategy, notePrefix: notePrefix)
            if entries.isEmpty {
                rows.append(RuleInfo(
                    customRuleID: nil,
                    enabled: true,
                    id: "\(nextID)",
                    type: "RULE-SET",
                    value: tag,
                    strategy: strategy,
                    count: "0",
                    note: ruleSetDownloads.contains(tag) ? "下载中" : "等待下载",
                    isSection: false
                ))
                nextID += 1
            } else {
                rows.append(sectionRule("\(notePrefix)内容：\(tag)"))
                for entry in entries {
                    rows.append(RuleInfo(
                        customRuleID: nil,
                        enabled: true,
                        id: "\(nextID)",
                        type: entry.type,
                        value: entry.value,
                        strategy: strategy,
                        count: "0",
                        note: tag,
                        isSection: false
                    ))
                    nextID += 1
                }
            }
        }
    }

    private func decompiledRuleSetEntries(tag: String, strategy: String, notePrefix: String) -> [(type: String, value: String)] {
        let url = ruleSetJSONURL(for: tag)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = object["rules"] as? [[String: Any]] else { return [] }

        var entries: [(type: String, value: String)] = []
        for rule in rules {
            appendRuleSetValues(type: "DOMAIN", key: "domain", from: rule, to: &entries)
            appendRuleSetValues(type: "DOMAIN-SUFFIX", key: "domain_suffix", from: rule, to: &entries)
            appendRuleSetValues(type: "DOMAIN-KEYWORD", key: "domain_keyword", from: rule, to: &entries)
            appendRuleSetValues(type: "DOMAIN-REGEX", key: "domain_regex", from: rule, to: &entries)
            appendRuleSetValues(type: "IP-CIDR", key: "ip_cidr", from: rule, to: &entries)
            appendRuleSetValues(type: "SRC-IP", key: "source_ip_cidr", from: rule, to: &entries)
            appendRuleSetValues(type: "PROCESS-NAME", key: "process_name", from: rule, to: &entries)
        }
        return entries
    }

    private func appendRuleSetValues(type: String, key: String, from rule: [String: Any], to entries: inout [(type: String, value: String)]) {
        if let values = rule[key] as? [String] {
            for value in values {
                entries.append((type, value))
            }
        } else if let value = rule[key] as? String {
            entries.append((type, value))
        }
    }

    private func displayStrategy(_ strategy: String) -> String {
        switch strategy {
        case TungBoxConfig.tagDirect: return "DIRECT"
        case TungBoxConfig.tagBlock: return "REJECT"
        case TungBoxConfig.tagManual: return "Proxy"
        case TungBoxConfig.tagAuto: return "AUTO"
        default: return strategy.isEmpty ? "未设置" : strategy
        }
    }

    private func appendEachRuleValue(
        type: String,
        values: Any,
        strategy: String,
        note: String,
        append: (String, String, String, String, Bool, String) -> Void
    ) {
        if let list = values as? [String] {
            for value in list {
                append(type, value, strategy, note, true, "0")
            }
        } else if let value = values as? String {
            append(type, value, strategy, note, true, "0")
        } else {
            append(type, compactDescription(values), strategy, note, true, "0")
        }
    }

    func customRouteRule(type: String, value: String, strategy: String) -> [String: Any] {
        let outbound = outboundForStrategy(strategy)
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case "DOMAIN":
            return ["domain": normalizedValue, "outbound": outbound]
        case "DOMAIN-SUFFIX":
            return ["domain_suffix": normalizedValue, "outbound": outbound]
        case "DOMAIN-KEYWORD":
            return ["domain_keyword": normalizedValue, "outbound": outbound]
        case "DOMAIN-WILDCARD":
            return ["domain_regex": wildcardRegex(from: normalizedValue), "outbound": outbound]
        case "DOMAIN-REGEX", "URL-REGEX":
            return ["domain_regex": normalizedValue, "outbound": outbound]
        case "RULE-SET":
            return ["rule_set": normalizedValue, "outbound": outbound]
        case "IP-CIDR":
            return ["ip_cidr": normalizedValue, "outbound": outbound]
        case "IP-CIDR6":
            return ["ip_cidr": normalizedValue, "outbound": outbound]
        case "GEOIP":
            return ["rule_set": normalizedValue.hasPrefix("geoip-") ? normalizedValue : "geoip-\(normalizedValue.lowercased())", "outbound": outbound]
        case "LAN":
            return ["ip_is_private": true, "outbound": outbound]
        case "SRC-IP":
            return ["source_ip_cidr": normalizedValue, "outbound": outbound]
        case "PROCESS-NAME":
            return ["process_name": normalizedValue, "outbound": outbound]
        case "PROCESS-PATH":
            return ["process_path": normalizedValue, "outbound": outbound]
        case "DEST-PORT":
            if let port = Int(normalizedValue) {
                return ["port": port, "outbound": outbound]
            }
            return ["port": normalizedValue, "outbound": outbound]
        case "PROTOCOL":
            return ["protocol": normalizedValue.lowercased(), "outbound": outbound]
        case "NETWORK":
            return ["network": normalizedValue.lowercased(), "outbound": outbound]
        default:
            return ["domain": normalizedValue, "outbound": outbound]
        }
    }

    func outboundForStrategy(_ strategy: String) -> String {
        switch strategy {
        case "DIRECT": return TungBoxConfig.tagDirect
        case "REJECT": return TungBoxConfig.tagBlock
        case "AUTO": return TungBoxConfig.tagAuto
        case "Proxy": return TungBoxConfig.tagManual
        default: return strategy
        }
    }

    private func wildcardRegex(from value: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: value)
            .replacingOccurrences(of: "\\*", with: ".*")
        return "^\(escaped)$"
    }

    func ensureOutboundSupport(in config: [String: Any], strategy: String) -> [String: Any] {
        var config = config
        var outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let requiredTag = outboundForStrategy(strategy)
        if !outbounds.contains(where: { ($0["tag"] as? String) == requiredTag }) {
            guard [TungBoxConfig.tagDirect, TungBoxConfig.tagBlock].contains(requiredTag) else {
                return config
            }
            let type = requiredTag == TungBoxConfig.tagBlock ? "block" : "direct"
            outbounds.append(["type": type, "tag": requiredTag])
            config["outbounds"] = outbounds
        }
        return config
    }

    func customRuleInsertIndex(in rules: [[String: Any]]) -> Int {
        var index = 0
        while index < rules.count {
            let rule = rules[index]
            if rule["action"] != nil || rule["clash_mode"] != nil {
                index += 1
            } else {
                break
            }
        }
        return index
    }

    func ruleSetSRSURL(for tag: String) -> URL {
        store.ruleSetsURL.appendingPathComponent(safeFileName(tag)).appendingPathExtension("srs")
    }

    func ruleSetJSONURL(for tag: String) -> URL {
        store.ruleSetsURL.appendingPathComponent(safeFileName(tag)).appendingPathExtension("json")
    }

    func safeFileName(_ text: String) -> String {
        text.map { char in
            char.isLetter || char.isNumber || char == "-" || char == "_" ? char : "_"
        }.map(String.init).joined()
    }

    func refreshRuleSetCachesIfNeeded() {
        let ruleSets = currentRouteRuleSets()
        guard !ruleSets.isEmpty, let binary = runner.findSingBox() else { return }
        for ruleSet in ruleSets {
            guard let tag = ruleSet["tag"] as? String,
                  let urlText = ruleSet["url"] as? String,
                  let url = URL(string: urlText),
                  !ruleSetJSONURL(for: tag).path.isEmpty,
                  !FileManager.default.fileExists(atPath: ruleSetJSONURL(for: tag).path),
                  !ruleSetDownloads.contains(tag) else { continue }
            ruleSetDownloads.insert(tag)
            let srsURL = ruleSetSRSURL(for: tag)
            let jsonURL = ruleSetJSONURL(for: tag)
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.downloadAndDecompileRuleSet(tag: tag, url: url, srsURL: srsURL, jsonURL: jsonURL, singBoxBinary: binary)
            }
        }
    }

    nonisolated func downloadAndDecompileRuleSet(tag: String, url: URL, srsURL: URL, jsonURL: URL, singBoxBinary: String) {
        do {
            let data = try Data(contentsOf: url)
            try data.write(to: srsURL, options: .atomic)

            let process = Process()
            process.currentDirectoryURL = srsURL.deletingLastPathComponent()
            process.executableURL = URL(fileURLWithPath: singBoxBinary)
            process.arguments = ["rule-set", "decompile", srsURL.path, "-o", jsonURL.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8) ?? "规则集解包失败"
                throw NSError.user(message)
            }

            DispatchQueue.main.async { [weak self] in
                self?.ruleSetDownloads.remove(tag)
                self?.appendLog("[规则集] \(tag) 已下载并解包\n")
                self?.ruleRows = self?.buildRuleRows(from: self?.editor.string ?? "") ?? []
                self?.rulesTable.reloadData()
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.ruleSetDownloads.remove(tag)
                self?.appendLog("[规则集] \(tag) 下载或解包失败：\(error.localizedDescription)\n")
            }
        }
    }

    func currentRouteRuleSets() -> [[String: Any]] {
        guard let config = parseConfigObject(from: editor.string),
              let route = config["route"] as? [String: Any],
              let ruleSets = route["rule_set"] as? [[String: Any]] else { return [] }
        return ruleSets
    }
}
