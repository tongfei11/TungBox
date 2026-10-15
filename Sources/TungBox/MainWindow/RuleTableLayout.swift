import AppKit

enum RuleTableLayout {
    static let columns: [(id: String, title: String, minimum: CGFloat)] = [
        ("enabled", "", 32), ("id", "#", 36), ("type", "类型", 114),
        ("value", "匹配值", 160), ("strategy", "策略", 112),
        ("count", "命中", 44), ("note", "备注", 100)
    ]

    static func widths(viewportWidth: CGFloat, spacing: CGFloat) -> [CGFloat] {
        // Leave a small gutter for AppKit's column edge/separator rounding.
        let extra = max(0, viewportWidth - 8 - spacing * CGFloat(columns.count) - columns.reduce(0) { $0 + $1.minimum })
        return columns.map { column in
            column.minimum + (column.id == "value" ? extra * 0.7 : column.id == "note" ? extra * 0.3 : 0)
        }
    }
}

/// Fit every rule field into the viewport; long values keep their full tooltip.
/// Uses the existing table, preserving row clicks, checkboxes and context menus.
final class RuleTableScrollView: MD3ScrollView {
    private var fittingColumns = false

    override func layout() {
        super.layout()
        guard !fittingColumns, let table = documentView as? NSTableView,
              table.tableColumns.map({ $0.identifier.rawValue }) == RuleTableLayout.columns.map(\.id),
              contentView.bounds.width > 0 else { return }
        fittingColumns = true
        defer { fittingColumns = false }
        let widths = RuleTableLayout.widths(viewportWidth: contentView.bounds.width, spacing: table.intercellSpacing.width)
        for (column, width) in zip(table.tableColumns, widths) where abs(column.width - width) > 0.5 {
            column.width = width
        }
        let width = max(contentView.bounds.width, widths.reduce(0, +) + table.intercellSpacing.width * CGFloat(widths.count))
        if abs(table.frame.width - width) > 0.5 {
            table.setFrameSize(NSSize(width: width, height: table.frame.height))
        }
    }
}
