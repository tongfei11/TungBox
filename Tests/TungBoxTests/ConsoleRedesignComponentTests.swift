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
        let formatted = ProcessResourceProbe.formattedMemory(bytes: bytes)
        XCTAssertTrue(formatted.contains("MB"))
        let ratio = ProcessResourceProbe.memoryRatio(bytes: bytes, baselineMB: 512.0)
        XCTAssertGreaterThan(ratio, 0.0)
        XCTAssertLessThanOrEqual(ratio, 1.0)
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
        let cards = (0..<9).map { i -> NSView in
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
    func testMD3ThemeChangeNotifiesChartViews() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let wave = SpeedWaveChartView(frame: NSRect(x: 0, y: 0, width: 200, height: 60))
        let trend = TrafficTrendChartView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
        let donut = TrafficDonutChartView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let ring = MemoryRingView(frame: NSRect(x: 0, y: 0, width: 68, height: 28))
        let eq = EqualizerBarsView(frame: NSRect(x: 0, y: 0, width: 54, height: 18))

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        window.contentView = container
        [wave, trend, donut, ring, eq].forEach { container.addSubview($0) }

        wave.themeChanged()
        trend.themeChanged()
        donut.themeChanged()
        ring.themeChanged()
        eq.themeChanged()

        XCTAssertTrue(wave.needsDisplay)
        XCTAssertTrue(trend.needsDisplay)
        XCTAssertTrue(donut.needsDisplay)
        XCTAssertTrue(ring.needsDisplay)
        XCTAssertTrue(eq.needsDisplay)
    }

    @MainActor
    func testRedesignedSubscriptionItemViewAndThemeSwitching() {
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

        // Iterate through all 10 color schemes in dark and light modes
        for isDark in [true, false] {
            MD3.isDark = isDark
            for schemeIdx in 0..<MD3.colorSchemes.count {
                MD3.currentSchemeIndex = schemeIdx
                itemView.themeChanged()
                XCTAssertNotNil(itemView.subviews.first?.layer?.backgroundColor)
            }
        }
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
    func testConnectionPillCellAndStatusCell() {
        let pillCell = ConnectionPillCell(frame: NSRect(x: 0, y: 0, width: 60, height: 30))
        pillCell.update(network: "TCP")
        XCTAssertEqual(pillCell.label.stringValue, "tcp")

        let statusCell = ConnectionStatusCell(frame: NSRect(x: 0, y: 0, width: 80, height: 30))
        statusCell.update(status: "成功")
        XCTAssertEqual(statusCell.label.stringValue, "成功")

        statusCell.update(status: "pending")
        XCTAssertEqual(statusCell.label.stringValue, "pending")

        for isDark in [true, false] {
            MD3.isDark = isDark
            for schemeIdx in 0..<MD3.colorSchemes.count {
                MD3.currentSchemeIndex = schemeIdx
                pillCell.themeChanged()
                statusCell.themeChanged()
            }
        }
    }

    @MainActor
    func testCenteredPillLabelCalculatesOffsetAndPadding() {
        let label = CenteredPillLabel(labelWithString: "DOMAIN-SUFFIX")
        label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        XCTAssertTrue(label.cell is CenteredPillTextFieldCell)

        let intrinsic = label.intrinsicContentSize
        XCTAssertGreaterThan(intrinsic.width, 90)

        if let cell = label.cell as? CenteredPillTextFieldCell {
            let drawing = cell.drawingRect(forBounds: NSRect(x: 0, y: 0, width: 120, height: 22))
            XCTAssertGreaterThan(drawing.origin.y, 0)
            XCTAssertLessThan(drawing.origin.y, 8)
        }
    }

    @MainActor
    func testSegmentButtonStyleCompactPadding() {
        let btn = MD3Button()
        btn.style = .segment
        btn.title = "直接连接"
        XCTAssertEqual(btn.style, .segment)
    }
}

