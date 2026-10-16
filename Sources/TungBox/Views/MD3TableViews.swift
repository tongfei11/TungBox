import AppKit
import Foundation

// MARK: - 紧贴字符的 Label Cell（无左右 padding）

/// 标准 `NSTextField(labelWithString:)` 在大字号下会有 ≈ 2-4pt 的水平 cell padding，
/// 导致字符视觉左缘 比 frame.x 多缩进几 pt —— 视觉上和按钮/卡片对不齐。
/// 这个 cell 把 padding 清零，字符从 frame.leading 紧贴绘制。
final class MD3TightLabelCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect { rect }
    override func titleRect(forBounds rect: NSRect) -> NSRect { rect }
}

/// 替换给定 NSTextField 的 cell 为紧贴版本，保留原有的字体/颜色/字符串。
@MainActor
func tightenLabelCell(_ label: NSTextField) {
    let new = MD3TightLabelCell()
    new.isEditable = false
    new.isBordered = false
    new.drawsBackground = false
    new.font = label.font
    new.textColor = label.textColor
    new.stringValue = label.stringValue
    new.alignment = label.alignment
    new.lineBreakMode = label.lineBreakMode
    new.usesSingleLineMode = true
    label.cell = new
}

// MARK: - MD3 Thin Overlay Scroller

/// 极简滚动条：
/// - 宽度只有系统默认的一半（≈ 7pt）
/// - 完全透明的滑槽（无灰条占位）
/// - 仅滚动时显示，停止后立即淡出
/// 配合 NSScrollView 的 `scrollerStyle = .overlay`。
final class MD3ThinScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        // 系统 overlay scroller 一般 15pt → 减半
        return 7
    }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // 不画滑槽底色
    }
    override func drawKnob() {
        let r = rect(for: .knob).insetBy(dx: 1.5, dy: 2)
        guard r.width > 0, r.height > 0 else { return }
        let radius = min(r.width, r.height) / 2
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        NSColor.secondaryLabelColor.withAlphaComponent(0.55).setFill()
        path.fill()
    }
    override func draw(_ dirtyRect: NSRect) {
        // 只画滑块，不画滑轨背景与边框
        drawKnob()
    }
}

class MD3ScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        self.scrollerStyle = .overlay
        self.autohidesScrollers = true
        self.drawsBackground = false
        if self.verticalScroller == nil { self.verticalScroller = MD3ThinScroller() }
        else if !(self.verticalScroller is MD3ThinScroller) { self.verticalScroller = MD3ThinScroller() }
        if self.horizontalScroller == nil { self.horizontalScroller = MD3ThinScroller() }
        else if !(self.horizontalScroller is MD3ThinScroller) { self.horizontalScroller = MD3ThinScroller() }
        self.verticalScroller?.knobStyle = .default
        self.horizontalScroller?.knobStyle = .default
    }

    override var scrollerStyle: NSScroller.Style {
        get { return .overlay }
        set { super.scrollerStyle = .overlay }
    }

    override func tile() {
        if self.scrollerStyle != .overlay {
            self.scrollerStyle = .overlay
        }
        super.tile()

        if verticalScroller == nil { verticalScroller = MD3ThinScroller() }
        else if !(verticalScroller is MD3ThinScroller) { verticalScroller = MD3ThinScroller() }
        if let h = horizontalScroller, !(h is MD3ThinScroller) {
            horizontalScroller = MD3ThinScroller()
        }
        verticalScroller?.knobStyle = .default
        horizontalScroller?.knobStyle = .default
    }
}

