import Foundation

/// Serializes selector writes from clicks and background restoration. Observations
/// made before/during a write cannot replace the newer optimistic selection.
@MainActor
final class SelectorSelectionCoordinator {
    struct Selection: Equatable, Sendable {
        let group: String
        let node: String
    }

    private var tail: Task<Void, Never>?
    private var pendingWrites = 0
    private var revision = 0
    private var choices: [UUID: [String: String]] = [:]

    var observationToken: Int? { pendingWrites == 0 ? revision : nil }

    func acceptsObservation(_ token: Int?) -> Bool {
        token != nil && pendingWrites == 0 && token == revision
    }

    func remember(profile: UUID, group: String, node: String) {
        choices[profile, default: [:]][group] = node
        revision += 1
    }

    func selections(in text: String, profile: UUID) -> [Selection] {
        guard let config = ConfigCodec.parseObject(from: text),
              let outbounds = config["outbounds"] as? [[String: Any]] else { return [] }
        return outbounds.compactMap { outbound in
            guard (outbound["type"] as? String)?.lowercased() == "selector",
                  let group = outbound["tag"] as? String else { return nil }
            let members = outbound["outbounds"] as? [String] ?? []
            let preferred = choices[profile]?[group]
            let node = preferred.flatMap { members.contains($0) ? $0 : nil } ?? outbound["default"] as? String
            guard let node, !node.isEmpty, members.contains(node) else { return nil }
            return Selection(group: group, node: node)
        }
    }

    /// Waits for an already dispatched old PUT to finish before sending the newer
    /// choice. An epoch check alone cannot retract an in-flight network request.
    func apply(selections: [Selection], ports: [Int],
               isCurrent: @escaping @MainActor () -> Bool,
               write: @escaping @MainActor (Selection, Int) async throws -> Void,
               finishPort: @escaping @MainActor (Int) async -> Void = { _ in }) async throws -> Bool {
        let previous = tail
        pendingWrites += 1
        revision += 1
        let operation = Task { @MainActor in
            await previous?.value
            guard isCurrent() else { return false }
            for port in ports {
                for selection in selections {
                    guard isCurrent() else { return false }
                    try await write(selection, port)
                    guard isCurrent() else { return false }
                }
                await finishPort(port)
                guard isCurrent() else { return false }
            }
            return true
        }
        let completion = Task { @MainActor in _ = await operation.result }
        tail = completion
        defer {
            pendingWrites -= 1
            revision += 1
            if pendingWrites == 0 { tail = nil }
        }
        return try await operation.value
    }
}
