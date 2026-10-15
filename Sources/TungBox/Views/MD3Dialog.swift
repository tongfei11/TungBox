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
