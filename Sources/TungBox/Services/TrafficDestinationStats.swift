import Foundation

/// Total bytes remain authoritative; unobserved/legacy traffic has no known destination.
struct TrafficDestinationStats {
    let proxy: Int
    let direct: Int
    let other: Int

    init(total: Int, proxy: Int, direct: Int) {
        let total = max(0, total)
        self.proxy = min(max(0, proxy), total)
        self.direct = min(max(0, direct), total - self.proxy)
        self.other = total - self.proxy - self.direct
    }

    var total: Int { SaturatingArithmetic.add(SaturatingArithmetic.add(proxy, direct), other) }
    var ratios: [Double] {
        guard total > 0 else { return [0, 0, 0] }
        return [proxy, direct, other].map { Double($0) / Double(total) }
    }

    var percentages: [Int] {
        let values = ratios.map { $0 * 100 }
        var result = values.map { Int($0) }
        if total > 0 {
            let order = values.indices.sorted {
                let lhs = values[$0] - Double(result[$0])
                let rhs = values[$1] - Double(result[$1])
                return lhs == rhs ? $0 < $1 : lhs > rhs
            }
            for index in order.prefix(100 - result.reduce(0, +)) { result[index] += 1 }
        }
        return result
    }
}

struct TrafficDestinationTracker {
    private var previousByPort: [Int: [String: ConnectionInfo]] = [:]

    mutating func record(
        connectionsByPort: [Int: [ConnectionInfo]],
        totals: [Int: (upload: Int64, download: Int64)],
        previousTotals: [Int: (upload: Int64, download: Int64)],
        proxyTags: Set<String>
    ) -> (proxy: Int, direct: Int) {
        var proxy = 0
        var direct = 0
        for (port, current) in totals {
            let connections = connectionsByPort[port] ?? []
            let previous = previousByPort[port] ?? [:]
            previousByPort[port] = connections.reduce(into: [:]) { $0[$1.id] = $1 }
            guard let baseline = previousTotals[port], current.upload >= baseline.upload,
                  current.download >= baseline.download else { continue }

            var proxyUp = 0, proxyDown = 0, directUp = 0, directDown = 0
            for connection in connections {
                let old = previous[connection.id]
                let up = SaturatingArithmetic.nonnegativeDifference(connection.upload, old?.upload ?? 0)
                let down = SaturatingArithmetic.nonnegativeDifference(connection.download, old?.download ?? 0)
                switch connection.outbound.lowercased() {
                case "direct", "直连":
                    directUp = SaturatingArithmetic.add(directUp, up)
                    directDown = SaturatingArithmetic.add(directDown, down)
                case "", "reject", "block", "dns": break
                default:
                    guard proxyTags.contains(connection.outbound) else { continue }
                    proxyUp = SaturatingArithmetic.add(proxyUp, up)
                    proxyDown = SaturatingArithmetic.add(proxyDown, down)
                }
            }
            // Only classify coherent observations within the process-level delta.
            // Closed short connections and inconsistent counters remain in Other.
            let upBudget = SaturatingArithmetic.clampedInt(SaturatingArithmetic.nonnegativeDifference(current.upload, baseline.upload))
            let downBudget = SaturatingArithmetic.clampedInt(SaturatingArithmetic.nonnegativeDifference(current.download, baseline.download))
            if SaturatingArithmetic.add(proxyUp, directUp) <= upBudget {
                proxy = SaturatingArithmetic.add(proxy, proxyUp)
                direct = SaturatingArithmetic.add(direct, directUp)
            }
            if SaturatingArithmetic.add(proxyDown, directDown) <= downBudget {
                proxy = SaturatingArithmetic.add(proxy, proxyDown)
                direct = SaturatingArithmetic.add(direct, directDown)
            }
        }
        return (proxy, direct)
    }
}
