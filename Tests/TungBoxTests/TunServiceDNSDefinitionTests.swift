import Foundation
import XCTest
@testable import TungBox

final class TunServiceDNSDefinitionTests: XCTestCase {
    private func definitions() throws -> (script: String, plist: String, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TungBox-DNSDefinition-\(UUID())")
        let store = Store(baseURL: root)
        return (TunServiceManager.serviceScript(store: store),
                TunServiceManager.launchDaemonPlist(scriptPath: TunServiceManager.scriptPath), root)
    }

    func testGeneratedScriptUsesCoreAutomaticDNSAddressAndCurrentDefinition() throws {
        let value = try definitions()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let assignment = try XCTUnwrap(value.script.components(separatedBy: .newlines).first { $0.hasPrefix("TUN_DNS_ADDR=") })
        XCTAssertEqual(assignment, "TUN_DNS_ADDR=\"\(TUNAddressPlan.dnsIPv4)\"")
        XCTAssertEqual(TunServiceManager.tunIPv4Address, TUNAddressPlan.interfaceIPv4)
        XCTAssertEqual(TunServiceManager.tunDNSIPv4Address, TUNAddressPlan.dnsIPv4)
        XCTAssertTrue(TunServiceManager.serviceDefinitionIsCurrent(script: value.script, plist: value.plist))
    }

    func testLegacyDaemonRequiresReinstallation() throws {
        let value = try definitions()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let legacy = value.script.replacingOccurrences(of: "2026-09-tun-recovery-v27", with: "2026-09-tun-recovery-v26")
            .replacingOccurrences(of: "TUN_DNS_ADDR=\"\(TUNAddressPlan.dnsIPv4)\"", with: "TUN_DNS_ADDR=\"198.18.0.2\"")
        XCTAssertFalse(TunServiceManager.serviceDefinitionIsCurrent(script: legacy, plist: value.plist))
    }

    func testCurrentVersionWithWrongDNSAddressIsRejected() throws {
        let value = try definitions()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let wrong = value.script.replacingOccurrences(of: "TUN_DNS_ADDR=\"\(TUNAddressPlan.dnsIPv4)\"", with: "TUN_DNS_ADDR=\"198.18.0.2\"")
        XCTAssertFalse(TunServiceManager.serviceDefinitionIsCurrent(script: wrong, plist: value.plist))
    }

    func testGeneratedShellPassesOfflineSyntaxCheck() throws {
        let value = try definitions()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let url = value.root.appendingPathComponent("daemon.sh")
        try value.script.write(to: url, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", url.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
