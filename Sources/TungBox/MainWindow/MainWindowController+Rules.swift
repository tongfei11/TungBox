import AppKit
import Foundation

extension MainWindowController {
    
    func makeRulesView() -> NSView {
        startRuleSetWatching()
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        let title = NSTextField(labelWithString: "规则")
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false
        tightenLabelCell(title)
        registerThemeObserver { [weak title] in
            title?.textColor = MD3.onSurface
        }

        let subtitle = NSTextField(labelWithString: "规则将按照从上到下的顺序匹配")
        subtitle.textColor = MD3.onSurfaceVariant
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        tightenLabelCell(subtitle)
        registerThemeObserver { [weak subtitle] in
            subtitle?.textColor = MD3.onSurfaceVariant
        }

        let headerStack = NSStackView(views: [title, subtitle])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 3
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        ruleSearchField.placeholderString = "搜索规则（类型 / 域名 / 关键词...）"
        ruleSearchField.target = self
        ruleSearchField.action = #selector(filterRulesClicked)
        ruleSearchField.translatesAutoresizingMaskIntoConstraints = false
        ruleSearchField.heightAnchor.constraint(equalToConstant: 34).isActive = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(filterRulesClicked),
            name: NSControl.textDidChangeNotification,
            object: ruleSearchField
        )