extension NSScrollView {
    /// 应用极简悬浮滚动条样式：无底色占位、宽度减半、仅滚动时显示。
    func applyThinOverlayScroller() {
        scrollerStyle = .overlay
        autohidesScrollers = true
        drawsBackground = false
        if verticalScroller == nil { verticalScroller = MD3ThinScroller() }
        else if !(verticalScroller is MD3ThinScroller) { verticalScroller = MD3ThinScroller() }
        if let h = horizontalScroller, !(h is MD3ThinScroller) {
            horizontalScroller = MD3ThinScroller()
        }
        // 让 knob 滚停后立即消失（fade out 立即触发）
        verticalScroller?.knobStyle = .default
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

final class MD3SubscriptionItemView: NSView, MD3Themeable {
    private let card = NSView()
    let titleLabel = NSTextField(labelWithString: "")
    let updatedAtPill = NSView()
    let updatedAtLabel = NSTextField(labelWithString: "")
    let refreshButton = NSButton()

    let domainStack = NSStackView()
    let linkIconView = NSImageView()
    let domainLabel = NSTextField(labelWithString: "")

    let trafficBox = NSView()
    let trafficHeaderLabel = NSTextField(labelWithString: "已用流量")
    let trafficLabel = NSTextField(labelWithString: "")
    let trafficPercentLabel = NSTextField(labelWithString: "")
    let trafficBar = NSView()
    let trafficFill = NSView()
    private var trafficFillWidth: NSLayoutConstraint!

    let expireRow = NSStackView()
    let expireIconCircle = NSView()
    let expireIconView = NSImageView()
    let expireTextCol = NSStackView()
    let expireTitleLabel = NSTextField(labelWithString: "到期时间")
    let expiresLabel = NSTextField(labelWithString: "")
    let errorLabel = NSTextField(labelWithString: "")

    var isSelected = false { didSet { updateColors() } }
    var isHovered = false { didSet { updateColors() } }
    var isRefreshing = false {
        didSet {
            if isRefreshing { startRefreshSpin() } else { stopRefreshSpin() }
        }
    }
    var onClick: (() -> Void)?
    var onRefresh: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder); setup()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
        addTrackingArea(area); trackingArea = area
    }
    override func mouseEntered(with event: NSEvent) {
        guard !isBlockedByMD3Dialog else { return }
        isHovered = true
    }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { onClick?() }

    private func setup() {
        wantsLayer = true

        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        updatedAtPill.wantsLayer = true
        updatedAtPill.layer?.cornerRadius = 10
        updatedAtPill.translatesAutoresizingMaskIntoConstraints = false

        updatedAtLabel.font = .systemFont(ofSize: 10, weight: .medium)
        updatedAtLabel.alignment = .center
        updatedAtLabel.lineBreakMode = .byTruncatingTail
        updatedAtLabel.maximumNumberOfLines = 1
        updatedAtLabel.translatesAutoresizingMaskIntoConstraints = false
        updatedAtPill.addSubview(updatedAtLabel)

        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")
        refreshButton.isBordered = false
        refreshButton.bezelStyle = .regularSquare
        refreshButton.imageScaling = .scaleProportionallyDown
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.wantsLayer = true
        refreshButton.layer?.cornerRadius = 13
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)

        linkIconView.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        linkIconView.translatesAutoresizingMaskIntoConstraints = false
        linkIconView.imageScaling = .scaleProportionallyDown

        domainLabel.font = .systemFont(ofSize: 11)
        domainLabel.lineBreakMode = .byTruncatingTail
        domainLabel.maximumNumberOfLines = 1
        domainLabel.translatesAutoresizingMaskIntoConstraints = false

        domainStack.orientation = .horizontal
        domainStack.spacing = 4
        domainStack.alignment = .centerY
        domainStack.translatesAutoresizingMaskIntoConstraints = false
        domainStack.addArrangedSubview(linkIconView)
        domainStack.addArrangedSubview(domainLabel)

        // Traffic Box
        trafficBox.wantsLayer = true
        trafficBox.layer?.cornerRadius = 8
        trafficBox.translatesAutoresizingMaskIntoConstraints = false

        trafficHeaderLabel.font = .systemFont(ofSize: 10, weight: .medium)
        trafficHeaderLabel.translatesAutoresizingMaskIntoConstraints = false

        trafficLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        trafficLabel.lineBreakMode = .byTruncatingTail
        trafficLabel.maximumNumberOfLines = 1
        trafficLabel.translatesAutoresizingMaskIntoConstraints = false

        trafficPercentLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        trafficPercentLabel.alignment = .right
        trafficPercentLabel.translatesAutoresizingMaskIntoConstraints = false

