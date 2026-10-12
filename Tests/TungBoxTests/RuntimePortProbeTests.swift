import Darwin
import XCTest
@testable import TungBox

final class RuntimePortProbeTests: XCTestCase {
    func testListenerWaitReturnsImmediatelyWhenReady() {
        let fixture = PortProbeFixture()
        fixture.connectResult = { _, _ in true }
        XCTAssertTrue(fixture.probe.waitForLocalTCPPort(7890, timeout: 6))
        XCTAssertEqual(fixture.calls, ["connect:7890"])
    }

    func testListenerWaitPollsUntilReadyWithoutUsingRealTime() {
        let fixture = PortProbeFixture()
        fixture.connectResult = { _, elapsed in elapsed >= 0.2 }
        XCTAssertTrue(fixture.probe.waitForLocalTCPPort(7890, timeout: 6))
        XCTAssertEqual(fixture.calls, ["connect:7890", "sleep:0.1", "connect:7890", "sleep:0.1", "connect:7890"])
    }

    func testListenerTimeoutDoesNotAddAnExtraProbeAtDeadline() {
        let fixture = PortProbeFixture()
        fixture.connectResult = { _, _ in false }
        XCTAssertFalse(fixture.probe.waitForLocalTCPPort(7890, timeout: 0.2))
        XCTAssertEqual(fixture.calls, ["connect:7890", "sleep:0.1", "connect:7890", "sleep:0.1"])
        fixture.clearCalls()
        XCTAssertFalse(fixture.probe.waitForLocalTCPPort(7890, timeout: 0))
        XCTAssertTrue(fixture.calls.isEmpty)
    }

    func testConnectionRefusalDoesNotMeanThePortCanBeBound() {
        let fixture = PortProbeFixture()
        fixture.connectResult = { _, _ in false }
        fixture.bindResult = { _, elapsed in elapsed >= 0.2 ? .available : .bindFailure(EADDRINUSE) }
        XCTAssertTrue(fixture.probe.waitForLocalTCPPortFree(7890, timeout: 3))
        fixture.clearCalls()
        XCTAssertTrue(fixture.probe.waitForLocalTCPPortsFree([7890, 9090], timeout: 3))
        XCTAssertEqual(fixture.calls, ["bind:7890", "sleep:0.1", "bind:7890", "sleep:0.1", "bind:7890", "bind:9090"])
    }

    func testMultiPortWaitRequiresEveryPortAndKeepsShortCircuitOrder() {
        let fixture = PortProbeFixture()
        fixture.bindResult = { port, elapsed in port == 9090 && elapsed < 0.2 ? .bindFailure(EADDRINUSE) : .available }
        XCTAssertTrue(fixture.probe.waitForLocalTCPPortsFree([7890, 9090], timeout: 3))
        XCTAssertEqual(fixture.calls, ["bind:7890", "bind:9090", "sleep:0.1", "bind:7890", "bind:9090", "sleep:0.1", "bind:7890", "bind:9090"])
    }

    func testBindWaitRechecksOnceAfterTimeoutIncludingZeroTimeout() {
        let fixture = PortProbeFixture()
        fixture.bindResult = { _, elapsed in elapsed >= 0.2 ? .available : .bindFailure(EADDRINUSE) }
        XCTAssertTrue(fixture.probe.waitForLocalTCPPortsFree([7890], timeout: 0.2))
        XCTAssertEqual(fixture.calls, ["bind:7890", "sleep:0.1", "bind:7890", "sleep:0.1", "bind:7890"])
        fixture.clearCalls()
        fixture.bindResult = { _, _ in .socketFailure(EMFILE) }
        XCTAssertFalse(fixture.probe.waitForLocalTCPPortsFree([7890, 9090], timeout: 0))
        XCTAssertEqual(fixture.calls, ["bind:7890"])
    }

    func testConnectionFreeWaitRechecksAtDeadline() {
        let fixture = PortProbeFixture()
        fixture.connectResult = { _, elapsed in elapsed < 0.2 }
        XCTAssertTrue(fixture.probe.waitForLocalTCPPortFree(7890, timeout: 0.2))
        XCTAssertEqual(fixture.calls, ["connect:7890", "sleep:0.1", "connect:7890", "sleep:0.1", "connect:7890"])
    }

    func testEmptyPortListNeedsNoSocketOperation() {
        let fixture = PortProbeFixture()
        XCTAssertTrue(fixture.probe.waitForLocalTCPPortsFree([], timeout: 0))
        XCTAssertTrue(fixture.probe.waitForLocalTCPPortsFree([], timeout: 3))
        XCTAssertTrue(fixture.calls.isEmpty)
    }

    func testBindDiagnosticsDistinguishSocketAndBindFailures() {
        let fixture = PortProbeFixture()
        for result in [RuntimePortProbe.BindResult.available, .socketFailure(EMFILE), .bindFailure(EADDRINUSE)] {
            fixture.bindResult = { _, _ in result }
            XCTAssertEqual(fixture.probe.canBindLocalTCPPort(8123), result == .available)
            let expected: String
            switch result {
            case .available: expected = "8123: 可 bind"
            case .socketFailure(let code): expected = "8123: socket() 失败 errno=\(code)(\(String(cString: strerror(code))))"
            case .bindFailure(let code): expected = "8123: bind 失败 errno=\(code)(\(String(cString: strerror(code))))"
            }
            XCTAssertEqual(fixture.probe.bindFailureReason(8123), expected)
        }
    }

