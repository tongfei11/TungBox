import AppKit
import Foundation

// MARK: - MD3 Panel (Card Component)

final class MD3Panel: NSView, MD3Themeable {
    enum CardType {
        case elevated
        case filled
        case outlined
    }

    var type: CardType = .filled {
        didSet { self.needsDisplay = true }
    }

    var isSelected: Bool = false {
        didSet { self.needsDisplay = true }
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
        layer?.cornerRadius = 16
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        super.updateLayer()
        guard let layer = self.layer else { return }

        switch type {
        case .elevated:
            layer.backgroundColor = MD3.surface.cgColor
            layer.borderWidth = isSelected ? 1.5 : 1.0
            layer.borderColor = isSelected ? MD3.primary.cgColor : MD3.outlineVariant.cgColor
            if isSelected && MD3.isDark {
                layer.shadowColor = MD3.primary.cgColor
                layer.shadowOpacity = 0.25
                layer.shadowRadius = 8
                layer.shadowOffset = .zero
            } else {
                layer.shadowColor = NSColor.black.cgColor
                layer.shadowOpacity = MD3.isDark ? 0.3 : 0.06
                layer.shadowRadius = 6
                layer.shadowOffset = CGSize(width: 0, height: -2)
            }
        case .filled:
            layer.backgroundColor = MD3.surfaceContainer.cgColor
            layer.borderWidth = isSelected ? 1.5 : 0
            layer.borderColor = isSelected ? MD3.primary.cgColor : NSColor.clear.cgColor
            if isSelected && MD3.isDark {
                layer.shadowColor = MD3.primary.cgColor
                layer.shadowOpacity = 0.2
                layer.shadowRadius = 6
                layer.shadowOffset = .zero
            } else {
                layer.shadowOpacity = 0
            }
        case .outlined:
            layer.backgroundColor = NSColor.clear.cgColor
            layer.borderColor = (isSelected ? MD3.primary : MD3.outlineVariant).cgColor
            layer.borderWidth = isSelected ? 1.5 : 1.0
            layer.shadowOpacity = 0
        }
    }

    func themeChanged() {
        self.needsDisplay = true
    }
}
// MARK: - MD3 Sidebar Item

final class MD3SidebarItem: NSView, MD3Themeable {
    private let iconView = NSImageView()
    private let labelField = NSTextField(labelWithString: "")
    private let selectionPill = NSView()
    private let badgeDot = NSView()

    var hasBadge: Bool = false {
        didSet { badgeDot.isHidden = !hasBadge }
    }

    private var _tag: Int = 0
    override var tag: Int {
        get { _tag }
        set { _tag = newValue }
    }

    var title: String = "" {
        didSet { labelField.stringValue = title }
    }

    var iconName: String = "" {
        didSet {
            iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            updateState()
        }
    }

    var isSelected: Bool = false {
        didSet { updateState() }
    }

    private var isHovered = false {
        didSet { updateState() }
    }

    private var isPressed = false {
        didSet { updateState() }
    }

    private var iconLeadingConstraint: NSLayoutConstraint?
    private var iconCenterConstraint: NSLayoutConstraint?

    var isFolded: Bool = false {
        didSet {
            guard oldValue != isFolded else { return }
            labelField.isHidden = isFolded
            if isFolded {
                iconLeadingConstraint?.isActive = false
                iconCenterConstraint?.isActive = true
            } else {
                iconCenterConstraint?.isActive = false
                iconLeadingConstraint?.isActive = true
            }
            needsLayout = true
        }
    }

    var target: AnyObject?
    var action: Selector?

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
        wantsLayer = true

        selectionPill.wantsLayer = true
        selectionPill.layer?.cornerRadius = 20
        addSubview(selectionPill)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        labelField.translatesAutoresizingMaskIntoConstraints = false
        selectionPill.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(labelField)
        addSubview(badgeDot)

        badgeDot.wantsLayer = true
        badgeDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        badgeDot.layer?.cornerRadius = 4
        badgeDot.translatesAutoresizingMaskIntoConstraints = false
        badgeDot.isHidden = true

        labelField.font = .systemFont(ofSize: 14, weight: .medium)
        labelField.textColor = MD3.onSurfaceVariant

        let leadingConstraint = iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        let centerConstraint = iconView.centerXAnchor.constraint(equalTo: centerXAnchor)
        self.iconLeadingConstraint = leadingConstraint
        self.iconCenterConstraint = centerConstraint

