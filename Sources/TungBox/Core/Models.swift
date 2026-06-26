import Foundation

struct ConfigProfile: Codable, Equatable {
    var id: UUID
    var name: String
    var fileName: String
    var updatedAt: Date
}

struct Subscription: Codable, Equatable {
    var id: UUID
    var name: String
    var url: String
    var profileID: UUID?
    var updatedAt: Date?
    var lastError: String?
    /// 标准 `subscription-userinfo` 响应头里的流量信息（字节数）。
    var upload: Int64?
    var download: Int64?
    var total: Int64?
    /// 套餐到期时间（来自 expire= unix 时间戳）。
    var expiresAt: Date?
}

struct NodeInfo {
    var tag: String
    var type: String
    var server: String
    var delay: String
    /// Stream transport (ws / grpc / http / quic / httpupgrade), empty for raw TCP.
    var transport: String = ""
    /// Whether the outbound carries UDP. Most proxy protocols relay UDP unless
    /// `network` is restricted to "tcp"; QUIC-based ones (hysteria2/tuic) are UDP.
    var supportsUDP: Bool = true
    /// Whether TLS is enabled on the outbound.
    var tls: Bool = false
}

struct NodeGroupInfo {
    var tag: String
    var type: String
    var members: [String]
    var current: String
}

struct RuleInfo {
    var customRuleID: UUID?
    var enabled: Bool
    var id: String
    var type: String
    var value: String
    var strategy: String
    var count: String
    var note: String
    var isSection: Bool
}

struct CustomRule: Codable, Equatable {
    var id: UUID
    var subscriptionID: UUID
    var type: String
    var value: String
    var strategy: String
    var note: String
    var enabled: Bool
    var createdAt: Date
}

struct ConnectionInfo {
    var id: String
    var network: String
    var status: String
    var source: String
    var destination: String
    var rule: String
    var outbound: String
    var upload: Int
    var download: Int
    var uploadSpeed: Int = 0
    var downloadSpeed: Int = 0
}

struct CoreRelease {
    var version: String
    var tag: String
    var assetName: String
    var downloadURL: URL
}

struct AppRelease {
    var version: String
    var tag: String
    var name: String
    var body: String
    var htmlURL: URL
    var publishedAt: Date?
}

enum AppUpdateCheckState {
    case notChecked
    case checking
    case upToDate(AppRelease)
    case available(AppRelease)
    case failed(String)
}

enum TungBoxConfig {
    static let tagAuto = "自动选择"
    static let tagManual = "节点选择"
    static let tagGlobal = "全局"
    static let tagDirect = "direct"
    static let tagBlock = "block"

    static let ruleSetPrivate = "geosite-private"
    static let ruleSetCN = "geosite-cn"
    static let ruleSetGeoIPCN = "geoip-cn"
    static let ruleSetGeolocationNotCN = "geosite-geolocation-!cn"

    static let defaultRuleSetURLs = [
        ruleSetPrivate: "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-private.srs",
        ruleSetCN: "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
        ruleSetGeolocationNotCN: "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-!cn.srs",
        ruleSetGeoIPCN: "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"
    ]

    static let urlTestURL = "https://www.gstatic.com/generate_204"

    // urltest 组的自动测速参数。订阅刷新时把这两个值塞进生成的 outbound：
    // - interval：多久重新测一次（分钟）。sing-box 收的是 duration 字符串 "3m"。
    // - tolerance：当前节点比最快节点慢多少毫秒之内不切换（避免来回抖动）。
    // 改动只影响下次订阅刷新生成的配置，旧 profile 不动。
    static let urlTestIntervalDefaultMinutes = 3
    static let urlTestToleranceDefaultMs = 50
    static let urlTestIntervalOptionsMinutes: [Int] = [1, 3, 5, 10, 30]
    static let urlTestToleranceOptionsMs: [Int] = [0, 30, 50, 100, 150, 300]

    static var urlTestIntervalMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: "urlTestIntervalMinutes")
        return stored > 0 ? stored : urlTestIntervalDefaultMinutes
    }

    static var urlTestIntervalString: String {
        "\(urlTestIntervalMinutes)m"
    }

    static var urlTestTolerance: Int {
        // object(forKey:) so 0 is a valid stored value (默认 50，但用户选 0 也应保留)
        if let stored = UserDefaults.standard.object(forKey: "urlTestToleranceMs") as? Int {
            return stored
        }
        return urlTestToleranceDefaultMs
    }

    static let clashAPIListen = "127.0.0.1:9090"
    static let clashAPIURL = "http://127.0.0.1:9090"
    static let mixedPort = 7890
    // The TUN daemon runs as an independent process; it keeps a clash_api for mode
    // routing but on a dedicated port so it never collides with the user proxy's 9090.
    static let tunDaemonClashPort = 9091

    static func ruleSetURL(for tag: String) -> String {
        let stored = UserDefaults.standard.string(forKey: ruleSetURLKey(tag))?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty {
            return stored
        }
        return defaultRuleSetURLs[tag] ?? ""
    }

    static func setRuleSetURL(_ url: String, for tag: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == defaultRuleSetURLs[tag] {
            UserDefaults.standard.removeObject(forKey: ruleSetURLKey(tag))
        } else {
            UserDefaults.standard.set(trimmed, forKey: ruleSetURLKey(tag))
        }
    }

    static func resolvedRuleSetURL(for tag: String, subscriptionURLs: [String: String]) -> String {
        let stored = UserDefaults.standard.string(forKey: ruleSetURLKey(tag))?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty {
            return stored
        }
        if let subscriptionURL = subscriptionURLs[tag]?.trimmingCharacters(in: .whitespacesAndNewlines), !subscriptionURL.isEmpty {
            return subscriptionURL
        }
        return defaultRuleSetURLs[tag] ?? ""
    }

    private static func ruleSetURLKey(_ tag: String) -> String {
        "ruleSetURL.\(tag)"
    }
}
