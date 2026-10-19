import AppKit
import Foundation

// MARK: - MD3 Button Cell
final class MD3ButtonCell: NSButtonCell {
    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        return frame
    }

    override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
        // Do nothing
    }
}

// MARK: - MD3 Button

final class MD3Button: NSButton, MD3Themeable {
    enum ButtonStyle {
        case filled
        case tonal
        case outlined
        case text
        case nav
        case destructive
        case segment
    }

    var style: ButtonStyle = .tonal {
        didSet {
            setupConstraints()
            updateColors()
        }
    }

    private let contentStack = NSStackView()
    private let iconView = NSImageView()
    private let labelField = NSTextField(labelWithString: "")
    private var activeConstraints: [NSLayoutConstraint] = []

    override var title: String {
        get { super.title }
        set {
            super.title = newValue
            labelField.stringValue = newValue
            labelField.isHidden = newValue.isEmpty
            setupConstraints()
            updateColors()
            invalidateIntrinsicContentSize()
        }
    }

    override var image: NSImage? {
        get { super.image }
        set {
            super.image = newValue
            if let img = newValue {
                img.isTemplate = true
                iconView.image = img
                iconView.isHidden = false
            } else {
                iconView.image = nil
                iconView.isHidden = true
            }
            setupConstraints()
            updateColors()
            invalidateIntrinsicContentSize()
        }
    }

    override var state: NSControl.StateValue {
        didSet {
            updateColors()
            self.needsDisplay = true
        }
    }

    private var isHovered = false {
        didSet {
            updateColors()
        }
    }
    private var isPressed = false {
        didSet {
            updateColors()
        }
    }
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let newCell = MD3ButtonCell()
        if let oldCell = self.cell {
            newCell.title = oldCell.title
            newCell.image = oldCell.image
            newCell.target = oldCell.target
            newCell.action = oldCell.action
            newCell.state = oldCell.state
            newCell.isEnabled = oldCell.isEnabled
        }
        self.cell = newCell

        self.wantsLayer = true
        self.isBordered = false
        self.focusRingType = .none

        contentStack.orientation = .horizontal
        contentStack.spacing = 8
        contentStack.alignment = .centerY
        contentStack.distribution = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.isHidden = true

        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.isEditable = false
        labelField.isSelectable = false
        labelField.drawsBackground = false
        labelField.isBezeled = false
        labelField.alignment = .center
        labelField.textColor = MD3.onSurface

        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(labelField)

        labelField.isHidden = self.title.isEmpty

        setupConstraints()
        updateColors()
    }

    private func setupConstraints() {
        NSLayoutConstraint.deactivate(activeConstraints)
        activeConstraints.removeAll()

        var constraints: [NSLayoutConstraint] = [
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 4),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),

            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ]

        if style == .nav {
            constraints.append(contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16))
            constraints.append(contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16))
        } else if style == .segment {
            constraints.append(contentStack.centerXAnchor.constraint(equalTo: centerXAnchor))
            constraints.append(contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4))
            constraints.append(contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4))
        } else if title.isEmpty && !iconView.isHidden {
            constraints.append(contentStack.centerXAnchor.constraint(equalTo: centerXAnchor))
        } else {
            constraints.append(contentStack.centerXAnchor.constraint(equalTo: centerXAnchor))
            constraints.append(contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12))
            constraints.append(contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12))
        }

        NSLayoutConstraint.activate(constraints)
        activeConstraints = constraints
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        if bounds.contains(localPoint) {
            return self
        }
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func resetCursorRects() {
        guard !isBlockedByMD3Dialog else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isBlockedByMD3Dialog else { return }

        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
    }

    private func getColors() -> (bg: NSColor, textCol: NSColor, borderCol: NSColor, borderWidth: CGFloat) {
        let isDark = MD3.isDark
        var bg = NSColor.clear
        var textCol = MD3.onSurface
        var borderCol = NSColor.clear
        var borderWidth: CGFloat = 0

        switch style {
        case .filled:
            bg = MD3.primary
            textCol = MD3.onPrimary
        case .tonal:
            bg = MD3.primaryContainer
            textCol = MD3.onPrimaryContainer
        case .outlined:
            bg = NSColor.clear
            textCol = MD3.primary
            borderCol = MD3.outline
            borderWidth = 1.0
        case .text:
            bg = NSColor.clear
            textCol = MD3.primary
        case .destructive:
            bg = isDark ? NSColor(calibratedRed: 0.35, green: 0.05, blue: 0.05, alpha: 1) : NSColor(calibratedRed: 0.95, green: 0.85, blue: 0.85, alpha: 1)
            textCol = isDark ? NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.70, alpha: 1) : NSColor(calibratedRed: 0.70, green: 0.05, blue: 0.05, alpha: 1)
            if !isDark {
                borderCol = textCol
                borderWidth = 1.0
            }
        case .nav:
            let isSelected = self.state == .on
            if isSelected {
                bg = MD3.primaryContainer
                textCol = MD3.onPrimaryContainer
            } else {
                bg = NSColor.clear
                textCol = MD3.onSurfaceVariant
            }
        case .segment:
            let isSelected = (self.state == .on)
            bg = NSColor.clear
            textCol = isSelected ? MD3.onPrimary : MD3.onSurfaceVariant
        }

        if isPressed {
            bg = bg.mixed(with: textCol, ratio: 0.16)
        } else if isHovered {
            bg = bg.mixed(with: textCol, ratio: 0.08)
        }

        return (bg, textCol, borderCol, borderWidth)
    }

    private func updateColors() {
        let colors = getColors()

        labelField.textColor = colors.textCol
        let font: NSFont
        if style == .nav {
            font = NSFont.systemFont(ofSize: 14, weight: self.state == .on ? .bold : .medium)
        } else if style == .segment {
            font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        } else {
            font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        }
        labelField.font = font

        if let img = iconView.image {
            img.isTemplate = true
            iconView.contentTintColor = colors.textCol
        }

        self.needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        guard let layer = self.layer else { return }

        let colors = getColors()
        layer.backgroundColor = colors.bg.cgColor
        layer.cornerRadius = style == .nav ? 12 : bounds.height / 2
        layer.borderColor = colors.borderCol.cgColor
        layer.borderWidth = colors.borderWidth
    }

    override var intrinsicContentSize: NSSize {
        if title.isEmpty && !iconView.isHidden {
            let h: CGFloat = 32
            return NSSize(width: h, height: h)
        }
        let labelSize = labelField.intrinsicContentSize
        let iconSize = iconView.isHidden ? .zero : NSSize(width: 18, height: 18)

        var width = labelSize.width
        if !iconView.isHidden {
            width += iconSize.width + contentStack.spacing
        }

        if style == .nav {
            width += 32
            return NSSize(width: max(width, 160), height: 40)
        } else if style == .segment {
            width += 24
            return NSSize(width: max(width, 60), height: 36)
        } else {
            width += 32
            return NSSize(width: max(width, 80), height: 36)
        }
    }

    func themeChanged() {
        updateColors()
    }
}
