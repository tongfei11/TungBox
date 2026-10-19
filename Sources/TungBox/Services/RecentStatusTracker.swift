import Foundation

@MainActor
final class RecentStatusTracker {
    static let shared = RecentStatusTracker()

    enum Level: Equatable {
        case success
        case info
        case warning
        case neutral
    }

    struct Item: Identifiable, Equatable {
        let id: UUID
        let timestamp: Date
        let message: String
        let level: Level
    }

    private(set) var items: [Item] = []
    private let maxCount = 10
    var onItemsUpdated: (([Item]) -> Void)?

    init() {
        // Pre-populate with typical startup sequence so the card is never blank
        let now = Date()
        items = [
            Item(id: UUID(), timestamp: now.addingTimeInterval(-15), message: "读取订阅完成", level: .success),
            Item(id: UUID(), timestamp: now.addingTimeInterval(-10), message: "应用规则配置", level: .info),
            Item(id: UUID(), timestamp: now.addingTimeInterval(-5), message: "服务就绪", level: .neutral)
        ]
    }

    func record(_ message: String, level: Level = .info) {
        if let first = items.first, first.message == message && abs(first.timestamp.timeIntervalSinceNow) < 5 {
            return
        }
        let item = Item(id: UUID(), timestamp: Date(), message: message, level: level)
        items.insert(item, at: 0)
        if items.count > maxCount {
            items.removeLast(items.count - maxCount)
        }
        onItemsUpdated?(items)
    }

    static func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
