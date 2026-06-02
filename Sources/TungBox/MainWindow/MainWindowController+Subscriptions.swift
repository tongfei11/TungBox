import AppKit
import Foundation

extension MainWindowController {
    
    func makeSubscriptionsView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }

        let title = NSTextField(labelWithString: "订阅")
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.textColor = MD3.onSurface
        title.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak title] in
            title?.textColor = MD3.onSurface
        }

        let addButton = MD3Button()
        addButton.title = "添加订阅"
        addButton.style = .filled
        addButton.target = self
        addButton.action = #selector(addSubscriptionClicked)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        addButton.widthAnchor.constraint(equalToConstant: 120).isActive = true
        
        let updateButton = MD3Button()
        updateButton.title = "更新选中"
        updateButton.style = .tonal
        updateButton.target = self
        updateButton.action = #selector(updateSubscriptionClicked)
        updateButton.translatesAutoresizingMaskIntoConstraints = false
        updateButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        updateButton.widthAnchor.constraint(equalToConstant: 120).isActive = true
        
        let deleteButton = MD3Button()
        deleteButton.title = "删除订阅"
        deleteButton.style = .destructive
        deleteButton.target = self
        deleteButton.action = #selector(deleteSubscriptionClicked)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        deleteButton.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let buttons = NSStackView(views: [addButton, updateButton, deleteButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        
        subscriptionTable.backgroundColor = .clear
        subscriptionTable.selectionHighlightStyle = .none
        subscriptionTable.autoresizingMask = [.width]
        
        let subColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("subscription"))
        subColumn.resizingMask = .autoresizingMask
        subscriptionTable.addTableColumn(subColumn)
        subscriptionTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        
        subscriptionTable.headerView = nil
        subscriptionTable.delegate = self
        subscriptionTable.dataSource = self
        subscriptionTable.rowHeight = 88
        scroll.documentView = subscriptionTable
        subscriptionTable.sizeLastColumnToFit()

        let panel = MD3Panel()
        panel.type = .filled
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(scroll)

        view.addSubview(title)
        view.addSubview(buttons)
        view.addSubview(panel)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),

            buttons.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            buttons.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),
            buttons.heightAnchor.constraint(equalToConstant: 36),

            panel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            panel.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 20),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8)
        ])

        return view
    }

    @objc func addSubscriptionClicked() {
        let nameField = MD3TextField()
        nameField.placeholderString = "订阅名称 (如: Xboard)"
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 432).isActive = true
        nameField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let urlField = MD3TextField()
        urlField.placeholderString = "https://..."
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.widthAnchor.constraint(equalToConstant: 432).isActive = true
        urlField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let stack = NSStackView(views: [nameField, urlField])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 432),
            container.heightAnchor.constraint(equalToConstant: 84)
        ])

        let dialog = showMD3Dialog(
            title: "添加订阅",
            message: "请输入新订阅的名称和配置 URL。",
            customView: container
        )
        
        dialog.window?.initialFirstResponder = nameField
        
        dialog.onConfirm = { [weak self, weak nameField, weak urlField, weak dialog] in
            guard let self = self else { return }
            let name = nameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = urlField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            guard !name.isEmpty else {
                self.showError(NSError.user("订阅名称不能为空"))
                return
            }
            guard !url.isEmpty else {
                self.showError(NSError.user("订阅 URL 不能为空"))
                return
            }

            let subscription = Subscription(
                id: UUID(),
                name: name,
                url: url,
                profileID: nil,
                updatedAt: nil
            )
            self.subscriptions.append(subscription)
            self.store.saveSubscriptions(self.subscriptions)
            self.selectSubscription(at: self.subscriptions.count - 1)
            self.refreshSubscription(at: self.subscriptions.count - 1)
            dialog?.dismiss()
        }
        
        dialog.onCancel = { [weak dialog] in
            dialog?.dismiss()
        }
    }

    @objc func updateSubscriptionClicked() {
        guard let index = selectedSubscriptionIndex, subscriptions.indices.contains(index) else {
            showError(NSError.user("请先选择一个订阅"))
            return
        }
        let subscription = subscriptions[index]

        let nameField = MD3TextField()
        nameField.stringValue = subscription.name
        nameField.placeholderString = "订阅名称"
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 432).isActive = true
        nameField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let urlField = MD3TextField()
        urlField.stringValue = subscription.url
        urlField.placeholderString = "https://..."
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.widthAnchor.constraint(equalToConstant: 432).isActive = true
        urlField.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let stack = NSStackView(views: [nameField, urlField])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 432),
            container.heightAnchor.constraint(equalToConstant: 84)
        ])

        let dialog = showMD3Dialog(
            title: "编辑订阅",
            message: "请修改订阅的名称或配置 URL。",
            customView: container
        )
        
        dialog.window?.initialFirstResponder = nameField
        
        dialog.onConfirm = { [weak self, weak nameField, weak urlField, weak dialog] in
            guard let self = self else { return }
            let name = nameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = urlField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            guard !name.isEmpty else {
                self.showError(NSError.user("订阅名称不能为空"))
                return
            }
            guard !url.isEmpty else {
                self.showError(NSError.user("订阅 URL 不能为空"))
                return
            }

            self.subscriptions[index] = Subscription(
                id: subscription.id,
                name: name,
                url: url,
                profileID: subscription.profileID,
                updatedAt: subscription.updatedAt
            )
            self.store.saveSubscriptions(self.subscriptions)
            self.subscriptionTable.reloadData()
            self.refreshSubscription(at: index)
            dialog?.dismiss()
        }
        
        dialog.onCancel = { [weak dialog] in
            dialog?.dismiss()
        }
    }

    @objc func deleteSubscriptionClicked() {
        guard let index = selectedSubscriptionIndex, subscriptions.indices.contains(index) else { return }
        subscriptions.remove(at: index)
        selectSubscription(at: nil)
        store.saveSubscriptions(subscriptions)
    }

    func selectSubscription(at index: Int?) {
        guard let index = index else {
            selectedSubscriptionIndex = nil
            subscriptionNameField.stringValue = ""
            subscriptionURLField.stringValue = ""
            nodes = []
            nodeTable.reloadData()
            subscriptionTable.reloadData()
            return
        }
        guard subscriptions.indices.contains(index) else { return }
        selectedSubscriptionIndex = index
        let subscription = subscriptions[index]
        subscriptionNameField.stringValue = subscription.name
        subscriptionURLField.stringValue = subscription.url
        
        // Load associated profile
        if let profileID = subscription.profileID,
           let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) {
            selectProfile(at: profileIndex)
        } else {
            nodes = []
            nodeTable.reloadData()
        }
        subscriptionTable.reloadData()
    }

    func createProfile(named name: String, content: String) {
        let profile = ConfigProfile(id: UUID(), name: name, fileName: "\(UUID().uuidString).json", updatedAt: Date())
        profiles.append(profile)
        try? content.write(to: store.configURL(for: profile), atomically: true, encoding: .utf8)
        store.saveProfiles(profiles)
        table.reloadData()
        selectProfile(at: profiles.count - 1)
    }

    func subscriptionFromFields(existing: Subscription?) throws -> Subscription {
        let name = subscriptionNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = subscriptionURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw NSError.user("请输入订阅名称") }
        guard !url.isEmpty else { throw NSError.user("请输入订阅 URL") }
        return Subscription(
            id: existing?.id ?? UUID(),
            name: name,
            url: url,
            profileID: existing?.profileID,
            updatedAt: existing?.updatedAt
        )
    }

    func refreshSubscription(at index: Int) {
        guard subscriptions.indices.contains(index) else { return }
        let subscription = subscriptions[index]
        appendLog("[订阅] 开始刷新 \(subscription.name)\n")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let content = try SubscriptionImporter.fetch(urlString: subscription.url)
                let config = try SubscriptionImporter.singBoxConfig(from: content, profileName: subscription.name)
                DispatchQueue.main.async {
                    self?.applySubscriptionConfig(config, at: index)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.appendLog("[订阅] \(subscription.name) 刷新失败：\(error.localizedDescription)\n")
                    self?.showError(error)
                }
            }
        }
    }

    func startSubscriptionTimer() {
        subscriptionTimer?.invalidate()
        subscriptionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.subscriptions.isEmpty else { return }
                self.appendLog("[订阅] 自动刷新开始\n")
                self.subscriptionAutoStatusLabel.stringValue = "订阅自动刷新：正在刷新 \(self.subscriptions.count) 个订阅"
                for index in self.subscriptions.indices {
                    self.refreshSubscription(at: index)
                }
            }
        }
    }

    func applySubscriptionConfig(_ config: String, at index: Int) {
        guard subscriptions.indices.contains(index) else { return }
        var subscription = subscriptions[index]
        let profileName = "订阅 - \(subscription.name)"
        let mergedConfig: String
        do {
            mergedConfig = try renderConfig(try applyCustomRules(to: config, subscriptionID: subscription.id))
        } catch {
            showError(error)
            return
        }

        if let profileID = subscription.profileID,
           let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) {
            profiles[profileIndex].name = profileName
            profiles[profileIndex].updatedAt = Date()
            try? mergedConfig.write(to: store.configURL(for: profiles[profileIndex]), atomically: true, encoding: .utf8)
            selectedIndex = profileIndex
        } else {
            let profile = ConfigProfile(id: UUID(), name: profileName, fileName: "\(UUID().uuidString).json", updatedAt: Date())
            profiles.append(profile)
            subscription.profileID = profile.id
            try? mergedConfig.write(to: store.configURL(for: profile), atomically: true, encoding: .utf8)
            selectedIndex = profiles.count - 1
        }

        subscription.updatedAt = Date()
        subscriptions[index] = subscription
        store.saveProfiles(profiles)
        store.saveSubscriptions(subscriptions)
        table.reloadData()
        subscriptionTable.reloadData()
        if let selectedIndex {
            selectProfile(at: selectedIndex, forceReload: true)
        }
        refreshNodesFromEditor()
        refreshHomeFeatureStatus()
        appendLog("[订阅] \(subscription.name) 已刷新并写入配置\n")
    }

    func currentSubscription() -> Subscription? {
        if let index = selectedSubscriptionIndex, subscriptions.indices.contains(index) {
            return subscriptions[index]
        }
        guard let selectedIndex, profiles.indices.contains(selectedIndex) else { return nil }
        let profileID = profiles[selectedIndex].id
        return subscriptions.first { $0.profileID == profileID }
    }
}
