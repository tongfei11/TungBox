import AppKit
import XCTest
@testable import TungBox

final class TrafficDestinationTests: XCTestCase {
    private func connection(_ id: String, _ outbound: String, up: Int = 0, down: Int) -> ConnectionInfo {
        ConnectionInfo(id: id, network: "tcp", status: "", source: "", destination: "", rule: "",
                       outbound: outbound, upload: up, download: down)
    }

    func testClassificationUsesBytesAndKeepsUnobservedClosedTrafficInOther() {
        var tracker = TrafficDestinationTracker()
        let baseline: [Int: (upload: Int64, download: Int64)] = [9090: (0, 100)]
        let first = tracker.record(connectionsByPort: [9090: [connection("p", "proxy", down: 100)]],
                                   totals: baseline, previousTotals: [:], proxyTags: ["proxy"])
        XCTAssertEqual(first.proxy, 0, "首次快照只建基准")
        let delta = tracker.record(connectionsByPort: [9090: [connection("p", "proxy", down: 400),
                                                              connection("d", "DIRECT", down: 50)]],
                                   totals: [9090: (0, 500)], previousTotals: baseline, proxyTags: ["proxy"])
        let stats = TrafficDestinationStats(total: 400, proxy: delta.proxy, direct: delta.direct)
        XCTAssertEqual(stats.proxy, 300)
        XCTAssertEqual(stats.direct, 50)
        XCTAssertEqual(stats.other, 50)
        XCTAssertEqual(stats.total, 400)
        XCTAssertEqual(stats.ratios[0], 0.75)
        XCTAssertEqual(stats.percentages.reduce(0, +), 100)
        let closed = tracker.record(connectionsByPort: [9090: []], totals: [9090: (0, 600)],
                                    previousTotals: [9090: (0, 500)], proxyTags: ["proxy"])
        XCTAssertEqual(TrafficDestinationStats(total: 100, proxy: closed.proxy, direct: closed.direct).other, 100)
    }

    func testPortsWithSameConnectionIDRestartAndRecoverIndependently() {
        var tracker = TrafficDestinationTracker()
        let baseline: [Int: (upload: Int64, download: Int64)] = [9090: (0, 100), 9091: (0, 100)]
        _ = tracker.record(connectionsByPort: [9090: [connection("same", "proxy", down: 100)],
                                               9091: [connection("same", "direct", down: 100)]],
                           totals: baseline, previousTotals: [:], proxyTags: ["proxy"])
        let delta = tracker.record(connectionsByPort: [9090: [connection("same", "proxy", down: 20)],
                                                      9091: [connection("same", "direct", down: 150)]],
                                   totals: [9090: (0, 20), 9091: (0, 150)], previousTotals: baseline, proxyTags: ["proxy"])
        XCTAssertEqual(delta.proxy, 0, "重启端口只重设基准")
        XCTAssertEqual(delta.direct, 50)
        let recovered = tracker.record(connectionsByPort: [9090: [connection("same", "proxy", down: 40)]],
                                       totals: [9090: (0, 40)], previousTotals: [9091: (0, 150)], proxyTags: ["proxy"])
        XCTAssertEqual(recovered.proxy, 0, "失败端口恢复后重新设基准")
        let next = tracker.record(connectionsByPort: [9090: [connection("same", "proxy", down: 60)]],
                                  totals: [9090: (0, 60)], previousTotals: [9090: (0, 40)], proxyTags: ["proxy"])
        XCTAssertEqual(next.proxy, 20)
    }

    func testIncoherentCountersAndUnknownRoutesDoNotInventClassifiedBytes() {
        var tracker = TrafficDestinationTracker()
        _ = tracker.record(connectionsByPort: [9090: []], totals: [9090: (0, 0)], previousTotals: [:], proxyTags: ["proxy"])
        let delta = tracker.record(connectionsByPort: [9090: [connection("p", "proxy", down: 200),
                                                              connection("d", "direct", up: 10, down: 0),
                                                              connection("u", "mystery-route", up: 20, down: 0)]],
                                   totals: [9090: (30, 100)], previousTotals: [9090: (0, 0)], proxyTags: ["proxy"])
        XCTAssertEqual(delta.proxy, 0)
        XCTAssertEqual(delta.direct, 10)
        XCTAssertEqual(TrafficDestinationStats(total: 130, proxy: delta.proxy, direct: delta.direct).other, 120)
        let legacy = TrafficDestinationStats(total: 760, proxy: 0, direct: 0)
        XCTAssertEqual(legacy.other, 760)
        XCTAssertEqual(legacy.percentages, [0, 0, 100])
        XCTAssertEqual(TrafficDestinationStats(total: 0, proxy: 0, direct: 0).percentages, [0, 0, 0])
    }

    func testHistoryRetainsExactlyThirtyCalendarDaysAcrossYearBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 12)))
        var history: [String: [String: Int]] = [:]
        for offset in -60...1 {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: now))
            history[TrafficHistoryRetention.dayKey(for: date, calendar: calendar)] = ["upload": 10, "download": 20, "proxy": 5]
        }
        let retained = TrafficHistoryRetention.retained(history, now: now, calendar: calendar)
        XCTAssertEqual(retained.count, 30)
        XCTAssertNotNil(retained["2025-12-17"])
        XCTAssertNil(retained["2025-12-16"])
        XCTAssertNotNil(retained["2026-01-15"])
        XCTAssertNil(retained["2026-01-16"])
        XCTAssertEqual(retained.values.reduce(0) { $0 + ($1["upload"] ?? 0) }, 300)
        XCTAssertEqual(TrafficHistoryRetention.retained(retained, now: now, calendar: calendar), retained)
    }

    @MainActor
    func testTotalTrafficFitsSummaryWidthWithoutChangingDetailPrecision() {
        let bytes = Int(760.4 * 1024 * 1024)
        XCTAssertEqual(MainWindowController.formattedTrafficBytes(bytes, fractionDigits: 0), "760 MB")
        XCTAssertEqual(MainWindowController.formattedTrafficBytes(bytes), "760.4 MB")
        for total in [bytes, Int(999.9 * 1024 * 1024), Int(1023.9 * 1024), Int.max] {
            let text = MainWindowController.formattedTrafficBytes(total, fractionDigits: 0)
            let font = MainWindowController.trafficSummaryFont(for: text)
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(width, 125, text)
        }
    }
}
