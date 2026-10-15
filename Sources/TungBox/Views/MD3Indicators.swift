import AppKit
import Foundation

// MARK: - MD3 Status Chip

final class MD3StatusChip: NSView, MD3Themeable {
    enum Status { case inactive, active, transitioning }

    // Icon slot holds EITHER the pulsing dot (idle/active) OR the rotating spinner
    // (transitioning) — both live inside the chip so nothing can overlap or clip.
    private let icon = NSView()
    private let dotLayer = CALayer()
    private let spinnerLayer = CAShapeLayer()
    private let label = NSTextField(labelWithString: "")

    var status: Status = .inactive {
        didSet { updateStatus() }
    }
    /// Label shown while `status == .transitioning` (e.g. "启动中" / "关闭中").
    var transitioningText: String = "处理中" {
        didSet { if status == .transitioning { updateStatus() } }
    }
    /// Back-compat boolean API (callers that only toggle on/off).
    var isActive: Bool {
        get { status == .active }
        set { status = newValue ? .active : .inactive }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8

        icon.wantsLayer = true
        icon.translatesAutoresizingMaskIntoConstraints = false

        dotLayer.cornerRadius = 4
        dotLayer.frame = CGRect(x: 2, y: 2, width: 8, height: 8)
        icon.layer?.addSublayer(dotLayer)

        spinnerLayer.fillColor = NSColor.clear.cgColor
        spinnerLayer.lineWidth = 2
        spinnerLayer.lineCap = .round
        spinnerLayer.frame = CGRect(x: 0, y: 0, width: 12, height: 12)
        let arc = CGMutablePath()
        arc.addArc(center: CGPoint(x: 6, y: 6), radius: 5, startAngle: 0, endAngle: .pi * 1.5, clockwise: false)
        spinnerLayer.path = arc
        spinnerLayer.isHidden = true
        icon.layer?.addSublayer(spinnerLayer)

        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        // The chip sizes to its content (an internal stack), so the label is never
        // compressed/truncated — "启动中" / "关闭中" always show in full.
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 12),
            icon.heightAnchor.constraint(equalToConstant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateStatus()
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        super.updateLayer()
        switch status {
        case .active:
            layer?.backgroundColor = MD3.successContainer.cgColor
            layer?.borderWidth = 0
            label.textColor = MD3.onSuccessContainer
            dotLayer.backgroundColor = MD3.success.cgColor
        case .transitioning:
            layer?.backgroundColor = MD3.primaryContainer.cgColor
            layer?.borderWidth = 0
            label.textColor = MD3.onPrimaryContainer
            spinnerLayer.strokeColor = MD3.onPrimaryContainer.cgColor
        case .inactive:
            layer?.backgroundColor = MD3.surfaceContainer.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = MD3.outlineVariant.cgColor
            label.textColor = MD3.onSurfaceVariant
            dotLayer.backgroundColor = MD3.onSurfaceVariant.cgColor
        }
    }

    private func updateStatus() {
        switch status {
        case .active: label.stringValue = "运行中"
        case .inactive: label.stringValue = "未启动"
        case .transitioning: label.stringValue = transitioningText
        }
        let transitioning = (status == .transitioning)
        spinnerLayer.isHidden = !transitioning
        dotLayer.isHidden = transitioning

        spinnerLayer.removeAnimation(forKey: "spin")
        dotLayer.removeAnimation(forKey: "pulse")
        if transitioning {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -CGFloat.pi * 2
            spin.duration = 0.8
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            spinnerLayer.add(spin, forKey: "spin")
        } else if status == .active {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.3
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            dotLayer.add(pulse, forKey: "pulse")
        }
        self.needsDisplay = true
    }

    func themeChanged() {
        self.needsDisplay = true
    }
}

// MARK: - MD3 Spinner (indeterminate circular progress)

/// Small circular loading indicator. Sized 16×16, hidden unless `isAnimating`.
/// Placed to the left of a switch while a runtime transition is in flight.
final class MD3Spinner: NSView, MD3Themeable {
    private let ring = CAShapeLayer()

