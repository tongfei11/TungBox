import AppKit
import Foundation

extension MainWindowController {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == subscriptionTable { return (subscriptions.count + 1) / 2 }
        if tableView == nodeTable { return nodes.count }
        if tableView == rulesTable { return filteredRuleRows().count }
        if tableView == connectionsTable { return filteredConnections().count }
        return profiles.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == subscriptionTable {
            let identifier = NSUserInterfaceItemIdentifier("SubCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? MD3SubscriptionCellView ?? MD3SubscriptionCellView(frame: .zero)
            cell.identifier = identifier
            
            let leftIndex = row * 2
            let rightIndex = row * 2 + 1
            
            let leftSub = subscriptions[leftIndex]
            let leftSelected = (selectedSubscriptionIndex == leftIndex)
            
            var rightSub: Subscription? = nil
            var rightSelected = false
            if rightIndex < subscriptions.count {
                rightSub = subscriptions[rightIndex]
                rightSelected = (selectedSubscriptionIndex == rightIndex)
            }
            
            cell.configure(
                leftSub: leftSub,
                leftSelected: leftSelected,
                rightSub: rightSub,
                rightSelected: rightSelected,
                leftClick: { [weak self] in
                    self?.selectSubscription(at: leftIndex)
                },
                rightClick: { [weak self] in
                    self?.selectSubscription(at: rightIndex)
                }
            )
            return cell
        } else if tableView == nodeTable {
            let identifier = NSUserInterfaceItemIdentifier("NodeCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? MD3NodeCellView ?? MD3NodeCellView(frame: .zero)
            cell.identifier = identifier
            cell.configure(with: nodes[row])
            return cell
        } else if tableView == rulesTable {
            let rows = filteredRuleRows()
            guard rows.indices.contains(row), let columnID = tableColumn?.identifier.rawValue else { return nil }
            return makeRuleCell(for: rows[row], columnID: columnID)
        } else if tableView == connectionsTable {
            guard connections.indices.contains(row), let columnID = tableColumn?.identifier.rawValue else { return nil }
            return makeConnectionCell(for: connections[row], columnID: columnID)
        } else {
            let identifier = NSUserInterfaceItemIdentifier("ProfileCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? MD3ProfileCellView ?? MD3ProfileCellView(frame: .zero)
            cell.identifier = identifier
            cell.configure(with: profiles[row], isSelected: tableView.selectedRow == row)
            return cell
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return MD3TableRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        if tableView == table {
            if tableView.selectedRow >= 0 {
                selectProfile(at: tableView.selectedRow)
            }
        } else if tableView == nodeTable {
            if tableView.selectedRow >= 0 {
                let selectedNode = nodes[tableView.selectedRow]
                if let config = parseConfigObject(from: editor.string),
                   let outbounds = config["outbounds"] as? [[String: Any]],
                   let selector = outbounds.first(where: { $0["tag"] as? String == "节点选择" }),
                   let defNode = selector["default"] as? String,
                   defNode == selectedNode.tag {
                    return
                }
                selectNode(at: tableView.selectedRow)
            }
        }
    }
}
