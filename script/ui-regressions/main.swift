import AppKit
import Foundation

extension DateFormatter {
    static let short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

@MainActor
func runUIRegression() {
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
let root = window.contentView!
let split = FixedSidebarLayout(frame: root.bounds)
split.translatesAutoresizingMaskIntoConstraints = false
root.addSubview(split)
NSLayoutConstraint.activate([split.leadingAnchor.constraint(equalTo: root.leadingAnchor), split.trailingAnchor.constraint(equalTo: root.trailingAnchor), split.topAnchor.constraint(equalTo: root.topAnchor), split.bottomAnchor.constraint(equalTo: root.bottomAnchor)])
let tabs = NSTabView()
tabs.tabViewType = .noTabsNoBorder
tabs.setContentHuggingPriority(.defaultLow, for: .horizontal)
tabs.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
tabs.translatesAutoresizingMaskIntoConstraints = false
split.mainContent.addSubview(tabs)
NSLayoutConstraint.activate([tabs.leadingAnchor.constraint(equalTo: split.mainContent.leadingAnchor), tabs.trailingAnchor.constraint(equalTo: split.mainContent.trailingAnchor), tabs.topAnchor.constraint(equalTo: split.mainContent.topAnchor), tabs.bottomAnchor.constraint(equalTo: split.mainContent.bottomAnchor)])
for width in [600.0, 1250.0, 800.0] {
    let page = NSView()
    let field = NSTextField(labelWithString: "Page")
    field.translatesAutoresizingMaskIntoConstraints = false
    page.addSubview(field)
    NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo: page.leadingAnchor), field.trailingAnchor.constraint(equalTo: page.trailingAnchor), field.widthAnchor.constraint(greaterThanOrEqualToConstant: width)])
    let item = NSTabViewItem(); item.view = page; tabs.addTabViewItem(item)
}
let before = window.frame
for index in [0, 1, 2, 0, 1, 0] {
    tabs.selectTabViewItem(at: index)
    root.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    print("page", index, "window", window.frame.width, "initial", before.width)
}
let custom = NSView()
custom.translatesAutoresizingMaskIntoConstraints = false
NSLayoutConstraint.activate([custom.widthAnchor.constraint(equalToConstant: 460), custom.heightAnchor.constraint(equalToConstant: 540)])
let dialog = MD3Dialog(title: "规则集", message: "测试", customView: custom)
dialog.translatesAutoresizingMaskIntoConstraints = false
root.addSubview(dialog)
NSLayoutConstraint.activate([dialog.leadingAnchor.constraint(equalTo: root.leadingAnchor), dialog.trailingAnchor.constraint(equalTo: root.trailingAnchor), dialog.topAnchor.constraint(equalTo: root.topAnchor), dialog.bottomAnchor.constraint(equalTo: root.bottomAnchor)])
dialog.present()
root.layoutSubtreeIfNeeded()
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
print("dialog", dialog.frame, "children", dialog.subviews.map(\.frame))
dialog.dismiss()
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
print("dismiss removed", dialog.superview == nil)
}

@main
struct Main {
    @MainActor static func main() { runUIRegression() }
}