        trafficBar.wantsLayer = true
        trafficBar.layer?.cornerRadius = 3
        trafficBar.translatesAutoresizingMaskIntoConstraints = false

        trafficFill.wantsLayer = true
        trafficFill.layer?.cornerRadius = 3
        trafficFill.translatesAutoresizingMaskIntoConstraints = false
        trafficBar.addSubview(trafficFill)

        trafficBox.addSubview(trafficHeaderLabel)
        trafficBox.addSubview(trafficLabel)
        trafficBox.addSubview(trafficPercentLabel)
        trafficBox.addSubview(trafficBar)

        trafficFillWidth = trafficFill.widthAnchor.constraint(equalTo: trafficBar.widthAnchor, multiplier: 0)

        // Expiration Row
        expireIconCircle.wantsLayer = true
        expireIconCircle.layer?.cornerRadius = 12
        expireIconCircle.translatesAutoresizingMaskIntoConstraints = false

        expireIconView.translatesAutoresizingMaskIntoConstraints = false
        expireIconView.imageScaling = .scaleProportionallyDown
        expireIconCircle.addSubview(expireIconView)

        expireTitleLabel.font = .systemFont(ofSize: 9, weight: .regular)
        expireTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        expiresLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        expiresLabel.translatesAutoresizingMaskIntoConstraints = false

        expireTextCol.orientation = .vertical
        expireTextCol.spacing = 1
        expireTextCol.alignment = .leading
        expireTextCol.translatesAutoresizingMaskIntoConstraints = false
        expireTextCol.addArrangedSubview(expireTitleLabel)
        expireTextCol.addArrangedSubview(expiresLabel)

        expireRow.orientation = .horizontal
        expireRow.spacing = 8
        expireRow.alignment = .centerY
        expireRow.translatesAutoresizingMaskIntoConstraints = false
        expireRow.addArrangedSubview(expireIconCircle)
        expireRow.addArrangedSubview(expireTextCol)

        errorLabel.font = .systemFont(ofSize: 10, weight: .medium)
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.maximumNumberOfLines = 1
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.isHidden = true

        for label in [titleLabel, domainLabel, trafficLabel, trafficPercentLabel, updatedAtLabel, expiresLabel, errorLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        card.addSubview(titleLabel)
        card.addSubview(updatedAtPill)
        card.addSubview(refreshButton)
        card.addSubview(domainStack)
        card.addSubview(trafficBox)
        card.addSubview(expireRow)
        card.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Top Row
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: updatedAtPill.leadingAnchor, constant: -8),

            refreshButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            refreshButton.widthAnchor.constraint(equalToConstant: 26),
            refreshButton.heightAnchor.constraint(equalToConstant: 26),

