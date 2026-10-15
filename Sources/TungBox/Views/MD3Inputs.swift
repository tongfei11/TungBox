import AppKit
import Foundation

// MARK: - MD3 Text Field

final class MD3TextFieldCell: NSTextFieldCell {
    var textInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var newRect = super.drawingRect(forBounds: rect)
        newRect.origin.x += textInsets.left
        newRect.origin.y += textInsets.top
        newRect.size.width -= (textInsets.left + textInsets.right)
        newRect.size.height -= (textInsets.top + textInsets.bottom)
        return newRect
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate anObject: Any?, start selStart: Int, length selLength: Int) {
        let insetRect = drawingRect(forBounds: rect)
        super.select(withFrame: insetRect, in: controlView, editor: textObj, delegate: anObject, start: selStart, length: selLength)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate anObject: Any?, event: NSEvent?) {
        let insetRect = drawingRect(forBounds: rect)
        super.edit(withFrame: insetRect, in: controlView, editor: textObj, delegate: anObject, event: event)
    }
}

final class MD3TextField: NSTextField, MD3Themeable {
    override class var cellClass: AnyClass? {
        get { MD3TextFieldCell.self }
        set {}
    }

    convenience init() {
        self.init(frame: .zero)
    }

    convenience init(string: String) {
        self.init(frame: .zero)
        self.stringValue = string
    }

    override var placeholderString: String? {
        didSet {
            updatePlaceholder()
        }
    }

    private func updatePlaceholder() {
        guard let placeholder = placeholderString else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: MD3.onSurfaceVariant.withAlphaComponent(0.6),
            .font: self.font ?? NSFont.systemFont(ofSize: 13)
        ]
        self.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: attrs)
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
        self.wantsLayer = true
        self.focusRingType = .none
        self.isBezeled = false
        self.drawsBackground = false

        NotificationCenter.default.addObserver(self, selector: #selector(textFocusDidChange), name: NSControl.textDidBeginEditingNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(textFocusDidChange), name: NSControl.textDidEndEditingNotification, object: self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func textFocusDidChange() {
        self.needsDisplay = true
    }

    var isFocused: Bool {
        if let window = self.window,
           let currentEditor = self.currentEditor(),
           window.firstResponder == currentEditor {
            return true
        }
        return false
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        self.layer?.cornerRadius = 8
        self.layer?.borderWidth = isFocused ? 2.0 : 1.0
        self.layer?.borderColor = isFocused ? MD3.primary.cgColor : MD3.outlineVariant.cgColor
        self.layer?.backgroundColor = MD3.surfaceContainer.cgColor
        self.textColor = MD3.onSurface
    }

    func themeChanged() {
        updatePlaceholder()
        self.needsDisplay = true
    }
}
// MARK: - MD3 Segmented Control

final class MD3PillView: NSView, MD3Themeable {
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
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = MD3.primary.cgColor
    }

    func themeChanged() {
        self.needsDisplay = true
    }
}

final class MD3SegmentedControl: NSView, MD3Themeable {
    private let stackView = NSStackView()
    private var buttons: [MD3Button] = []
    private let slidingPill = MD3PillView()

    var items: [String] = [] {
        didSet { setupSegments() }
    }

    var selectedSegment: Int = 0 {
        didSet { updateSelection(animated: true) }
    }

    var target: AnyObject?
    var action: Selector?

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
        layer?.borderWidth = 1

        addSubview(slidingPill)

        stackView.orientation = .horizontal
        stackView.spacing = 0
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override func layout() {
        stackView.layoutSubtreeIfNeeded()
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        slidingPill.layer?.cornerRadius = (bounds.height - 8) / 2
        updateSelection(animated: false)
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        super.updateLayer()
        layer?.borderColor = MD3.outlineVariant.cgColor
        layer?.borderWidth = 1
        layer?.backgroundColor = MD3.surfaceContainer.mixed(with: MD3.outlineVariant, ratio: 0.3).cgColor
    }

    private func setupSegments() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()

