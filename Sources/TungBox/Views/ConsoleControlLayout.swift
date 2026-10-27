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

    static func settingsButtonGrid(_ buttons: [NSView]) -> NSView {
        let rows = stride(from: 0, to: buttons.count, by: 2).map { index in
            [buttons[index], index + 1 < buttons.count ? buttons[index + 1] : NSView()]
        }
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 12
        grid.rowSpacing = 10
        grid.xPlacement = .leading
        grid.yPlacement = .center
        grid.translatesAutoresizingMaskIntoConstraints = false
        return grid
    }
}
