import AppKit
import Foundation

// MARK: - Color Mix & Hex Helper

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((hex & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(hex & 0x0000FF) / 255.0
        self.init(calibratedRed: r, green: g, blue: b, alpha: alpha)
    }

    func mixed(with color: NSColor, ratio: CGFloat) -> NSColor {
        guard let selfRGB = self.usingColorSpace(.deviceRGB),
              let targetRGB = color.usingColorSpace(.deviceRGB) else {
            return self
        }
        
        let r = selfRGB.redComponent * (1.0 - ratio) + targetRGB.redComponent * ratio
        let g = selfRGB.greenComponent * (1.0 - ratio) + targetRGB.greenComponent * ratio
        let b = selfRGB.blueComponent * (1.0 - ratio) + targetRGB.blueComponent * ratio
        let a = selfRGB.alphaComponent * (1.0 - ratio) + targetRGB.alphaComponent * ratio
        
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - MD3 Design System Colors

struct MD3ColorScheme: Sendable {
    let name: String
    let lightPrimary: NSColor
    let lightAccent: NSColor
    let lightBackground: NSColor
    let darkPrimary: NSColor
    let darkAccent: NSColor
    let darkBackground: NSColor
}

@MainActor
enum MD3 {
    static var isDark: Bool {
        get { _isDark }
        set { _isDark = newValue }
    }
    private static var _isDark = false

    static let colorSchemes: [MD3ColorScheme] = [
        MD3ColorScheme(
            name: "经典蓝 (Classic Blue)",
            lightPrimary: NSColor(hex: 0x1A73E8),
            lightAccent: NSColor(hex: 0xE8F0FE),
            lightBackground: NSColor(hex: 0xFAFAFF),
            darkPrimary: NSColor(hex: 0x8AB4F8),
            darkAccent: NSColor(hex: 0x174EA6),
            darkBackground: NSColor(hex: 0x0E1015)
        ),
        MD3ColorScheme(
            name: "翡翠绿 (Emerald Green)",
            lightPrimary: NSColor(hex: 0x0F9D58),
            lightAccent: NSColor(hex: 0xE6F4EA),
            lightBackground: NSColor(hex: 0xFAFBFB),
            darkPrimary: NSColor(hex: 0x81C995),
            darkAccent: NSColor(hex: 0x0D522C),
            darkBackground: NSColor(hex: 0x0E1310)
        ),
        MD3ColorScheme(
            name: "夕阳橙 (Sunset Orange)",
            lightPrimary: NSColor(hex: 0xE65100),
            lightAccent: NSColor(hex: 0xFDF0E6),
            lightBackground: NSColor(hex: 0xFCFAF9),
            darkPrimary: NSColor(hex: 0xFFB74D),
            darkAccent: NSColor(hex: 0x8D3C00),
            darkBackground: NSColor(hex: 0x13110E)
        ),
        MD3ColorScheme(
            name: "樱花粉 (Sakura Pink)",
            lightPrimary: NSColor(hex: 0xD81B60),
            lightAccent: NSColor(hex: 0xFCE4EC),
            lightBackground: NSColor(hex: 0xFFF9FA),
            darkPrimary: NSColor(hex: 0xF48FB1),
            darkAccent: NSColor(hex: 0x880E4F),
            darkBackground: NSColor(hex: 0x140E10)
        ),
        MD3ColorScheme(
            name: "紫罗兰 (Purple Velvet)",
            lightPrimary: NSColor(hex: 0x7B1FA2),
            lightAccent: NSColor(hex: 0xF3E5F5),
            lightBackground: NSColor(hex: 0xFAF9FB),
            darkPrimary: NSColor(hex: 0xCE93D8),
            darkAccent: NSColor(hex: 0x4A148C),
            darkBackground: NSColor(hex: 0x110E14)
        ),
        MD3ColorScheme(
            name: "深海绿 (Teal Breeze)",
            lightPrimary: NSColor(hex: 0x00796B),
            lightAccent: NSColor(hex: 0xE0F2F1),
            lightBackground: NSColor(hex: 0xF9FBFB),
            darkPrimary: NSColor(hex: 0x80CBC4),
            darkAccent: NSColor(hex: 0x004D40),
            darkBackground: NSColor(hex: 0x0E1313)
        ),
        MD3ColorScheme(
            name: "琥珀金 (Sandy Gold)",
            lightPrimary: NSColor(hex: 0xE6A100),
            lightAccent: NSColor(hex: 0xFFFDE7),
            lightBackground: NSColor(hex: 0xFCFCFA),
            darkPrimary: NSColor(hex: 0xFFD54F),
            darkAccent: NSColor(hex: 0x5F4B00),
            darkBackground: NSColor(hex: 0x13120E)
        ),
        MD3ColorScheme(
            name: "绯红红 (Crimson Red)",
            lightPrimary: NSColor(hex: 0xC62828),
            lightAccent: NSColor(hex: 0xFFEBEE),
            lightBackground: NSColor(hex: 0xFFFDFD),
            darkPrimary: NSColor(hex: 0xEF9A9A),
            darkAccent: NSColor(hex: 0x7F0000),
            darkBackground: NSColor(hex: 0x140E0E)
        ),
        MD3ColorScheme(
            name: "极客灰 (Charcoal Gray)",
            lightPrimary: NSColor(hex: 0x37474F),
            lightAccent: NSColor(hex: 0xECEFF1),
            lightBackground: NSColor(hex: 0xF8F9FA),
            darkPrimary: NSColor(hex: 0x90A4AE),
            darkAccent: NSColor(hex: 0x263238),
            darkBackground: NSColor(hex: 0x101213)
        ),
        MD3ColorScheme(
            name: "靛蓝夜 (Indigo Night)",
            lightPrimary: NSColor(hex: 0x3F51B5),
            lightAccent: NSColor(hex: 0xE8EAF6),
            lightBackground: NSColor(hex: 0xFAF9FD),
            darkPrimary: NSColor(hex: 0x9FA8DA),
            darkAccent: NSColor(hex: 0x1A237E),
            darkBackground: NSColor(hex: 0x0E0F14)
        )
    ]

    static var currentSchemeIndex: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: "MD3ColorSchemeIndex")
            if val >= 0 && val < colorSchemes.count {
                return val
            }
            return 0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "MD3ColorSchemeIndex")
        }
    }
    
    static var currentScheme: MD3ColorScheme {
        colorSchemes[currentSchemeIndex]
    }

    static var primary: NSColor {
        isDark ? currentScheme.darkPrimary : currentScheme.lightPrimary
    }
    static var onPrimary: NSColor {
        isDark ? currentScheme.darkBackground : NSColor.white
    }
    static var primaryContainer: NSColor {
        isDark ? currentScheme.darkAccent : currentScheme.lightAccent
    }
    static var onPrimaryContainer: NSColor {
        isDark ? currentScheme.darkPrimary : currentScheme.lightPrimary
    }
    
    static var secondaryContainer: NSColor {
        isDark ? currentScheme.darkAccent.mixed(with: .white, ratio: 0.1) : currentScheme.lightAccent.mixed(with: .black, ratio: 0.05)
    }
    static var onSecondaryContainer: NSColor {
        isDark ? currentScheme.darkPrimary : currentScheme.lightPrimary
    }
    
    static var surface: NSColor {
        isDark ? currentScheme.darkBackground.mixed(with: .white, ratio: 0.06) : NSColor.white
    }
    static var onSurface: NSColor {
        isDark ? NSColor(calibratedRed: 0.89, green: 0.89, blue: 0.92, alpha: 1) : NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1)
    }
    static var surfaceContainer: NSColor {
        isDark ? currentScheme.darkBackground.mixed(with: .white, ratio: 0.12) : currentScheme.lightBackground.mixed(with: currentScheme.lightPrimary, ratio: 0.04)
    }
    static var surfaceContainerLow: NSColor {
        isDark ? currentScheme.darkBackground.mixed(with: .white, ratio: 0.08) : currentScheme.lightBackground.mixed(with: currentScheme.lightPrimary, ratio: 0.02)
    }
    static var onSurfaceVariant: NSColor {
        isDark ? NSColor(calibratedRed: 0.75, green: 0.76, blue: 0.80, alpha: 1) : NSColor(calibratedRed: 0.27, green: 0.28, blue: 0.33, alpha: 1)
    }
    static var outline: NSColor {
        isDark ? NSColor(calibratedRed: 0.54, green: 0.55, blue: 0.59, alpha: 1) : NSColor(calibratedRed: 0.45, green: 0.46, blue: 0.51, alpha: 1)
    }
    static var outlineVariant: NSColor {
        isDark ? currentScheme.darkBackground.mixed(with: currentScheme.darkPrimary, ratio: 0.12) : currentScheme.lightBackground.mixed(with: currentScheme.lightPrimary, ratio: 0.08)
    }
    static var background: NSColor {
        isDark ? currentScheme.darkBackground : currentScheme.lightBackground
    }
    
    // Status colors
    static var success: NSColor {
        isDark ? NSColor(calibratedRed: 0.44, green: 0.81, blue: 0.55, alpha: 1) : NSColor(calibratedRed: 0.10, green: 0.55, blue: 0.23, alpha: 1)
    }
    static var successContainer: NSColor {
        isDark ? NSColor(calibratedRed: 0.05, green: 0.28, blue: 0.12, alpha: 1) : NSColor(calibratedRed: 0.85, green: 0.95, blue: 0.88, alpha: 1)
    }
    static var onSuccessContainer: NSColor {
        isDark ? NSColor(calibratedRed: 0.70, green: 0.94, blue: 0.76, alpha: 1) : NSColor(calibratedRed: 0.03, green: 0.22, blue: 0.07, alpha: 1)
    }
    
    static var error: NSColor {
        isDark ? NSColor(calibratedRed: 1.00, green: 0.45, blue: 0.45, alpha: 1) : NSColor(calibratedRed: 0.75, green: 0.10, blue: 0.10, alpha: 1)
    }
}