        for (index, item) in items.enumerated() {
            let button = MD3Button()
            button.title = item
            button.tag = index
            button.target = self
            button.action = #selector(segmentClicked(_:))
            button.style = .segment
            button.state = (index == selectedSegment) ? .on : .off
            stackView.addArrangedSubview(button)
            buttons.append(button)
        }

        updateSelection(animated: false)
    }

    @objc private func segmentClicked(_ sender: MD3Button) {
        selectedSegment = sender.tag
        if let target = target, let action = action {
            NSApplication.shared.sendAction(action, to: target, from: self)
        }
    }

    private func updateSelection(animated: Bool) {
        for button in buttons {
            let isSelected = button.tag == selectedSegment
            button.state = isSelected ? .on : .off
        }

        guard !buttons.isEmpty, selectedSegment < buttons.count else { return }

        let targetButton = buttons[selectedSegment]
        let inset: CGFloat = 4
        let targetFrame = convert(targetButton.bounds, from: targetButton).insetBy(dx: inset, dy: inset)

        if targetFrame.width <= 0 || targetFrame.height <= 0 { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                slidingPill.animator().frame = targetFrame
            }
        } else {
            slidingPill.frame = targetFrame
        }
    }

    func themeChanged() {
        self.needsDisplay = true
        slidingPill.themeChanged()
    }
}
// MARK: - MD3 Switch
final class MD3Switch: NSControl, MD3Themeable {
    private let track = NSView()
    private let thumb = NSView()
    private var isPressed = false

    var isOn: Bool = false {
        didSet {
            guard oldValue != isOn else { return }
            updateVisuals(animated: true)
        }
    }

    override var isEnabled: Bool {
        didSet {
            updateVisuals(animated: false)
        }
    }

    private var thumbLeadingConstraint: NSLayoutConstraint?

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

        track.wantsLayer = true
        track.layer?.cornerRadius = 14
        track.translatesAutoresizingMaskIntoConstraints = false
        addSubview(track)

        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 10
        thumb.layer?.shadowColor = NSColor.black.cgColor
        thumb.layer?.shadowOpacity = 0.2
        thumb.layer?.shadowRadius = 1
        thumb.layer?.shadowOffset = CGSize(width: 0, height: 1)
        thumb.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumb)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 52),
            heightAnchor.constraint(equalToConstant: 28),

            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.topAnchor.constraint(equalTo: topAnchor),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),

            thumb.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 20),
            thumb.heightAnchor.constraint(equalToConstant: 20)
        ])

        thumbLeadingConstraint = thumb.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
        thumbLeadingConstraint?.isActive = true

        updateVisuals(animated: false)
    }

    // The track and thumb only draw. Route their complete hit area to the control
    // and handle mouse-up directly, without gesture recognition or event-loop waits.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, !isBlockedByMD3Dialog,
              bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        isEnabled && !isBlockedByMD3Dialog
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        isPressed = isEnabled && !isBlockedByMD3Dialog
            && bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        defer { isPressed = false }
        guard wasPressed, isEnabled, !isBlockedByMD3Dialog,
              bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        isOn.toggle()
        sendAction(action, to: target)
    }

    private func updateVisuals(animated: Bool) {
        let targetConstant: CGFloat = isOn ? (52 - 20 - 4) : 4
        let trackColor = isOn ? MD3.primary : MD3.surfaceContainer
        let thumbColor = isOn ? MD3.onPrimary : MD3.outline

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                thumbLeadingConstraint?.animator().constant = targetConstant
                track.animator().layer?.backgroundColor = trackColor.cgColor
                thumb.animator().layer?.backgroundColor = thumbColor.cgColor
            })
        } else {
            thumbLeadingConstraint?.constant = targetConstant
            track.layer?.backgroundColor = trackColor.cgColor
            thumb.layer?.backgroundColor = thumbColor.cgColor
        }
    }

    func themeChanged() {
        updateVisuals(animated: false)
    }
}
// MARK: - MD3 Checkbox