            updatedAtPill.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            updatedAtPill.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -6),
            updatedAtPill.heightAnchor.constraint(equalToConstant: 20),

            updatedAtLabel.leadingAnchor.constraint(equalTo: updatedAtPill.leadingAnchor, constant: 8),
            updatedAtLabel.trailingAnchor.constraint(equalTo: updatedAtPill.trailingAnchor, constant: -8),
            updatedAtLabel.centerYAnchor.constraint(equalTo: updatedAtPill.centerYAnchor),

            // Sub-header
            linkIconView.widthAnchor.constraint(equalToConstant: 12),
            linkIconView.heightAnchor.constraint(equalToConstant: 12),

            domainStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            domainStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            domainStack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16),

            // Traffic Box
            trafficBox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            trafficBox.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            trafficBox.topAnchor.constraint(equalTo: domainStack.bottomAnchor, constant: 10),
            trafficBox.heightAnchor.constraint(equalToConstant: 50),

            trafficHeaderLabel.leadingAnchor.constraint(equalTo: trafficBox.leadingAnchor, constant: 10),
            trafficHeaderLabel.topAnchor.constraint(equalTo: trafficBox.topAnchor, constant: 6),

            trafficLabel.leadingAnchor.constraint(equalTo: trafficHeaderLabel.leadingAnchor),
            trafficLabel.topAnchor.constraint(equalTo: trafficHeaderLabel.bottomAnchor, constant: 1),
            trafficLabel.trailingAnchor.constraint(lessThanOrEqualTo: trafficPercentLabel.leadingAnchor, constant: -8),

            trafficPercentLabel.trailingAnchor.constraint(equalTo: trafficBox.trailingAnchor, constant: -10),
            trafficPercentLabel.centerYAnchor.constraint(equalTo: trafficLabel.centerYAnchor),

            trafficBar.leadingAnchor.constraint(equalTo: trafficBox.leadingAnchor, constant: 10),
            trafficBar.trailingAnchor.constraint(equalTo: trafficBox.trailingAnchor, constant: -10),
            trafficBar.bottomAnchor.constraint(equalTo: trafficBox.bottomAnchor, constant: -7),
            trafficBar.heightAnchor.constraint(equalToConstant: 5),

            trafficFill.leadingAnchor.constraint(equalTo: trafficBar.leadingAnchor),
            trafficFill.topAnchor.constraint(equalTo: trafficBar.topAnchor),
            trafficFill.bottomAnchor.constraint(equalTo: trafficBar.bottomAnchor),
            trafficFillWidth,

            // Expiration Row
            expireIconCircle.widthAnchor.constraint(equalToConstant: 24),
            expireIconCircle.heightAnchor.constraint(equalToConstant: 24),
            expireIconView.centerXAnchor.constraint(equalTo: expireIconCircle.centerXAnchor),
            expireIconView.centerYAnchor.constraint(equalTo: expireIconCircle.centerYAnchor),
            expireIconView.widthAnchor.constraint(equalToConstant: 13),
            expireIconView.heightAnchor.constraint(equalToConstant: 13),

            expireRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            expireRow.topAnchor.constraint(equalTo: trafficBox.bottomAnchor, constant: 9),
            expireRow.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16),

            errorLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            errorLabel.topAnchor.constraint(equalTo: trafficBox.bottomAnchor, constant: 10),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16)
        ])

        updateColors()
    }

    @objc private func refreshClicked() {
        guard !isRefreshing else { return }
        isRefreshing = true
        onRefresh?()
        // 即便上层瞬间完成也至少转一圈，避免动画一闪而过感觉没反应
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isRefreshing = false
        }
    }

    private func startRefreshSpin() {
        guard let layer = refreshButton.layer, layer.bounds.width > 0 else { return }
        // NSView 的 backing layer 在 macOS 上 anchorPoint 默认是 (0, 0) ——
        // transform.rotation.z 会绕左下角转，导致图标在按钮区域内绕大圈跑。
        // 把 anchorPoint 移到中心，同时把 position 同步偏移，保证视觉 frame 不动。
        if layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            let oldAnchor = layer.anchorPoint
            let dx = (0.5 - oldAnchor.x) * layer.bounds.width
            let dy = (0.5 - oldAnchor.y) * layer.bounds.height
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: layer.position.x + dx, y: layer.position.y + dy)
        }
        layer.removeAnimation(forKey: "spin")
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -CGFloat.pi * 2
        spin.duration = 0.9
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        layer.add(spin, forKey: "spin")
    }

    private func stopRefreshSpin() {
        refreshButton.layer?.removeAnimation(forKey: "spin")
    }

    func configure(with sub: Subscription, selected: Bool) {
        self.isSelected = selected

        titleLabel.stringValue = sub.name
        domainLabel.stringValue = URL(string: sub.url)?.host ?? sub.url

        // 流量
        let used = SubscriptionTraffic.used(upload: sub.upload, download: sub.download)
        if let total = sub.total, total > 0 {
            let warning = SubscriptionTraffic.isInconsistent(used: used, total: total) ? " (异常)" : ""
            trafficLabel.stringValue = "\(Self.formatBytes(used)) / \(Self.formatBytes(total))\(warning)"
            let frac = max(0, min(1, Double(used) / Double(total)))
            trafficPercentLabel.stringValue = String(format: "%.1f%%", frac * 100)
            trafficFillWidth.isActive = false
            trafficFillWidth = trafficFill.widthAnchor.constraint(equalTo: trafficBar.widthAnchor, multiplier: CGFloat(max(frac, 0.001)))
            trafficFillWidth.isActive = true
        } else {
            if let total = sub.total, SubscriptionTraffic.isInconsistent(used: used, total: total) {
                trafficLabel.stringValue = "流量数据异常"
            } else {
                trafficLabel.stringValue = used > 0 ? "\(Self.formatBytes(used)) / 不限" : "未获取流量信息"
            }
            trafficPercentLabel.stringValue = ""
            trafficFillWidth.isActive = false
            trafficFillWidth = trafficFill.widthAnchor.constraint(equalTo: trafficBar.widthAnchor, multiplier: 0)
            trafficFillWidth.isActive = true
        }

        // 上次刷新
        if let updated = sub.updatedAt {
            updatedAtLabel.stringValue = Self.relativeAgo(from: updated)
        } else {
            updatedAtLabel.stringValue = "未刷新"
        }

        // 到期
        if let exp = sub.expiresAt {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            expiresLabel.stringValue = f.string(from: exp)
            expireTitleLabel.stringValue = "到期时间"
            expireIconView.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "到期时间")
        } else {
            expiresLabel.stringValue = "无限期"
            expireTitleLabel.stringValue = "有效期"
            expireIconView.image = NSImage(systemSymbolName: "infinity", accessibilityDescription: "无限期")
        }

        // 错误
        if let err = sub.lastError, !err.isEmpty {
            errorLabel.stringValue = "失败：\(String(err.prefix(60)))"
            errorLabel.isHidden = false
            trafficLabel.isHidden = true
            expireRow.isHidden = true
        } else {
            errorLabel.isHidden = true
            trafficLabel.isHidden = false
            expireRow.isHidden = false
        }

        updateColors()
    }

    func updateColors() {
        let isDark = MD3.isDark
        if isSelected {
            card.layer?.backgroundColor = isDark
                ? MD3.primary.withAlphaComponent(0.12).cgColor
                : MD3.primaryContainer.withAlphaComponent(0.4).cgColor
            card.layer?.borderColor = MD3.primary.cgColor
            card.layer?.borderWidth = 1.8
            card.layer?.shadowColor = MD3.primary.cgColor
            card.layer?.shadowRadius = 8
            card.layer?.shadowOpacity = 0.28
            card.layer?.shadowOffset = .zero
        } else {
            let bg = isHovered ? MD3.surfaceContainerHigh : MD3.surfaceContainer
            card.layer?.backgroundColor = bg.cgColor
            card.layer?.borderColor = MD3.outlineVariant.withAlphaComponent(0.35).cgColor
            card.layer?.borderWidth = 1
            card.layer?.shadowOpacity = 0
        }

        titleLabel.textColor = MD3.onSurface
        domainLabel.textColor = MD3.onSurfaceVariant
        linkIconView.contentTintColor = MD3.onSurfaceVariant

        updatedAtPill.layer?.backgroundColor = MD3.surfaceContainerHighest.withAlphaComponent(0.6).cgColor
        updatedAtLabel.textColor = MD3.onSurfaceVariant

        refreshButton.layer?.backgroundColor = MD3.surfaceContainerHighest.cgColor
        refreshButton.contentTintColor = MD3.primary

        trafficBox.layer?.backgroundColor = isDark
            ? MD3.surfaceContainerLow.cgColor
            : MD3.surface.cgColor
        trafficBox.layer?.borderColor = MD3.outlineVariant.withAlphaComponent(0.2).cgColor
        trafficBox.layer?.borderWidth = 1

        trafficHeaderLabel.textColor = MD3.onSurfaceVariant
        trafficLabel.textColor = MD3.primary
        trafficPercentLabel.textColor = MD3.onSurfaceVariant
        trafficBar.layer?.backgroundColor = MD3.surfaceContainerHighest.cgColor
        trafficFill.layer?.backgroundColor = MD3.primary.cgColor

        expireIconCircle.layer?.backgroundColor = MD3.surfaceContainerHighest.cgColor
        expireIconView.contentTintColor = MD3.primary
        expireTitleLabel.textColor = MD3.onSurfaceVariant
        expiresLabel.textColor = MD3.onSurface
        errorLabel.textColor = MD3.error
    }

    func themeChanged() { updateColors() }

    /// 字节数 → "127GB" 这种最大 3 位整数 + 单位（不显示小数，进位）。
    static func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0B" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]
        var v = Double(bytes), i = 0
        while v >= 1000, i < units.count - 1 { v /= 1024; i += 1 }
        return "\(Int(v.rounded()))\(units[i])"
    }

    /// 相对时间 "刚刚 / 5分钟前 / 3小时前 / 2天前"（最多 999 天）。
    static func relativeAgo(from date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 { return "刚刚" }
        let m = secs / 60
        if m < 60 { return "\(m)分钟前" }
        let h = m / 60
        if h < 24 { return "\(h)小时前" }
        let d = min(999, h / 24)
        return "\(d)天前"
    }
}

