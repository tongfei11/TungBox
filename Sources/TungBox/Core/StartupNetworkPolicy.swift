import Foundation

/// Opens automatic network work only after the first confirmed proxy/TUN connection.
/// A fresh installation must be able to import a reachable subscription and connect
/// without touching GitHub first.
struct FirstConnectionGate {
    private(set) var hasConnected = false

    mutating func markConnected() -> Bool {
        guard !hasConnected else { return false }
        hasConnected = true
        return true
    }
}

enum StartupNetworkPolicy {
    /// Subscription endpoints are the only network dependency allowed before the
    /// first proxy connection. Force them to use the physical network instead of a
    /// stale 127.0.0.1 system-proxy setting left by an earlier app/session.
    static var directConnectionProxyDictionary: [AnyHashable: Any] {
        [
            "HTTPEnable": 0,
            "HTTPSEnable": 0,
            "SOCKSEnable": 0
        ]
    }

    static func postConnectionProxyDictionary(proxyPort: Int?) -> [AnyHashable: Any] {
        guard let proxyPort else { return directConnectionProxyDictionary }
        return [
            "HTTPEnable": 1,
            "HTTPProxy": "127.0.0.1",
            "HTTPPort": proxyPort,
            "HTTPSEnable": 1,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": proxyPort,
            "SOCKSEnable": 0
        ]
    }
}