final class MD3Checkbox: NSControl, MD3Themeable {
    var title: String = "" {
        didSet {
            labelField.stringValue = title
            invalidateIntrinsicContentSize()
        }
    }

    var isChecked: Bool = false {
        didSet {
            updateColors()
        }
    }

    override var isEnabled: Bool {
        didSet {
            updateColors()
        }
    }

    private let boxView = NSView()
    private let checkIcon = NSImageView()
    private let labelField = NSTextField(labelWithString: "")

    private var isHovered = false {
        didSet {
            updateColors()
        }
    }

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = labelField.intrinsicContentSize
        return NSSize(width: 18 + 8 + labelSize.width, height: 24)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea {
            removeTrackingArea(old)
        }
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let newArea = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        trackingArea = newArea
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isBlockedByMD3Dialog else { return }

        guard isEnabled else { return }
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        guard isEnabled else { return }
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isChecked.toggle()
        sendAction(action, to: target)
    }

    private func setup() {
        wantsLayer = true

        boxView.wantsLayer = true
        boxView.layer?.cornerRadius = 4
        boxView.layer?.borderWidth = 2
        boxView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(boxView)

        checkIcon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        checkIcon.imageScaling = .scaleProportionallyDown
        checkIcon.translatesAutoresizingMaskIntoConstraints = false
        boxView.addSubview(checkIcon)

        labelField.font = .systemFont(ofSize: 13)
        labelField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)

        NSLayoutConstraint.activate([
            boxView.leadingAnchor.constraint(equalTo: leadingAnchor),
            boxView.centerYAnchor.constraint(equalTo: centerYAnchor),
            boxView.widthAnchor.constraint(equalToConstant: 18),
            boxView.heightAnchor.constraint(equalToConstant: 18),

            checkIcon.centerXAnchor.constraint(equalTo: boxView.centerXAnchor),
            checkIcon.centerYAnchor.constraint(equalTo: boxView.centerYAnchor),
            checkIcon.widthAnchor.constraint(equalToConstant: 12),
            checkIcon.heightAnchor.constraint(equalToConstant: 12),

            labelField.leadingAnchor.constraint(equalTo: boxView.trailingAnchor, constant: 8),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            heightAnchor.constraint(equalToConstant: 24)
        ])

        updateColors()
    }

    func updateColors() {
        if isEnabled {
            alphaValue = 1.0
            if isChecked {
                boxView.layer?.backgroundColor = MD3.primary.cgColor
                boxView.layer?.borderColor = MD3.primary.cgColor
                checkIcon.isHidden = false
                checkIcon.contentTintColor = MD3.onPrimary
            } else {
                boxView.layer?.backgroundColor = isHovered ? MD3.surfaceContainer.cgColor : NSColor.clear.cgColor
                boxView.layer?.borderColor = MD3.outline.cgColor
                checkIcon.isHidden = true
            }
            labelField.textColor = MD3.onSurface
        } else {
            alphaValue = 0.38
            if isChecked {
                boxView.layer?.backgroundColor = MD3.onSurface.withAlphaComponent(0.12).cgColor
                boxView.layer?.borderColor = NSColor.clear.cgColor
                checkIcon.isHidden = false
                checkIcon.contentTintColor = MD3.onSurface.withAlphaComponent(0.38)
            } else {
                boxView.layer?.backgroundColor = NSColor.clear.cgColor
                boxView.layer?.borderColor = MD3.onSurface.withAlphaComponent(0.12).cgColor
                checkIcon.isHidden = true
            }
            labelField.textColor = MD3.onSurface.withAlphaComponent(0.38)
        }
    }

    func themeChanged() {
        updateColors()
    }

    var state: NSControl.StateValue {
        get {
            isChecked ? .on : .off
        }
        set {
            isChecked = (newValue == .on)
        }
    }

    convenience init(checkboxWithTitle title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.labelField.stringValue = title
        self.target = target
        self.action = action
        invalidateIntrinsicContentSize()
    }
}
// MARK: - MD3 PopUp Button

