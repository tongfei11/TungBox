import Foundation

enum SubscriptionRefreshSchedule {
    static let defaultsKey = "subscriptionRefreshMinutes"
    static let options: [(title: String, minutes: Int)] = [
        ("关闭", 0), ("30 分钟", 30), ("1 小时", 60), ("2 小时", 120),
        ("4 小时", 240), ("6 小时", 360), ("12 小时", 720), ("24 小时", 1440)
    ]

    static func minutes(defaults: UserDefaults = .standard) -> Int {
        guard let saved = defaults.object(forKey: defaultsKey) as? Int,
              options.contains(where: { $0.minutes == saved }) else { return 60 }
        return saved
    }

    static func statusText(minutes: Int) -> String {
        if minutes == 0 { return "已关闭" }
        return minutes < 60 ? "每 \(minutes) 分钟" : "每 \(minutes / 60) 小时"
    }

    @MainActor
    static func makeTimer(minutes: Int, handler: @escaping @Sendable (Timer) -> Void) -> Timer? {
        guard minutes > 0 else { return nil }
        let timer = Timer(timeInterval: TimeInterval(minutes) * 60, repeats: true, block: handler)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
