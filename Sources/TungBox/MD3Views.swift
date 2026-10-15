import AppKit
import Foundation

// Tracking areas receive hover independently of hitTest. Only the topmost
// dialog and its descendants may react while a modal overlay is attached.
extension NSView {
    var isBlockedByMD3Dialog: Bool {
        guard let root = window?.contentView,
              let dialog = root.subviews.reversed().compactMap({ $0 as? MD3Dialog }).first(where: { !$0.isHidden }) else { return false }
        return self !== dialog && !isDescendant(of: dialog)
    }
}

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

final class MD3ScrollView: NSScrollView {
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
    // 仿 Clash Verge 排版：
    //   左侧顶部：站点名（粗体）+ 域名（小）
    //   左侧底部：流量进度条 + 「已用 / 总量」文本
    //   右侧顶部：刷新按钮
    //   右侧底部：上次刷新时间 + 到期日期
    private let card = NSView()
    let titleLabel = NSTextField(labelWithString: "")
    let domainLabel = NSTextField(labelWithString: "")
    let trafficLabel = NSTextField(labelWithString: "")
    let trafficBar = NSView()      // 进度条背景
    let trafficFill = NSView()     // 进度条填充
    private var trafficFillWidth: NSLayoutConstraint!
    private let refreshButton = NSButton()
    let updatedAtLabel = NSTextField(labelWithString: "")
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
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        domainLabel.font = .systemFont(ofSize: 11)
        domainLabel.lineBreakMode = .byTruncatingTail
        domainLabel.maximumNumberOfLines = 1
        domainLabel.translatesAutoresizingMaskIntoConstraints = false

        trafficBar.wantsLayer = true
        trafficBar.layer?.cornerRadius = 2
        trafficBar.translatesAutoresizingMaskIntoConstraints = false

        trafficFill.wantsLayer = true
        trafficFill.layer?.cornerRadius = 2
        trafficFill.translatesAutoresizingMaskIntoConstraints = false
        trafficBar.addSubview(trafficFill)

        trafficLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        trafficLabel.lineBreakMode = .byTruncatingTail
        trafficLabel.maximumNumberOfLines = 1
        trafficLabel.translatesAutoresizingMaskIntoConstraints = false

        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")
        refreshButton.isBordered = false
        refreshButton.bezelStyle = .regularSquare
        refreshButton.imageScaling = .scaleProportionallyDown
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.wantsLayer = true   // 旋转动画需要
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)

        updatedAtLabel.font = .systemFont(ofSize: 10)
        updatedAtLabel.alignment = .right
        updatedAtLabel.lineBreakMode = .byTruncatingTail
        updatedAtLabel.maximumNumberOfLines = 1
        updatedAtLabel.translatesAutoresizingMaskIntoConstraints = false

        expiresLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        expiresLabel.alignment = .right
        expiresLabel.lineBreakMode = .byTruncatingTail
        expiresLabel.maximumNumberOfLines = 1
        expiresLabel.translatesAutoresizingMaskIntoConstraints = false

        errorLabel.font = .systemFont(ofSize: 10, weight: .medium)
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.maximumNumberOfLines = 1
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.isHidden = true

        // Long subscription metadata must truncate inside the card, not widen it.
        for label in [titleLabel, domainLabel, trafficLabel, updatedAtLabel, expiresLabel, errorLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        card.addSubview(titleLabel)
        card.addSubview(domainLabel)
        card.addSubview(trafficLabel)
        card.addSubview(trafficBar)
        card.addSubview(refreshButton)
        card.addSubview(updatedAtLabel)
        card.addSubview(expiresLabel)
        card.addSubview(errorLabel)

        trafficFillWidth = trafficFill.widthAnchor.constraint(equalTo: trafficBar.widthAnchor, multiplier: 0)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            // === 第一行：左 titleLabel ↔ 右 refreshButton ===
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -8),

            refreshButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            refreshButton.widthAnchor.constraint(equalToConstant: 22),
            refreshButton.heightAnchor.constraint(equalToConstant: 22),

            // === 第二行：左 domainLabel ↔ 右 updatedAtLabel ===
            domainLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            domainLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            domainLabel.trailingAnchor.constraint(lessThanOrEqualTo: updatedAtLabel.leadingAnchor, constant: -8),

            updatedAtLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            updatedAtLabel.centerYAnchor.constraint(equalTo: domainLabel.centerYAnchor),

            // === 第三行（底部）：左 trafficLabel ↔ 右 expiresLabel；进度条贴底缘 ===
            trafficBar.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            trafficBar.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            trafficBar.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            trafficBar.heightAnchor.constraint(equalToConstant: 4),

            trafficLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            trafficLabel.bottomAnchor.constraint(equalTo: trafficBar.topAnchor, constant: -4),
            trafficLabel.trailingAnchor.constraint(lessThanOrEqualTo: expiresLabel.leadingAnchor, constant: -8),

            expiresLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            expiresLabel.centerYAnchor.constraint(equalTo: trafficLabel.centerYAnchor),

            trafficFill.leadingAnchor.constraint(equalTo: trafficBar.leadingAnchor),
            trafficFill.topAnchor.constraint(equalTo: trafficBar.topAnchor),
            trafficFill.bottomAnchor.constraint(equalTo: trafficBar.bottomAnchor),
            trafficFillWidth,

            errorLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            errorLabel.bottomAnchor.constraint(equalTo: trafficBar.topAnchor, constant: -4),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14)
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
            let warning = SubscriptionTraffic.isInconsistent(used: used, total: total) ? "（数据异常）" : ""
            trafficLabel.stringValue = "\(Self.formatBytes(used)) / \(Self.formatBytes(total))\(warning)"
            let frac = max(0, min(1, Double(used) / Double(total)))
            trafficFillWidth.isActive = false
            trafficFillWidth = trafficFill.widthAnchor.constraint(equalTo: trafficBar.widthAnchor, multiplier: CGFloat(max(frac, 0.001)))
            trafficFillWidth.isActive = true
        } else {
            if let total = sub.total, SubscriptionTraffic.isInconsistent(used: used, total: total) {
                trafficLabel.stringValue = "流量数据异常"
            } else {
                trafficLabel.stringValue = used > 0 ? "已用 \(Self.formatBytes(used)) / 不限" : "未获取流量信息"
            }
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
        } else {
            expiresLabel.stringValue = "无限期"
        }

        // 错误
        if let err = sub.lastError, !err.isEmpty {
            errorLabel.stringValue = "失败：\(String(err.prefix(60)))"
            errorLabel.isHidden = false
            trafficLabel.isHidden = true
        } else {
            errorLabel.isHidden = true
            trafficLabel.isHidden = false
        }

        updateColors()
    }

    func updateColors() {
        if isSelected {
            card.layer?.backgroundColor = MD3.primaryContainer.cgColor
            card.layer?.borderColor = MD3.primary.cgColor
            card.layer?.borderWidth = 1.5
            titleLabel.textColor = MD3.onPrimaryContainer
            domainLabel.textColor = MD3.onPrimaryContainer.withAlphaComponent(0.75)
            trafficLabel.textColor = MD3.onPrimaryContainer
            updatedAtLabel.textColor = MD3.onPrimaryContainer.withAlphaComponent(0.7)
            expiresLabel.textColor = MD3.onPrimaryContainer
            refreshButton.contentTintColor = MD3.onPrimaryContainer
            trafficBar.layer?.backgroundColor = MD3.onPrimaryContainer.withAlphaComponent(0.2).cgColor
            trafficFill.layer?.backgroundColor = MD3.primary.cgColor
        } else {
            let bg = isHovered ? MD3.surfaceContainer : MD3.surface
            card.layer?.backgroundColor = bg.cgColor
            card.layer?.borderColor = MD3.outlineVariant.cgColor
            card.layer?.borderWidth = 1
            titleLabel.textColor = MD3.onSurface
            domainLabel.textColor = MD3.onSurfaceVariant
            trafficLabel.textColor = MD3.onSurface
            updatedAtLabel.textColor = MD3.onSurfaceVariant
            expiresLabel.textColor = MD3.onSurface
            refreshButton.contentTintColor = MD3.primary
            trafficBar.layer?.backgroundColor = MD3.outlineVariant.cgColor
            trafficFill.layer?.backgroundColor = MD3.primary.cgColor
        }
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
        layer?.cornerRadius = 6
        
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = MD3.onSurface
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        // 内容不能强制把 cell 撑宽：超长名字必须收敛，由外层 fillEqually 决定列宽。
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
        actionButton.layer?.cornerRadius = 4
        actionButton.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.target = self
        actionButton.action = #selector(actionButtonClicked)
        actionButton.isEnabled = isActionEnabled
        actionButton.isHidden = !isActionEnabled
        
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
        if isSelected && !isInteractive {
            // Current auto-pick inside a urltest group: mark it as selected but
            // with a softer container tint so it reads as "locked, not clickable".
            layer?.backgroundColor = MD3.primaryContainer.cgColor
            nameLabel.textColor = MD3.onPrimaryContainer
            subLabel.textColor = MD3.onPrimaryContainer.withAlphaComponent(0.7)
        } else if !isInteractive {
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
        
        if ms < 400 {
            // Good (Green)
            let bg = NSColor(red: 0.88, green: 0.96, blue: 0.90, alpha: 1.0)
            let text = NSColor(red: 0.15, green: 0.54, blue: 0.28, alpha: 1.0)
            return (bg, text)
        } else if ms < 800 {
            // Fair (Orange)
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

// MARK: - MD3 Dialog (Custom Overlay modal dialog)

@MainActor
final class MD3Dialog: NSView, MD3Themeable {
    private let scrimView = NSView()
    private let card = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private let contentViewContainer = NSView()
    private let buttonStack = NSStackView()
    
    private let cancelButton = MD3Button()
    private let confirmButton = MD3Button()
    
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    
    init(
        title: String,
        message: String,
        customView: NSView?,
        confirmTitle: String = "确定",
        cancelTitle: String = "取消"
    ) {
        super.init(frame: .zero)
        setup(title: title, message: message, customView: customView, confirmTitle: confirmTitle, cancelTitle: cancelTitle)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup(
        title: String,
        message: String,
        customView: NSView?,
        confirmTitle: String,
        cancelTitle: String
    ) {
        wantsLayer = true
        
        // 1. Scrim background overlay
        scrimView.wantsLayer = true
        scrimView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrimView)
        
        // Click scrim to dismiss
        let click = NSClickGestureRecognizer(target: self, action: #selector(scrimClicked))
        scrimView.addGestureRecognizer(click)
        
        // 2. Dialog card container
        card.wantsLayer = true
        card.layer?.cornerRadius = 28
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        
        // Shadow for elevation 3
        card.shadow = NSShadow()
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.24
        card.layer?.shadowOffset = CGSize(width: 0, height: -4)
        card.layer?.shadowRadius = 16
        
        // Title
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 22, weight: .regular)
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)
        
        // Message (Body)
        messageLabel.stringValue = message
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.cell?.wraps = true
        messageLabel.isBezeled = false
        messageLabel.drawsBackground = false
        messageLabel.isEditable = false
        messageLabel.isSelectable = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(messageLabel)
        
        // Custom View Container
        if customView != nil {
            contentViewContainer.wantsLayer = true
            contentViewContainer.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(contentViewContainer)
            
            if let custom = customView {
                custom.translatesAutoresizingMaskIntoConstraints = false
                contentViewContainer.addSubview(custom)
                NSLayoutConstraint.activate([
                    custom.leadingAnchor.constraint(equalTo: contentViewContainer.leadingAnchor),
                    custom.trailingAnchor.constraint(equalTo: contentViewContainer.trailingAnchor),
                    custom.topAnchor.constraint(equalTo: contentViewContainer.topAnchor),
                    custom.bottomAnchor.constraint(equalTo: contentViewContainer.bottomAnchor)
                ])
            }
        }
        
        // Action Buttons
        cancelButton.title = cancelTitle
        cancelButton.style = .text
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        if cancelTitle.isEmpty {
            cancelButton.isHidden = true
        }
        
        confirmButton.title = confirmTitle
        confirmButton.style = .filled
        confirmButton.target = self
        confirmButton.action = #selector(confirmClicked)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .centerY
        buttonStack.addArrangedSubview(cancelButton)
        buttonStack.addArrangedSubview(confirmButton)
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(buttonStack)
        
        // 3. Layout constraints
        var constraints = [
            scrimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrimView.topAnchor.constraint(equalTo: topAnchor),
            scrimView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 480),
            
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            
            messageLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            
            buttonStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            buttonStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ]
        
        if customView != nil {
            constraints.append(contentsOf: [
                contentViewContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
                contentViewContainer.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
                contentViewContainer.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 20),
                
                buttonStack.topAnchor.constraint(equalTo: contentViewContainer.bottomAnchor, constant: 24)
            ])
        } else {
            constraints.append(buttonStack.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24))
        }
        
        NSLayoutConstraint.activate(constraints)
        
        updateColors()
    }
    
    // Keep passive content inside the modal boundary. Plain NSViews and labels
    // can forward unhandled mouse events along the responder chain.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        guard let hit = super.hitTest(point) else { return self }
        if hit === scrimView { return hit }
        var candidate: NSView? = hit
        while let view = candidate, view !== self {
            if let field = view as? NSTextField {
                if field.isEditable || field.isSelectable { return hit }
            } else if view is NSControl || view is NSScrollView || view is NSTextView {
                return hit
            }
            if !(view is NSTextField), !view.gestureRecognizers.isEmpty { return hit }
            candidate = view.superview
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let root = superview, let window else { return }
        // Clear hover that was already active when a button opened the dialog.
        let event = NSEvent.enterExitEvent(with: .mouseExited, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        func reset(_ view: NSView) {
            guard view !== self else { return }
            if !view.trackingAreas.isEmpty { view.mouseExited(with: event) }
            window.invalidateCursorRects(for: view)
            for child in view.subviews { reset(child) }
        }
        reset(root)
        NSCursor.arrow.set()
    }

    override func removeFromSuperview() {
        let previousWindow = window
        super.removeFromSuperview()
        // Rebuild cursors after the modal restriction is lifted.
        func refresh(_ view: NSView) {
            previousWindow?.invalidateCursorRects(for: view)
            for child in view.subviews { refresh(child) }
        }
        if let root = previousWindow?.contentView { refresh(root) }
    }

    @objc private func scrimClicked() {
        cancelClicked()
    }
    
    @objc private func cancelClicked() {
        onCancel?()
    }
    
    @objc private func confirmClicked() {
        onConfirm?()
    }

    func present() {
        self.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }
    
    func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        } completionHandler: {
            DispatchQueue.main.async {
                self.removeFromSuperview()
            }
        }
    }
    
    func updateColors() {
        scrimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        card.layer?.backgroundColor = MD3.surfaceContainer.cgColor
        titleLabel.textColor = MD3.onSurface
        messageLabel.textColor = MD3.onSurfaceVariant
    }
    
    func themeChanged() {
        updateColors()
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

    func update(text: String) {
        if textField?.stringValue != text { textField?.stringValue = text }
        if textField?.textColor != MD3.onSurface { textField?.textColor = MD3.onSurface }
    }
}
