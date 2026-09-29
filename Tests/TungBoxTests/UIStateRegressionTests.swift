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
}
