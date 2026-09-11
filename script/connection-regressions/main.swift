let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
let controller = MainWindowController(window: window)
let root = window.contentView!
controller.split.frame = root.bounds
controller.split.autoresizingMask = [.width, .height]
root.addSubview(controller.split)
controller.pages.tabViewType = .noTabsNoBorder
for index in 0..<5 {
    let item = NSTabViewItem()
    item.view = index == 4 ? controller.makeConnectionsView() : NSView()
    controller.pages.addTabViewItem(item)
}
controller.split.installPages(controller.pages)
controller.pages.selectTabViewItem(at: 4)
window.orderFrontRegardless()
let fixture = (0..<1000).map { index in
    ConnectionInfo(id: "test-\(index)", network: "tcp", status: "活跃", source: "127.0.0.1",
        destination: "test-\(index).example:443", rule: "DOMAIN", outbound: "测试节点", upload: 100, download: 200)
}
controller.applyConnections(fixture, detail: "测试")
root.layoutSubtreeIfNeeded()
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
let before = clock()
for _ in 0..<10 {
    controller.applyConnections(fixture, detail: "测试")
    root.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
let cpu = Double(clock() - before) / Double(CLOCKS_PER_SEC)
print("1000 connections, 10 identical updates: CPU seconds", cpu)
func settle() {
    root.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
precondition(controller.connectionsTable.numberOfRows == 1000)
let trafficColumn = controller.connectionsTable.column(withIdentifier: NSUserInterfaceItemIdentifier("traffic"))
let cell = controller.connectionsTable.view(atColumn: trafficColumn, row: 0, makeIfNecessary: true) as! ConnectionTextCell
let originalText = cell.textField!.stringValue
controller.connectionsTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
var changed = fixture
changed[0].upload += 4096
controller.connectionRefreshTime = Date().addingTimeInterval(-2)
controller.applyConnections(changed, detail: "测试")
settle()
precondition(controller.connectionsTable.view(atColumn: trafficColumn, row: 0, makeIfNecessary: false) === cell)
precondition(cell.textField!.stringValue != originalText)
precondition(controller.connectionsTable.selectedRow == 0)
precondition(controller.displayedConnections[0].uploadSpeed > 0)
controller.applyConnections(changed, detail: "测试")
settle()
precondition(controller.displayedConnections[0].uploadSpeed == 0)
precondition(!cell.textField!.stringValue.contains("/s"))
controller.connectionsTable.scrollRowToVisible(900)
settle()
changed[0].destination = "changed.example:443"
controller.applyConnections(changed, detail: "滚动")
controller.connectionsTable.scrollRowToVisible(0)
settle()
let destinationColumn = controller.connectionsTable.column(withIdentifier: NSUserInterfaceItemIdentifier("destination"))
let destinationCell = controller.connectionsTable.view(atColumn: destinationColumn, row: 0, makeIfNecessary: true) as! ConnectionTextCell
precondition(destinationCell.textField!.stringValue == "changed.example:443")
controller.connectionFilterField.stringValue = "test-99.example"
controller.connectionFilterChanged()
settle()
precondition(controller.connectionsTable.numberOfRows == 1)
precondition(controller.displayedConnections[0].id == "test-99")
controller.connectionFilterField.stringValue = ""
controller.connectionFilterChanged()
settle()
precondition(controller.connectionsTable.numberOfRows == 1000)
let cached = controller.displayedConnections
controller.pages.selectTabViewItem(at: 0)
controller.applyConnections(Array(changed.prefix(3)), detail: "后台")
precondition(controller.displayedConnections == cached)
controller.pages.selectTabViewItem(at: 4)
controller.refreshConnectionsTable()
settle()
precondition(controller.connectionsTable.numberOfRows == 3)
window.orderOut(nil)
controller.applyConnections(Array(changed.prefix(2)), detail: "后台")
precondition(controller.displayedConnections.count == 3)
window.orderFrontRegardless()
controller.refreshConnectionsTable()
settle()
precondition(controller.connectionsTable.numberOfRows == 2)
controller.applyConnections([], detail: "空")
settle()
precondition(controller.connectionsTable.numberOfRows == 0)
print("Cell identity, traffic, selection, filtering, hidden-page and reopen regressions passed")