// MARK: - View Theme Refresh Helper

@MainActor
protocol MD3Themeable: AnyObject {
    func themeChanged()
}

extension NSView {
    func refreshSubviews() {
        self.needsDisplay = true
        if let themeable = self as? MD3Themeable {
            themeable.themeChanged()
        }
        for subview in subviews {
            subview.refreshSubviews()
        }
    }
}

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
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    override func mouseEntered(with event: NSEvent) {
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
        let font = style == .nav
            ? NSFont.systemFont(ofSize: 14, weight: self.state == .on ? .bold : .medium)
            : NSFont.systemFont(ofSize: 13, weight: .semibold)
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
            layer.borderWidth = 0
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = MD3.isDark ? 0.3 : 0.06
            layer.shadowRadius = 6
            layer.shadowOffset = CGSize(width: 0, height: -2)
        case .filled:
            layer.backgroundColor = MD3.surfaceContainer.cgColor
            layer.borderWidth = 0
            layer.shadowOpacity = 0
        case .outlined:
            layer.backgroundColor = NSColor.clear.cgColor
            layer.borderColor = MD3.outlineVariant.cgColor
            layer.borderWidth = 1.0
            layer.shadowOpacity = 0
        }
    }
    
    func themeChanged() {
        self.needsDisplay = true
    }
}