        NSLayoutConstraint.activate([
            selectionPill.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectionPill.trailingAnchor.constraint(equalTo: trailingAnchor),
            selectionPill.topAnchor.constraint(equalTo: topAnchor),
            selectionPill.bottomAnchor.constraint(equalTo: bottomAnchor),

            leadingConstraint,
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            labelField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),

            badgeDot.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: 6),
            badgeDot.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            badgeDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeDot.widthAnchor.constraint(equalToConstant: 8),
            badgeDot.heightAnchor.constraint(equalToConstant: 8)
        ])

        updateState()
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

    override func mouseEntered(with event: NSEvent) {
        guard !isBlockedByMD3Dialog else { return }

        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
    }

    // 背景、图标、文字和角标仅负责绘制，整行 hover 区域统一由菜单项处理点击。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, !isBlockedByMD3Dialog,
              bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        !isBlockedByMD3Dialog
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard !isBlockedByMD3Dialog,
              bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        defer { isPressed = false }
        guard wasPressed, !isBlockedByMD3Dialog,
              bounds.contains(convert(event.locationInWindow, from: nil)),
              let target, let action else { return }
        NSApplication.shared.sendAction(action, to: target, from: self)
    }

    private func updateState() {
        var pillBg = NSColor.clear
        var contentCol = MD3.onSurfaceVariant

        if isSelected {
            pillBg = MD3.primaryContainer
            contentCol = MD3.onPrimaryContainer
            labelField.font = .systemFont(ofSize: 14, weight: .bold)
        } else {
            pillBg = NSColor.clear
            contentCol = MD3.onSurfaceVariant
            labelField.font = .systemFont(ofSize: 14, weight: .medium)
        }

        if isPressed {
            pillBg = pillBg.mixed(with: contentCol, ratio: 0.16)
        } else if isHovered {
            pillBg = pillBg.mixed(with: contentCol, ratio: 0.08)
        }

        selectionPill.layer?.backgroundColor = pillBg.cgColor

        labelField.textColor = contentCol
        if let img = iconView.image {
            img.isTemplate = true
            iconView.image = img
            iconView.contentTintColor = contentCol
        }
    }

    func themeChanged() {
        updateState()
    }
}

final class CenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let titleSize = cellSize(forBounds: rect)
        var newRect = rect
        let yOffset = (rect.height - titleSize.height) / 2.0
        newRect.origin.y += yOffset
        newRect.size.height = titleSize.height
        return newRect
    }
}

final class CenteredLabel: NSTextField {
    override class var cellClass: AnyClass? {
        get { CenteredTextFieldCell.self }
        set {}
    }
}

final class MD3AppVersionFooter: NSControl, MD3Themeable {
    private let stackView = NSStackView()
    private let versionLabel = NSTextField(labelWithString: "")
    private let badgeLabel = CenteredLabel(labelWithString: "NEW")
    private let badgeContainer = NSView()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { updateColors() }
    }
    private var isPressed = false {
        didSet { updateColors() }
    }

    var versionText: String = "" {
        didSet {
            versionLabel.stringValue = versionText
            invalidateIntrinsicContentSize()
        }
    }

    var showsNewBadge: Bool = false {
        didSet {
            badgeContainer.isHidden = !showsNewBadge
            invalidateIntrinsicContentSize()
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

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10

        versionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        versionLabel.maximumNumberOfLines = 1
        versionLabel.lineBreakMode = .byTruncatingTail
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.font = .systemFont(ofSize: 9, weight: .bold)
        badgeLabel.alignment = .center
        badgeLabel.maximumNumberOfLines = 1
        badgeLabel.lineBreakMode = .byTruncatingTail
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.cornerRadius = 6
        badgeLabel.layer?.masksToBounds = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.isHidden = true
        badgeContainer.addSubview(badgeLabel)

        stackView.orientation = .vertical
        stackView.spacing = 4
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        stackView.addArrangedSubview(badgeContainer)
        stackView.addArrangedSubview(versionLabel)

        NSLayoutConstraint.activate([
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor),
            badgeLabel.topAnchor.constraint(equalTo: badgeContainer.topAnchor),
            badgeLabel.bottomAnchor.constraint(equalTo: badgeContainer.bottomAnchor),
            badgeLabel.widthAnchor.constraint(equalToConstant: 34),
            badgeLabel.heightAnchor.constraint(equalToConstant: 16),

            badgeContainer.heightAnchor.constraint(equalTo: badgeLabel.heightAnchor),
            badgeContainer.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            badgeContainer.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),

            versionLabel.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            versionLabel.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),

            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])

        updateColors()
    }

    override var intrinsicContentSize: NSSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: versionLabel.font ?? NSFont.systemFont(ofSize: 13)]
        let versionWidth = ceil((versionText as NSString).size(withAttributes: attributes).width)
        let width = versionWidth + 16
        if showsNewBadge {
            return NSSize(width: width, height: 48)
        } else {
            return NSSize(width: width, height: 28)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
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
    }

    override func mouseUp(with event: NSEvent) {
        defer { isPressed = false }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        guard let action else { return }
        NSApp.sendAction(action, to: target, from: self)
    }

    override func resetCursorRects() {
        guard !isBlockedByMD3Dialog else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    func themeChanged() {
        updateColors()
    }

    private func updateColors() {
        versionLabel.textColor = MD3.onSurfaceVariant
        badgeLabel.textColor = MD3.onPrimary
        badgeLabel.layer?.backgroundColor = MD3.primary.cgColor
        layer?.backgroundColor = (isHovered || isPressed)
            ? MD3.surfaceContainer.cgColor
            : NSColor.clear.cgColor
    }
}

