import Foundation

final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ value: Value) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&value)
    }
}

final class Store: @unchecked Sendable {
    let baseURL: URL
    let profilesURL: URL
    let subscriptionsURL: URL
    let subscriptionFoldersURL: URL
    let profileFoldersURL: URL
    let customRulesURL: URL
    let ruleSetsURL: URL
    /// Root for user-authored rule sets, one folder per subscription. Distinct from
    /// `ruleSetsURL` (which caches downloaded SRS rule sets).
    let customRuleSetsURL: URL
    let coreURL: URL
    let coreBinaryURL: URL
    let tunRequestConfigURL: URL
    let tunRequestFlagURL: URL
    let tunRequestHeartbeatURL: URL
    let logURL: URL
    let appLogURL: URL

    init(baseURL overrideURL: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseURL = overrideURL ?? appSupport.appendingPathComponent("TungBox", isDirectory: true)
        profilesURL = baseURL.appendingPathComponent("profiles.json")
        subscriptionsURL = baseURL.appendingPathComponent("subscriptions.json")
        subscriptionFoldersURL = baseURL.appendingPathComponent("subscriptions", isDirectory: true)
        profileFoldersURL = baseURL.appendingPathComponent("profiles", isDirectory: true)
        customRulesURL = baseURL.appendingPathComponent("custom-rules.json")
        ruleSetsURL = baseURL.appendingPathComponent("rule-sets", isDirectory: true)
        customRuleSetsURL = baseURL.appendingPathComponent("custom-rulesets", isDirectory: true)
        coreURL = baseURL.appendingPathComponent("core", isDirectory: true)
        coreBinaryURL = coreURL.appendingPathComponent("sing-box")
        tunRequestConfigURL = baseURL.appendingPathComponent("tun-request.json")
        tunRequestFlagURL = baseURL.appendingPathComponent("tun-request-enabled")
        tunRequestHeartbeatURL = baseURL.appendingPathComponent("tun-request-heartbeat")
        logURL = baseURL.appendingPathComponent("sing-box.log")
        appLogURL = baseURL.appendingPathComponent("app.log")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: ruleSetsURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: coreURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: subscriptionFoldersURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: profileFoldersURL, withIntermediateDirectories: true)
        migrateLegacyConfigLayout()
        pruneMissingProfileRecords()
        migrateLegacyCustomRules()
        cleanupObsoleteGeneratedFiles()
    }

    private func relativePath(for url: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(baseURL.standardizedFileURL.path.count + 1))
    }

    func subscriptionFolder(for id: UUID) -> URL {
        let url = subscriptionFoldersURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func profileFileName(id: UUID, subscriptionID: UUID? = nil) -> String {
        let url: URL
        if let subscriptionID {
            url = subscriptionFoldersURL.appendingPathComponent(subscriptionID.uuidString, isDirectory: true)
                .appendingPathComponent("config.json")
        } else {
            url = profileFoldersURL.appendingPathComponent(id.uuidString, isDirectory: true)
                .appendingPathComponent("config.json")
        }
        return relativePath(for: url)
    }

    private func migrateLegacyConfigLayout() {
        var profiles = loadProfiles()
        let subscriptions = loadSubscriptions()
        let links = Dictionary(grouping: subscriptions.compactMap { sub in
            sub.profileID.map { ($0, sub.id) }
        }, by: { $0.0 })
        var changed = false

        for index in profiles.indices {
            let profile = profiles[index]
            let linkedSubscriptionID = links[profile.id]?.count == 1 ? links[profile.id]?.first?.1 : nil
            let desiredName = profileFileName(id: profile.id, subscriptionID: linkedSubscriptionID)
            guard profile.fileName != desiredName else { continue }
            let source = baseURL.appendingPathComponent(profile.fileName)
            let destination = baseURL.appendingPathComponent(desiredName)
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: source.path),
               !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.moveItem(at: source, to: destination)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                profiles[index].fileName = desiredName
                changed = true
            }
        }

        for subscription in subscriptions {
            let folder = subscriptionFolder(for: subscription.id)
            migrateFile(
                from: baseURL.appendingPathComponent("rule-base-\(subscription.id.uuidString).json"),
                to: folder.appendingPathComponent("rule-base.json")
            )
            migrateFile(
                from: baseURL.appendingPathComponent("rule-projection-\(subscription.id.uuidString).json"),
                to: folder.appendingPathComponent("rule-projection.json")
            )
            let oldRuleSets = customRuleSetsURL.appendingPathComponent(subscription.id.uuidString, isDirectory: true)
            let newRuleSets = folder.appendingPathComponent("custom-rulesets", isDirectory: true)
            if FileManager.default.fileExists(atPath: oldRuleSets.path),
               !FileManager.default.fileExists(atPath: newRuleSets.path) {
                try? FileManager.default.moveItem(at: oldRuleSets, to: newRuleSets)
            }
        }
        if changed { saveProfiles(profiles) }
    }

    private func migrateFile(from source: URL, to destination: URL) {
        guard FileManager.default.fileExists(atPath: source.path),
              !FileManager.default.fileExists(atPath: destination.path) else { return }
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: source, to: destination)
    }

    private func pruneMissingProfileRecords() {
        let profiles = loadProfiles()
        let retained = profiles.filter { profile in
            FileManager.default.fileExists(atPath: baseURL.appendingPathComponent(profile.fileName).path)
        }
        guard retained.count != profiles.count else { return }
        let retainedIDs = Set(retained.map(\.id))
        saveProfiles(retained)

        var subscriptions = loadSubscriptions()
        var subscriptionsChanged = false
        for index in subscriptions.indices {
            if let profileID = subscriptions[index].profileID, !retainedIDs.contains(profileID) {
                subscriptions[index].profileID = nil
                subscriptionsChanged = true
            }
        }
        if subscriptionsChanged { saveSubscriptions(subscriptions) }
    }

    private func migrateLegacyCustomRules() {
        guard let data = try? Data(contentsOf: customRulesURL),
              let rules = try? JSONDecoder().decode([CustomRule].self, from: data) else { return }
        let grouped = Dictionary(grouping: rules, by: \.subscriptionID)
        var completed = true
        for (subscriptionID, subscriptionRules) in grouped {
            let url = customRulesURL(for: subscriptionID)
            guard let encoded = try? JSONEncoder.pretty.encode(subscriptionRules),
                  (try? encoded.write(to: url, options: .atomic)) != nil else {
                completed = false
                continue
            }
        }
        if completed { try? FileManager.default.removeItem(at: customRulesURL) }
    }

    /// Remove diagnostic and test copies created by older builds. These files are
    /// never user-authored and are not read by the current runtime.
    private func cleanupObsoleteGeneratedFiles() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in files {
            let name = url.lastPathComponent
            let obsolete = (name.hasPrefix("test_") && url.pathExtension.lowercased() == "json")
                || (name.hasPrefix("before-refresh-") && url.pathExtension.lowercased() == "json")
                || name == "tun-config-debug.json"
                || name == "tun-request-debug.json"
            if obsolete { try? FileManager.default.removeItem(at: url) }
        }
    }

    func loadProfiles() -> [ConfigProfile] {
        guard let data = try? Data(contentsOf: profilesURL) else { return [] }
        return (try? JSONDecoder().decode([ConfigProfile].self, from: data)) ?? []
    }

    func saveProfiles(_ profiles: [ConfigProfile]) {
        guard let data = try? JSONEncoder.pretty.encode(profiles) else { return }
        try? data.write(to: profilesURL, options: .atomic)
    }

    func loadSubscriptions() -> [Subscription] {
        guard let data = try? Data(contentsOf: subscriptionsURL) else { return [] }
        return (try? JSONDecoder().decode([Subscription].self, from: data)) ?? []
    }

    func saveSubscriptions(_ subscriptions: [Subscription]) {
        guard let data = try? JSONEncoder.pretty.encode(subscriptions) else { return }
        try? data.write(to: subscriptionsURL, options: .atomic)
    }

    func loadCustomRules() -> [CustomRule] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: subscriptionFoldersURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var rules: [CustomRule] = []
        for folder in folders {
            let url = folder.appendingPathComponent("custom-rules.json")
            guard let data = try? Data(contentsOf: url),
                  let stored = try? JSONDecoder().decode([CustomRule].self, from: data) else { continue }
            rules.append(contentsOf: stored)
        }
        // Keep reading a legacy file if migration could not write one of its groups.
        if let data = try? Data(contentsOf: customRulesURL),
           let legacy = try? JSONDecoder().decode([CustomRule].self, from: data) {
            let existing = Set(rules.map(\.id))
            rules.append(contentsOf: legacy.filter { !existing.contains($0.id) })
        }
        return rules
    }

    func saveCustomRules(_ rules: [CustomRule]) {
        let grouped = Dictionary(grouping: rules, by: \.subscriptionID)
        var completed = true
        for (subscriptionID, subscriptionRules) in grouped {
            guard let data = try? JSONEncoder.pretty.encode(subscriptionRules),
                  (try? data.write(to: customRulesURL(for: subscriptionID), options: .atomic)) != nil else {
                completed = false
                continue
            }
        }
        guard completed else {
            if let data = try? JSONEncoder.pretty.encode(rules) {
                try? data.write(to: customRulesURL, options: .atomic)
            }
            return
        }
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: subscriptionFoldersURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for folder in folders {
            guard let subscriptionID = UUID(uuidString: folder.lastPathComponent),
                  grouped[subscriptionID] == nil else { continue }
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("custom-rules.json"))
        }
        try? FileManager.default.removeItem(at: customRulesURL)
    }

    func customRulesURL(for subscriptionID: UUID) -> URL {
        subscriptionFolder(for: subscriptionID).appendingPathComponent("custom-rules.json")
    }

    func configURL(for profile: ConfigProfile) -> URL {
        let url = baseURL.appendingPathComponent(profile.fileName)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }

    func ruleBaseURL(for id: UUID) -> URL {
        subscriptionFolder(for: id).appendingPathComponent("rule-base.json")
    }

    func saveRuleBase(_ config: String, for id: UUID) throws {
        // Preserve the complete original subscription so no user data needs to be inferred.
        _ = try JSONSerialization.jsonObject(with: Data(config.utf8))
        try Data(config.utf8).write(to: ruleBaseURL(for: id), options: .atomic)
    }

    func baseRouteRules(for id: UUID) throws -> [[String: Any]] {
        let url = ruleBaseURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError.user("旧配置尚无独立规则来源。请先备份配置并刷新订阅，再编辑规则集；现有配置保持不变。")
        }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return (object?["route"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
    }

    func ruleProjectionURL(for id: UUID) -> URL { subscriptionFolder(for: id).appendingPathComponent("rule-projection.json") }

    func saveRuleProjection(_ text: String, for id: UUID) throws {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        let rules = (object?["route"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
        try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]).write(to: ruleProjectionURL(for: id), options: .atomic)
    }

    func verifyRuleProjection(_ rules: [[String: Any]], for id: UUID) throws {
        let url = ruleProjectionURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let old = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]] ?? []
        guard NSArray(array: rules).isEqual(to: old) else {
            throw NSError.user("配置规则已被手动修改，为避免覆盖已停止重建。请备份修改并刷新订阅后重试。")
        }
    }

    // MARK: - Custom rule sets (per subscription, one YAML file each)

    func ruleSetsFolder(for subscriptionID: UUID) -> URL {
        subscriptionFolder(for: subscriptionID).appendingPathComponent("custom-rulesets", isDirectory: true)
    }

    func ruleSetFileURL(for set: CustomRuleSet) -> URL {
        ruleSetsFolder(for: set.subscriptionID).appendingPathComponent("\(set.id.uuidString).yml")
    }

    /// Load every rule set for a subscription. Files that fail to parse/validate are
    /// returned separately so the UI can flag them and config generation can skip them.
    func loadRuleSets(for subscriptionID: UUID) -> (valid: [CustomRuleSet], invalid: [InvalidRuleSet]) {
        let folder = ruleSetsFolder(for: subscriptionID)
        guard FileManager.default.fileExists(atPath: folder.path) else { return ([], []) }
        let files: [URL]
        do { files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) }
        catch { return ([], [InvalidRuleSet(fileURL: folder, name: "规则集目录", reason: error.localizedDescription)]) }
        var valid: [CustomRuleSet] = []
        var invalid: [InvalidRuleSet] = []
        for file in files where file.pathExtension.lowercased() == "yml" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else {
                invalid.append(InvalidRuleSet(fileURL: file, name: file.deletingPathExtension().lastPathComponent, reason: "无法读取文件"))
                continue
            }
            switch RuleSetFormat.deserialize(text, subscriptionID: subscriptionID) {
            case .success(let set):
                valid.append(set)
            case .failure(let error):
                let name = nameHint(in: text) ?? file.deletingPathExtension().lastPathComponent
                invalid.append(InvalidRuleSet(fileURL: file, name: name, reason: error.message))
            }
        }
        let duplicateIDs = Dictionary(grouping: valid, by: \.id).filter { $0.value.count > 1 }.keys
        let duplicateNames = Dictionary(grouping: valid, by: \.name).filter { $0.value.count > 1 }.keys
        let duplicates = valid.filter { duplicateIDs.contains($0.id) || duplicateNames.contains($0.name) }
        if !duplicates.isEmpty {
            // Locate the actual files, including user-renamed copies.
            for file in files where file.pathExtension.lowercased() == "yml" {
                if let text = try? String(contentsOf: file, encoding: .utf8),
                   case .success(let set) = RuleSetFormat.deserialize(text, subscriptionID: subscriptionID),
                   duplicates.contains(set) {
                    invalid.append(InvalidRuleSet(fileURL: file, name: set.name, reason: "同一订阅中 UUID 或名称重复"))
                }
            }
            valid.removeAll { duplicates.contains($0) }
        }
        valid.sort { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        return (valid, invalid)
    }

    func saveRuleSet(_ set: CustomRuleSet) throws {
        let existing = loadRuleSets(for: set.subscriptionID).valid
        guard !existing.contains(where: { $0.id != set.id && $0.name == set.name }) else {
            throw NSError.user("同一订阅中已存在同名规则集")
        }
        let folder = ruleSetsFolder(for: set.subscriptionID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(RuleSetFormat.serialize(set).utf8).write(to: ruleSetFileURL(for: set), options: .atomic)
    }

    func deleteRuleSet(_ set: CustomRuleSet) throws {
        try FileManager.default.removeItem(at: ruleSetFileURL(for: set))
    }

    func deleteRuleSetFile(at url: URL) throws {
        let folder = url.deletingLastPathComponent()
        guard url.pathExtension.lowercased() == "yml",
              folder.lastPathComponent == "custom-rulesets",
              folder.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == subscriptionFoldersURL.standardizedFileURL else {
            throw NSError.user("只能删除当前规则集目录中的 YAML 文件")
        }
        try FileManager.default.removeItem(at: url)
    }

    /// Remove a subscription's entire rule-set folder (used when the subscription is deleted).
    func deleteRuleSetsFolder(for subscriptionID: UUID) throws {
        let folder = ruleSetsFolder(for: subscriptionID)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    func detachProfile(_ profile: ConfigProfile, from subscriptionID: UUID) throws -> ConfigProfile {
        var detached = profile
        let source = configURL(for: profile)
        detached.fileName = profileFileName(id: profile.id)
        let destination = configURL(for: detached)
        if FileManager.default.fileExists(atPath: source.path), source.standardizedFileURL != destination.standardizedFileURL {
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: source, to: destination)
        }
        let folder = subscriptionFolder(for: subscriptionID)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        return detached
    }

    /// Best-effort name lookup for an invalid file, so the UI can still label it.
    private func nameHint(in yaml: String) -> String? {
        for line in yaml.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("name:") {
                let v = t.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
                return v.replacingOccurrences(of: "\"", with: "")
            }
        }
        return nil
    }

    /// If the file at `url` is larger than `maxBytes`, rename it to `<url>.old`
    /// (replacing any prior .old). Returns silently for files that don't exist
    /// or are below the threshold. Used to keep user-owned text logs from
    /// growing without bound — the TUN daemon's root-owned logs use a parallel
    /// rotation in TunServiceManager.
    static func rotateIfNeeded(at url: URL, maxBytes: UInt64) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              size > maxBytes else {
            return
        }
        let oldURL = url.appendingPathExtension("old")
        try? fm.removeItem(at: oldURL)
        try? fm.moveItem(at: url, to: oldURL)
    }
}
