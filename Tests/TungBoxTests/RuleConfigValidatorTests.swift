import XCTest
@testable import TungBox

final class RuleConfigValidatorTests: XCTestCase {
    private enum Failure: Error { case invalid, timedOut }

    @MainActor
    func testSlowValidationKeepsMainActorAndSwitchQueueResponsive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let validator = RuleConfigValidator()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let validation = Task {
            try await validator.validate("{}", directory: directory) { url in
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{}")
                signal.yield(())
                signal.finish()
                guard release.wait(timeout: .now() + 3) == .success else { throw Failure.timedOut }
            }
        }
        defer { release.signal() }
        var iterator = started.makeAsyncIterator()
        await iterator.next()
        let coordinator = RuntimeCoordinator()
        let request = coordinator.begin(.init(systemProxyEnabled: false, tunEnabled: false,
            mixedProxyPort: 7890, reason: "mock off", forceRestart: false, refreshNodeDelays: false))
        let switchFinished = try await coordinator.performBlocking(for: request) { true }
        XCTAssertTrue(switchFinished, "规则校验未完成时，关闭代理仍应可以执行")
        release.signal()
        try await validation.value
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @MainActor
    func testFailedValidationPropagatesErrorAndCleansCandidate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let validator = RuleConfigValidator()
        do {
            try await validator.validate("{}", directory: directory) { _ in throw Failure.invalid }
            XCTFail("校验失败应阻止提交候选配置")
        } catch Failure.invalid { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
