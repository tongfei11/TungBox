import AppKit
import Foundation

extension DateFormatter {
    static let short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

@MainActor
final class ClickProbe: NSObject {
    var count = 0
    @objc func clicked(_ sender: Any?) { count += 1 }
}

@main
struct Main {
    @MainActor static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
        window.makeKeyAndOrderFront(nil)
        let root = window.contentView!
        let behind = MD3Button(frame: root.bounds)
        let probe = ClickProbe()
        behind.target = probe
        behind.action = #selector(ClickProbe.clicked(_:))
        root.addSubview(behind)
        let input = NSTextField(string: "editable")
        input.heightAnchor.constraint(equalToConstant: 30).isActive = true
        for custom in [nil, input] as [NSView?] {
            let dialog = MD3Dialog(title: "Core 更新", message: "当前版本：1.13.13\n最新版本：1.14.0", customView: custom)
            dialog.frame = root.bounds
            root.addSubview(dialog)
            root.layoutSubtreeIfNeeded()
            let card = dialog.subviews[1]
            let label = card.subviews.compactMap { $0 as? NSTextField }.last!
            for local in [NSPoint(x: 10, y: 10), NSPoint(x: card.bounds.maxX - 10, y: card.bounds.midY), label.convert(NSPoint(x: 5, y: 5), to: card)] {
                let point = card.convert(local, to: root)
                let hit = root.hitTest(point)
                precondition(hit === dialog, "Dialog text and blank space must be absorbed by the modal boundary; got \(String(describing: hit))")
            }
            let stack = card.subviews.compactMap { $0 as? NSStackView }.last!
            let confirm = stack.arrangedSubviews.last!
            precondition(root.hitTest(confirm.convert(NSPoint(x: confirm.bounds.midX, y: confirm.bounds.midY), to: root)) === confirm, "Confirm must remain clickable")
            if custom != nil {
                let hit = root.hitTest(input.convert(NSPoint(x: 5, y: 5), to: root))
                precondition(hit === input || hit?.isDescendant(of: input) == true, "Custom input must remain interactive")
                let location = input.convert(NSPoint(x: 10, y: 10), to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                    window.sendEvent(event)
                }
                precondition(window.firstResponder is NSTextView, "Click must focus the input editor")
                precondition(probe.count == 0, "Input click must not trigger the underlying button")
                window.makeFirstResponder(nil)
            }
            let scrimHit = root.hitTest(NSPoint(x: 5, y: 5))
            precondition(scrimHit === dialog || scrimHit?.isDescendant(of: dialog) == true, "Scrim must block underlying controls")
            dialog.removeFromSuperview()
        }
        print("Dialog text, blank space, scrim, buttons and custom input regressions passed")
    }
}
