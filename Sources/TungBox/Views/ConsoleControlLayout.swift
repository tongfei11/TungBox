import AppKit

/// Page actions share the compact height of the Nodes latency-test button.
@MainActor
enum ConsoleControlLayout {
    static let actionHeight: CGFloat = 34
    static let tabFontSize: CGFloat = 13

    static func configurePageTabs(_ control: MD3SegmentedControl) {
        control.customFontSize = tabFontSize
        control.selectionInset = 0
        control.heightAnchor.constraint(equalToConstant: actionHeight).isActive = true
    }

    static func equalizeActionWidths(_ buttons: [NSView]) {
        guard let first = buttons.first else { return }
        for button in buttons {
            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        for button in buttons.dropFirst() {
            button.widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true
        }
    }

    static func equalizePageActions(in view: NSView) {
        func actions(in parent: NSView) -> [MD3Button] {
            parent.subviews.flatMap { child in
                if let button = child as? MD3Button, button.style != .segment, button.style != .nav {
                    return [button]
                }
                return actions(in: child)
            }
        }
        equalizeActionWidths(actions(in: view))
    }

    static func settingsButtonGrid(_ buttons: [NSView]) -> NSView {
        let rows = stride(from: 0, to: buttons.count, by: 2).map { index in
            [buttons[index], index + 1 < buttons.count ? buttons[index + 1] : NSView()]
        }
        let grid = NSGridView(views: rows)
        equalizeActionWidths(buttons)
        grid.columnSpacing = 12
        grid.rowSpacing = 10
        grid.xPlacement = .fill
        grid.yPlacement = .center
        grid.translatesAutoresizingMaskIntoConstraints = false
        return grid
    }
}
