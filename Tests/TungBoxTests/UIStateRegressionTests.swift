import AppKit
import XCTest
@testable import TungBox

final class UIStateRegressionTests: XCTestCase {
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
private final class SidebarActionRecorder: NSObject {
    var senders: [MD3SidebarItem] = []

    @objc func selectItem(_ sender: MD3SidebarItem) {
        senders.append(sender)
    }
}
