import Foundation
import XCTest
@testable import TungBox

/// Every operation uses injected commands/settings; no OS proxy or controller is touched.
final class SystemOperationsTests: XCTestCase {
    private func manager(_ trace: ProxyCommandTrace, timeout: TimeInterval = 4) -> SystemProxyManager {
        .init(commandRunner: { trace.run($0, $1, $2) }, settingsReader: { nil }, ownershipCheckTimeout: timeout)
    }

    func testServicesPreserveOrderDuplicatesAndExcludeDisabledVPNInterfaces() {
        let trace = ProxyCommandTrace { _ in """
        An asterisk (*) denotes that a network service is disabled.
          USB Ethernet
        *Disabled Ethernet
        Tailscale
        SURGE Bridge
        Work VPN
        Wi-Fi
        USB Ethernet

        """ }
        XCTAssertEqual(manager(trace).activeNetworkServices(), ["USB Ethernet", "Wi-Fi", "USB Ethernet"])
        XCTAssertEqual(trace.calls.map(\.args), [["-listallnetworkservices"]])
        XCTAssertTrue(trace.calls.allSatisfy { $0.binary == "/usr/sbin/networksetup" && $0.timeout == 3 })
    }

    func testEmptyServiceListFallsBackToWiFiAndKeepsExistingErrorTextInterpretation() {
        for output in ["", "\n *Disabled\nVPN\nAn asterisk (*) denotes disabled services."] {
            XCTAssertEqual(manager(ProxyCommandTrace { _ in output }).activeNetworkServices(), ["Wi-Fi"])
        }
        // Refactoring does not reinterpret nonempty command output as a new error state.
        XCTAssertEqual(manager(ProxyCommandTrace { _ in "Operation not permitted" }).activeNetworkServices(), ["Operation not permitted"])
    }

    func testEnableUsesSameCommandsInOrderForEachService() {
        let trace = ProxyCommandTrace { call in call.args == ["-listallnetworkservices"] ? "Ethernet\nWi-Fi\nVPN" : "" }
        manager(trace).apply(enabled: true, port: 8123)
        XCTAssertEqual(trace.calls.map(\.args), [["-listallnetworkservices"]] + ["Ethernet", "Wi-Fi"].flatMap { service in
            [
                ["-setwebproxy", service, "127.0.0.1", "8123"],
                ["-setsecurewebproxy", service, "127.0.0.1", "8123"],
                ["-setsocksfirewallproxy", service, "127.0.0.1", "8123"],
                ["-setwebproxystate", service, "on"],
                ["-setsecurewebproxystate", service, "on"],
                ["-setsocksfirewallproxystate", service, "on"]
            ]
        })
        XCTAssertTrue(trace.calls.allSatisfy { $0.binary == "/usr/sbin/networksetup" && $0.timeout == 3 })
    }

    func testEnableCommandFailuresDoNotSkipRemainingCommandsOrServices() {
        let trace = ProxyCommandTrace { call in call.args == ["-listallnetworkservices"] ? "Ethernet\nWi-Fi" : "Error: permission denied" }
        manager(trace).apply(enabled: true, port: 7890)
        XCTAssertEqual(trace.calls.count, 13)
        XCTAssertEqual(trace.calls.last?.args, ["-setsocksfirewallproxystate", "Wi-Fi", "on"])
    }

    func testOwnershipRequiresEnabledExactLocalHostAndMatchingPort() {
        let fixtures: [(String, Bool)] = [
            ("Enabled: Yes\nServer: 127.0.0.1\nPort: 7890", true),
            (" enabled: yEs \nServer: localhost \nPort: 7890 ", true),
            ("Enabled: Yes\nServer: ::1\nPort: 7890", true),
            ("Enabled: No\nServer: 127.0.0.1\nPort: 7890", false),
            ("Enabled: Yes\nServer: 127.0.0.1\nPort: 7891", false),
            ("Enabled: Yes\nServer: 127.0.0.1\nPort: 07890", false),
            ("Enabled: Yes\nServer: external.test\nPort: 7890", false),
            ("Enabled: Yes\nServer: LOCALHOST\nPort: 7890", false),
            ("Enabled: Yes\n Server: localhost\nPort: 7890", false),
            ("Enabled: Yes\nServer: [::1]\nPort: 7890", false),
            ("Enabled: Yes\nServer: 127.0.0.1", false),
            ("Error: permission denied", false), ("", false)
        ]
        for (output, expected) in fixtures {
            let trace = ProxyCommandTrace { _ in output }
            XCTAssertEqual(manager(trace).proxySettingMatches(service: "Wi-Fi", getter: "-getwebproxy", port: 7890), expected, output)
            XCTAssertEqual(trace.calls.map(\.args), [["-getwebproxy", "Wi-Fi"]])
        }
    }

