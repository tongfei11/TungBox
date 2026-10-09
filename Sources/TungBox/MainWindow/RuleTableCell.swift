import AppKit

/// Builds rule cells without requiring a running window or controller.
@MainActor
enum RuleTableCell {
    static func make(for rule: RuleInfo, columnID: String, configureCheckbox: (MD3Checkbox, UUID) -> Void = { _, _ in }) -> NSView {
        // Invalid references need an explicit warning, independent of enable state.
        // Warning rows and rule sets can still be toggled through the context menu.
        if columnID == "enabled" && !rule.isSection && (rule.referenceError != nil || rule.ruleSetID != nil || rule.ruleSetInvalidURL != nil) {
            let mark = rule.referenceError != nil || rule.ruleSetInvalidURL != nil ? "⚠" : (rule.enabled ? "●" : "○")
            let label = NSTextField(labelWithString: mark)
            label.font = .systemFont(ofSize: 13)
            label.textColor = rule.referenceError != nil ? MD3.warning :
                (rule.ruleSetInvalidURL != nil ? .systemRed : (rule.enabled ? MD3.primary : MD3.onSurfaceVariant))
            label.toolTip = rule.referenceError.map { $0 + (rule.enabled ? "" : "（规则已停用）") } ?? rule.note
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            let container = NSView()
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            return container
        }
        if columnID == "enabled" && !rule.isSection {
            let button = MD3Checkbox(checkboxWithTitle: "", target: nil, action: nil)
            button.state = rule.enabled ? .on : .off
            button.isEnabled = rule.customRuleID != nil
            if let ruleID = rule.customRuleID {
                configureCheckbox(button, ruleID)
            }
            button.translatesAutoresizingMaskIntoConstraints = false
            let container = NSView()
            container.addSubview(button)
            // Keep the checkbox compact and centered (not the whole column), but let
            // it span the full row height so it's an easy target. MD3Checkbox toggles
            // on any in-bounds click and consumes the event, so a click on it wins
            // over table row selection.
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                button.topAnchor.constraint(equalTo: container.topAnchor),
                button.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            return container
        }

        let text: String
        switch columnID {
        case "enabled": text = rule.isSection ? "#" : ""
        case "id": text = rule.id
        case "type": text = rule.type
        case "value": text = rule.value
        case "strategy": text = rule.strategy
        case "count": text = rule.count
        case "note": text = rule.note
        default: text = ""
        }

        let label = NSTextField(labelWithString: text)
        label.font = rule.isSection ? .systemFont(ofSize: 13, weight: .bold) : .systemFont(ofSize: 13)
        label.textColor = columnID == "strategy" && rule.strategyReferenceError != nil ? MD3.warning :
            (rule.isSection ? MD3.onSurfaceVariant : MD3.onSurface)
        label.toolTip = columnID == "strategy" ? rule.strategyReferenceError : rule.referenceError
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }
}
