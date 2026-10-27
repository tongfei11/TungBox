import AppKit

/// Donut chart for displaying traffic breakdown (Proxy vs Direct vs Other) with center text.
final class TrafficDonutChartView: NSView, MD3Themeable {
    var proxyRatio: Double = 0 { didSet { needsDisplay = true } }
    var directRatio: Double = 0 { didSet { needsDisplay = true } }
    var otherRatio: Double = 0.00 { didSet { needsDisplay = true } }
    var centerTotalText: String = "0 B" { didSet { needsDisplay = true } }
    var centerSubText: String = "今日" { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 98, height: 98)
    }

    func themeChanged() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let strokeWidth: CGFloat = 10.5
        let radius = min(bounds.width, bounds.height) / 2 - strokeWidth / 2 - 2
        guard radius > 10 else { return }

        // Slices
        let total = max(proxyRatio + directRatio + otherRatio, 1.0)
        let proxyAngle = CGFloat(proxyRatio / total) * 2 * .pi
        let directAngle = CGFloat(directRatio / total) * 2 * .pi
        let otherAngle = CGFloat(otherRatio / total) * 2 * .pi

        let proxyColor = MD3.primary
        let directColor = MD3.downloadColor
        let otherColor = MD3.onSurfaceVariant

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

        // Center Text with auto-scaling to guarantee it never touches the donut ring
        let innerRadius = radius - strokeWidth / 2
        let maxAllowedWidth = max((innerRadius - 4) * 2, 40.0)

        var fontSize: CGFloat = 13.0
        var titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: MD3.onSurface
        ]
        var titleSize = (centerTotalText as NSString).size(withAttributes: titleAttrs)
        while titleSize.width > maxAllowedWidth && fontSize > 8.5 {
            fontSize -= 0.5
            titleAttrs[.font] = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            titleSize = (centerTotalText as NSString).size(withAttributes: titleAttrs)
        }

        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: MD3.onSurfaceVariant
        ]
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