    func testDisableOnlyTurnsOffOwnedProtocols() {
        let trace = ProxyCommandTrace { call in
            switch call.args.first {
            case "-getwebproxy": return "Enabled: Yes\nServer: localhost\nPort: 7890"
            case "-getsecurewebproxy": return "Enabled: Yes\nServer: external.test\nPort: 7890"
            case "-getsocksfirewallproxy": return "Enabled: Yes\nServer: ::1\nPort: 7890"
            default: return ""
            }
        }
        manager(trace).disableIfOwned(service: "Wi-Fi", port: 7890)
        XCTAssertEqual(Set(trace.calls.filter { $0.args.first?.hasPrefix("-get") == true }.map(\.args)),
                       Set([["-getwebproxy", "Wi-Fi"], ["-getsecurewebproxy", "Wi-Fi"], ["-getsocksfirewallproxy", "Wi-Fi"]]))
        XCTAssertEqual(Set(trace.calls.filter { $0.args.last == "off" }.map(\.args)),
                       Set([["-setwebproxystate", "Wi-Fi", "off"], ["-setsocksfirewallproxystate", "Wi-Fi", "off"]]))
    }

    func testDisableDoesNotChangeDisabledForeignOrUnreadableSettings() {
        let trace = ProxyCommandTrace { call in
            switch call.args.first {
            case "-getwebproxy": return "Enabled: No\nServer: 127.0.0.1\nPort: 7890"
            case "-getsecurewebproxy": return "Enabled: Yes\nServer: 127.0.0.1\nPort: 9999"
            default: return "Error: timed out"
            }
        }
        manager(trace).disableIfOwned(service: "Wi-Fi", port: 7890)
        XCTAssertEqual(trace.calls.count, 3)
        XCTAssertFalse(trace.calls.contains { $0.args.last == "off" })
    }

    func testDisableWalksServicesAndContinuesAfterSetterFailure() {
        let trace = ProxyCommandTrace { call in
            if call.args == ["-listallnetworkservices"] { return "Ethernet\nWi-Fi" }
            if call.args.first?.hasPrefix("-get") == true { return "Enabled: Yes\nServer: 127.0.0.1\nPort: 7890" }
            return "Error: permission denied"
        }
        manager(trace).apply(enabled: false, port: 7890)
        XCTAssertEqual(trace.calls.count, 13)
        for service in ["Ethernet", "Wi-Fi"] {
            XCTAssertEqual(Set(trace.calls.filter { $0.args.last == "off" && $0.args[1] == service }.map { $0.args[0] }),
                           Set(["-setwebproxystate", "-setsecurewebproxystate", "-setsocksfirewallproxystate"]))
        }
        XCTAssertTrue(trace.calls.allSatisfy { $0.binary == "/usr/sbin/networksetup" && $0.timeout == 3 })
    }

    func testOwnershipQueriesRunConcurrentlyBeforeDisableCommands() {
        let entered = DispatchGroup()
        for _ in 0..<3 { entered.enter() }
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let trace = ProxyCommandTrace { call in
            if call.args.first?.hasPrefix("-get") == true {
                entered.leave()
                _ = release.wait(timeout: .now() + 1)
                return "Enabled: Yes\nServer: 127.0.0.1\nPort: 7890"
            }
            return ""
        }
        let subject = manager(trace)
        DispatchQueue.global().async {
            subject.disableIfOwned(service: "Wi-Fi", port: 7890)
            finished.signal()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 0.5), .success, "三种归属查询不能串行等待")
        XCTAssertFalse(trace.calls.contains { $0.args.last == "off" })
        for _ in 0..<3 { release.signal() }
        XCTAssertEqual(finished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(trace.calls.filter { $0.args.last == "off" }.count, 3)
    }

