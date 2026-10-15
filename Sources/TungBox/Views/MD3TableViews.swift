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
