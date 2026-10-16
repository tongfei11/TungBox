import AppKit

/// Compact circular ring gauge displaying memory usage ratio and percentage.
final class MemoryRingView: NSView, MD3Themeable {
    var ratio: Double = 0.12 { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func themeChanged() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let ringDiameter: CGFloat = 24
        let strokeWidth: CGFloat = 3.5
        let center = CGPoint(x: 4 + ringDiameter / 2, y: bounds.midY)
        let radius = ringDiameter / 2 - strokeWidth / 2

        // Background track
        ctx.setLineWidth(strokeWidth)
        ctx.setStrokeColor(MD3.outlineVariant.withAlphaComponent(0.35).cgColor)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.strokePath()

        // Progress arc
        let clamped = min(max(ratio, 0.0), 1.0)
        let startAngle: CGFloat = -.pi / 2
        let endAngle = startAngle + CGFloat(clamped) * 2 * .pi

        ctx.setLineCap(.round)
        ctx.setStrokeColor(MD3.primary.cgColor)
        ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        ctx.strokePath()

        // Percentage text
        let pctText = "\(Int(clamped * 100))%"
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: MD3.onSurface
        ]
        let size = (pctText as NSString).size(withAttributes: textAttrs)
        let textRect = CGRect(x: center.x + radius + 8, y: center.y - size.height / 2, width: size.width, height: size.height)
        (pctText as NSString).draw(in: textRect, withAttributes: textAttrs)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 68, height: 28)
    }
}
