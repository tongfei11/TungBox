import Foundation

enum SaturatingArithmetic {
    static func add(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard overflow else { return sum }
        return rhs >= 0 ? Int64.max : Int64.min
    }

    static func add(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard overflow else { return sum }
        return rhs >= 0 ? Int.max : Int.min
    }

    static func nonnegativeDifference(_ current: Int64, _ previous: Int64) -> Int64 {
        guard current >= previous else { return 0 }
        let (difference, overflow) = current.subtractingReportingOverflow(previous)
        return overflow ? Int64.max : max(0, difference)
    }

    static func nonnegativeDifference(_ current: Int, _ previous: Int) -> Int {
        guard current >= previous else { return 0 }
        let (difference, overflow) = current.subtractingReportingOverflow(previous)
        return overflow ? Int.max : max(0, difference)
    }

    static func clampedInt(_ value: Int64) -> Int {
        if value >= Int64(Int.max) { return Int.max }
        if value <= Int64(Int.min) { return Int.min }
        return Int(value)
    }

    static func rate(bytes: Int64, elapsed: TimeInterval) -> Int {
        guard bytes > 0, elapsed > 0 else { return 0 }
        let value = Double(bytes) / elapsed
        guard value.isFinite, value < Double(Int.max) else { return Int.max }
        return Int(value)
    }

    static func rate(bytes: Int, elapsed: TimeInterval) -> Int {
        guard bytes > 0, elapsed > 0 else { return 0 }
        let value = Double(bytes) / elapsed
        guard value.isFinite, value < Double(Int.max) else { return Int.max }
        return Int(value)
    }
}

enum SubscriptionTraffic {
    static func used(upload: Int64?, download: Int64?) -> Int64 {
        SaturatingArithmetic.add(max(0, upload ?? 0), max(0, download ?? 0))
    }

    static func isInconsistent(used: Int64, total: Int64?) -> Bool {
        guard let total else { return false }
        return total < 0 || used > total
    }
}
