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
    let customRulesURL: URL
    let ruleSetsURL: URL
    let coreURL: URL
    let coreBinaryURL: URL
    let tunRequestConfigURL: URL
    let tunRequestFlagURL: URL
    let tunRequestHeartbeatURL: URL
    let logURL: URL
    let appLogURL: URL

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
        tunRequestHeartbeatURL = baseURL.appendingPathComponent("tun-request-heartbeat")
        logURL = baseURL.appendingPathComponent("sing-box.log")
        appLogURL = baseURL.appendingPathComponent("app.log")
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
