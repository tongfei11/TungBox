import AppKit
import XCTest
@testable import TungBox

/// Hidden standalone views and fake switches only; never creates TungBox's controller.
final class CompactConsoleLayoutTests: XCTestCase {
    @MainActor
    func testPageTabsFitAtActionHeightWithLargerText() throws {
        _ = NSApplication.shared
        for (titles, width) in [(SettingsPageNavigation.titles, SettingsPageNavigation.width),
                                (["直连 / 绕过代理", "全局代理", "规则判定"], CGFloat(480))] {
            let control = MD3SegmentedControl(frame: NSRect(x: 0, y: 0, width: width, height: ConsoleControlLayout.actionHeight))
            control.items = titles
            ConsoleControlLayout.configurePageTabs(control)
            for selected in titles.indices {
                control.selectedSegment = selected
                control.layoutSubtreeIfNeeded()
                let pill = try XCTUnwrap(control.subviews.compactMap { $0 as? MD3PillView }.first)
                XCTAssertEqual(pill.frame.height, ConsoleControlLayout.actionHeight, accuracy: 0.5)
                let buttons = descendants(control).compactMap { $0 as? MD3Button }
                XCTAssertEqual(buttons.map(\.title), titles)
                for button in buttons {
                    let label = try XCTUnwrap(descendants(button).compactMap { $0 as? NSTextField }.first)
                    XCTAssertEqual(label.font?.pointSize, ConsoleControlLayout.tabFontSize)
                    XCTAssertGreaterThanOrEqual(label.frame.width + 0.5, label.intrinsicContentSize.width, button.title)
                    XCTAssertEqual(button.frame.height, ConsoleControlLayout.actionHeight, accuracy: 0.5)
                    XCTAssertTrue(control.bounds.insetBy(dx: -0.5, dy: -0.5).contains(control.convert(button.bounds, from: button)))
                }
            }
            if let prefix = ProcessInfo.processInfo.environment["TUNGBOX_LAYOUT_PREVIEW"] {
                let image = try XCTUnwrap(control.bitmapImageRepForCachingDisplay(in: control.bounds))
                control.cacheDisplay(in: control.bounds, to: image)
                try XCTUnwrap(image.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: prefix + "-tabs-\(titles.count).png"))
            }
        }
        let home = MD3SegmentedControl(frame: NSRect(x: 0, y: 0, width: 185, height: 24))
        home.heightAnchor.constraint(equalToConstant: 24).isActive = true
        home.items = ["今日", "近 7 天", "近 30 天"]
        home.layoutSubtreeIfNeeded()
        let homePill = try XCTUnwrap(home.subviews.compactMap { $0 as? MD3PillView }.first)
        XCTAssertEqual(homePill.frame.height, 16, accuracy: 0.5)
        for label in descendants(home).compactMap({ $0 as? NSTextField }) {
            XCTAssertEqual(label.font?.pointSize, 10, "首页维持原来的小号 tab")
        }
        XCTAssertLessThan(SettingsPageNavigation.width + 100, ConsoleLayout.defaultContentSize.width - ConsoleLayout.sidebarWidth)
    }

    @MainActor
    func testPageActionsKeepEqualCompactWidths() throws {
        _ = NSApplication.shared
        let groups = [
            ["检查 Core 更新", "安装最新 Core", "导入 sing-box Core", "安装旧版 Core（测试）", "打开 Core 目录"],
            ["安装 TUN 服务", "重新安装 TUN 服务", "重载 TUN 服务", "打开 TUN 日志"],
            ["打开 GitHub 项目", "提交反馈", "查看版本发布", "打开配置目录"],
            ["刷新规则集", "清空规则集缓存"],
            ["添加规则集", "添加规则", "删除选中"],
            ["添加订阅", "从文件导入", "从剪贴板", "删除订阅"],
            ["刷新", "关闭全部"], ["复制", "清空"], ["⚡ 延迟测试"]
        ]
        for (index, titles) in groups.enumerated() {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 240),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.contentView = nil; window.close() }
            let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))
            window.contentView = root
            root.wantsLayer = true
            root.layer?.backgroundColor = MD3.background.cgColor
            let buttons = titles.map { title in
                let button = MD3Button()
                button.title = title
                if index >= 4 && index <= 6 { button.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil) }
                button.style = .outlined
                button.translatesAutoresizingMaskIntoConstraints = false
                button.heightAnchor.constraint(equalToConstant: ConsoleControlLayout.actionHeight).isActive = true
                return button
            }
            let grid: NSView
            if index < 4 {
                grid = ConsoleControlLayout.settingsButtonGrid(buttons)
            } else {
                let row = NSStackView(views: buttons)
                row.orientation = .horizontal
                row.spacing = 10
                row.translatesAutoresizingMaskIntoConstraints = false
                ConsoleControlLayout.equalizeActionWidths(buttons)
                grid = row
            }
            root.addSubview(grid)
            NSLayoutConstraint.activate([
                grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
                grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 20)
            ])
            root.layoutSubtreeIfNeeded()
            XCTAssertLessThan(grid.frame.width, index < 4 ? 416 : 756, "同页按钮等宽且留白紧凑")
            for button in buttons {
                XCTAssertEqual(button.frame.height, ConsoleControlLayout.actionHeight, accuracy: 0.5)
                XCTAssertEqual(button.frame.width, buttons.map { $0.intrinsicContentSize.width }.max() ?? 0, accuracy: 1)
                let label = try XCTUnwrap(descendants(button).compactMap { $0 as? NSTextField }.first)
                XCTAssertGreaterThanOrEqual(label.frame.width + 0.5, label.intrinsicContentSize.width, button.title)
                XCTAssertTrue(grid.bounds.insetBy(dx: -0.5, dy: -0.5).contains(grid.convert(button.bounds, from: button)))
            }
            if let prefix = ProcessInfo.processInfo.environment["TUNGBOX_LAYOUT_PREVIEW"] {
                let image = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
                root.cacheDisplay(in: root.bounds, to: image)
                try XCTUnwrap(image.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: prefix + "-actions-\(index).png"))
            }
        }
    }

    @MainActor
    func testSubscriptionCardFitsDesignHeightAndRefreshBadge() throws {
        _ = NSApplication.shared
        let previousDark = MD3.isDark
        defer { MD3.isDark = previousDark }
        MD3.isDark = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 375, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let card = MD3SubscriptionItemView(frame: NSRect(x: 0, y: 0, width: 375, height: 200))
        window.contentView = card
        card.configure(with: Subscription(id: UUID(), name: "tt", url: "https://tungcloud.vip/config", updatedAt: Date(),
                                          upload: 20 * 1024, download: 184 * 1024 * 1024 * 1024, total: 3 * 1024 * 1024 * 1024 * 1024), selected: true)
        card.layoutSubtreeIfNeeded()
        XCTAssertEqual(card.updatedAtPill.frame.height, 22, accuracy: 0.5)
        XCTAssertEqual(card.refreshButton.frame.height, 26, accuracy: 0.5)
        XCTAssertEqual(card.refreshButton.frame.width, 26, accuracy: 0.5)
        XCTAssertEqual(card.trafficBox.frame.height, 68, accuracy: 0.5)
        for view in [card.titleLabel, card.updatedAtPill, card.refreshButton, card.trafficBox, card.expireRow] {
            XCTAssertTrue(card.bounds.contains(card.convert(view.bounds, from: view)))
        }
        if let prefix = ProcessInfo.processInfo.environment["TUNGBOX_LAYOUT_PREVIEW"] {
            let image = try XCTUnwrap(card.bitmapImageRepForCachingDisplay(in: card.bounds))
            card.cacheDisplay(in: card.bounds, to: image)
            try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: prefix + "-subscription.png"))
        }
    }

    @MainActor
    func testNormalWindowRejectsBothResizeAxesAndRestoresSizeAfterFullscreen() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: ConsoleLayout.defaultContentSize),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.delegate = nil; window.close() }
        let delegate = ConsoleWindowDelegate()
        delegate.configure(window)
        let fixedFrame = window.frame.size
        for size in [NSSize(width: 800, height: 500), NSSize(width: 1400, height: 900)] {
            XCTAssertEqual(delegate.windowWillResize(window, to: size), fixedFrame)
        }
        XCTAssertFalse(delegate.windowShouldZoom(window, toFrame: NSRect(x: 0, y: 0, width: 1400, height: 900)))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))

        let notice = Notification(name: NSWindow.willEnterFullScreenNotification, object: window)
        delegate.windowWillEnterFullScreen(notice)
        XCTAssertEqual(delegate.windowWillResize(window, to: NSSize(width: 1400, height: 900)), NSSize(width: 1400, height: 900))
        window.setContentSize(NSSize(width: 1400, height: 900))
        delegate.windowWillExitFullScreen(notice)
        delegate.windowDidExitFullScreen(notice)
        XCTAssertEqual(window.contentView?.bounds.size, ConsoleLayout.defaultContentSize)
        delegate.windowWillEnterFullScreen(notice)
        delegate.windowDidFailToEnterFullScreen(window)
        XCTAssertEqual(delegate.windowWillResize(window, to: NSSize(width: 1200, height: 800)), fixedFrame)
        var closeCount = 0
        delegate.onClose = { _ in closeCount += 1 }
        delegate.windowWillClose(notice)
        XCTAssertEqual(closeCount, 1)
    }

    @MainActor
    func testDashboardKeepsStatusSwitchAndAllCardsVisibleAtFixedAndFullscreenSizes() throws {
        _ = NSApplication.shared
        for size in [ConsoleLayout.defaultContentSize, NSSize(width: 1440, height: 900)] {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.contentView = nil; window.close() }
            let root = FixedSidebarLayout(frame: NSRect(origin: .zero, size: size))
            window.contentView = root
            root.wantsLayer = true
            root.layer?.backgroundColor = MD3.background.cgColor

            let chip = MD3StatusChip()
            chip.translatesAutoresizingMaskIntoConstraints = false
            chip.heightAnchor.constraint(equalToConstant: 28).isActive = true
            chip.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
            let toggle = MD3Switch()
            let row = NSStackView(views: [chip, NSView(), toggle])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 4
            let statusCard = HomeDashboardLayout.card(title: "系统代理", views: [row]).view
            func card(_ title: String, _ value: String) -> NSView {
                let label = NSTextField(labelWithString: value)
                label.font = .systemFont(ofSize: 24, weight: .bold)
                label.textColor = MD3.primary
                return HomeDashboardLayout.card(title: title, views: [label]).view
            }
            let cards = [statusCard, card("TUN 模式", "未启动"), card("出站模式", "规则判定"),
                         card("节点名称与延迟", "美国 03 · 159 ms"), card("实时上传", "999.9 KB/s"),
                         card("实时下载", "15.8 KB/s"), card("活动连接数", "40"), card("流量统计", "2.8 GB")]
            let grid = HomeDashboardLayout.grid(serviceCard: cards[0], tunCard: cards[1], outboundCard: cards[2],
                                                nodeLatencyCard: cards[3], uploadCard: cards[4], downloadCard: cards[5],
                                                activeConnectionsCard: cards[6], trafficStatsCard: cards[7])
            let page = NSView()
            root.layoutSubtreeIfNeeded()
            root.mainContent.install(page)
            page.addSubview(grid)
            NSLayoutConstraint.activate([
                grid.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 24),
                grid.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -24),
                grid.topAnchor.constraint(equalTo: page.topAnchor, constant: 100),
                grid.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -24)
            ])
            for state in [MD3StatusChip.Status.active, .inactive, .transitioning] {
                chip.status = state
                root.layoutSubtreeIfNeeded()
                root.layoutSubtreeIfNeeded()
                XCTAssertEqual(root.sidebar.frame.width, ConsoleLayout.sidebarWidth, accuracy: 0.5)
                let label = try XCTUnwrap(descendants(chip).compactMap { $0 as? NSTextField }.first)
                XCTAssertGreaterThanOrEqual(label.frame.width + 0.5, label.intrinsicContentSize.width)
                XCTAssertTrue(chip.bounds.insetBy(dx: -0.5, dy: -0.5).contains(chip.convert(label.bounds, from: label)))
                let chipRect = statusCard.convert(chip.bounds, from: chip)
                let switchRect = statusCard.convert(toggle.bounds, from: toggle)
                XCTAssertFalse(chipRect.intersects(switchRect))
                XCTAssertTrue(statusCard.bounds.contains(chipRect))
                XCTAssertTrue(statusCard.bounds.contains(switchRect))
                for card in cards {
                    XCTAssertTrue(grid.bounds.insetBy(dx: -0.5, dy: -0.5).contains(card.frame))
                    XCTAssertGreaterThanOrEqual(card.frame.height, 128)
                    XCTAssertFalse(card.hasAmbiguousLayout)
                }
            }
            if let prefix = ProcessInfo.processInfo.environment["TUNGBOX_LAYOUT_PREVIEW"], size == ConsoleLayout.defaultContentSize {
                let image = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
                root.cacheDisplay(in: root.bounds, to: image)
                try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: prefix + "-home.png"))
            }
        }
    }

    @MainActor
    func testRuleColumnsRemainVisibleAfterViewportChanges() throws {
        let scroll = RuleTableScrollView(frame: NSRect(x: 0, y: 0, width: 739, height: 400))
        let table = ControlFriendlyTableView()
        table.columnAutoresizingStyle = .noColumnAutoresizing
        scroll.documentView = table
        for spec in RuleTableLayout.columns {
            let column = NSTableColumn(identifier: .init(spec.id))
            column.title = spec.title
            column.minWidth = spec.minimum
            column.width = spec.minimum
            table.addTableColumn(column)
        }
        for width in [739, 1219, 739] as [CGFloat] {
            scroll.setFrameSize(NSSize(width: width, height: 400))
            scroll.needsLayout = true
            scroll.layoutSubtreeIfNeeded()
            scroll.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(table.rect(ofColumn: 6).maxX, scroll.contentView.bounds.width + 1, "备注列不能被挤到窗口外")
            for (column, spec) in zip(table.tableColumns, RuleTableLayout.columns) {
                XCTAssertGreaterThanOrEqual(column.width, spec.minimum)
            }
        }
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
