import Foundation
import XCTest
@testable import TungBox

final class ErrorPresentationTests: XCTestCase {
    func testTimeoutUsesDomainAndCodeRegardlessOfLanguage() {
        for description in ["The request timed out.", "请求超时", "unrelated localized description"] {
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                                userInfo: [NSLocalizedDescriptionKey: description])
            XCTAssertTrue(ErrorPresentation.isTimeout(error))
        }
        XCTAssertFalse(ErrorPresentation.isTimeout(NSError.user("超时规则不是合法规则")))
        XCTAssertFalse(ErrorPresentation.isTimeout(URLError(.cannotConnectToHost)))
    }

    func testWrappedTimeoutCannotReappearAsDialog() {
        let wrapper = NSError(domain: "TungBox", code: 1, userInfo: [
            NSUnderlyingErrorKey: URLError(.timedOut), NSLocalizedDescriptionKey: "模式同步失败"
        ])
        XCTAssertTrue(ErrorPresentation.isTimeout(wrapper))
        let failure = ErrorPresentation.runtimeFailure(wrapper, operation: .systemProxyStart)
        XCTAssertFalse(failure.presentsDialog)
        XCTAssertTrue(failure.message.hasPrefix("系统代理启动失败："))
        XCTAssertTrue(failure.message.contains("超时"))
        XCTAssertFalse(failure.message.contains("TUN"))
    }

    func testEveryRuntimeTimeoutHasOperationContextWithoutModal() {
        for operation: ErrorPresentation.RuntimeOperation in [.tunStart, .systemProxyStart, .systemProxyStop, .tunControlVerification, .modeSynchronization] {
            let failure = ErrorPresentation.runtimeFailure(URLError(.timedOut), operation: operation)
            XCTAssertFalse(failure.presentsDialog)
            XCTAssertTrue(failure.message.hasPrefix(operation.title + "："))
            XCTAssertFalse(failure.message.contains("The request timed out"))
        }
    }

    func testTunControlTimeoutIsNotMisreportedAsAuthenticationRejection() {
        let failure = ErrorPresentation.runtimeFailure(URLError(.timedOut), operation: .tunControlVerification)
        XCTAssertEqual(failure.message, "TUN 启动失败：本地控制接口 9091 响应超时，已停止 TUN。请查看 TUN 日志后重试。")
        XCTAssertFalse(failure.presentsDialog)
        XCTAssertFalse(failure.message.contains("认证失败"))
    }

    func testExplicitFailureRetainsReasonAndCanBePresentedWithoutModal() {
        let error = NSError.user("本地控制接口未拒绝无认证请求")
        let failure = ErrorPresentation.runtimeFailure(error, operation: .tunControlVerification, allowDialog: false)
        XCTAssertFalse(failure.presentsDialog)
        XCTAssertTrue(failure.message.contains("9091 校验失败，已停止 TUN"))
        XCTAssertTrue(failure.message.contains(error.localizedDescription))
        let startFailure = ErrorPresentation.runtimeFailure(NSError.user("TUN 服务不可用：未安装"), operation: .tunStart)
        XCTAssertTrue(startFailure.presentsDialog)
        XCTAssertEqual(startFailure.message, "TUN 启动失败：TUN 服务不可用：未安装")
    }
}
