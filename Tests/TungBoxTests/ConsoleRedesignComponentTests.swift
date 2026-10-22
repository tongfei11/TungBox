import XCTest
@testable import TungBox

final class ConsoleRedesignComponentTests: XCTestCase {
    func testCountryFlagHelperIdentifiesCommonRegions() {
        XCTAssertEqual(CountryFlagHelper.flag(for: "香港 11"), "🇭🇰")
        XCTAssertEqual(CountryFlagHelper.flag(for: "HK - BGP 01"), "🇭🇰")
        XCTAssertEqual(CountryFlagHelper.flag(for: "UDP 美国 03"), "🇺🇸")
        XCTAssertEqual(CountryFlagHelper.flag(for: "ATLS 日本 03"), "🇯🇵")
        XCTAssertEqual(CountryFlagHelper.flag(for: "台湾 02"), "🇹🇼")
        XCTAssertEqual(CountryFlagHelper.flag(for: "英国 01"), "🇬🇧")
        XCTAssertEqual(CountryFlagHelper.flag(for: "土耳其 01"), "🇹🇷")
        XCTAssertEqual(CountryFlagHelper.flag(for: "未知节点"), "🌐")
    }

    func testProcessResourceProbeFormattedOutput() {
        let bytes: UInt64 = 65 * 1024 * 1024 + 300 * 1024
        XCTAssertEqual(ProcessResourceProbe.formattedMemory(bytes: bytes), "65.3 MB")
        XCTAssertEqual(ProcessResourceProbe.memoryRatio(bytes: bytes, baselineMB: 512), 0.1275253, accuracy: 0.000001)
    }

    @MainActor
    func testRecentStatusTrackerRecordsAndLimitsCount() {
        let tracker = RecentStatusTracker()
        let initialCount = tracker.items.count
        XCTAssertGreaterThan(initialCount, 0)

        tracker.record("测试事件 1", level: .success)
        XCTAssertEqual(tracker.items.first?.message, "测试事件 1")
        XCTAssertEqual(tracker.items.first?.level, .success)

        for i in 2...15 {
            tracker.record("批量事件 \(i)", level: .info)
        }
        XCTAssertLessThanOrEqual(tracker.items.count, 10)
    }

    func testTrafficTrendStoreDataGeneration() {
        let todayData = TrafficTrendStore.trendData(for: .today, totalUploadBytes: 1000 * 1024 * 1024, totalDownloadBytes: 500 * 1024 * 1024)
        XCTAssertEqual(todayData.xLabels.count, 5)
        XCTAssertFalse(todayData.uploadValuesMB.isEmpty)
        XCTAssertFalse(todayData.downloadValuesMB.isEmpty)
        XCTAssertGreaterThan(todayData.maxMB, 0)

        let weekData = TrafficTrendStore.trendData(for: .last7Days, totalUploadBytes: 1000 * 1024 * 1024, totalDownloadBytes: 500 * 1024 * 1024)
        XCTAssertEqual(weekData.xLabels.count, 7)
    }

    @MainActor
    func testSpeedRingBufferAccumulationAndTrimming() {
        let buffer = SpeedRingBuffer()
        for i in 1...30 {
            buffer.record(uploadSpeedBytes: i * 1024, downloadSpeedBytes: (i + 1) * 1024)
        }
        XCTAssertLessThanOrEqual(buffer.uploadSamples.count, 25)
        XCTAssertLessThanOrEqual(buffer.downloadSamples.count, 25)
        XCTAssertEqual(buffer.uploadSamples.last, 30.0)
        XCTAssertEqual(buffer.downloadSamples.last, 31.0)
    }

    @MainActor
    func testModernDashboardGridLayoutContainsAllCards() {
        let cards = (0..<9).map { _ -> NSView in
            let v = NSView()
            v.translatesAutoresizingMaskIntoConstraints = false
            return v
        }
        let grid = HomeDashboardLayout.dashboardGrid(
            systemProxyCard: cards[0],
            tunCard: cards[1],
            outboundCard: cards[2],
            currentNodeCard: cards[3],
            trafficTrendCard: cards[4],
            realtimeSpeedCard: cards[5],
            activeConnectionsCard: cards[6],
            trafficDestinationCard: cards[7],
            recentStatusCard: cards[8]
        )
        XCTAssertEqual(grid.subviews.count, 9)
        for card in cards {
            XCTAssertTrue(grid.subviews.contains(card))
        }
    }

