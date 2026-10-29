import AppKit

enum TrayLatencyStyle {
    static func color(for delay: String) -> NSColor {
        let value = Int(delay.replacingOccurrences(of: " ms", with: "").trimmingCharacters(in: .whitespaces))
        guard let value else { return .secondaryLabelColor }
        return NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex: UInt32
            if value < 400 { hex = dark ? 0x65D887 : 0x007C2D }
            else if value < 800 { hex = dark ? 0xFFBD59 : 0x9E5B00 }
            else { hex = dark ? 0xFF8078 : 0xC62828 }
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
}

/// Read-only results are labels, not disabled commands: keep their full colors.
final class TrayReadOnlyNodeView: NSView {
    let label = NSTextField(labelWithString: "")
    private let check = NSTextField(labelWithString: "")

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        autoresizingMask = [.width]
        check.frame = NSRect(x: 4, y: 2, width: 16, height: 20)
        check.font = .menuFont(ofSize: 0)
        check.textColor = .disabledControlTextColor
        label.frame = NSRect(x: 20, y: 2, width: width - 32, height: 20)
        label.autoresizingMask = [.width]
        label.lineBreakMode = .byTruncatingTail
        addSubview(check)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(title: NSAttributedString, selected: Bool) {
        label.attributedStringValue = title
        check.stringValue = selected ? "✓" : ""
        setAccessibilityLabel((selected ? "已选中，" : "") + title.string)
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
