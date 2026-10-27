import Foundation

enum TrafficHistoryRetention {
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// The dashboard exposes today plus the preceding 29 calendar days.
    static func retained(_ history: [String: [String: Int]], now: Date = Date(), calendar: Calendar = .current) -> [String: [String: Int]] {
        guard let oldest = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) else { return [:] }
        let firstKey = dayKey(for: oldest, calendar: calendar)
        let lastKey = dayKey(for: now, calendar: calendar)
        return history.filter { $0.key >= firstKey && $0.key <= lastKey }
    }
}
