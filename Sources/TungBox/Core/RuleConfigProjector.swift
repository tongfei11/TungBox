import Foundation

/// Rebuilds route rules from an independent subscription baseline and explicit
/// user-rule snapshots. No window, storage, Core process or runtime side effects.
enum RuleConfigProjector {
    /// Undo only this mutation; keep later edits and never resurrect deleted subscriptions.
    static func restoringMutation(current: [CustomRule], previous: [CustomRule], attempted: [CustomRule],
                                  subscriptionExists: Bool) -> [CustomRule] {
        guard subscriptionExists else { return current }
        var result = current
        let ids = Set(previous.map(\.id)).union(attempted.map(\.id))
        for id in ids {
            let before = previous.first { $0.id == id }
            let after = attempted.first { $0.id == id }
            guard before != after, result.first(where: { $0.id == id }) == after else { continue }
            if let before {
                if let index = result.firstIndex(where: { $0.id == id }) { result[index] = before }
                else { result.insert(before, at: min(previous.firstIndex(where: { $0.id == id }) ?? result.count, result.count)) }
            } else { result.removeAll { $0.id == id } }
        }
        return result
    }

    struct Projection {
        let config: [String: Any]
        let routeRules: [[String: Any]]
    }

    static func project(config: [String: Any], subscriptionID: UUID, base: [[String: Any]],
                        customRules: [CustomRule], ruleSets: [CustomRuleSet], fallbackProxyTag: String) throws -> Projection {
        var config = config
        var specs = customRules.filter { $0.subscriptionID == subscriptionID && $0.enabled }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
            .map { (type: $0.type, value: $0.value, strategy: $0.strategy) }
        // Store supplies rule sets in their persisted order. An invalid dependency
        // excludes the whole set, never just its failing entries.
        for set in ruleSets where set.subscriptionID == subscriptionID && set.enabled {
            if RuleRouting.referenceError(for: set, config: config) != nil { continue }
            specs += set.rules.map { (type: $0.type, value: $0.value, strategy: set.outbound) }
        }
        var generated: [[String: Any]] = []
        for spec in specs {
            try RuleSetFormat.validate(type: spec.type, value: spec.value)
            if RuleRouting.referenceError(type: spec.type, value: spec.value, strategy: spec.strategy, config: config) != nil { continue }
            if spec.strategy != "REJECT" { config = RuleRouting.ensureOutboundSupport(in: config, strategy: spec.strategy) }
            generated.append(RuleRouting.customRouteRule(type: spec.type, value: spec.value, strategy: spec.strategy))
        }
        config = RuleRouting.rebuildingRules(in: config, base: base, generated: generated, fallbackProxyTag: fallbackProxyTag)
        return Projection(config: config, routeRules: (config["route"] as? [String: Any])?["rules"] as? [[String: Any]] ?? [])
    }

    /// Preserve the existing one-time legacy migration: remove exact known set
    /// projections, retaining other rules and all unrelated configuration fields.
    static func legacyBase(in config: [String: Any], ruleSets: [CustomRuleSet]) -> [String: Any] {
        var config = config
        var route = config["route"] as? [String: Any] ?? [:]
        var routeRules = route["rules"] as? [[String: Any]] ?? []
        for set in ruleSets {
            let generated = set.rules.map { RuleRouting.customRouteRule(type: $0.type, value: $0.value, strategy: set.outbound) }
            routeRules.removeAll { existing in generated.contains { NSDictionary(dictionary: $0).isEqual(to: existing) } }
        }
        route["rules"] = routeRules
        config["route"] = route
        return config
    }
}