// MARK: - MD3 Split View
final class MD3SplitView: NSSplitView {
    override var dividerColor: NSColor {
        MD3.outlineVariant
    }
}

// MARK: - MD3 Color Scheme Row
final class MD3ColorSchemeRow: NSView, MD3Themeable {
    let index: Int
    var isSelected: Bool = false {
        didSet { updateState() }
    }

    var onClick: (() -> Void)?

    private let selectionPill = NSView()
    private let radioOuter = NSView()
    private let radioInner = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let dotsStack = NSStackView()
    private let primaryDot = NSView()
    private let accentDot = NSView()
    private let bgDot = NSView()

    private var isHovered = false { didSet { updateState() } }
    private var isPressed = false { didSet { updateState() } }
    private var trackingArea: NSTrackingArea?

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true

        selectionPill.wantsLayer = true
        selectionPill.layer?.cornerRadius = 8
        addSubview(selectionPill)

        radioOuter.wantsLayer = true
        radioOuter.layer?.cornerRadius = 8
        radioOuter.layer?.borderWidth = 2

        radioInner.wantsLayer = true
        radioInner.layer?.cornerRadius = 4
        radioOuter.addSubview(radioInner)

        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.drawsBackground = false
        nameLabel.isBezeled = false

        primaryDot.wantsLayer = true
        primaryDot.layer?.cornerRadius = 8
        accentDot.wantsLayer = true
        accentDot.layer?.cornerRadius = 8
        bgDot.wantsLayer = true
        bgDot.layer?.cornerRadius = 8

        dotsStack.orientation = .horizontal
        dotsStack.spacing = 6
        dotsStack.addArrangedSubview(primaryDot)
        dotsStack.addArrangedSubview(accentDot)
        dotsStack.addArrangedSubview(bgDot)

        selectionPill.translatesAutoresizingMaskIntoConstraints = false
        radioOuter.translatesAutoresizingMaskIntoConstraints = false
        radioInner.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        dotsStack.translatesAutoresizingMaskIntoConstraints = false
        primaryDot.translatesAutoresizingMaskIntoConstraints = false
        accentDot.translatesAutoresizingMaskIntoConstraints = false
        bgDot.translatesAutoresizingMaskIntoConstraints = false

        addSubview(radioOuter)
        addSubview(nameLabel)
        addSubview(dotsStack)

        NSLayoutConstraint.activate([
            selectionPill.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectionPill.trailingAnchor.constraint(equalTo: trailingAnchor),
            selectionPill.topAnchor.constraint(equalTo: topAnchor),
            selectionPill.bottomAnchor.constraint(equalTo: bottomAnchor),

            radioOuter.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            radioOuter.centerYAnchor.constraint(equalTo: centerYAnchor),
            radioOuter.widthAnchor.constraint(equalToConstant: 16),
            radioOuter.heightAnchor.constraint(equalToConstant: 16),

            radioInner.centerXAnchor.constraint(equalTo: radioOuter.centerXAnchor),
            radioInner.centerYAnchor.constraint(equalTo: radioOuter.centerYAnchor),
            radioInner.widthAnchor.constraint(equalToConstant: 8),
            radioInner.heightAnchor.constraint(equalToConstant: 8),

            nameLabel.leadingAnchor.constraint(equalTo: radioOuter.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: dotsStack.leadingAnchor, constant: -12),

            dotsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            dotsStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            primaryDot.widthAnchor.constraint(equalToConstant: 16),
            primaryDot.heightAnchor.constraint(equalToConstant: 16),
            accentDot.widthAnchor.constraint(equalToConstant: 16),
            accentDot.heightAnchor.constraint(equalToConstant: 16),
            bgDot.widthAnchor.constraint(equalToConstant: 16),
            bgDot.heightAnchor.constraint(equalToConstant: 16)
        ])

