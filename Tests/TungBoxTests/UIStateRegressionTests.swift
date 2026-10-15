import AppKit
import XCTest
@testable import TungBox

final class UIStateRegressionTests: XCTestCase {
    @MainActor
    func testTableCheckboxAcceptsFirstClickAndRowSelectionUpdatesText() throws {
        let table = ControlFriendlyTableView()
        let checkbox = MD3Checkbox()
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        XCTAssertTrue(table.validateProposedFirstResponder(checkbox, for: event))
        let row = MD3TableRowView()
        let cell = MD3NodeCellView()
        cell.configure(with: NodeInfo(tag: "测试节点", type: "trojan", server: "demo.invalid", delay: "20 ms"))
        row.addSubview(cell)
        row.isSelected = true
        XCTAssertEqual(cell.titleLabel.textColor, MD3.onPrimaryContainer)
        row.isSelected = false
        XCTAssertEqual(cell.titleLabel.stringValue, "测试节点")
        XCTAssertEqual(cell.titleLabel.textColor, MD3.onSurface)
        XCTAssertEqual(cell.urlDelayChip.value, "20 ms")
        let scroll = MD3ScrollView()
        scroll.scrollerStyle = .legacy
        scroll.tile()
        XCTAssertEqual(scroll.scrollerStyle, .overlay)
        XCTAssertTrue(scroll.verticalScroller is MD3ThinScroller)
    }

    @MainActor
    func testSubscriptionCellReuseUsesLatestDataAndMockCallbacks() throws {
        let cell = MD3SubscriptionCellView()
        let left = Subscription(id: UUID(), name: "订阅 A", url: "https://first.invalid/config")
        let right = Subscription(id: UUID(), name: "订阅 B", url: "https://second.invalid/config", lastError: "演示错误")
        var clicked: [String] = []
        var refreshes = 0
        cell.configure(leftSub: left, leftSelected: true, rightSub: right, rightSelected: false,
                       leftClick: { clicked.append("A") }, rightClick: { clicked.append("B") },
                       leftRefresh: { refreshes += 1 })
        XCTAssertEqual(cell.leftItem.domainLabel.stringValue, "first.invalid")
        XCTAssertFalse(cell.rightItem.errorLabel.isHidden)
        XCTAssertTrue(cell.rightItem.trafficLabel.isHidden)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        cell.leftItem.mouseDown(with: event)
        let refreshButton = try XCTUnwrap(descendants(in: cell.leftItem).compactMap { $0 as? NSButton }.first)
        refreshButton.performClick(nil)
        refreshButton.performClick(nil)
        XCTAssertEqual(refreshes, 1, "刷新中重复点击不能触发第二次假刷新")
        cell.leftItem.isRefreshing = false

        cell.configure(leftSub: right, leftSelected: false, rightSub: nil, rightSelected: false,
                       leftClick: { clicked.append("B") }, rightClick: nil)
        cell.leftItem.mouseDown(with: event)
        XCTAssertEqual(clicked, ["A", "B"])
        XCTAssertEqual(cell.leftItem.titleLabel.stringValue, "订阅 B")
        XCTAssertTrue(cell.rightItem.isHidden)
    }

