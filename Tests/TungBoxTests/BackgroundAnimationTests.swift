import XCTest
@testable import TungBox

final class BackgroundAnimationTests: XCTestCase {
    @MainActor
    func testAnimationEligibilityRequiresEnabledVisibleWindowAndView() {
        XCTAssertTrue(EqualizerBarsView.shouldRunAnimation(
            isAnimationEnabled: true,
            hasWindow: true,
            windowIsVisible: true,
            windowIsMiniaturized: false,
            windowHasVisibleOcclusion: true,
            viewHasHiddenAncestor: false
        ))

        let blockedStates: [(Bool, Bool, Bool, Bool, Bool, Bool)] = [
            (false, true, true, false, true, false),  // disabled by controller
            (true, false, true, false, true, false),  // detached
            (true, true, false, false, true, false),  // ordered off screen
            (true, true, true, true, true, false),    // minimized
            (true, true, true, false, false, false),  // fully occluded
            (true, true, true, false, true, true)     // hidden view/ancestor
        ]

        for state in blockedStates {
            XCTAssertFalse(EqualizerBarsView.shouldRunAnimation(
                isAnimationEnabled: state.0,
                hasWindow: state.1,
                windowIsVisible: state.2,
                windowIsMiniaturized: state.3,
                windowHasVisibleOcclusion: state.4,
                viewHasHiddenAncestor: state.5
            ))
        }
    }

    @MainActor
    func testTimerReconciliationReusesTimerAndInvalidatesWhenDisabled() {
        let view = EqualizerBarsView()

        view.reconcileAnimationTimer(shouldRun: true)
        let firstTimer = view.animationTimer
        XCTAssertNotNil(firstTimer)

        view.reconcileAnimationTimer(shouldRun: true)
        XCTAssertTrue(view.animationTimer === firstTimer)

        view.reconcileAnimationTimer(shouldRun: false)
        XCTAssertNil(view.animationTimer)
        XCTAssertFalse(firstTimer?.isValid ?? true)
    }

    @MainActor
    func testHidingParentInvalidatesAnimationTimer() {
        let parent = NSView()
        let view = EqualizerBarsView()
        parent.addSubview(view)
        view.reconcileAnimationTimer(shouldRun: true)
        XCTAssertNotNil(view.animationTimer)

        parent.isHidden = true

        XCTAssertNil(view.animationTimer)
    }

    @MainActor
    func testDeallocatingViewInvalidatesAnimationTimer() {
        weak var weakView: EqualizerBarsView?
        let timer = autoreleasepool {
            let view = EqualizerBarsView()
            weakView = view
            view.reconcileAnimationTimer(shouldRun: true)
            return view.animationTimer
        }

        XCTAssertNil(weakView)
        XCTAssertFalse(timer?.isValid ?? true)
    }
}
