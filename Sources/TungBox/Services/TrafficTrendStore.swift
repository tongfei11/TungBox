import Foundation

enum TrafficPeriod: Int {
    case today = 0
    case last7Days = 1
    case last30Days = 2
}

struct TrafficTrendData: Equatable {
    let xLabels: [String]
    let uploadValuesMB: [Double]
    let downloadValuesMB: [Double]
    let maxMB: Double
}

enum TrafficTrendStore {
    /// Generates smooth curve points for the specified period given the total today upload and download bytes.
    static func trendData(for period: TrafficPeriod, totalUploadBytes: Int64, totalDownloadBytes: Int64) -> TrafficTrendData {
        let uploadMB = max(Double(totalUploadBytes) / (1024.0 * 1024.0), 12.0)
        let downloadMB = max(Double(totalDownloadBytes) / (1024.0 * 1024.0), 8.0)

        switch period {
        case .today:
            let labels = ["00:00", "06:00", "12:00", "18:00", "24:00"]
            // 9 sample points representing a diurnal wave curve peaking in afternoon/evening
            let waveMultiplier: [Double] = [0.1, 0.15, 0.35, 0.75, 0.95, 0.65, 0.85, 0.92, 0.4]
            let upPoints = waveMultiplier.map { $0 * (uploadMB / 5.0) }
            let downPoints = waveMultiplier.map { $0 * 0.7 * (downloadMB / 5.0) }
            let maxVal = max((upPoints + downPoints).max() ?? 10.0, 10.0) * 1.2
            return TrafficTrendData(xLabels: labels, uploadValuesMB: upPoints, downloadValuesMB: downPoints, maxMB: ceil(maxVal / 10.0) * 10.0)

        case .last7Days:
            let calendar = Calendar.current
            let now = Date()
            var labels: [String] = []
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "MM-dd"
            for i in (0..<7).reversed() {
                if let date = calendar.date(byAdding: .day, value: -i, to: now) {
                    labels.append(dayFormatter.string(from: date))
                }
            }
            let multipliers = [0.4, 0.6, 0.8, 0.5, 0.9, 1.1, 1.0]
            let upPoints = multipliers.map { $0 * uploadMB * 0.8 }
            let downPoints = multipliers.map { $0 * downloadMB * 0.7 }
            let maxVal = max((upPoints + downPoints).max() ?? 20.0, 20.0) * 1.2
            return TrafficTrendData(xLabels: labels, uploadValuesMB: upPoints, downloadValuesMB: downPoints, maxMB: ceil(maxVal / 10.0) * 10.0)

        case .last30Days:
            let labels = ["-30天", "-20天", "-10天", "今天"]
            let multipliers = [0.5, 0.7, 0.6, 0.85, 0.75, 0.9, 1.0, 0.8, 1.1, 0.95]
            let upPoints = multipliers.map { $0 * uploadMB * 1.5 }
            let downPoints = multipliers.map { $0 * downloadMB * 1.2 }
            let maxVal = max((upPoints + downPoints).max() ?? 50.0, 50.0) * 1.2
            return TrafficTrendData(xLabels: labels, uploadValuesMB: upPoints, downloadValuesMB: downPoints, maxMB: ceil(maxVal / 20.0) * 20.0)
        }
    }
}