    @MainActor
    func testDialogKeepsPassiveHitsInsideAndRoutesOnlyMockCallbacks() async throws {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let field = MD3TextField(string: "独立弹窗输入")
        field.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let dialog = MD3Dialog(title: "测试弹窗", message: "这段文字不能穿透到背景", customView: field)
        dialog.frame = root.bounds
        root.addSubview(dialog)
        root.layoutSubtreeIfNeeded()
        var confirmed = 0, cancelled = 0
        dialog.onConfirm = { confirmed += 1 }
        dialog.onCancel = { cancelled += 1 }
        let views = descendants(in: dialog)
        let title = try XCTUnwrap(views.compactMap { $0 as? NSTextField }.first { $0.stringValue == "测试弹窗" })
        let titlePoint = title.convert(NSPoint(x: title.bounds.midX, y: title.bounds.midY), to: root)
        XCTAssertTrue(root.hitTest(titlePoint) === dialog)
        let fieldPoint = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: root)
        XCTAssertTrue(root.hitTest(fieldPoint) === field)
        let buttons = views.compactMap { $0 as? MD3Button }
        try XCTUnwrap(buttons.first { $0.title == "确定" }).performClick(nil)
        try XCTUnwrap(buttons.first { $0.title == "取消" }).performClick(nil)
        XCTAssertEqual(confirmed, 1)
        XCTAssertEqual(cancelled, 1)
        XCTAssertTrue(dialog.superview === root, "回调由调用者决定是否关闭弹窗")
        dialog.dismiss()
        for _ in 0..<20 where dialog.superview != nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNil(dialog.superview)
    }

    @MainActor
    func testOnlyTopVisibleDialogAllowsItsOwnDescendants() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        window.contentView = root
        let background = MD3Button(frame: NSRect(x: 10, y: 10, width: 100, height: 40))
        root.addSubview(background)
        let lowerField = MD3TextField()
        let lower = MD3Dialog(title: "下层", message: "", customView: lowerField)
        lower.frame = root.bounds
        root.addSubview(lower)
        let upperField = MD3TextField()
        let upper = MD3Dialog(title: "上层", message: "", customView: upperField)
        upper.frame = root.bounds
        root.addSubview(upper)
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(background.isBlockedByMD3Dialog)
        XCTAssertTrue(lowerField.isBlockedByMD3Dialog)
        XCTAssertFalse(upperField.isBlockedByMD3Dialog)
        upper.isHidden = true
        XCTAssertFalse(lowerField.isBlockedByMD3Dialog)
        upper.removeFromSuperview()
        lower.removeFromSuperview()
        XCTAssertFalse(background.isBlockedByMD3Dialog)
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    private func descendants(in view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(in: $0) }
    }

    @MainActor
    func testSegmentedSelectionUsesMockTargetAfterItemsChange() throws {
        let control = MD3SegmentedControl(frame: NSRect(x: 0, y: 0, width: 300, height: 36))
        let recorder = InputActionRecorder()
        control.items = ["直连", "全局", "规则"]
        control.target = recorder
        control.action = #selector(InputActionRecorder.selectSegment(_:))
        let stack = try XCTUnwrap(control.subviews.compactMap { $0 as? NSStackView }.first)
        let buttons = stack.arrangedSubviews.compactMap { $0 as? MD3Button }
        XCTAssertEqual(buttons.count, 3)
        buttons[2].performClick(nil)
        XCTAssertEqual(control.selectedSegment, 2)
        XCTAssertEqual(buttons.map(\.state), [.off, .off, .on])
        XCTAssertEqual(recorder.segments, [2])

        control.selectedSegment = 0
        control.items = ["今日", "近七天"]
        let replaced = stack.arrangedSubviews.compactMap { $0 as? MD3Button }
        XCTAssertEqual(replaced.map(\.title), ["今日", "近七天"])
        replaced[1].performClick(nil)
        XCTAssertEqual(control.selectedSegment, 1)
        XCTAssertEqual(recorder.segments, [2, 1], "程序刷新不应额外发送用户动作")
    }

    @MainActor
    func testTextAndPopupKeepValuesAcrossThemeRefresh() throws {
        let previousDark = MD3.isDark
        defer { MD3.isDark = previousDark }
        let root = NSView()
        let field = MD3TextField(string: "尚未保存的输入")
        field.placeholderString = "请输入规则"
        let popup = MD3PopUpButton()
        popup.addItems(withTitles: ["DIRECT", "测试节点"])
        popup.item(at: 1)?.representedObject = "node-id"
        popup.selectItem(at: 1)
        root.addSubview(field)
        root.addSubview(popup)
        for dark in [false, true] {
            MD3.isDark = dark
            root.refreshSubviews()
            field.updateLayer()
            XCTAssertEqual(field.stringValue, "尚未保存的输入")
            XCTAssertEqual(field.placeholderAttributedString?.string, "请输入规则")
            XCTAssertEqual(field.textColor, MD3.onSurface)
            XCTAssertEqual(popup.titleOfSelectedItem, "测试节点")
            XCTAssertEqual(popup.selectedItem?.representedObject as? String, "node-id")
        }
    }

    @MainActor
    func testStatusAndLoadingIndicatorsReturnToIdle() throws {
        let chip = MD3StatusChip(frame: .zero)
        let stack = try XCTUnwrap(chip.subviews.first as? NSStackView)
        let label = try XCTUnwrap(stack.arrangedSubviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(label.stringValue, "未启动")
        chip.transitioningText = "启动中"
        chip.status = .transitioning
        XCTAssertEqual(label.stringValue, "启动中")
        chip.isActive = true
        XCTAssertEqual(label.stringValue, "运行中")
        chip.status = .transitioning
        chip.transitioningText = "关闭中"
        chip.themeChanged()
        XCTAssertEqual(label.stringValue, "关闭中")
        chip.isActive = false
        XCTAssertEqual(label.stringValue, "未启动")

        let spinner = MD3Spinner(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        XCTAssertTrue(spinner.isHidden)
        spinner.isAnimating = true
        spinner.themeChanged()
        XCTAssertFalse(spinner.isHidden)
        spinner.isAnimating = false
        XCTAssertTrue(spinner.isHidden)
    }

    @MainActor
    func testLatencyIndicatorKeepsWarningBoundariesAndFailureState() throws {
        let chip = MD3LatencyChip(frame: .zero)
        let label = try XCTUnwrap(chip.subviews.first as? NSTextField)
        var colors: [CGColor] = []
        for value in ["未测试", "测试中", "399 ms", "400 ms", "799 ms", "800 ms", "失败", "—"] {
            chip.value = value
            chip.themeChanged()
            chip.updateLayer()
            XCTAssertEqual(label.stringValue, value)
            colors.append(try XCTUnwrap(chip.layer?.backgroundColor))
        }
        XCTAssertEqual(colors[2], MD3.successContainer.cgColor)
        XCTAssertNotEqual(colors[2], colors[3])
        XCTAssertEqual(colors[3], colors[4])
        XCTAssertNotEqual(colors[4], colors[5])
        XCTAssertEqual(colors[5], colors[6])
        XCTAssertEqual(colors[0], colors[7])
    }

    @MainActor
    func testCheckboxAndRadioActionsStayLocalAndRespectDisabledState() throws {
        let recorder = InputActionRecorder()
        let checkbox = MD3Checkbox(checkboxWithTitle: "独立复选测试", target: recorder,
                                   action: #selector(InputActionRecorder.check(_:)))
        let radio = MD3RadioButton(radioButtonWithTitle: "独立单选测试", target: recorder,
                                  action: #selector(InputActionRecorder.selectRadio(_:)))
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        checkbox.mouseDown(with: event)
        checkbox.isEnabled = false
        checkbox.mouseDown(with: event)
        checkbox.isEnabled = true
        checkbox.mouseDown(with: event)
        XCTAssertEqual(recorder.checks, [true, false])
        XCTAssertEqual(checkbox.state, .off)

        radio.mouseDown(with: event)
        radio.mouseDown(with: event)
        radio.state = .off
        radio.isEnabled = false
        radio.mouseDown(with: event)
        XCTAssertEqual(recorder.radios, [true])
        XCTAssertEqual(radio.state, .off)
        radio.isEnabled = true
        radio.mouseDown(with: event)
        XCTAssertEqual(recorder.radios, [true, true])
    }

    @MainActor
    func testThemeRefreshReachesButtonsInsidePlainContainers() throws {
        let previousDark = MD3.isDark
        defer { MD3.isDark = previousDark }
        let root = NSView()
        let container = NSView()
        let button = MD3Button(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        button.style = .filled
        button.title = "独立主题测试"
        button.image = NSImage(size: NSSize(width: 18, height: 18))
        root.addSubview(container)
        container.addSubview(button)
        let stack = try XCTUnwrap(button.subviews.compactMap { $0 as? NSStackView }.first)
        let label = try XCTUnwrap(stack.arrangedSubviews.compactMap { $0 as? NSTextField }.first)
        let icon = try XCTUnwrap(stack.arrangedSubviews.compactMap { $0 as? NSImageView }.first)
        let originalSize = button.intrinsicContentSize

        for dark in [false, true, false] {
            MD3.isDark = dark
            root.refreshSubviews()
            button.updateLayer()
            XCTAssertEqual(label.textColor, MD3.onPrimary)
            XCTAssertEqual(icon.contentTintColor, MD3.onPrimary)
            XCTAssertEqual(button.layer?.backgroundColor, MD3.primary.cgColor)
            XCTAssertEqual(button.intrinsicContentSize, originalSize)
            XCTAssertEqual(button.title, "独立主题测试")
        }
    }

    @MainActor
    func testButtonHitAreaSurvivesStyleAndContentChanges() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        let button = MD3Button(frame: NSRect(x: 30, y: 40, width: 200, height: 40))
        root.addSubview(button)
        let styles: [MD3Button.ButtonStyle] = [.filled, .tonal, .outlined, .text, .nav, .destructive, .segment]
        for style in styles {
            button.style = style
            for title in ["", "测试按钮"] {
                button.title = title
                button.image = NSImage(size: NSSize(width: 18, height: 18))
                root.layoutSubtreeIfNeeded()
                for point in [NSPoint(x: 2, y: 2), NSPoint(x: 100, y: 20), NSPoint(x: 198, y: 38)] {
                    XCTAssertTrue(root.hitTest(button.convert(point, to: root)) === button)
                }
                XCTAssertNil(button.hitTest(NSPoint(x: 29, y: 60)))
                if title.isEmpty {
                    XCTAssertEqual(button.intrinsicContentSize.width, button.intrinsicContentSize.height)
                } else {
                    XCTAssertGreaterThan(button.intrinsicContentSize.width, button.intrinsicContentSize.height)
                }
            }
        }
    }

    @MainActor
    func testButtonActionUsesMockTargetAndRespectsDisabledState() {
        let button = MD3Button(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let recorder = ButtonActionRecorder()
        button.title = "独立按钮测试"
        button.target = recorder
        button.action = #selector(ButtonActionRecorder.click(_:))
        button.performClick(nil)
        XCTAssertEqual(recorder.senders.count, 1)
        XCTAssertTrue(recorder.senders.first === button)

        button.isEnabled = false
        button.performClick(nil)
        XCTAssertEqual(recorder.senders.count, 1)
        button.isEnabled = true
        button.style = .outlined
        button.performClick(nil)
        XCTAssertEqual(recorder.senders.count, 2)
        XCTAssertTrue(recorder.senders.last === button)
    }

    @MainActor
    func testSwitchTrackAndThumbRouteClicksToTheControl() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let control = MD3Switch(frame: NSRect(x: 30, y: 30, width: 52, height: 28))
        root.addSubview(control)
        for isOn in [false, true] {
            control.isOn = isOn
            root.layoutSubtreeIfNeeded()
            for x: CGFloat in [2, 14, 26, 38, 50] {
                let point = control.convert(NSPoint(x: x, y: 14), to: root)
                XCTAssertTrue(root.hitTest(point) === control, "滑块和轨道应统一由开关响应")
            }
        }
    }

    @MainActor
    func testSwitchSendsOneActionWhileMockDelayTestIsActive() throws {
        for refreshingSelection in [false, true] {
            let control = MD3Switch(frame: NSRect(x: 0, y: 0, width: 52, height: 28))
            let recorder = SwitchActionRecorder()
            let id = UUID()
            recorder.testState.begin(id: id, tags: ["first", "second"])
            if refreshingSelection { recorder.testState.refreshSelection(id: id) }
            control.isOn = true
            control.target = recorder
            control.action = #selector(SwitchActionRecorder.toggle(_:))
            let point = NSPoint(x: 38, y: 14)
            let down = try switchEvent(.leftMouseDown, at: point, in: control)
            let up = try switchEvent(.leftMouseUp, at: point, in: control)
            XCTAssertTrue(control.isEnabled)
            control.mouseDown(with: down)
            // Status polling may reassign the same value between down and up.
            control.isOn = true
            control.isOn = true
            XCTAssertTrue(recorder.values.isEmpty)
            control.mouseUp(with: up)
            XCTAssertEqual(recorder.values, [false])
            XCTAssertFalse(recorder.testState.isActive)
            XCTAssertEqual(recorder.testState.phase, .cancelled)
            control.mouseUp(with: up)
            XCTAssertEqual(recorder.values, [false], "一次点击只能发出一次切换意图")
        }
    }

    @MainActor
    func testSwitchAcceptsFirstClickButRejectsDisabledAndOutsideRelease() throws {
        let control = MD3Switch(frame: NSRect(x: 0, y: 0, width: 52, height: 28))
        let recorder = SwitchActionRecorder()
        control.target = recorder
        control.action = #selector(SwitchActionRecorder.toggle(_:))
        let down = try switchEvent(.leftMouseDown, at: NSPoint(x: 2, y: 14), in: control)
        let insideUp = try switchEvent(.leftMouseUp, at: NSPoint(x: 2, y: 14), in: control)
        XCTAssertTrue(control.acceptsFirstMouse(for: down))
        XCTAssertFalse(control.mouseDownCanMoveWindow)
        control.mouseDown(with: down)
        control.mouseUp(with: try switchEvent(.leftMouseUp, at: NSPoint(x: 54, y: 14), in: control))
        XCTAssertTrue(recorder.values.isEmpty)
        control.isEnabled = false
        XCTAssertFalse(control.acceptsFirstMouse(for: down))
        control.mouseDown(with: down)
        control.mouseUp(with: insideUp)
        XCTAssertTrue(recorder.values.isEmpty)
        control.isEnabled = true
        control.mouseDown(with: down)
        control.mouseUp(with: insideUp)
        XCTAssertEqual(recorder.values, [true])
    }

    @MainActor
    private func switchEvent(_ type: NSEvent.EventType, at point: NSPoint, in control: MD3Switch) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: control.convert(point, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1
        ))
    }

    func testTrayPresentationFollowsUserIntentWithoutWaitingForRuntimeShutdown() {
        XCTAssertTrue(TrayPresentationState.isActive(systemProxyEnabled: true, tunEnabled: false))
        XCTAssertTrue(TrayPresentationState.isActive(systemProxyEnabled: false, tunEnabled: true))
        XCTAssertFalse(TrayPresentationState.isActive(systemProxyEnabled: false, tunEnabled: false))
    }

    @MainActor
    func testLogTextViewExpandsVerticallyInsideItsScrollView() {
        let textView = NSTextView()
        LogTextViewLayout.configure(textView)

        XCTAssertTrue(textView.isVerticallyResizable)
        XCTAssertFalse(textView.isHorizontallyResizable)
        XCTAssertTrue(textView.autoresizingMask.contains(.width))
        XCTAssertEqual(textView.textContainer?.widthTracksTextView, true)
        XCTAssertEqual(textView.textContainer?.containerSize.height, CGFloat.greatestFiniteMagnitude)
    }

    func testSessionLogBufferTrimsOldLinesAndKeepsLineCountAccurate() {
        var buffer = "old-1\nold-2\nnew-1\nnew-2\n"

        XCTAssertTrue(SessionLogBuffer.trim(&buffer, maximum: 20, retained: 14))
        XCTAssertEqual(buffer, "new-1\nnew-2\n")
        XCTAssertEqual(SessionLogBuffer.lineCount(in: buffer), 2)
    }

    @MainActor
    func testSidebarHoverAreaRoutesAllClicksToTheItem() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let item = MD3SidebarItem(frame: NSRect(x: 30, y: 50, width: 144, height: 40))
        item.title = "节点"
        item.iconName = "network"
        item.hasBadge = true
        root.addSubview(item)

        for folded in [false, true] {
            item.isFolded = folded
            for selected in [false, true] {
                item.isSelected = selected
                root.layoutSubtreeIfNeeded()
                for x: CGFloat in [2, 24, 64, 112, 142] {
                    for y: CGFloat in [2, 20, 38] {
                        let point = item.convert(NSPoint(x: x, y: y), to: root)
                        XCTAssertTrue(root.hitTest(point) === item, "整个 hover 区域都应由侧栏项处理：\(x), \(y)")
                    }
                }
            }
        }
        XCTAssertNil(item.hitTest(NSPoint(x: 29, y: 70)))
        item.isHidden = true
        XCTAssertNil(item.hitTest(NSPoint(x: 60, y: 70)))
    }

    @MainActor
    func testSidebarBlankAreaSendsOneActionPerCompletedClick() throws {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let item = MD3SidebarItem(frame: NSRect(x: 30, y: 50, width: 144, height: 40))
        let recorder = SidebarActionRecorder()
        item.title = "节点"
        item.target = recorder
        item.action = #selector(SidebarActionRecorder.selectItem(_:))
        root.addSubview(item)
        root.layoutSubtreeIfNeeded()

        for point in [NSPoint(x: 130, y: 20), NSPoint(x: 72, y: 2), NSPoint(x: 72, y: 38)] {
            let hit = try XCTUnwrap(root.hitTest(item.convert(point, to: root)) as? MD3SidebarItem)
            let down = try sidebarEvent(.leftMouseDown, at: point, in: item)
            let up = try sidebarEvent(.leftMouseUp, at: point, in: item)
            let previousCount = recorder.senders.count
            hit.mouseDown(with: down)
            XCTAssertEqual(recorder.senders.count, previousCount)
            hit.mouseUp(with: up)
            XCTAssertEqual(recorder.senders.count, previousCount + 1)
            hit.mouseUp(with: up)
            XCTAssertEqual(recorder.senders.count, previousCount + 1)
            XCTAssertTrue(recorder.senders.last === item)
        }

        item.mouseDown(with: try sidebarEvent(.leftMouseDown, at: NSPoint(x: 130, y: 20), in: item))
        item.mouseUp(with: try sidebarEvent(.leftMouseUp, at: NSPoint(x: 150, y: 20), in: item))
        XCTAssertEqual(recorder.senders.count, 3, "按下后移出区域松开不应切换页面")
    }

    @MainActor
    func testSidebarAcceptsFirstClickWithoutDraggingWindow() throws {
        let item = MD3SidebarItem(frame: NSRect(x: 0, y: 0, width: 144, height: 40))
        let event = try sidebarEvent(.leftMouseDown, at: NSPoint(x: 130, y: 20), in: item)
        XCTAssertTrue(item.acceptsFirstMouse(for: event))
        XCTAssertFalse(item.mouseDownCanMoveWindow)
    }

    @MainActor
    private func sidebarEvent(_ type: NSEvent.EventType, at point: NSPoint, in item: MD3SidebarItem) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: item.convert(point, to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }
}

@MainActor
private final class ButtonActionRecorder: NSObject {
    var senders: [MD3Button] = []

    @objc func click(_ sender: MD3Button) {
        senders.append(sender)
    }
}

@MainActor
private final class SwitchActionRecorder: NSObject {
    var values: [Bool] = []
    var testState = NodeDelayTestState()

    @objc func toggle(_ sender: MD3Switch) {
        values.append(sender.isOn)
        if let id = testState.requestID { testState.finish(id: id, succeeded: false) }
    }
}

@MainActor
private final class SidebarActionRecorder: NSObject {
    var senders: [MD3SidebarItem] = []

    @objc func selectItem(_ sender: MD3SidebarItem) {
        senders.append(sender)
    }
}

@MainActor
private final class InputActionRecorder: NSObject {
    var segments: [Int] = []
    var checks: [Bool] = []
    var radios: [Bool] = []

    @objc func selectSegment(_ sender: MD3SegmentedControl) { segments.append(sender.selectedSegment) }
    @objc func check(_ sender: MD3Checkbox) { checks.append(sender.isChecked) }
    @objc func selectRadio(_ sender: MD3RadioButton) { radios.append(sender.isSelected) }
}