final class MD3PopUpButton: NSPopUpButton, MD3Themeable {
    private var isHovered = false {
        didSet {
            needsDisplay = true
        }
    }

    private var trackingArea: NSTrackingArea?

    convenience init() {
        self.init(frame: .zero, pullsDown: false)
    }

    override init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame, pullsDown: flag)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize {
        let titleString = titleOfSelectedItem ?? ""
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13)
        ]
        let titleSize = titleString.size(withAttributes: attrs)
        return NSSize(width: max(100, titleSize.width + 48), height: 36)
    }

    override func selectItem(at index: Int) {
        super.selectItem(at: index)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func selectItem(withTitle title: String) {
        super.selectItem(withTitle: title)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private func setup() {
        wantsLayer = true
        isBordered = false
        if let popUpCell = cell as? NSPopUpButtonCell {
            popUpCell.arrowPosition = .noArrow
            popUpCell.isBordered = false
        }
        font = .systemFont(ofSize: 13, weight: .medium)
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea {
            removeTrackingArea(old)
        }
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let newArea = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        trackingArea = newArea
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isBlockedByMD3Dialog else { return }

        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let isHighlighted = cell?.isHighlighted == true
        let inset: CGFloat = isHighlighted ? 1.5 : 1.0
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: 8, yRadius: 8)

        if isHovered {
            MD3.surfaceContainer.setFill()
        } else {
            MD3.surfaceContainerLow.setFill()
        }
        path.fill()

        let strokeColor = isHighlighted ? MD3.primary : MD3.outlineVariant
        let strokeWidth: CGFloat = isHighlighted ? 2.0 : 1.0

        strokeColor.setStroke()
        path.lineWidth = strokeWidth
        path.stroke()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: MD3.onSurface,
            .paragraphStyle: paragraphStyle
        ]

        // Prefer the selected item's attributed title (the rule-type popup uses it to
        // grey the Chinese half); fall back to the plain title for other popups.
        if let attributed = selectedItem?.attributedTitle, attributed.length > 0 {
            let size = attributed.size()
            let rect = NSRect(
                x: 12,
                y: (bounds.height - size.height) / 2,
                width: bounds.width - 36,
                height: size.height
            )
            attributed.draw(in: rect)
        } else {
            let titleString = titleOfSelectedItem ?? ""
            let titleSize = titleString.size(withAttributes: attrs)
            let titleRect = NSRect(
                x: 12,
                y: (bounds.height - titleSize.height) / 2,
                width: bounds.width - 36,
                height: titleSize.height
            )
            titleString.draw(in: titleRect, withAttributes: attrs)
        }

        // Draw custom chevron arrow
        let isFlipped = self.isFlipped
        let iconCenterX = bounds.width - 18
        let iconCenterY = bounds.height / 2

        let pathArrow = NSBezierPath()
        pathArrow.lineWidth = 1.5
        pathArrow.lineCapStyle = .round
        pathArrow.lineJoinStyle = .round

        if isFlipped {
            pathArrow.move(to: NSPoint(x: iconCenterX - 4, y: iconCenterY - 2))
            pathArrow.line(to: NSPoint(x: iconCenterX, y: iconCenterY + 2))
            pathArrow.line(to: NSPoint(x: iconCenterX + 4, y: iconCenterY - 2))
        } else {
            pathArrow.move(to: NSPoint(x: iconCenterX - 4, y: iconCenterY + 2))
            pathArrow.line(to: NSPoint(x: iconCenterX, y: iconCenterY - 2))
            pathArrow.line(to: NSPoint(x: iconCenterX + 4, y: iconCenterY + 2))
        }

        MD3.onSurfaceVariant.setStroke()
        pathArrow.stroke()
    }

    func themeChanged() {
        needsDisplay = true
    }
}
// MARK: - MD3 Radio Button

final class MD3RadioButton: NSControl, MD3Themeable {
    var title: String = "" {
        didSet {
            labelField.stringValue = title
            invalidateIntrinsicContentSize()
        }
    }

