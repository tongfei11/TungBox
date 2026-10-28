import Foundation

enum NodeDelayTestPolicy {
    /// Explicit outbound probes remain valid across a live mode-only switch.
    /// Other configuration changes must still invalidate the running test.
    static func configurationIdentity(_ text: String) -> Data? {
        guard let data = text.data(using: .utf8),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if var experimental = config["experimental"] as? [String: Any],
           var api = experimental["clash_api"] as? [String: Any] {
            api.removeValue(forKey: "default_mode")
            experimental["clash_api"] = api
            config["experimental"] = experimental
        }
        return try? JSONSerialization.data(withJSONObject: config, options: .sortedKeys)
    }

    static func refreshAfterModeChange(from previous: String, to next: String, pendingRefresh: Bool = false) -> Bool {
        ["rule", "global"].contains(next.lowercased())
            && (previous.caseInsensitiveCompare("Direct") == .orderedSame || pendingRefresh)
    }

    @MainActor
    static func runtimeIsReady(
        tunStartup: Task<Bool, Never>?,
        isCurrent: () -> Bool
    ) async -> Bool {
        if let tunStartup, !(await tunStartup.value) { return false }
        return !Task.isCancelled && isCurrent()
    }
}
