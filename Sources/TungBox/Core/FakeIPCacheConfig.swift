import Foundation

/// Keep synthetic DNS addresses resolvable after a Core reload or restart.
/// Paths and cache IDs belong to each runtime and must remain independent.
enum FakeIPCacheConfig {
    static func applying(to config: [String: Any]) -> [String: Any] {
        let dns = config["dns"] as? [String: Any] ?? [:]
        let typedFakeIP = (dns["servers"] as? [[String: Any]] ?? []).contains {
            ($0["type"] as? String)?.lowercased() == "fakeip"
        }
        let legacyFakeIP = (dns["fakeip"] as? [String: Any])?["enabled"] as? Bool == true
        guard typedFakeIP || legacyFakeIP else { return config }

        var result = config
        var experimental = config["experimental"] as? [String: Any] ?? [:]
        var cache = experimental["cache_file"] as? [String: Any] ?? [:]
        cache["enabled"] = true
        cache["store_fakeip"] = true
        experimental["cache_file"] = cache
        result["experimental"] = experimental
        return result
    }
}