final class MD3SubscriptionCellView: NSTableCellView, MD3Themeable {
    let leftItem = MD3SubscriptionItemView()
    let rightItem = MD3SubscriptionItemView()

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

        leftItem.translatesAutoresizingMaskIntoConstraints = false
        rightItem.translatesAutoresizingMaskIntoConstraints = false

        addSubview(leftItem)
        addSubview(rightItem)

        NSLayoutConstraint.activate([
            // 卡片左右贴 cell 边缘 = 贴 table 边缘（intercellSpacing 已清零），
            // 行间距由 NSTableView 自己控制。中央左右各 4pt 留 8pt 间隙。
            leftItem.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftItem.topAnchor.constraint(equalTo: topAnchor),
            leftItem.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftItem.trailingAnchor.constraint(equalTo: centerXAnchor, constant: -4),

            rightItem.leadingAnchor.constraint(equalTo: centerXAnchor, constant: 4),
            rightItem.topAnchor.constraint(equalTo: topAnchor),
            rightItem.bottomAnchor.constraint(equalTo: bottomAnchor),
            rightItem.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    func configure(leftSub: Subscription?, leftSelected: Bool, rightSub: Subscription?, rightSelected: Bool, leftClick: (() -> Void)?, rightClick: (() -> Void)?, leftRefresh: (() -> Void)? = nil, rightRefresh: (() -> Void)? = nil) {
        if let left = leftSub {
            leftItem.isHidden = false
            leftItem.configure(with: left, selected: leftSelected)
            leftItem.onClick = leftClick
            leftItem.onRefresh = leftRefresh
        } else {
            leftItem.isHidden = true
        }

        if let right = rightSub {
            rightItem.isHidden = false
            rightItem.configure(with: right, selected: rightSelected)
            rightItem.onClick = rightClick
            rightItem.onRefresh = rightRefresh
        } else {
            rightItem.isHidden = true
        }
    }

    func themeChanged() {
        leftItem.themeChanged()
        rightItem.themeChanged()
    }
}

final class MD3NodeCellView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    let urlDelayChip = MD3LatencyChip()

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

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(urlDelayChip)

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

    override func drawSelection(in dirtyRect: NSRect) {
        // Skip native blue selection background drawing
    }

    override func drawBackground(in dirtyRect: NSRect) {
        // Skip native row background drawing
    }

    override func draw(_ dirtyRect: NSRect) {
        // Clear background of the row to transparent before drawing
        NSColor.clear.set()
        dirtyRect.fill()

        if isSelected {
            var shouldDraw = true
            for sub in subviews {
                if let cell = sub as? NSTableCellView, cell is MD3SubscriptionCellView {
                    shouldDraw = false
                    break
                }
            }

            if shouldDraw {
                let selectionRect = bounds.insetBy(dx: 6, dy: 3)
                let path = NSBezierPath(roundedRect: selectionRect, xRadius: 10, yRadius: 10)

                MD3.primary.withAlphaComponent(0.08).setFill()
                path.fill()

                MD3.primary.withAlphaComponent(0.4).setStroke()
                path.lineWidth = 1.0
                path.stroke()
            }
        }

        super.draw(dirtyRect)
    }

    override var isSelected: Bool {
        didSet {
            self.needsDisplay = true
            for sub in subviews {
                if let cell = sub as? NSTableCellView {
                    updateCellColors(cell, selected: isSelected)
                }
            }
        }
    }

    private func updateCellColors(_ cell: NSTableCellView, selected: Bool) {
        if let profileCell = cell as? MD3ProfileCellView {
            profileCell.titleLabel.textColor = selected ? MD3.onPrimaryContainer : MD3.onSurface
        } else if cell is MD3SubscriptionCellView {
            // No-op. Selected items are manually controlled inside cells.
        } else if let nodeCell = cell as? MD3NodeCellView {
            nodeCell.titleLabel.textColor = selected ? MD3.onPrimaryContainer : MD3.onSurface
            nodeCell.subtitleLabel.textColor = selected ? MD3.onPrimaryContainer.withAlphaComponent(0.8) : MD3.onSurfaceVariant
        }
    }
}
/// NSTableView only lets a short allow-list of controls (NSButton etc.) receive the
/// first click on a not-yet-selected row; custom NSControl subclasses like
/// MD3Checkbox get swallowed by row selection instead, making in-cell checkboxes
/// feel dead. Allow them explicitly so a click always reaches the checkbox.
final class ControlFriendlyTableView: NSTableView {
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if responder is MD3Checkbox { return true }
        return super.validateProposedFirstResponder(responder, for: event)
    }

}

