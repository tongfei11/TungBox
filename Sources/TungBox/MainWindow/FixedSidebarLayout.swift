import AppKit

/// Navigation is always visible. Avoid split-view collapse and restoration state.
final class FixedSidebarLayout: NSView {
    let sidebar = NSView()
    let mainContent = PageViewport()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [sidebar, mainContent] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 180),
            mainContent.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 1),
            mainContent.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainContent.topAnchor.constraint(equalTo: topAnchor),
            mainContent.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Keep page fitting sizes from becoming window minimum-size constraints.
    /// AppKit's tab view otherwise expands the window when selecting a wide page.
    func installPages(_ pages: NSTabView) {
        mainContent.install(pages)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// A frame-managed boundary: descendant Auto Layout cannot resize the window.
final class PageViewport: NSView {
    private var contentWidth: NSLayoutConstraint?
    private var contentHeight: NSLayoutConstraint?

    func install(_ content: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        contentWidth = content.widthAnchor.constraint(equalToConstant: bounds.width)
        contentHeight = content.heightAnchor.constraint(equalToConstant: bounds.height)
        NSLayoutConstraint.activate([contentWidth!, contentHeight!])
        needsLayout = true
    }

    override func layout() {
        contentWidth?.constant = bounds.width
        contentHeight?.constant = bounds.height
        super.layout()
        for view in subviews {
            view.frame = bounds
        }
    }
}

final class ConsoleTabView: NSTabView {
    override func addTabViewItem(_ tabViewItem: NSTabViewItem) {
        if let page = tabViewItem.view {
            let viewport = PageViewport()
            viewport.install(page)
            tabViewItem.view = viewport
        }
        super.addTabViewItem(tabViewItem)
    }
}
