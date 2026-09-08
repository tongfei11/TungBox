import Foundation

func expectNil(_ value: Any?) { precondition(value == nil) }
func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs, "Expected \(rhs), got \(lhs)") }
func expectTrue(_ value: Bool) { precondition(value) }
func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw NSError(domain: "Tests", code: 1) }; return value }

final class CompatibilityTests {
    func testLegacyFakeIPMigrationPreservesRangesAndReferences() throws {
        let original: [String: Any] = [
            "dns": [
                "servers": [["tag": "local", "address": "223.5.5.5"], ["tag": "fake", "address": "fakeip"]],
                "fakeip": ["enabled": true, "inet4_range": "198.19.0.0/16", "inet6_range": "fc00::/18"],
                "rules": [["query_type": ["A", "AAAA"], "server": "fake"]], "final": "local"
            ],
            "route": ["default_domain_resolver": "local"]
        ]
        let result = ConfigCompatibilityChecker.autoFix(config: original).config
        let dns = try unwrap(result["dns"] as? [String: Any])
        let servers = try unwrap(dns["servers"] as? [[String: Any]])
        expectNil(dns["fakeip"])
        expectEqual(servers[0]["type"] as? String, "udp")
        expectEqual(servers[1]["type"] as? String, "fakeip")
        expectNil(servers[1]["address"])
        expectEqual(servers[1]["inet4_range"] as? String, "198.19.0.0/16")
        expectEqual(servers[1]["inet6_range"] as? String, "fc00::/18")
        expectEqual((dns["rules"] as? [[String: Any]])?.first?["server"] as? String, "fake")
        expectEqual((result["route"] as? [String: Any])?["default_domain_resolver"] as? String, "local")
        expectTrue(NSDictionary(dictionary: result).isEqual(to: ConfigCompatibilityChecker.autoFix(config: result).config))
    }

    func testUnusedDisabledFakeIPIsRemoved() throws {
        let result = ConfigCompatibilityChecker.autoFix(config: ["dns": ["servers": [["type": "local", "tag": "local"]], "fakeip": ["enabled": false]]]).config
        expectNil((result["dns"] as? [String: Any])?["fakeip"])
    }
}

try CompatibilityTests().testLegacyFakeIPMigrationPreservesRangesAndReferences()
try CompatibilityTests().testUnusedDisabledFakeIPIsRemoved()
print("Compatibility regression tests passed")

// Exercise real AppKit layout on macOS, including resize and reattachment.
import AppKit
let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
let layout = FixedSidebarLayout(frame: NSRect(x: 0, y: 0, width: 1080, height: 720))
window.contentView = layout
for width in [1080.0, 800.0, 1600.0, 1080.0] {
    window.setContentSize(NSSize(width: width, height: 720))
    layout.layoutSubtreeIfNeeded()
    expectEqual(layout.sidebar.frame.width, 180)
    expectEqual(layout.mainContent.frame.minX, 181)
    expectEqual(layout.mainContent.frame.width, CGFloat(width - 181))
}
window.contentView = NSView()
window.contentView = layout
layout.layoutSubtreeIfNeeded()
expectEqual(layout.sidebar.frame.width, 180)
print("Sidebar layout regression tests passed")

// The same migrated fixture must be accepted by the actual installed core.
if let corePath = ProcessInfo.processInfo.environment["TUNGBOX_CORE_PATH"] {
    let fixture: [String: Any] = ["dns": ["servers": [["tag": "local", "address": "223.5.5.5"], ["tag": "fake", "address": "fakeip"]], "fakeip": ["enabled": true, "inet4_range": "198.18.0.0/15", "inet6_range": "fc00::/18"]], "outbounds": [["type": "direct", "tag": "direct"]], "route": ["default_domain_resolver": "local"]]
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let configURL = directory.appendingPathComponent("config.json")
    func check(_ config: [String: Any]) throws -> Int32 {
        try JSONSerialization.data(withJSONObject: config).write(to: configURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: corePath)
        process.arguments = ["check", "-c", configURL.path]
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys.filter({ $0.hasPrefix("ENABLE_DEPRECATED_") }) { environment.removeValue(forKey: key) }
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
    expectTrue(try check(fixture) != 0)
    expectEqual(try check(ConfigCompatibilityChecker.autoFix(config: fixture).config), 0)
    print("Core rejects original FakeIP fixture and accepts migrated configuration")
}
