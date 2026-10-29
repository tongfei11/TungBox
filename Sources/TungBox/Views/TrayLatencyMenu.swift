import AppKit

enum TrayLatencyStyle {
    static func color(for delay: String) -> NSColor {
        let value = Int(delay.replacingOccurrences(of: " ms", with: "").trimmingCharacters(in: .whitespaces))
        guard let value else { return .secondaryLabelColor }
        return NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex: UInt32
            if value < 400 { hex = dark ? 0x8EE0A0 : 0x064023 }
            else if value < 800 { hex = dark ? 0xFFD080 : 0x5C3000 }
            else { hex = dark ? 0xFFB4AB : 0x701010 }
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
}

/// A control inside a menu view handles its own click, leaving menu tracking open.
final class TrayLatencyTestView: NSView {
    let button = NSButton(title: "延迟测试", target: nil, action: nil)
    var onTest: (() -> Void)?

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 28))
        autoresizingMask = [.width]
        button.isBordered = false
        button.font = .menuFont(ofSize: 0)
        button.alignment = .left
        button.frame = NSRect(x: 20, y: 0, width: width - 32, height: 28)
        button.autoresizingMask = [.width]
        button.target = self
        button.action = #selector(testClicked)
        addSubview(button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(isTesting: Bool) {
        button.title = isTesting ? "正在测试…" : "延迟测试"
        button.isEnabled = !isTesting
    }

    @objc private func testClicked() { onTest?() }
}