        updateState()
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

        guard let window = self.window else { return }
        var keepTracking = true
        while keepTracking {
            if let nextEvent = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
                let mouseLocation = convert(nextEvent.locationInWindow, from: nil)
                let isInside = bounds.contains(mouseLocation)

                switch nextEvent.type {
                case .leftMouseDragged:
                    isPressed = isInside
                case .leftMouseUp:
                    keepTracking = false
                    isPressed = false
                    if isInside {
                        onClick?()
                    }
                default:
                    break
                }
            }
        }
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        super.updateLayer()
        updateState()
    }

    func updateState() {
        let isDark = MD3.isDark
        let scheme = MD3.colorSchemes[index]

        nameLabel.stringValue = scheme.name
        nameLabel.textColor = MD3.onSurface

        primaryDot.layer?.backgroundColor = (isDark ? scheme.darkPrimary : scheme.lightPrimary).cgColor
        accentDot.layer?.backgroundColor = (isDark ? scheme.darkAccent : scheme.lightAccent).cgColor
        bgDot.layer?.backgroundColor = (isDark ? scheme.darkBackground : scheme.lightBackground).cgColor

        primaryDot.layer?.borderColor = MD3.outlineVariant.cgColor
        primaryDot.layer?.borderWidth = 0.5
        accentDot.layer?.borderColor = MD3.outlineVariant.cgColor
        accentDot.layer?.borderWidth = 0.5
        bgDot.layer?.borderColor = MD3.outlineVariant.cgColor
        bgDot.layer?.borderWidth = 0.5

        radioOuter.layer?.borderColor = (isSelected ? MD3.primary : MD3.outline).cgColor
        radioInner.isHidden = !isSelected
        radioInner.layer?.backgroundColor = MD3.primary.cgColor

        var pillBg = NSColor.clear
        let contentCol = isSelected ? MD3.onPrimaryContainer : MD3.onSurface

        if isSelected {
            pillBg = MD3.primaryContainer
        }

        if isPressed {
            pillBg = pillBg.mixed(with: contentCol, ratio: 0.16)
        } else if isHovered {
            pillBg = pillBg.mixed(with: contentCol, ratio: 0.08)
        }

        selectionPill.layer?.backgroundColor = pillBg.cgColor
    }

    func themeChanged() {
        updateState()
    }
}
// MARK: - MD3 Node Tile View
final class MD3NodeTileView: NSView, MD3Themeable {
    /// Updates latency/spinner only; preserves the existing tile and layout tree.
    static func refreshDelays(in root: NSView, delays: [String: String]) {
        if let tile = root as? MD3NodeTileView {
            if let delay = delays[tile.nodeTag], tile.delayValue != delay {
                tile.delayValue = delay
            }
            return
        }
        for child in root.subviews { refreshDelays(in: child, delays: delays) }
    }

    let nameLabel = NSTextField(labelWithString: "")
    let subLabel = NSTextField(labelWithString: "")
    let actionButton = NSButton()
    private let radioCircle = NSView()
    private let radioDot = NSView()

    var isSelected: Bool = false {
        didSet {
            updateStyle()
        }
    }

    var groupTag: String = ""
    var nodeTag: String = ""
    var isInteractive: Bool = true {
        didSet {
            updateStyle()
        }
    }
    var delayValue: String = "" {
        didSet {
            updateDelayState()
        }
    }