/// Reusable connection text; unchanged values do not invalidate AppKit drawing/layout.
final class ConnectionTextCell: NSTableCellView, MD3Themeable {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func themeChanged() {
        textField?.textColor = MD3.onSurface
    }

    func update(text: String, isMuted: Bool = false) {
        if textField?.stringValue != text { textField?.stringValue = text }
        let color = isMuted ? MD3.onSurfaceVariant : MD3.onSurface
        if textField?.textColor != color { textField?.textColor = color }
    }
}

final class ConnectionPillCell: NSTableCellView, MD3Themeable {
    let pill = NSView()
    let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 5
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)

        label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 20),
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),

            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(network: String) {
        label.stringValue = network.lowercased()
        updateColors()
    }

    func updateColors() {
        pill.layer?.backgroundColor = MD3.surfaceContainerHighest.withAlphaComponent(0.45).cgColor
        pill.layer?.borderColor = MD3.outlineVariant.withAlphaComponent(0.25).cgColor
        pill.layer?.borderWidth = 1
        label.textColor = MD3.onSurface
    }

    func themeChanged() { updateColors() }
}

final class ConnectionStatusCell: NSTableCellView, MD3Themeable {
    let pill = NSView()
    let dot = NSView()
    let label = NSTextField(labelWithString: "")
    private var currentStatus: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 10
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(dot)

        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 20),

            dot.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 7),
            dot.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(status: String) {
        currentStatus = status
        updateColors()
    }

    func updateColors() {
        let s = currentStatus.lowercased()
        let isSuccess = s.contains("成功") || s == "active" || s == "open" || s == "established"
        let isPending = s.contains("pending") || s.contains("connecting")

        if isSuccess {
            label.stringValue = "成功"
            label.textColor = MD3.onSuccessContainer
            dot.layer?.backgroundColor = MD3.success.cgColor
            pill.layer?.backgroundColor = MD3.successContainer.withAlphaComponent(0.6).cgColor
        } else if isPending {
            label.stringValue = "pending"
            label.textColor = MD3.warning
            dot.layer?.backgroundColor = MD3.warning.cgColor
            pill.layer?.backgroundColor = MD3.warning.withAlphaComponent(0.15).cgColor
        } else {
            label.stringValue = currentStatus
            label.textColor = MD3.onSurfaceVariant
            dot.layer?.backgroundColor = MD3.onSurfaceVariant.cgColor
            pill.layer?.backgroundColor = MD3.surfaceContainerHighest.withAlphaComponent(0.4).cgColor
        }
    }

    func themeChanged() { updateColors() }
}
