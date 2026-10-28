import XCTest
@testable import TungBox

final class NodeDelayTestPolicyTests: XCTestCase {
    func testModeOnlyConfigChangesPreserveRunningProbeIdentity() throws {
        var config: [String: Any] = [
            "experimental": ["clash_api": ["default_mode": "Rule", "external_controller": "127.0.0.1:9090"]],
            "outbounds": [["type": "trojan", "tag": "first", "server": "example.invalid"]]
        ]
        let original = try ConfigCodec.render(config)
        for mode in ["Global", "Direct", "Rule"] {
            config["experimental"] = ["clash_api": ["default_mode": mode, "external_controller": "127.0.0.1:9090"]]
            XCTAssertEqual(NodeDelayTestPolicy.configurationIdentity(original), NodeDelayTestPolicy.configurationIdentity(try ConfigCodec.render(config)))
        }
    }

    func testNodeAndRoutingChangesStillInvalidateRunningProbeIdentity() throws {
        let original: [String: Any] = [
            "experimental": ["clash_api": ["default_mode": "Rule"]],
            "outbounds": [["type": "trojan", "tag": "first", "server": "example.invalid"]],
            "route": ["final": "first"]
        ]
        let identity = NodeDelayTestPolicy.configurationIdentity(try ConfigCodec.render(original))
        for key in ["outbounds", "route"] {
            var changed = original
            if key == "outbounds" { changed[key] = [["type": "trojan", "tag": "first", "server": "changed.invalid"]] }
            else { changed[key] = ["final": "direct"] }
            XCTAssertNotEqual(identity, NodeDelayTestPolicy.configurationIdentity(try ConfigCodec.render(changed)))
        }
        XCTAssertNil(NodeDelayTestPolicy.configurationIdentity("invalid"))
    }

    func testModeTransitionMatrixOnlyRefreshesWhenLeavingDirect() {
        for previous in ["Direct", "Global", "Rule"] {
            for next in ["Direct", "Global", "Rule"] {
                XCTAssertEqual(NodeDelayTestPolicy.refreshAfterModeChange(from: previous, to: next),
                               previous == "Direct" && next != "Direct", "\(previous) → \(next)")
            }
        }
        XCTAssertTrue(NodeDelayTestPolicy.refreshAfterModeChange(from: "direct", to: "RULE"))
    }

    func testRapidRuleGlobalSwitchKeepsPendingRefreshButDirectCancelsIt() {
        XCTAssertTrue(NodeDelayTestPolicy.refreshAfterModeChange(from: "Rule", to: "Global", pendingRefresh: true))
        XCTAssertFalse(NodeDelayTestPolicy.refreshAfterModeChange(from: "Global", to: "Direct", pendingRefresh: true))
    }

    @MainActor
    func testSlowTunStartupIsAwaitedBeforeSnapshotAndAllNodeResults() async {
        let (stream, signal) = AsyncStream<Bool>.makeStream()
        let startup = Task {
            for await ready in stream { return ready }
            return false
        }
        var tunOnline = false
        var state = NodeDelayTestState()
        let test = Task { @MainActor in
            guard await NodeDelayTestPolicy.runtimeIsReady(tunStartup: startup, isCurrent: { true }) else { return }
            XCTAssertTrue(tunOnline, "不能在 TUN 就绪前捕获运行状态")
            let id = UUID()
            state.begin(id: id, tags: ["first", "second"])
            for tag in ["first", "second"] { state.receivedResult(id: id, tag: tag) }
            state.finish(id: id, succeeded: true)
        }
        await Task.yield()
        XCTAssertEqual(state.phase, .idle)
        tunOnline = true
        signal.yield(true)
        signal.finish()
        await test.value
        XCTAssertEqual(state.completed, 2)
        XCTAssertEqual(state.phase, .completed)
    }

    @MainActor
    func testFailedTunStartupDoesNotStartTest() async {
        let startup = Task { false }
        let ready = await NodeDelayTestPolicy.runtimeIsReady(tunStartup: startup, isCurrent: { true })
        XCTAssertFalse(ready)
    }

    @MainActor
    func testNewerTogglePreventsOlderStartupFromStartingTest() async {
        let (stream, signal) = AsyncStream<Bool>.makeStream()
        let startup = Task {
            for await ready in stream { return ready }
            return false
        }
        var transition = 1
        let gate = Task { @MainActor in
            await NodeDelayTestPolicy.runtimeIsReady(tunStartup: startup, isCurrent: { transition == 1 })
        }
        await Task.yield()
        transition = 2
        signal.yield(true)
        signal.finish()
        let ready = await gate.value
        XCTAssertFalse(ready)
    }

    @MainActor
    func testSystemProxyOnlyAndOfflineTransitionsDoNotNeedTunReadiness() async {
        let ready = await NodeDelayTestPolicy.runtimeIsReady(tunStartup: nil, isCurrent: { true })
        XCTAssertTrue(ready)
        let stale = await NodeDelayTestPolicy.runtimeIsReady(tunStartup: nil, isCurrent: { false })
        XCTAssertFalse(stale)
    }
}
