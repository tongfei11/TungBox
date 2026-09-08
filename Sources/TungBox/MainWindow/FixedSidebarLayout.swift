import AppKit

/// Navigation is always visible. Avoid split-view collapse and restoration state.
final class FixedSidebarLayout: NSView {
    let sidebar = NSView()
    let mainContent = NSView()

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

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