    var isSelected: Bool = false {
        didSet {
            updateColors()
        }
    }

    override var isEnabled: Bool {
        didSet {
            updateColors()
        }
    }

    private let radioOuter = NSView()
    private let radioInner = NSView()
    private let labelField = NSTextField(labelWithString: "")

    private var isHovered = false {
        didSet {
            updateColors()
        }
    }

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = labelField.intrinsicContentSize
        return NSSize(width: 20 + 8 + labelSize.width, height: 24)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea {
            removeTrackingArea(old)
        }
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let newArea = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        trackingArea = newArea
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isBlockedByMD3Dialog else { return }

        guard isEnabled else { return }
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        guard isEnabled else { return }
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if !isSelected {
            isSelected = true
            sendAction(action, to: target)
        }
    }

    private func setup() {
        wantsLayer = true

        radioOuter.wantsLayer = true
        radioOuter.layer?.cornerRadius = 10
        radioOuter.layer?.borderWidth = 2
        radioOuter.translatesAutoresizingMaskIntoConstraints = false
        addSubview(radioOuter)

        radioInner.wantsLayer = true
        radioInner.layer?.cornerRadius = 5
        radioInner.translatesAutoresizingMaskIntoConstraints = false
        radioOuter.addSubview(radioInner)

        labelField.font = .systemFont(ofSize: 13, weight: .medium)
        labelField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)

        NSLayoutConstraint.activate([
            radioOuter.leadingAnchor.constraint(equalTo: leadingAnchor),
            radioOuter.centerYAnchor.constraint(equalTo: centerYAnchor),
            radioOuter.widthAnchor.constraint(equalToConstant: 20),
            radioOuter.heightAnchor.constraint(equalToConstant: 20),

            radioInner.centerXAnchor.constraint(equalTo: radioOuter.centerXAnchor),
            radioInner.centerYAnchor.constraint(equalTo: radioOuter.centerYAnchor),
            radioInner.widthAnchor.constraint(equalToConstant: 10),
            radioInner.heightAnchor.constraint(equalToConstant: 10),

            labelField.leadingAnchor.constraint(equalTo: radioOuter.trailingAnchor, constant: 8),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            heightAnchor.constraint(equalToConstant: 24)
        ])

        updateColors()
    }

    func updateColors() {
        if isEnabled {
            alphaValue = 1.0
            if isSelected {
                radioOuter.layer?.borderColor = MD3.primary.cgColor
                radioOuter.layer?.backgroundColor = isHovered ? MD3.primary.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
                radioInner.layer?.backgroundColor = MD3.primary.cgColor
                radioInner.isHidden = false
            } else {
                radioOuter.layer?.borderColor = MD3.outline.cgColor
                radioOuter.layer?.backgroundColor = isHovered ? MD3.onSurface.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
                radioInner.layer?.backgroundColor = NSColor.clear.cgColor
                radioInner.isHidden = true
            }
            labelField.textColor = MD3.onSurface
        } else {
            alphaValue = 0.38
            if isSelected {
                radioOuter.layer?.borderColor = MD3.onSurface.withAlphaComponent(0.38).cgColor
                radioInner.layer?.backgroundColor = MD3.onSurface.withAlphaComponent(0.38).cgColor
                radioInner.isHidden = false
            } else {
                radioOuter.layer?.borderColor = MD3.onSurface.withAlphaComponent(0.38).cgColor
                radioInner.isHidden = true
            }
            labelField.textColor = MD3.onSurface.withAlphaComponent(0.38)
        }
    }

    func themeChanged() {
        updateColors()
    }

    var state: NSControl.StateValue {
        get {
            isSelected ? .on : .off
        }
        set {
            isSelected = (newValue == .on)
        }
    }

    convenience init(radioButtonWithTitle title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.labelField.stringValue = title
        self.target = target
        self.action = action
        invalidateIntrinsicContentSize()
    }
}
