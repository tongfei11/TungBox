import Foundation

/// Core checks may download/read rule sets and wait for a subprocess. Keep this
/// work off MainActor and off the queue serving proxy/TUN switch requests.
struct RuleConfigValidator: Sendable {
    let operations = RuntimeCoordinator.Operations(
        queue: DispatchQueue(label: "com.tungbox.rule-validation", qos: .userInitiated)
    )

    func validate(_ text: String, directory: URL,
                  check: @escaping @Sendable (URL) throws -> Void) async throws {
        try await operations.perform {
            let url = directory.appendingPathComponent("rules-check-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: url) }
            try Data(text.utf8).write(to: url, options: .atomic)
            try check(url)
        }
    }
}