// MARK: - MD3 Status Chip

final class MD3StatusChip: NSView, MD3Themeable {
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")
    
    var isActive: Bool = false {
        didSet { updateStatus() }
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
        
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(dot)
        addSubview(label)
        
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        updateStatus()
    }
    
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        super.updateLayer()
        if isActive {
            layer?.backgroundColor = MD3.successContainer.cgColor
            layer?.borderWidth = 0
            label.textColor = MD3.onSuccessContainer
            dot.layer?.backgroundColor = MD3.success.cgColor
        } else {
            layer?.backgroundColor = MD3.surfaceContainer.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = MD3.outlineVariant.cgColor
            label.textColor = MD3.onSurfaceVariant
            dot.layer?.backgroundColor = MD3.onSurfaceVariant.cgColor
        }
    }
    
    private func updateStatus() {
        label.stringValue = isActive ? "运行中" : "未启动"
        self.needsDisplay = true
        
        dot.layer?.removeAllAnimations()
        if isActive {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1.0
            anim.toValue = 0.3
            anim.duration = 0.8
            anim.autoreverses = true
            anim.repeatCount = .infinity
            dot.layer?.add(anim, forKey: "pulse")
        }
    }
    
    func themeChanged() {
        self.needsDisplay = true
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
                if ms < 150 {
                    layer?.backgroundColor = MD3.successContainer.cgColor
                    layer?.borderWidth = 0
                    label.textColor = MD3.onSuccessContainer
                } else if ms < 400 {
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

// MARK: - MD3 Table Cell Views

final class MD3ProfileCellView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    func configure(with profile: ConfigProfile, isSelected: Bool) {
        titleLabel.stringValue = profile.name
        titleLabel.textColor = isSelected ? MD3.onPrimaryContainer : MD3.onSurface
    }
}

final class MD3SubscriptionCellView: NSTableCellView, MD3Themeable {
    private let cardView = NSView()
    private let iconView = NSImageView()
    private let checkImageView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(labelWithString: "")
    
    private var isSelected = false
    
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
        
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 12
        cardView.layer?.borderWidth = 1
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)
        
        iconView.image = NSImage(systemSymbolName: "personalhotspot", accessibilityDescription: nil)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(iconView)
        
        // 勾选 Icon
        checkImageView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        checkImageView.imageScaling = .scaleProportionallyDown
        checkImageView.translatesAutoresizingMaskIntoConstraints = false
        checkImageView.isHidden = true
        cardView.addSubview(checkImageView)
        
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.alignment = .right
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        cardView.addSubview(titleLabel)
        cardView.addSubview(subtitleLabel)
        cardView.addSubview(statusLabel)
        
        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            cardView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            
            iconView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -16),
            
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -16),
            
            checkImageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            checkImageView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            checkImageView.widthAnchor.constraint(equalToConstant: 18),
            checkImageView.heightAnchor.constraint(equalToConstant: 18),
            
            statusLabel.trailingAnchor.constraint(equalTo: checkImageView.leadingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            statusLabel.widthAnchor.constraint(equalToConstant: 130)
        ])
        
        updateColors()
    }
    
    func configure(with sub: Subscription, selected: Bool = false) {
        self.isSelected = selected
        
        titleLabel.stringValue = sub.name
        subtitleLabel.stringValue = sub.url
        
        if let updateDate = sub.updatedAt {
            statusLabel.stringValue = "更新于: \(DateFormatter.short.string(from: updateDate))"
        } else {
            statusLabel.stringValue = "未刷新"
        }
        
        updateColors()
    }
    
    func updateColors(selected: Bool) {
        self.isSelected = selected
        updateColors()
    }
    
    func updateColors() {
        checkImageView.isHidden = !isSelected
        
        // Remove background fill completely so it blends with the window background
        cardView.layer?.backgroundColor = NSColor.clear.cgColor
        
        if isSelected {
            cardView.layer?.borderWidth = 1.5
            cardView.layer?.borderColor = MD3.primary.cgColor
            titleLabel.textColor = MD3.primary
            subtitleLabel.textColor = MD3.onSurfaceVariant
            statusLabel.textColor = MD3.onSurfaceVariant
            iconView.contentTintColor = MD3.primary
            checkImageView.contentTintColor = MD3.primary
        } else {
            cardView.layer?.borderWidth = 1.0
            cardView.layer?.borderColor = MD3.outlineVariant.cgColor
            titleLabel.textColor = MD3.onSurface
            subtitleLabel.textColor = MD3.onSurfaceVariant
            statusLabel.textColor = MD3.onSurfaceVariant
            iconView.contentTintColor = MD3.onSurfaceVariant
        }
    }
    
    func themeChanged() {
        updateColors()
    }
}

