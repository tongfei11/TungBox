import AppKit
import XCTest
@testable import TungBox

final class UIStateRegressionTests: XCTestCase {
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
