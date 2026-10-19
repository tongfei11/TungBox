import AppKit

/// Mini live wave graph showing real-time network speeds with gradient fill and scale ticks.
final class SpeedWaveChartView: NSView, MD3Themeable {
    var samples: [Double] = [] {
        didSet { needsDisplay = true }
    }

    var lineColor: NSColor = MD3.primary {
        didSet { needsDisplay = true }
    }

    var maxScaleKB: Double = 10.0 {
        didSet { needsDisplay = true }
    }

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

        let paddingRight: CGFloat = 46
        let paddingBottom: CGFloat = 8
        let paddingTop: CGFloat = 6
        let chartWidth = bounds.width - paddingRight
        let chartHeight = bounds.height - paddingTop - paddingBottom
        guard chartWidth > 15, chartHeight > 10 else { return }

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: MD3.isDark ? MD3.onSurfaceVariant.withAlphaComponent(0.65) : MD3.onSurfaceVariant
        ]

        // Reference ticks
        let ticks: [(ratio: CGFloat, text: String)] = [
            (1.0, "\(Int(maxScaleKB)) KB/s"),
            (0.5, "\(Int(maxScaleKB / 2)) KB/s"),
            (0.0, "0")
        ]

        ctx.setLineWidth(0.5)
        let strokeColor = MD3.isDark ? MD3.outlineVariant.withAlphaComponent(0.25) : MD3.outlineVariant.withAlphaComponent(0.5)
        ctx.setStrokeColor(strokeColor.cgColor)

        for tick in ticks {
            let y = paddingBottom + chartHeight * tick.ratio
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: chartWidth, y: y))
            ctx.strokePath()

            let size = (tick.text as NSString).size(withAttributes: textAttrs)
            let labelRect = CGRect(x: chartWidth + 6, y: y - size.height / 2, width: size.width, height: size.height)
            (tick.text as NSString).draw(in: labelRect, withAttributes: textAttrs)
        }

        guard samples.count >= 2 else { return }

        var points: [CGPoint] = []
        for (i, val) in samples.enumerated() {
            let x = (CGFloat(i) / CGFloat(samples.count - 1)) * chartWidth
            let y = paddingBottom + (CGFloat(min(val, maxScaleKB)) / CGFloat(maxScaleKB)) * chartHeight
            points.append(CGPoint(x: x, y: y))
        }

        let path = CGMutablePath()
        path.move(to: points[0])
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            let midX = (prev.x + curr.x) / 2
            path.addCurve(to: curr, control1: CGPoint(x: midX, y: prev.y), control2: CGPoint(x: midX, y: curr.y))
        }

        // Fill area
        let fillPath = path.mutableCopy()!
        fillPath.addLine(to: CGPoint(x: points.last!.x, y: paddingBottom))
        fillPath.addLine(to: CGPoint(x: points.first!.x, y: paddingBottom))
        fillPath.closeSubpath()

        ctx.saveGState()
        ctx.addPath(fillPath)
        ctx.clip()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [lineColor.withAlphaComponent(0.3).cgColor, lineColor.withAlphaComponent(0.0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: bounds.height - paddingTop), end: CGPoint(x: 0, y: paddingBottom), options: [])
        }
        ctx.restoreGState()

        // Stroke
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(1.8)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }
}
