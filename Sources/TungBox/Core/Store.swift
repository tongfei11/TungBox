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
}

final class Store {
    let baseURL: URL
    let profilesURL: URL
    let subscriptionsURL: URL
    let customRulesURL: URL
    let ruleSetsURL: URL
    let coreURL: URL
    let coreBinaryURL: URL
    let tunRequestConfigURL: URL
    let tunRequestFlagURL: URL
    let logURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseURL = appSupport.appendingPathComponent("TungBox", isDirectory: true)
        profilesURL = baseURL.appendingPathComponent("profiles.json")
        subscriptionsURL = baseURL.appendingPathComponent("subscriptions.json")
        customRulesURL = baseURL.appendingPathComponent("custom-rules.json")
        ruleSetsURL = baseURL.appendingPathComponent("rule-sets", isDirectory: true)
        coreURL = baseURL.appendingPathComponent("core", isDirectory: true)
        coreBinaryURL = coreURL.appendingPathComponent("sing-box")
        tunRequestConfigURL = baseURL.appendingPathComponent("tun-request.json")
        tunRequestFlagURL = baseURL.appendingPathComponent("tun-request-enabled")
        logURL = baseURL.appendingPathComponent("sing-box.log")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: ruleSetsURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: coreURL, withIntermediateDirectories: true)
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
        guard let data = try? Data(contentsOf: customRulesURL) else { return [] }
        return (try? JSONDecoder().decode([CustomRule].self, from: data)) ?? []
    }

    func saveCustomRules(_ rules: [CustomRule]) {
        guard let data = try? JSONEncoder.pretty.encode(rules) else { return }
        try? data.write(to: customRulesURL, options: .atomic)
    }

    func configURL(for profile: ConfigProfile) -> URL {
        baseURL.appendingPathComponent(profile.fileName)
    }
}
