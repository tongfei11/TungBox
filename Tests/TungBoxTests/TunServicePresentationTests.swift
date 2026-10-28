import XCTest
@testable import TungBox

final class TunServicePresentationTests: XCTestCase {
    func testOldServicePromptsEvenWhenTunIsOffAndDoesNotRepeatOnRefresh() {
        var state = TunServicePresentationState()
        state.accept(.updateRequired, requestID: state.beginCheck())
        XCTAssertEqual(state.homeStatusText(tunEnabled: false), "TUN 服务：需要更新")
        XCTAssertTrue(state.claimUpdatePrompt(canPresent: true))
        state.accept(.updateRequired, requestID: state.beginCheck())
        XCTAssertFalse(state.claimUpdatePrompt(canPresent: true))
        // An explicit attempt to enable TUN may offer the upgrade again.
        XCTAssertTrue(state.claimUpdatePrompt(canPresent: true, force: true))
    }

    func testHiddenWindowOrExistingDialogDoesNotConsumePrompt() {
        var state = TunServicePresentationState()
        state.accept(.updateRequired, requestID: state.beginCheck())
        XCTAssertFalse(state.claimUpdatePrompt(canPresent: false))
        XCTAssertTrue(state.claimUpdatePrompt(canPresent: true))
    }

    func testHealthyMissingAndBrokenServicesDoNotReportAnUpgrade() {
        for status: TunServiceStatus in [.installedRunning, .installedIdle, .notInstalled, .abnormal("服务未加载")] {
            var state = TunServicePresentationState()
            state.accept(status, requestID: state.beginCheck())
            XCTAssertFalse(state.claimUpdatePrompt(canPresent: true))
            XCTAssertFalse(status.needsUpdate)
        }
        XCTAssertTrue(TunServiceStatus.updateRequired.shouldReinstall)
        XCTAssertFalse(TunServiceStatus.updateRequired.isUsable)
        XCTAssertTrue(TunServiceStatus.updateRequired.isInstalled)
    }

    func testLatePreInstallCheckCannotRestoreUpgradeAfterSuccessfulUpdate() {
        var state = TunServicePresentationState()
        let oldCheck = state.beginCheck()
        let afterInstall = state.beginCheck()
        XCTAssertTrue(state.accept(.installedIdle, requestID: afterInstall))
        XCTAssertFalse(state.accept(.updateRequired, requestID: oldCheck))
        XCTAssertFalse(state.claimUpdatePrompt(canPresent: true))
        XCTAssertEqual(state.homeStatusText(tunEnabled: true), "TUN 服务：已安装，随代理开启")
    }

    func testServiceOperationInvalidatesInFlightCheck() {
        var state = TunServicePresentationState()
        let oldCheck = state.beginCheck()
        let operationID = state.operationID
        state.beginOperation()
        XCTAssertNotEqual(state.operationID, operationID)
        XCTAssertFalse(state.accept(.updateRequired, requestID: oldCheck))
        XCTAssertFalse(state.claimUpdatePrompt(canPresent: true))
    }

    func testBackgroundChecksDoNotInvalidateToggleOperation() {
        var state = TunServicePresentationState()
        let operationID = state.operationID
        _ = state.beginCheck()
        _ = state.beginCheck()
        XCTAssertEqual(state.operationID, operationID)
    }
}