final class MD3NodeCellView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    let urlDelayChip = MD3LatencyChip()
    let tcpDelayChip = MD3LatencyChip()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        urlDelayChip.translatesAutoresizingMaskIntoConstraints = false
        tcpDelayChip.translatesAutoresizingMaskIntoConstraints = false
        tcpDelayChip.isHidden = true
        
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(urlDelayChip)
        addSubview(tcpDelayChip)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: urlDelayChip.leadingAnchor, constant: -16),
            
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: urlDelayChip.leadingAnchor, constant: -16),
            
            urlDelayChip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            urlDelayChip.centerYAnchor.constraint(equalTo: centerYAnchor),
            urlDelayChip.widthAnchor.constraint(equalToConstant: 75)
        ])
    }
    
    func configure(with node: NodeInfo) {
        titleLabel.stringValue = node.tag
        titleLabel.textColor = MD3.onSurface
        
        subtitleLabel.stringValue = "\(node.type.uppercased())  •  \(node.server)"
        subtitleLabel.textColor = MD3.onSurfaceVariant
        
        urlDelayChip.value = node.delay
    }
}

// MARK: - MD3 Table Row View (Custom Rounded Selection)

final class MD3TableRowView: NSTableRowView {
    private let selectionIndicator = NSView()
    
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
        selectionIndicator.wantsLayer = true
        selectionIndicator.layer?.cornerRadius = 10
        addSubview(selectionIndicator)
    }
    
    override func layout() {
        super.layout()
        selectionIndicator.frame = bounds.insetBy(dx: 6, dy: 3)
    }
    
    override func drawSelection(in dirtyRect: NSRect) {
        // Skip native blue selection background drawing
    }
    
    override var wantsUpdateLayer: Bool { true }
    
    override func updateLayer() {
        super.updateLayer()
        selectionIndicator.isHidden = !isSelected
        selectionIndicator.layer?.backgroundColor = MD3.primaryContainer.cgColor
        
        for sub in subviews {
            if let cell = sub as? NSTableCellView {
                if cell is MD3SubscriptionCellView {
                    selectionIndicator.isHidden = true
                }
                updateCellColors(cell, selected: isSelected)
            }
        }
    }
    
    override var isSelected: Bool {
        didSet {
            self.needsDisplay = true
            selectionIndicator.isHidden = !isSelected
            
            for sub in subviews {
                if let cell = sub as? NSTableCellView {
                    if cell is MD3SubscriptionCellView {
                        selectionIndicator.isHidden = true
                    }
                    updateCellColors(cell, selected: isSelected)
                }
            }
        }
    }
    
    private func updateCellColors(_ cell: NSTableCellView, selected: Bool) {
        if let profileCell = cell as? MD3ProfileCellView {
            profileCell.titleLabel.textColor = selected ? MD3.onPrimaryContainer : MD3.onSurface
        } else if let subCell = cell as? MD3SubscriptionCellView {
            subCell.updateColors(selected: selected)
        } else if let nodeCell = cell as? MD3NodeCellView {
            nodeCell.titleLabel.textColor = selected ? MD3.onPrimaryContainer : MD3.onSurface
            nodeCell.subtitleLabel.textColor = selected ? MD3.onPrimaryContainer.withAlphaComponent(0.8) : MD3.onSurfaceVariant
        }
    }
}

