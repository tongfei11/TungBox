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
    enum SubscriptionRoute: Equatable, Sendable {
        case systemProxy
        case direct
    }

    /// A subscription may itself require an already-running proxy app. Prefer the
    /// current macOS proxy, but retain a direct fallback for stale proxy settings.
    static func subscriptionRoutes(systemProxyConfigured: Bool) -> [SubscriptionRoute] {
        systemProxyConfigured ? [.systemProxy, .direct] : [.systemProxy]
    }

    static func systemProxyConfigured(in settings: [String: Any]) -> Bool {
        [
            "HTTPEnable",
            "HTTPSEnable",
            "SOCKSEnable",
            "ProxyAutoConfigEnable",
            "ProxyAutoDiscoveryEnable"
        ].contains { (settings[$0] as? Int) == 1 }
    }

    static func proxyDictionary(for route: SubscriptionRoute) -> [AnyHashable: Any]? {
        switch route {
        case .systemProxy: nil
        case .direct: directConnectionProxyDictionary
        }
    }

    /// Used only as a fallback after a configured system proxy cannot fetch the
    /// subscription, and for TUN requests that must ignore stale system settings.
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