    @MainActor
    func testSubscriptionItemFormatsDomainTrafficAndExpiry() {
        let itemView = MD3SubscriptionItemView(frame: NSRect(x: 0, y: 0, width: 350, height: 150))
        let date = Calendar.current.date(byAdding: .day, value: 30, to: Date())
        let sub = Subscription(
            id: UUID(),
            name: "萌喵加速",
            url: "https://sub.cat.net/clash",
            profileID: nil,
            updatedAt: Date(),
            lastError: nil,
            upload: 10 * 1024 * 1024 * 1024,
            download: 40 * 1024 * 1024 * 1024,
            total: 500 * 1024 * 1024 * 1024,
            expiresAt: date
        )

        itemView.configure(with: sub, selected: true)
        XCTAssertEqual(itemView.titleLabel.stringValue, "萌喵加速")
        XCTAssertEqual(itemView.domainLabel.stringValue, "sub.cat.net")
        XCTAssertEqual(itemView.trafficPercentLabel.stringValue, "10.0%")
        XCTAssertEqual(itemView.expireTitleLabel.stringValue, "到期时间")
        XCTAssertFalse(itemView.expiresLabel.stringValue.isEmpty)
    }

    @MainActor
    func testRuleTableCellPillsAndStrategies() {
        let domainRule = RuleInfo(customRuleID: UUID(), enabled: true, id: "1", type: "DOMAIN-SUFFIX",
                                  value: "zdxlz.com", strategy: "DIRECT", count: "0", note: "自定义", isSection: false)
        let typeCell = RuleTableCell.make(for: domainRule, columnID: "type")
        XCTAssertFalse(typeCell.subviews.isEmpty)

        let strategyCell = RuleTableCell.make(for: domainRule, columnID: "strategy")
        guard let label = strategyCell.subviews.first as? NSTextField else {
            XCTFail("Strategy cell missing NSTextField")
            return
        }
        XCTAssertEqual(label.stringValue, "DIRECT")

        let sectionRule = RuleInfo(customRuleID: nil, enabled: false, id: "", type: "",
                                   value: "# 自定义规则 (4)", strategy: "", count: "", note: "", isSection: true)
        let sectionEnabledCell = RuleTableCell.make(for: sectionRule, columnID: "enabled")
        XCTAssertTrue(sectionEnabledCell.subviews.first is NSImageView)
    }

    @MainActor
    func testCenteredPillLabelCalculatesOffsetAndPadding() throws {
        let label = CenteredPillLabel(labelWithString: "DOMAIN-SUFFIX")
        label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        XCTAssertTrue(label.cell is CenteredPillTextFieldCell)

        let intrinsic = label.intrinsicContentSize
        XCTAssertGreaterThan(intrinsic.width, 90)

        let cell = try XCTUnwrap(label.cell as? CenteredPillTextFieldCell)
        let drawing = cell.drawingRect(forBounds: NSRect(x: 0, y: 0, width: 120, height: 22))
        XCTAssertGreaterThan(drawing.origin.y, 0)
        XCTAssertLessThan(drawing.origin.y, 8)
    }

    @MainActor
    func testRecentStatusTrackerDeduplication() {
        let tracker = RecentStatusTracker()
        tracker.record("重复事件", level: .success)
        let countAfterFirst = tracker.items.count
        tracker.record("重复事件", level: .success)
        XCTAssertEqual(tracker.items.count, countAfterFirst)

        tracker.record("不同事件", level: .info)
        XCTAssertEqual(tracker.items.count, countAfterFirst + 1)
        XCTAssertEqual(tracker.items.first?.message, "不同事件")
    }

    func testHostsIPAddressValidation() {
        XCTAssertTrue(DNSConfig.isValidIPAddress("127.0.0.1"))
        XCTAssertTrue(DNSConfig.isValidIPAddress("192.168.1.1"))
        XCTAssertTrue(DNSConfig.isValidIPAddress("::1"))
        XCTAssertTrue(DNSConfig.isValidIPAddress("240e:ff:e020:99b::1"))
        XCTAssertFalse(DNSConfig.isValidIPAddress("not.an.ip"))
        XCTAssertFalse(DNSConfig.isValidIPAddress("999.999.999.999"))
        XCTAssertFalse(DNSConfig.isValidIPAddress(""))
    }

}
