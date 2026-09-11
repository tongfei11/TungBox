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
let tabs = ConsoleTabView()
tabs.tabViewType = .noTabsNoBorder
tabs.setContentHuggingPriority(.defaultLow, for: .horizontal)
tabs.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
split.installPages(tabs)
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
    precondition(window.frame == before, "Page selection changed the window frame")
    precondition(tabs.frame.size == split.mainContent.bounds.size, "Pages must fit the available area")
}
// Exercise actual two-column subscription cards with oversized metadata.
let subscriptionPage = NSView()
let cell = MD3SubscriptionCellView()
cell.translatesAutoresizingMaskIntoConstraints = false
subscriptionPage.addSubview(cell)
NSLayoutConstraint.activate([
    cell.leadingAnchor.constraint(equalTo: subscriptionPage.leadingAnchor, constant: 32),
    cell.trailingAnchor.constraint(equalTo: subscriptionPage.trailingAnchor, constant: -32),
    cell.topAnchor.constraint(equalTo: subscriptionPage.topAnchor, constant: 100),
    cell.heightAnchor.constraint(equalToConstant: 84)
])
let subscription = Subscription(id: UUID(), name: String(repeating: "长订阅名称", count: 30),
    url: "https://" + String(repeating: "long-domain", count: 20) + ".example/subscription",
    updatedAt: Date(), lastError: String(repeating: "刷新错误", count: 40),
    upload: 123456789, download: 987654321, total: 9999999999, expiresAt: Date())
cell.configure(leftSub: subscription, leftSelected: true, rightSub: subscription,
    rightSelected: false, leftClick: nil, rightClick: nil)
let subscriptionTab = NSTabViewItem()
subscriptionTab.view = subscriptionPage
tabs.addTabViewItem(subscriptionTab)
for width in [1080.0, 900.0, 1400.0, 1080.0] {
    window.setContentSize(NSSize(width: width, height: 720))
    let expected = window.frame
    for index in [3, 0, 3, 1, 3] {
        tabs.selectTabViewItem(at: index)
        root.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        precondition(window.frame == expected, "Subscription page changed the window frame")
        precondition(tabs.frame.size == split.mainContent.bounds.size)
    }
    precondition(cell.frame.width <= tabs.bounds.width)
    for card in [cell.leftItem, cell.rightItem] {
        precondition(card.titleLabel.frame.maxX <= card.bounds.width)
        precondition(card.domainLabel.frame.maxX <= card.updatedAtLabel.frame.minX)
    }
    window.orderOut(nil)
    window.orderFrontRegardless()
    root.layoutSubtreeIfNeeded()
    precondition(window.frame == expected, "Reopening changed the window frame")
}
print("Page selection, long subscription metadata, resize and reopen regressions passed")
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
