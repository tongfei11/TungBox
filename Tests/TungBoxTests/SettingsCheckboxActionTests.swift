import AppKit
import XCTest
@testable import TungBox

/// Exercises AppKit dispatch without opening the controller or touching live settings.
final class SettingsCheckboxActionTests: XCTestCase {
    @MainActor
    private final class Target: NSObject {
        let defaults: UserDefaults
        var receivedState: NSControl.StateValue?
        init(defaults: UserDefaults) { self.defaults = defaults }

        @objc func dnsReadSystemHostsToggled(_ sender: MD3Checkbox) {
            receivedState = sender.state
            DNSConfig.setReadSystemHosts(sender.state == .on, defaults: defaults)
        }
    }

    @MainActor
    func testActualHandlersAcceptCheckboxSenderAtCompileTime() {
        // These assignments fail to compile if a handler regresses to NSButton:
        // MD3Checkbox is an NSControl and does not inherit NSButton.
        let hosts: (MainWindowController) -> (MD3Checkbox) -> Void = MainWindowController.dnsReadSystemHostsToggled(_:)
        let fakeIP: (MainWindowController) -> (MD3Checkbox) -> Void = MainWindowController.dnsFakeIPToggled(_:)
        let strictRoute: (MainWindowController) -> (MD3Checkbox) -> Void = MainWindowController.tunStrictRouteToggled(_:)
        let nat: (MainWindowController) -> (MD3Checkbox) -> Void = MainWindowController.tunEINToggled(_:)
        _ = (hosts, fakeIP, strictRoute, nat)
    }

    @MainActor
    func testCheckboxDispatchPersistsOnAndOffAndRecreatesState() throws {
        _ = NSApplication.shared
        let suite = "TungBox.SettingsCheckboxActionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let target = Target(defaults: defaults)
        let checkbox = MD3Checkbox(frame: .zero)
        checkbox.target = target
        checkbox.action = #selector(MainWindowController.dnsReadSystemHostsToggled(_:))
        XCTAssertEqual(checkbox.state, .off)

        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        checkbox.mouseDown(with: click)
        XCTAssertEqual(target.receivedState, .on)
        XCTAssertTrue(DNSConfig.readSystemHosts(from: defaults))

        let recreatedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let recreated = MD3Checkbox(frame: .zero)
        recreated.state = DNSConfig.readSystemHosts(from: recreatedDefaults) ? .on : .off
        XCTAssertEqual(recreated.state, .on)
        recreated.target = target
        recreated.action = checkbox.action
        recreated.mouseDown(with: click)
        XCTAssertEqual(target.receivedState, .off)
        XCTAssertFalse(DNSConfig.readSystemHosts(from: defaults))
    }

}