// MARK: - MD3 Sidebar Item

final class MD3SidebarItem: NSView, MD3Themeable {
    private let iconView = NSImageView()
    private let labelField = NSTextField(labelWithString: "")
    private let selectionPill = NSView()
    
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
            labelField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor)
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
        if isPressed {
            isPressed = false
            if let target = target, let action = action {
                NSApplication.shared.sendAction(action, to: target, from: self)
            }
        }
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

// MARK: - MD3 Switch
final class MD3Switch: NSControl, MD3Themeable {
    private let track = NSView()
    private let thumb = NSView()
    
    var isOn: Bool = false {
        didSet {
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
        
        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)
        
        updateVisuals(animated: false)
    }
    
    @objc private func clicked() {
        guard isEnabled else { return }
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

// MARK: - MD3 Node Tile View
final class MD3NodeTileView: NSView, MD3Themeable {
    let nameLabel = NSTextField(labelWithString: "")
    let subLabel = NSTextField(labelWithString: "")
    let actionButton = NSButton()
    
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
        
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = MD3.onSurface
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        
        subLabel.font = .systemFont(ofSize: 9, weight: .regular)
        subLabel.textColor = MD3.onSurfaceVariant
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        
        actionButton.isBordered = false
        actionButton.wantsLayer = true
        actionButton.layer?.cornerRadius = 4
        actionButton.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.target = self
        actionButton.action = #selector(actionButtonClicked)
        
        addSubview(nameLabel)
        addSubview(subLabel)
        addSubview(actionButton)
        
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            
            subLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            subLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            subLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -6),
            
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            actionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            actionButton.heightAnchor.constraint(equalToConstant: 18),
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 28)
        ])
        
        updateStyle()
    }
    
    func themeChanged() {
        updateStyle()
    }
    
    private func updateStyle() {
        if !isInteractive {
            layer?.backgroundColor = MD3.surfaceContainerLow.cgColor
            nameLabel.textColor = MD3.onSurfaceVariant.withAlphaComponent(0.6)
            subLabel.textColor = MD3.onSurfaceVariant.withAlphaComponent(0.4)
        } else if isSelected {
            layer?.backgroundColor = MD3.primary.cgColor
            nameLabel.textColor = MD3.onPrimary
            subLabel.textColor = MD3.onPrimary.withAlphaComponent(0.7)
        } else {
            layer?.backgroundColor = MD3.surfaceContainerLow.cgColor
            nameLabel.textColor = MD3.onSurface
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
            actionButton.contentTintColor = (isSelected && isInteractive) ? MD3.onPrimary : MD3.primary
        } else if delay.isEmpty || delay == "未测试" || delay == "—" {
            actionButton.image = NSImage(systemSymbolName: "bolt", accessibilityDescription: "测试延迟")
            actionButton.title = ""
            actionButton.layer?.backgroundColor = NSColor.clear.cgColor
            actionButton.contentTintColor = (isSelected && isInteractive) ? MD3.onPrimary : (isInteractive ? MD3.onSurfaceVariant : MD3.onSurfaceVariant.withAlphaComponent(0.6))
        } else {
            actionButton.image = nil
            let numStr = delay.replacingOccurrences(of: " ms", with: "")
            actionButton.title = numStr
            
            let colors = getDelayColors(delayStr: delay, isSelected: isSelected && isInteractive)
            actionButton.layer?.backgroundColor = colors.bg.cgColor
            actionButton.contentTintColor = colors.text
        }
    }
    
    private func getDelayColors(delayStr: String, isSelected: Bool) -> (bg: NSColor, text: NSColor) {
        if isSelected {
            return (NSColor.white.withAlphaComponent(0.2), NSColor.white)
        }
        
        let cleaned = delayStr.replacingOccurrences(of: " ms", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ms = Int(cleaned) else {
            return (MD3.surfaceContainer, MD3.onSurfaceVariant)
        }
        
        if ms < 100 {
            // Excellent (Green)
            let bg = NSColor(red: 0.88, green: 0.96, blue: 0.90, alpha: 1.0)
            let text = NSColor(red: 0.15, green: 0.54, blue: 0.28, alpha: 1.0)
            return (bg, text)
        } else if ms < 250 {
            // Normal (Yellow)
            let bg = NSColor(red: 0.99, green: 0.96, blue: 0.85, alpha: 1.0)
            let text = NSColor(red: 0.65, green: 0.45, blue: 0.05, alpha: 1.0)
            return (bg, text)
        } else {
            // Poor (Red)
            let bg = NSColor(red: 0.99, green: 0.90, blue: 0.90, alpha: 1.0)
            let text = NSColor(red: 0.80, green: 0.20, blue: 0.20, alpha: 1.0)
            return (bg, text)
        }
    }
    
    @objc private func actionButtonClicked() {
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
                if ms < 100 {
                    label.textColor = NSColor(red: 0.15, green: 0.54, blue: 0.28, alpha: 1.0)
                } else if ms < 250 {
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