    var isAnimating: Bool = false {
        didSet {
            guard isAnimating != oldValue else { return }
            isHidden = !isAnimating
            if isAnimating { startSpinning() } else { ring.removeAnimation(forKey: "spin") }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 16) }

    private func setup() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 16).isActive = true
        heightAnchor.constraint(equalToConstant: 16).isActive = true

        ring.fillColor = NSColor.clear.cgColor
        ring.lineWidth = 2
        ring.lineCap = .round
        ring.strokeColor = MD3.primary.cgColor
        ring.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.addSublayer(ring)
        isHidden = true
    }

    override func layout() {
        super.layout()
        ring.frame = bounds
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let path = CGMutablePath()
        // A 3/4 arc so the gap makes the rotation visible.
        path.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 1.5, clockwise: false)
        ring.path = path
        if isAnimating { startSpinning() }
    }

    private func startSpinning() {
        ring.removeAnimation(forKey: "spin")
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -CGFloat.pi * 2
        spin.duration = 0.9
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        ring.add(spin, forKey: "spin")
    }

    func themeChanged() {
        ring.strokeColor = MD3.primary.cgColor
    }
}

// MARK: - MD3 Latency Chip

final class MD3LatencyChip: NSView, MD3Themeable {
    private let label = NSTextField(labelWithString: "")

    var value: String = "未测试" {
        didSet { updateValue() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6

        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])

        updateValue()
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        super.updateLayer()

        let val = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if val == "未测试" {
            layer?.backgroundColor = MD3.surfaceContainer.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = MD3.outlineVariant.cgColor
            label.textColor = MD3.onSurfaceVariant
        } else if val == "测试中" {
            layer?.backgroundColor = MD3.primaryContainer.cgColor
            layer?.borderWidth = 0
            label.textColor = MD3.onPrimaryContainer
        } else if val == "失败" {
            let dark = MD3.isDark
            layer?.backgroundColor = dark ? NSColor(calibratedRed: 0.35, green: 0.05, blue: 0.05, alpha: 1).cgColor : NSColor(calibratedRed: 0.95, green: 0.85, blue: 0.85, alpha: 1).cgColor
            layer?.borderWidth = 0
            label.textColor = dark ? NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.70, alpha: 1) : NSColor(calibratedRed: 0.70, green: 0.05, blue: 0.05, alpha: 1)
        } else {
            let cleanVal = val.replacingOccurrences(of: " ms", with: "")
            if let ms = Int(cleanVal) {
                if ms < 400 {
                    layer?.backgroundColor = MD3.successContainer.cgColor
                    layer?.borderWidth = 0
                    label.textColor = MD3.onSuccessContainer
                } else if ms < 800 {
                    let dark = MD3.isDark
                    layer?.backgroundColor = dark ? NSColor(calibratedRed: 0.35, green: 0.25, blue: 0.05, alpha: 1).cgColor : NSColor(calibratedRed: 0.99, green: 0.93, blue: 0.80, alpha: 1).cgColor
                    layer?.borderWidth = 0
                    label.textColor = dark ? NSColor(calibratedRed: 0.99, green: 0.80, blue: 0.40, alpha: 1) : NSColor(calibratedRed: 0.60, green: 0.40, blue: 0.00, alpha: 1)
                } else {
                    let dark = MD3.isDark
                    layer?.backgroundColor = dark ? NSColor(calibratedRed: 0.35, green: 0.05, blue: 0.05, alpha: 1).cgColor : NSColor(calibratedRed: 0.95, green: 0.85, blue: 0.85, alpha: 1).cgColor
                    layer?.borderWidth = 0
                    label.textColor = dark ? NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.70, alpha: 1) : NSColor(calibratedRed: 0.70, green: 0.05, blue: 0.05, alpha: 1)
                }
            } else {
                layer?.backgroundColor = MD3.surfaceContainer.cgColor
                layer?.borderWidth = 1
                layer?.borderColor = MD3.outlineVariant.cgColor
                label.textColor = MD3.onSurfaceVariant
            }
        }
    }

    private func updateValue() {
        label.stringValue = value
        self.needsDisplay = true
    }

    func themeChanged() {
        self.needsDisplay = true
    }
}