    var onClick: (() -> Void)?
    var onTestClick: (() -> Void)?
    /// Delay values on node tiles are display-only.  Testing is triggered from
    /// the page or group header so a tile cannot start a second test by accident.
    var isActionEnabled: Bool = true {
        didSet {
            actionButton.isEnabled = isActionEnabled
            actionButton.isHidden = !isActionEnabled
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

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        radioCircle.wantsLayer = true
        radioCircle.layer?.cornerRadius = 7
        radioCircle.layer?.borderWidth = 1.5
        radioCircle.translatesAutoresizingMaskIntoConstraints = false

        radioDot.wantsLayer = true
        radioDot.layer?.cornerRadius = 3.5
        radioDot.translatesAutoresizingMaskIntoConstraints = false
        radioCircle.addSubview(radioDot)

        NSLayoutConstraint.activate([
            radioDot.centerXAnchor.constraint(equalTo: radioCircle.centerXAnchor),
            radioDot.centerYAnchor.constraint(equalTo: radioCircle.centerYAnchor),
            radioDot.widthAnchor.constraint(equalToConstant: 7),
            radioDot.heightAnchor.constraint(equalToConstant: 7)
        ])

        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = MD3.onSurface
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        subLabel.font = .systemFont(ofSize: 9, weight: .regular)
        subLabel.textColor = MD3.onSurfaceVariant
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        subLabel.lineBreakMode = .byTruncatingTail
        subLabel.maximumNumberOfLines = 1
        subLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        actionButton.isBordered = false
        actionButton.wantsLayer = true
        actionButton.layer?.cornerRadius = 5
        actionButton.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.target = self
        actionButton.action = #selector(actionButtonClicked)
        actionButton.isEnabled = isActionEnabled
        actionButton.isHidden = !isActionEnabled

        addSubview(radioCircle)
        addSubview(nameLabel)
        addSubview(subLabel)
        addSubview(actionButton)

        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            radioCircle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            radioCircle.centerYAnchor.constraint(equalTo: centerYAnchor),
            radioCircle.widthAnchor.constraint(equalToConstant: 14),
            radioCircle.heightAnchor.constraint(equalToConstant: 14),

            nameLabel.leadingAnchor.constraint(equalTo: radioCircle.trailingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -6),

            subLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            subLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            subLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -6),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionButton.heightAnchor.constraint(equalToConstant: 20),
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])

        updateStyle()
    }

    func themeChanged() {
        updateStyle()
    }

    private func updateStyle() {
        if isSelected && !isInteractive {
            layer?.backgroundColor = MD3.primaryContainer.cgColor
            layer?.borderColor = MD3.primary.withAlphaComponent(0.6).cgColor
            layer?.borderWidth = 1.5
            radioCircle.layer?.borderColor = MD3.primary.cgColor
            radioDot.layer?.backgroundColor = MD3.primary.cgColor
            radioDot.isHidden = false
            nameLabel.textColor = MD3.onPrimaryContainer
            subLabel.textColor = MD3.onPrimaryContainer.withAlphaComponent(0.7)
        } else if isSelected {
            layer?.backgroundColor = MD3.isDark 
                ? MD3.primary.withAlphaComponent(0.12).cgColor 
                : MD3.primaryContainer.withAlphaComponent(0.4).cgColor
            layer?.borderColor = MD3.primary.cgColor
            layer?.borderWidth = 1.5
            radioCircle.layer?.borderColor = MD3.primary.cgColor
            radioDot.layer?.backgroundColor = MD3.primary.cgColor
            radioDot.isHidden = false
            nameLabel.textColor = MD3.onSurface
            nameLabel.font = .systemFont(ofSize: 12, weight: .bold)
            subLabel.textColor = MD3.onSurfaceVariant
        } else if !isInteractive {
            layer?.backgroundColor = MD3.surfaceContainerLow.cgColor
            layer?.borderColor = MD3.outlineVariant.withAlphaComponent(0.3).cgColor
            layer?.borderWidth = 1
            radioCircle.layer?.borderColor = MD3.outlineVariant.withAlphaComponent(0.5).cgColor
            radioDot.isHidden = true
            nameLabel.textColor = MD3.onSurfaceVariant.withAlphaComponent(0.6)
            nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
            subLabel.textColor = MD3.onSurfaceVariant.withAlphaComponent(0.4)
        } else {
            layer?.backgroundColor = MD3.surfaceContainerLow.cgColor
            layer?.borderColor = MD3.outlineVariant.withAlphaComponent(0.4).cgColor
            layer?.borderWidth = 1
            radioCircle.layer?.borderColor = MD3.outlineVariant.cgColor
            radioDot.isHidden = true
            nameLabel.textColor = MD3.onSurface
            nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
            subLabel.textColor = MD3.onSurfaceVariant
        }
        updateDelayState()
    }

    private func updateDelayState() {
        let delay = delayValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if delay == "测试中" {
            actionButton.image = nil
            actionButton.title = "..."
            actionButton.layer?.backgroundColor = NSColor.clear.cgColor
            actionButton.contentTintColor = MD3.primary
        } else if delay.isEmpty || delay == "未测试" || delay == "—" {
            actionButton.image = NSImage(systemSymbolName: "bolt", accessibilityDescription: "测试延迟")
            actionButton.title = ""
            actionButton.layer?.backgroundColor = NSColor.clear.cgColor
            actionButton.contentTintColor = MD3.onSurfaceVariant.withAlphaComponent(0.7)
        } else {
            actionButton.image = nil
            let numStr = delay.replacingOccurrences(of: " ms", with: "")
            actionButton.title = numStr

            let colors = getDelayColors(delayStr: delay)
            actionButton.layer?.backgroundColor = colors.bg.cgColor
            actionButton.contentTintColor = colors.text
        }
    }

    private func getDelayColors(delayStr: String) -> (bg: NSColor, text: NSColor) {
        let cleaned = delayStr.replacingOccurrences(of: " ms", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ms = Int(cleaned) else {
            if delayStr.contains("超时") || delayStr.contains("失败") {
                return (MD3.errorContainer, MD3.onErrorContainer)
            }
            return (MD3.surfaceContainer, MD3.onSurfaceVariant)
        }

        if ms < 350 {
            return (MD3.successContainer, MD3.onSuccessContainer)
        } else if ms < 750 {
            let bg = MD3.isDark 
                ? NSColor(calibratedRed: 0.35, green: 0.26, blue: 0.08, alpha: 0.6) 
                : NSColor(calibratedRed: 0.98, green: 0.92, blue: 0.78, alpha: 0.9)
            let text = MD3.isDark 
                ? NSColor(calibratedRed: 0.96, green: 0.78, blue: 0.35, alpha: 1.0) 
                : NSColor(calibratedRed: 0.68, green: 0.44, blue: 0.05, alpha: 1.0)
            return (bg, text)
        } else {
            return (MD3.errorContainer, MD3.onErrorContainer)
        }
    }

    @objc private func actionButtonClicked() {
        guard isActionEnabled else { return }
        onTestClick?()
    }

    override func mouseDown(with event: NSEvent) {
        if isInteractive {
            onClick?()
        }
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class MD3GroupDelayButton: NSView, MD3Themeable {
    let label = NSTextField(labelWithString: "")
    let iconView = NSImageView()

    var delayValue: String = "" {
        didSet {
            updateState()
        }
    }

    var isHovered: Bool = false {
        didSet {
            updateState()
        }
    }

    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        if label.isHidden {
            return NSSize(width: 18, height: 18)
        } else {
            let labelSize = label.intrinsicContentSize
            return NSSize(width: max(labelSize.width + 12, 32), height: 18)
        }
    }

    override func resetCursorRects() {
        guard !isBlockedByMD3Dialog else { return }
        addCursorRect(bounds, cursor: .pointingHand)
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

        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        label.textColor = MD3.onSurfaceVariant
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        iconView.image = NSImage(systemSymbolName: "bolt", accessibilityDescription: "测试延迟")
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = MD3.onSurfaceVariant
        iconView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(iconView)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12)
        ])

        updateState()
    }

    func themeChanged() {
        updateState()
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

    override func mouseEntered(with event: NSEvent) {
        guard !isBlockedByMD3Dialog else { return }

        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    private func updateState() {
        let delay = delayValue.trimmingCharacters(in: .whitespacesAndNewlines)
        iconView.contentTintColor = isHovered ? MD3.primary : MD3.onSurfaceVariant

        if delay == "测试中" {
            label.stringValue = "..."
            label.textColor = MD3.primary
            label.isHidden = false
            iconView.isHidden = true
        } else if isHovered {
            label.isHidden = true
            iconView.isHidden = false
        } else if delay.isEmpty || delay == "—" || delay == "未测试" {
            label.isHidden = true
            iconView.isHidden = false
        } else {
            let numStr = delay.replacingOccurrences(of: " ms", with: "")
            label.stringValue = numStr
            label.isHidden = false
            iconView.isHidden = true

            if let ms = Int(numStr) {
                if ms < 400 {
                    label.textColor = NSColor(red: 0.15, green: 0.54, blue: 0.28, alpha: 1.0)
                } else if ms < 800 {
                    label.textColor = NSColor(red: 0.65, green: 0.45, blue: 0.05, alpha: 1.0)
                } else {
                    label.textColor = NSColor(red: 0.80, green: 0.20, blue: 0.20, alpha: 1.0)
                }
            } else {
                label.textColor = MD3.onSurfaceVariant
            }
        }
        invalidateIntrinsicContentSize()
    }
}