    func testOwnershipTimeoutSkipsUnconfirmedAndLateResults() {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let lateReturned = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let trace = ProxyCommandTrace { call in
            if call.args.first == "-getwebproxy" {
                entered.signal()
                _ = release.wait(timeout: .now() + 2)
                lateReturned.signal()
                return "Enabled: Yes\nServer: 127.0.0.1\nPort: 7890"
            }
            return "Enabled: No\nServer: 127.0.0.1\nPort: 7890"
        }
        let subject = manager(trace, timeout: 0.05)
        DispatchQueue.global().async {
            subject.disableIfOwned(service: "Wi-Fi", port: 7890)
            finished.signal()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(finished.wait(timeout: .now() + 1), .success, "不能等待卡住的查询结束")
        XCTAssertFalse(trace.calls.contains { $0.args.last == "off" })
        release.signal()
        XCTAssertEqual(lateReturned.wait(timeout: .now() + 1), .success)
        XCTAssertFalse(trace.calls.contains { $0.args.last == "off" }, "迟到的归属结果不能触发清理")
    }

    func testStatusMatchesAllAcceptedLocalHostPairs() {
        for http in ["127.0.0.1", "localhost", "::1"] {
            for https in ["127.0.0.1", "localhost", "::1"] {
                let subject = SystemProxyManager(commandRunner: { _, _, _ in XCTFail("状态读取不应执行命令"); return "" },
                    settingsReader: { ["HTTPEnable": 1, "HTTPProxy": http, "HTTPPort": 7890,
                                       "HTTPSEnable": 1, "HTTPSProxy": https, "HTTPSPort": 7890] })
                let status = subject.currentStatus(expectedPort: 7890)
                XCTAssertTrue(status.matches)
                XCTAssertFalse(status.hasExternalProxy)
                XCTAssertEqual(status.message, "HTTP/HTTPS 已指向 127.0.0.1:7890")
            }
        }
    }

    func testStatusReportsEnabledForeignOrWrongPortProxy() {
        let subject = SystemProxyManager(commandRunner: { _, _, _ in "" }, settingsReader: {
            ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 9999,
             "HTTPSEnable": 1, "HTTPSProxy": "external.test", "HTTPSPort": 7890]
        })
        let status = subject.currentStatus(expectedPort: 7890)
        XCTAssertFalse(status.matches)
        XCTAssertTrue(status.hasExternalProxy)
        XCTAssertEqual(status.message, "HTTP 127.0.0.1:9999 开启，HTTPS external.test:7890 开启，预期 127.0.0.1:7890")
    }

    func testStatusDisabledProtocolsDoNotCountAsExternalAndSOCKSPACStayIgnored() {
        let subject = SystemProxyManager(commandRunner: { _, _, _ in "" }, settingsReader: {
            ["HTTPEnable": 0, "HTTPProxy": "external.test", "HTTPPort": 9999,
             "HTTPSEnable": 1, "HTTPSProxy": "localhost", "HTTPSPort": 7890,
             "SOCKSEnable": 1, "SOCKSProxy": "external.test", "ProxyAutoConfigEnable": 1]
        })
        let status = subject.currentStatus(expectedPort: 7890)
        XCTAssertFalse(status.matches)
        XCTAssertFalse(status.hasExternalProxy)
        XCTAssertEqual(status.message, "HTTP external.test:9999 关闭，HTTPS localhost:7890 开启，预期 127.0.0.1:7890")
    }

    func testStatusUnreadableMissingAndMalformedFieldsPreserveDefaults() {
        let unreadable = manager(ProxyCommandTrace { _ in "" }).currentStatus(expectedPort: 7890)
        XCTAssertFalse(unreadable.matches)
        XCTAssertFalse(unreadable.hasExternalProxy)
        XCTAssertEqual(unreadable.message, "无法读取系统代理")
        let malformed = SystemProxyManager(commandRunner: { _, _, _ in "" }, settingsReader: {
            ["HTTPEnable": "1", "HTTPProxy": 123, "HTTPPort": "7890", "HTTPSEnable": 2]
        }).currentStatus(expectedPort: 7890)
        XCTAssertFalse(malformed.matches)
        XCTAssertFalse(malformed.hasExternalProxy)
        XCTAssertEqual(malformed.message, "HTTP -:0 关闭，HTTPS -:0 关闭，预期 127.0.0.1:7890")
        let empty = SystemProxyManager(commandRunner: { _, _, _ in "" }, settingsReader: { [:] }).currentStatus(expectedPort: 7890)
        XCTAssertEqual(empty.message, malformed.message)
    }
}

private final class ProxyCommandTrace: Sendable {
    struct Call: Sendable {
        let binary: String
        let args: [String]
        let timeout: TimeInterval
    }
    private let recorded = LockedValue<[Call]>([])
    private let response: @Sendable (Call) -> String
    var calls: [Call] { recorded.get() }

    init(_ response: @escaping @Sendable (Call) -> String) { self.response = response }

    func run(_ binary: String, _ args: [String], _ timeout: TimeInterval) -> String {
        let call = Call(binary: binary, args: args, timeout: timeout)
        recorded.mutate { $0.append(call) }
        return response(call)
    }
}
