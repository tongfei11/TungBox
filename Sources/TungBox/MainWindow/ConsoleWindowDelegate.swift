import AppKit

/// Normal windows keep their fixed content size; native full-screen transitions
/// may use the screen's size. Does not own a controller or perform system work.
@MainActor
final class ConsoleWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: ((Notification) -> Void)?
    private var changingFullScreen = false

    func configure(_ window: NSWindow) {
        window.contentMinSize = ConsoleLayout.defaultContentSize
        window.collectionBehavior = [.fullScreenPrimary, .fullScreenDisallowsTiling]
        window.delegate = self
    }

    private func allowsResize(_ window: NSWindow) -> Bool {
        changingFullScreen || window.styleMask.contains(.fullScreen)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        allowsResize(sender) ? frameSize : sender.frameRect(forContentRect: NSRect(origin: .zero, size: ConsoleLayout.defaultContentSize)).size
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, !allowsResize(window),
              window.contentView?.frame.size != ConsoleLayout.defaultContentSize else { return }
        window.setContentSize(ConsoleLayout.defaultContentSize)
    }

    func windowWillEnterFullScreen(_ notification: Notification) { changingFullScreen = true }
    func windowDidEnterFullScreen(_ notification: Notification) { changingFullScreen = false }
    func windowWillExitFullScreen(_ notification: Notification) { changingFullScreen = true }
    func windowDidExitFullScreen(_ notification: Notification) {
        changingFullScreen = false
        windowDidResize(notification)
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        changingFullScreen = false
        windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
    }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { changingFullScreen = false }
    func windowWillClose(_ notification: Notification) { onClose?(notification) }
}