    func testCleanupOnlySignalsMatchingCommandsAndPreservesCommandOrder() {
        let fixture = PortProbeFixture()
        fixture.commandResult = { binary, args in
            if binary == "/usr/sbin/lsof" { return args.contains("-iTCP:7890") ? "101\ninvalid\t102 101" : "103" }
            return args.contains("102") ? "/usr/bin/unrelated" : "/mock/path/sing-box run"
        }
        fixture.probe.killSingBoxHoldersOfPorts([7890, 9090])
        XCTAssertEqual(fixture.calls, [
            "command:/usr/sbin/lsof:-nP|-iTCP:7890|-t:2.0",
            "command:/bin/ps:-p|101|-o|command=:2.0", "signal:101:\(SIGKILL)",
            "command:/bin/ps:-p|102|-o|command=:2.0",
            "command:/bin/ps:-p|101|-o|command=:2.0", "signal:101:\(SIGKILL)",
            "command:/usr/sbin/lsof:-nP|-iTCP:9090|-t:2.0",
            "command:/bin/ps:-p|103|-o|command=:2.0", "signal:103:\(SIGKILL)"
        ])
    }

    func testCleanupIgnoresUnparseableOrEmptyCommandResults() {
        let fixture = PortProbeFixture()
        fixture.commandResult = { binary, _ in binary == "/usr/sbin/lsof" ? "Error: timed out\n104" : "" }
        fixture.probe.killSingBoxHoldersOfPorts([7890])
        XCTAssertFalse(fixture.calls.contains { $0.hasPrefix("signal:") })
        XCTAssertEqual(fixture.calls.count, 2)
    }

    func testSignalFailureDoesNotSkipLaterHolders() {
        let fixture = PortProbeFixture()
        fixture.commandResult = { binary, _ in binary == "/usr/sbin/lsof" ? "101\n102" : "sing-box" }
        fixture.probe.killSingBoxHoldersOfPorts([7890])
        // Every injected signal returns -1; the original cleanup is best effort.
        XCTAssertEqual(fixture.calls.filter { $0.hasPrefix("signal:") }, ["signal:101:\(SIGKILL)", "signal:102:\(SIGKILL)"])
    }

    func testHolderDescriptionKeepsThreeRowLimitAndFDLineCount() {
        let fixture = PortProbeFixture()
        fixture.commandResult = { _, args in
            if args == ["-p", "999"] { return "COMMAND PID\nfd1\nfd2\n" }
            return "COMMAND PID USER\nsing-box 101 test\nmalformed\nother 102 test\nomitted 103 test\n"
        }
        XCTAssertEqual(fixture.probe.portHoldersDescription([7890]), "7890:sing-box(pid 101,uid test); 7890:other(pid 102,uid test)；bind 探测=[7890: 可 bind]；本进程fd=3")
        XCTAssertEqual(fixture.calls, ["command:/usr/sbin/lsof:-nP|-iTCP:7890:2.0", "bind:7890", "command:/usr/sbin/lsof:-p|999:2.0"])
    }

    func testEmptyHolderDescriptionKeepsBindErrorsAndZeroFDCount() {
        let fixture = PortProbeFixture()
        fixture.bindResult = { _, _ in .bindFailure(EADDRINUSE) }
        let reason = "8123: bind 失败 errno=\(EADDRINUSE)(\(String(cString: strerror(EADDRINUSE))))"
        XCTAssertEqual(fixture.probe.portHoldersDescription([8123]), "无监听者；bind 探测=[\(reason)]；本进程fd=0")
    }
}

/// All probes, waits, commands, PIDs and signals are virtual. No live defaults.
private final class PortProbeFixture: @unchecked Sendable {
    private struct State {
        var elapsed: TimeInterval = 0
        var calls: [String] = []
    }
    private let state = LockedValue(State())
    var connectResult: @Sendable (Int, TimeInterval) -> Bool = { _, _ in false }
    var bindResult: @Sendable (Int, TimeInterval) -> RuntimePortProbe.BindResult = { _, _ in .available }
    var commandResult: @Sendable (String, [String]) -> String = { _, _ in "" }

    var calls: [String] { state.get().calls }
    func clearCalls() { state.mutate { $0.calls.removeAll() } }
    private func record(_ call: String) { state.mutate { $0.calls.append(call) } }

    var probe: RuntimePortProbe {
        RuntimePortProbe(operations: .init(
            connect: { [self] port in record("connect:\(port)"); return connectResult(port, state.get().elapsed) },
            bind: { [self] port in record("bind:\(port)"); return bindResult(port, state.get().elapsed) },
            command: { [self] binary, args, timeout in
                record("command:\(binary):\(args.joined(separator: "|")):\(timeout)")
                return commandResult(binary, args)
            },
            signal: { [self] pid, signal in record("signal:\(pid):\(signal)"); return -1 },
            currentPID: { 999 },
            now: { [self] in Date(timeIntervalSince1970: state.get().elapsed) },
            sleep: { [self] interval in record("sleep:\(interval)"); state.mutate { $0.elapsed += interval } }
        ))
    }
}
