import AppKit

/// Donut chart for displaying traffic breakdown (Proxy vs Direct vs Other) with center text.
final class TrafficDonutChartView: NSView, MD3Themeable {
    var proxyRatio: Double = 0.64 { didSet { needsDisplay = true } }
    var directRatio: Double = 0.36 { didSet { needsDisplay = true } }
    var otherRatio: Double = 0.00 { didSet { needsDisplay = true } }
    var centerTotalText: String = "3.3 GB" { didSet { needsDisplay = true } }
    var centerSubText: String = "今日" { didSet { needsDisplay = true } }

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

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let strokeWidth: CGFloat = 16
        let radius = min(bounds.width, bounds.height) / 2 - strokeWidth / 2 - 2
        guard radius > 10 else { return }

        // Slices
        let total = max(proxyRatio + directRatio + otherRatio, 1.0)
        let proxyAngle = CGFloat(proxyRatio / total) * 2 * .pi
        let directAngle = CGFloat(directRatio / total) * 2 * .pi
        let otherAngle = CGFloat(otherRatio / total) * 2 * .pi

        let proxyColor = MD3.primary
        let directColor = NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0)
        let otherColor = MD3.outlineVariant.withAlphaComponent(0.4)

        var currentAngle: CGFloat = -.pi / 2
        let gap: CGFloat = 0.04

        func drawArc(angle: CGFloat, color: NSColor) {
            guard angle > 0.05 else { return }
            let start = currentAngle + gap
            let end = currentAngle + angle - gap
            if end > start {
                ctx.setLineWidth(strokeWidth)
                ctx.setLineCap(.round)
                ctx.setStrokeColor(color.cgColor)
                ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                ctx.strokePath()
            }
            currentAngle += angle
        }

        drawArc(angle: proxyAngle, color: proxyColor)
        drawArc(angle: directAngle, color: directColor)
        drawArc(angle: otherAngle, color: otherColor)

        // Center Text
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: MD3.onSurface
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: MD3.onSurfaceVariant
        ]

        let titleSize = (centerTotalText as NSString).size(withAttributes: titleAttrs)
        let subSize = (centerSubText as NSString).size(withAttributes: subAttrs)
        let totalH = titleSize.height + subSize.height + 2

        let titleY: CGFloat
        let subY: CGFloat
        if isFlipped {
            titleY = center.y - totalH / 2
            subY = titleY + titleSize.height + 2
        } else {
            subY = center.y - totalH / 2
            titleY = subY + subSize.height + 2
        }

        let titleRect = CGRect(x: center.x - titleSize.width / 2, y: titleY, width: titleSize.width, height: titleSize.height)
        let subRect = CGRect(x: center.x - subSize.width / 2, y: subY, width: subSize.width, height: subSize.height)

        (centerTotalText as NSString).draw(in: titleRect, withAttributes: titleAttrs)
        (centerSubText as NSString).draw(in: subRect, withAttributes: subAttrs)
    }
}
