import AppKit

/// Draws smooth dual-spline area chart for upload and download traffic trends.
final class TrafficTrendChartView: NSView, MD3Themeable {
    var data: TrafficTrendData = TrafficTrendStore.trendData(for: .today, totalUploadBytes: 2 * 1024 * 1024 * 1024, totalDownloadBytes: 1200 * 1024 * 1024) {
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

        let paddingLeft: CGFloat = 50
        let paddingBottom: CGFloat = 26
        let paddingTop: CGFloat = 16
        let paddingRight: CGFloat = 12

        let chartWidth = bounds.width - paddingLeft - paddingRight
        let chartHeight = bounds.height - paddingTop - paddingBottom
        guard chartWidth > 20, chartHeight > 20 else { return }

        // Grid lines & Y-axis labels
        let gridSteps = 4
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: MD3.onSurfaceVariant.withAlphaComponent(0.65)
        ]

        ctx.setLineWidth(1.0)
        ctx.setStrokeColor(MD3.outlineVariant.withAlphaComponent(0.35).cgColor)

        for i in 0...gridSteps {
            let ratio = CGFloat(i) / CGFloat(gridSteps)
            let y = paddingBottom + chartHeight * ratio
            let mbVal = Int(data.maxMB * Double(ratio))
            let label = "\(mbVal) MB"

            // Draw line
            ctx.move(to: CGPoint(x: paddingLeft, y: y))
            ctx.addLine(to: CGPoint(x: bounds.width - paddingRight, y: y))
            ctx.strokePath()

            // Draw label
            let size = (label as NSString).size(withAttributes: textAttrs)
            let labelRect = CGRect(x: paddingLeft - size.width - 6, y: y - size.height / 2, width: size.width, height: size.height)
            (label as NSString).draw(in: labelRect, withAttributes: textAttrs)
        }

        // X-axis labels
        let xLabels = data.xLabels
        if !xLabels.isEmpty {
            for (idx, xText) in xLabels.enumerated() {
                let xRatio = CGFloat(idx) / CGFloat(max(xLabels.count - 1, 1))
                let x = paddingLeft + chartWidth * xRatio
                let size = (xText as NSString).size(withAttributes: textAttrs)
                let labelRect = CGRect(x: x - size.width / 2, y: 4, width: size.width, height: size.height)
                (xText as NSString).draw(in: labelRect, withAttributes: textAttrs)
            }
        }

        // Draw Curves
        let maxVal = max(data.maxMB, 1.0)
        let primaryColor = MD3.primary
        let downloadColor = NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0) // Sky Blue

        drawSpline(points: data.downloadValuesMB, maxVal: maxVal, chartRect: CGRect(x: paddingLeft, y: paddingBottom, width: chartWidth, height: chartHeight), color: downloadColor, in: ctx)
        drawSpline(points: data.uploadValuesMB, maxVal: maxVal, chartRect: CGRect(x: paddingLeft, y: paddingBottom, width: chartWidth, height: chartHeight), color: primaryColor, in: ctx)
    }

    private func drawSpline(points: [Double], maxVal: Double, chartRect: CGRect, color: NSColor, in ctx: CGContext) {
        guard points.count >= 2 else { return }

        var cgPoints: [CGPoint] = []
        for (i, val) in points.enumerated() {
            let x = chartRect.minX + (CGFloat(i) / CGFloat(points.count - 1)) * chartRect.width
            let y = chartRect.minY + (CGFloat(min(val, maxVal)) / CGFloat(maxVal)) * chartRect.height
            cgPoints.append(CGPoint(x: x, y: y))
        }

        let path = CGMutablePath()
        path.move(to: cgPoints[0])
        for i in 1..<cgPoints.count {
            let prev = cgPoints[i - 1]
            let curr = cgPoints[i]
            let midX = (prev.x + curr.x) / 2
            path.addCurve(to: curr, control1: CGPoint(x: midX, y: prev.y), control2: CGPoint(x: midX, y: curr.y))
        }

        // Area Fill Path
        let fillPath = path.mutableCopy()!
        fillPath.addLine(to: CGPoint(x: cgPoints.last!.x, y: chartRect.minY))
        fillPath.addLine(to: CGPoint(x: cgPoints.first!.x, y: chartRect.minY))
        fillPath.closeSubpath()

        ctx.saveGState()
        ctx.addPath(fillPath)
        ctx.clip()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [color.withAlphaComponent(0.35).cgColor, color.withAlphaComponent(0.0).cgColor] as CFArray
        let locations: [CGFloat] = [0.0, 1.0]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: chartRect.maxY), end: CGPoint(x: 0, y: chartRect.minY), options: [])
        }
        ctx.restoreGState()

        // Stroke Curve
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(2.2)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }
}