        let addRuleSetButton = MD3Button()
        addRuleSetButton.title = "添加规则集"
        addRuleSetButton.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)
        addRuleSetButton.style = .outlined
        addRuleSetButton.target = self
        addRuleSetButton.action = #selector(showAddRuleSetDialog)
        addRuleSetButton.translatesAutoresizingMaskIntoConstraints = false
        addRuleSetButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let addRuleButton = MD3Button()
        addRuleButton.title = "添加规则"
        addRuleButton.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: nil)
        addRuleButton.style = .filled
        addRuleButton.target = self
        addRuleButton.action = #selector(showAddCustomRuleDialog)
        addRuleButton.translatesAutoresizingMaskIntoConstraints = false
        addRuleButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let deleteRuleButton = MD3Button()
        deleteRuleButton.title = "删除选中"
        deleteRuleButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        deleteRuleButton.style = .destructive
        deleteRuleButton.target = self
        deleteRuleButton.action = #selector(deleteSelectedRuleClicked)
        deleteRuleButton.translatesAutoresizingMaskIntoConstraints = false
        deleteRuleButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let ruleToolbar = NSStackView(views: [ruleSearchField, addRuleSetButton, addRuleButton, deleteRuleButton])
        ruleToolbar.orientation = .horizontal
        ruleToolbar.spacing = 10
        ruleToolbar.alignment = .centerY
        ruleToolbar.translatesAutoresizingMaskIntoConstraints = false
        ruleSearchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        ruleSearchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for button in [addRuleSetButton, addRuleButton, deleteRuleButton] {
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        let scroll = RuleTableScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.applyThinOverlayScroller()
        scroll.documentView = rulesTable

        rulesTable.backgroundColor = .clear
        rulesTable.usesAlternatingRowBackgroundColors = false
        rulesTable.headerView = NSTableHeaderView()
        rulesTable.delegate = self
        rulesTable.dataSource = self
        rulesTable.rowHeight = 44
        rulesTable.columnAutoresizingStyle = .noColumnAutoresizing
        rulesTable.gridStyleMask = [.solidHorizontalGridLineMask]
        rulesTable.gridColor = MD3.outlineVariant.withAlphaComponent(0.25)
        rulesTable.menu = ruleContextMenu()
        rulesTable.target = self
        rulesTable.action = #selector(rulesTableClicked(_:))
        rulesTable.registerForDraggedTypes([.string])
        rulesTable.draggingDestinationFeedbackStyle = .gap
        for column in RuleTableLayout.columns {
            rulesTable.addTableColumn(ruleColumn(column.id, title: column.title, width: column.minimum))
        }

        let panel = MD3Panel()
        panel.type = .filled
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(scroll)

        view.addSubview(headerStack)
        view.addSubview(ruleToolbar)
        view.addSubview(panel)

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),

            ruleToolbar.leadingAnchor.constraint(equalTo: headerStack.leadingAnchor),
            ruleToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            ruleToolbar.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 18),
            ruleToolbar.heightAnchor.constraint(equalToConstant: 34),

            panel.leadingAnchor.constraint(equalTo: headerStack.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            panel.topAnchor.constraint(equalTo: ruleToolbar.bottomAnchor, constant: 14),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),

            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -6)
        ])

        refreshRulesFromEditor()
        return view
    }

    private func ruleColumn(_ id: String, title: String, width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = width
        column.headerCell.font = .systemFont(ofSize: 12, weight: .semibold)
        column.resizingMask = []
        return column
    }

    private func ruleContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self   // items are built dynamically in menuWillOpen
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu == rulesTable.menu else { return }
        let row = rulesTable.clickedRow
        if row >= 0 {
            rulesTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        menu.removeAllItems()
        let rows = filteredRuleRows()
        guard rows.indices.contains(rulesTable.selectedRow) else { return }
        let selected = rows[rulesTable.selectedRow]

        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        if selected.customRuleID != nil {
            add("编辑自定义规则", #selector(editCustomRuleClicked))
            add("\(selected.enableActionTitle)自定义规则", #selector(toggleSelectedCustomRuleEnabled))
            menu.addItem(.separator())
            add("删除自定义规则", #selector(deleteCustomRuleClicked))
        } else if let setID = selected.ruleSetID, customRuleSets.contains(where: { $0.id == setID }) {
            add("编辑规则集", #selector(editRuleSetClicked))
            add("\(selected.enableActionTitle)规则集", #selector(toggleRuleSetEnabledClicked))
            menu.addItem(.separator())
            add("删除规则集", #selector(deleteRuleSetClicked))
        } else if selected.ruleSetInvalidURL != nil {
            add("在访达中显示", #selector(revealInvalidRuleSetClicked))
            menu.addItem(.separator())
            add("删除无效规则集文件", #selector(deleteInvalidRuleSetClicked))
        }
    }

    /// The rule set for the currently-selected rule-set row, if any.
    func selectedRuleSet() -> CustomRuleSet? {
        let rows = filteredRuleRows()
        guard rows.indices.contains(rulesTable.selectedRow),
              let id = rows[rulesTable.selectedRow].ruleSetID else { return nil }
        return customRuleSets.first { $0.id == id }
    }

    func selectedInvalidRuleSet() -> InvalidRuleSet? {
        let rows = filteredRuleRows()
        guard rows.indices.contains(rulesTable.selectedRow),
              let url = rows[rulesTable.selectedRow].ruleSetInvalidURL else { return nil }
        return invalidRuleSets.first { $0.fileURL == url }
    }

    @objc func editRuleSetClicked() {
        if let set = selectedRuleSet() { editRuleSet(set) }
    }

    @objc func toggleRuleSetEnabledClicked() {
        let rows = filteredRuleRows()
        guard rows.indices.contains(rulesTable.selectedRow), let set = selectedRuleSet() else { return }
        setRuleSetEnabled(set, to: !rows[rulesTable.selectedRow].isEffectivelyEnabled)
    }

    @objc func deleteRuleSetClicked() {
        if let set = selectedRuleSet() { deleteRuleSet(set) }
    }

    @objc func deleteSelectedRuleClicked() {
        let rows = filteredRuleRows()
        let row = rulesTable.selectedRow
        guard rows.indices.contains(row) else {
            showToast("请先选中要删除的规则", style: .warning)
            return
        }
        let selected = rows[row]
        if selected.customRuleID != nil {
            deleteCustomRuleClicked()
        } else if let setID = selected.ruleSetID,
                  let set = customRuleSets.first(where: { $0.id == setID }) {
            deleteRuleSet(set)
        } else if selected.ruleSetInvalidURL != nil {
            deleteInvalidRuleSetClicked()
        } else {
            showToast("订阅内置规则不能删除", style: .info)
        }
    }

    @objc func revealInvalidRuleSetClicked() {
        if let invalid = selectedInvalidRuleSet() {
            NSWorkspace.shared.activateFileViewerSelecting([invalid.fileURL])
        }
    }

    @objc func deleteInvalidRuleSetClicked() {
        if let invalid = selectedInvalidRuleSet() { deleteInvalidRuleSet(invalid) }
    }

    @objc func filterRulesClicked() {
        rulesTable.reloadData()
    }

    @objc func deleteCustomRuleClicked() {
        Task { @MainActor [weak self] in await self?.deleteSelectedCustomRule() }
    }

    private func deleteSelectedCustomRule() async {
        guard beginRuleChange() else { return }
        defer { isApplyingRuleSets = false }
        do {
            let rows = filteredRuleRows()
            let row = rulesTable.selectedRow
            guard rows.indices.contains(row), let ruleID = rows[row].customRuleID else {
                throw NSError.user("请先选中一条自定义规则")
            }
            guard let subscription = currentSubscription() else {
                throw NSError.user("请先选择一个订阅")
            }
            try ensureRuleBase(for: subscription)
            guard customRules.contains(where: { $0.id == ruleID }) else {
                throw NSError.user("没有找到选中的自定义规则")
            }
            let previousRules = customRules
            let previousConfig = editor.string
            customRules.removeAll { $0.id == ruleID }
            let attemptedRules = customRules
            store.saveCustomRules(customRules)
            let candidate = try renderConfig(try applyCustomRules(to: previousConfig, subscriptionID: subscription.id))
            do {
                try await commitRuleConfig(candidate, previous: previousConfig)
            } catch {
                restoreCustomRuleMutation(previous: previousRules, attempted: attemptedRules, subscriptionID: subscription.id)
                throw error
            }
            appendLog("[规则] 已删除选中的自定义规则\n")
            refreshRulesFromEditor()
            showToast("已删除自定义规则", style: .success)
        } catch {
            showError(error)
        }
    }

    @objc func toggleRuleEnabled(_ sender: MD3Checkbox) {
        setCustomRuleEnabled(at: sender.tag, to: sender.state == .on)
    }

    @objc func toggleSelectedCustomRuleEnabled() {
        let rows = filteredRuleRows()
        guard rows.indices.contains(rulesTable.selectedRow),
              let ruleID = rows[rulesTable.selectedRow].customRuleID,
              let index = customRules.firstIndex(where: { $0.id == ruleID }) else { return }
        setCustomRuleEnabled(at: index, to: !rows[rulesTable.selectedRow].isEffectivelyEnabled)
    }

    /// Covers blank space around a checkbox; warning marks stay read-only.
    /// The checkbox consumes its own click so these paths never toggle twice.
    @objc func rulesTableClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        let column = sender.clickedColumn
        guard row >= 0, column >= 0,
              sender.tableColumns[column].identifier.rawValue == "enabled" else { return }
        let rows = filteredRuleRows()
        guard rows.indices.contains(row),
              rows[row].referenceError == nil,
              let ruleID = rows[row].customRuleID,
              let idx = customRules.firstIndex(where: { $0.id == ruleID }) else { return }
        setCustomRuleEnabled(at: idx, to: !customRules[idx].enabled)
    }

    func setCustomRuleEnabled(at idx: Int, to enabled: Bool) {
        guard customRules.indices.contains(idx) else { return }
        let id = customRules[idx].id
        Task { @MainActor [weak self] in await self?.applyCustomRuleEnabled(id: id, to: enabled) }
    }

    private func applyCustomRuleEnabled(id: UUID, to enabled: Bool) async {
        guard let idx = customRules.firstIndex(where: { $0.id == id }), beginRuleChange() else { return }
        defer { isApplyingRuleSets = false }
        guard customRules[idx].enabled != enabled else { return }
        if enabled, let error = RuleRouting.enableError(for: customRules[idx], config: parseConfigObject(from: editor.string)) {
            showError(NSError.user("启用失败：\(error)"))
            refreshRulesFromEditor()
            return
        }
        let previousRules = customRules
        let previousConfig = editor.string
        customRules[idx].enabled = enabled
        let attemptedRules = customRules
        store.saveCustomRules(customRules)
        appendLog("[规则] 正在\(enabled ? "启用" : "停用") \(customRules[idx].type) \(customRules[idx].value)\n")

        // Regenerate config to apply the toggle
        if let sub = currentSubscription() {
            do {
                try ensureRuleBase(for: sub)
                let candidate = try renderConfig(try applyCustomRules(to: previousConfig, subscriptionID: sub.id))
                try await commitRuleConfig(candidate, previous: previousConfig)
                showToast("规则已\(enabled ? "启用" : "停用")：\(ruleSetApplyStatus)",
                          style: ruleSetApplyStatus.hasPrefix("已生效") ? .success : .info)
            } catch {
                // Rollback
                restoreCustomRuleMutation(previous: previousRules, attempted: attemptedRules, subscriptionID: sub.id)
                showToast("规则更新失败：\(error.localizedDescription)", style: .error)
            }
        }
        refreshRulesFromEditor()
    }

    func refreshRulesFromEditor() {
        loadRuleSetsForCurrentSubscription()
        ruleRows = buildRuleRows(from: editor.string)
        cachedRuleSearchQuery = nil
        cachedFilteredRuleRows = nil
        rulesTable.reloadData()
        refreshRuleSetCachesIfNeeded()
    }

    @objc func refreshRuleSetsManuallyClicked() {
        let sets = currentRouteRuleSets()
        guard !sets.isEmpty else { showToast("当前配置没有规则集", style: .warning); return }
        ruleSetDownloads.removeAll()
        appendLog("[规则集] 手动刷新 \(sets.count) 个规则集\n")
        refreshRuleSetCachesIfNeeded()
        showToast("正在刷新 \(sets.count) 个规则集", style: .info)
    }

    @objc func clearRuleSetCacheClicked() {
        let dir = store.ruleSetsURL
        guard FileManager.default.fileExists(atPath: dir.path) else { showToast("缓存为空", style: .info); return }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var n = 0
        for f in files { try? FileManager.default.removeItem(at: f); n += 1 }
        ruleSetDownloads.removeAll()
        appendLog("[规则集] 已清空缓存（\(n) 个文件）\n")
        showToast("已清空 \(n) 个规则集缓存", style: .success)
    }

    func filteredRuleRows() -> [RuleInfo] {
        let query = ruleSearchField.stringValue
        if cachedRuleSearchQuery == query, let cachedFilteredRuleRows {
            return cachedFilteredRuleRows
        }

        let filteredRows = ruleRows.filter { row in
            RuleSearch.matches(
                type: row.type,
                value: row.value,
                strategy: row.strategy,
                note: row.note,
                isSection: row.isSection,
                query: query
            )
        }
        cachedRuleSearchQuery = query
        cachedFilteredRuleRows = filteredRows
        return filteredRows
    }

    func customRulesForCurrentSubscription() -> [CustomRule] {
        guard let subscription = currentSubscription() else { return [] }
        return customRules
            .filter { $0.subscriptionID == subscription.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func applyCustomRules(to text: String, subscriptionID: UUID) throws -> [String: Any] {
        guard let config = parseConfigObject(from: text) else { throw NSError.user("当前配置不是有效 JSON") }
        let base = try store.baseRouteRules(for: subscriptionID)
        let sets = store.loadRuleSets(for: subscriptionID).valid
        let projection = try RuleConfigProjector.project(
            config: config, subscriptionID: subscriptionID, base: base,
            customRules: customRules, ruleSets: sets, fallbackProxyTag: nodes.first?.tag ?? "direct"
        )
        pendingRuleProjection = (subscriptionID, projection.routeRules)
        return projection.config
    }

    func buildRuleRows(from text: String) -> [RuleInfo] {
        guard let config = parseConfigObject(from: text) else {
            return ConfigInspection.ruleRows(in: nil)
        }
        let sets = ruleSetsForCurrentSubscription()
        var entriesByTag: [String: [RuleSetEntry]] = [:]
        for tag in ConfigInspection.referencedRuleSetTags(in: config) {
            if let data = try? Data(contentsOf: ruleSetJSONURL(for: tag)) {
                entriesByTag[tag] = ConfigInspection.ruleSetEntries(from: data)
            }
        }
        let context = ConfigInspection.RuleContext(
            customRules: customRulesForCurrentSubscription(),
            ruleSets: sets.map { .init(ruleSet: $0, referenceError: ruleSetReferenceError($0, config: config)) },
            invalidRuleSets: invalidRuleSets,
            ruleSetApplyStatus: ruleSetApplyStatus,
            cachedRuleSetEntries: entriesByTag,
            downloadingRuleSets: ruleSetDownloads
        )
        return ConfigInspection.ruleRows(in: config, context: context)
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
                  !ruleSetJSONURL(for: tag).path.isEmpty,
                  !FileManager.default.fileExists(atPath: ruleSetJSONURL(for: tag).path),
                  !ruleSetDownloads.contains(tag) else { continue }
            let srsURL = ruleSetSRSURL(for: tag)
            let jsonURL = ruleSetJSONURL(for: tag)
            let action = RuleSetRuntime.cachePreparationAction(
                hasLocalSRS: FileManager.default.fileExists(atPath: srsURL.path),
                hasConnected: firstConnectionGate.hasConnected
            )
            guard action != .waitForConnection else { continue }
            let sourceURL = (ruleSet["url"] as? String).flatMap(URL.init(string:))
            guard action != .download || sourceURL != nil else { continue }
            ruleSetDownloads.insert(tag)
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.prepareRuleSetCache(
                    tag: tag,
                    sourceURL: sourceURL,
                    action: action,
                    srsURL: srsURL,
                    jsonURL: jsonURL,
                    singBoxBinary: binary
                )
            }
        }
    }

    nonisolated func prepareRuleSetCache(
        tag: String,
        sourceURL: URL?,
        action: RuleSetRuntime.CachePreparationAction,
        srsURL: URL,
        jsonURL: URL,
        singBoxBinary: String
    ) {
        let temporarySRS = srsURL.deletingLastPathComponent()
            .appendingPathComponent(".\(RuleSetRuntime.safeFileName(for: tag))-\(UUID().uuidString).srs")
        let temporaryJSON = jsonURL.deletingLastPathComponent()
            .appendingPathComponent(".\(RuleSetRuntime.safeFileName(for: tag))-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: temporarySRS)
            try? FileManager.default.removeItem(at: temporaryJSON)
        }
        do {
            let inputSRS: URL
            if action == .download {
                guard let sourceURL else { throw NSError.user("规则集缺少下载地址") }
                let data = try BoundedRemoteDataLoader.fetch(url: sourceURL, maxBytes: SecurityLimits.ruleSetBytes)
                try data.write(to: temporarySRS, options: .atomic)
                inputSRS = temporarySRS
            } else {
                inputSRS = srsURL
            }

            let process = Process()
            process.currentDirectoryURL = srsURL.deletingLastPathComponent()
            process.executableURL = URL(fileURLWithPath: singBoxBinary)
            process.arguments = ["rule-set", "decompile", inputSRS.path, "-o", temporaryJSON.path]
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

            if action == .download {
                if FileManager.default.fileExists(atPath: srsURL.path) {
                    _ = try FileManager.default.replaceItemAt(srsURL, withItemAt: temporarySRS)
                } else {
                    try FileManager.default.moveItem(at: temporarySRS, to: srsURL)
                }
            }
            if FileManager.default.fileExists(atPath: jsonURL.path) {
                _ = try FileManager.default.replaceItemAt(jsonURL, withItemAt: temporaryJSON)
            } else {
                try FileManager.default.moveItem(at: temporaryJSON, to: jsonURL)
            }

            DispatchQueue.main.async { [weak self] in
                self?.ruleSetDownloads.remove(tag)
                self?.appendLog("[规则集] \(tag) 已\(action == .download ? "下载并" : "从本地")解包\n")
                self?.ruleRows = self?.buildRuleRows(from: self?.editor.string ?? "") ?? []
                self?.cachedRuleSearchQuery = nil
                self?.cachedFilteredRuleRows = nil
                self?.rulesTable.reloadData()
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.ruleSetDownloads.remove(tag)
                self?.appendLog("[规则集] \(tag) 缓存准备失败：\(error.localizedDescription)\n")
            }
        }
    }

    func currentRouteRuleSets() -> [[String: Any]] {
        guard let config = parseConfigObject(from: editor.string),
              let route = config["route"] as? [String: Any],
              let ruleSets = route["rule_set"] as? [[String: Any]] else { return [] }
        return ruleSets
    }

    func makeRuleCell(for rule: RuleInfo, columnID: String) -> NSView {
        RuleTableCell.make(for: rule, columnID: columnID) { [self] button, ruleID in
            // The action indexes persisted rules, not display rows with section headers.
            button.tag = customRules.firstIndex(where: { $0.id == ruleID }) ?? -1
            button.target = self
            button.action = #selector(toggleRuleEnabled(_:))
        }
    }
}
