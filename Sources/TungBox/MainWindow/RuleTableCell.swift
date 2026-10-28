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
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                button.topAnchor.constraint(equalTo: container.topAnchor),
                button.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            return container
        }
        if columnID == "enabled" && rule.isSection {
            let imgView = NSImageView()
            if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) {
                chevron.isTemplate = true
                imgView.image = chevron
            }
            imgView.contentTintColor = MD3.onSurfaceVariant
            imgView.translatesAutoresizingMaskIntoConstraints = false
            let container = NSView()
            container.addSubview(imgView)
            NSLayoutConstraint.activate([
                imgView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                imgView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                imgView.widthAnchor.constraint(equalToConstant: 12),
                imgView.heightAnchor.constraint(equalToConstant: 12)
            ])
            return container
        }

        if columnID == "type" && !rule.isSection && !rule.type.isEmpty {
            let label = CenteredPillLabel(labelWithString: rule.type)
            label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            label.wantsLayer = true
            label.layer?.cornerRadius = 6
            label.layer?.borderWidth = 1
            if rule.type == "规则集" {
                label.textColor = MD3.primary
                label.layer?.backgroundColor = MD3.primary.withAlphaComponent(0.18).cgColor
                label.layer?.borderColor = MD3.primary.withAlphaComponent(0.4).cgColor
            } else {
                label.textColor = MD3.onSurface
                label.layer?.backgroundColor = MD3.surfaceContainerHighest.withAlphaComponent(0.45).cgColor
                label.layer?.borderColor = MD3.outlineVariant.withAlphaComponent(0.3).cgColor
            }
            let container = NSView()
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                label.heightAnchor.constraint(equalToConstant: 22),
                label.widthAnchor.constraint(greaterThanOrEqualToConstant: 54)
            ])
            return container
        }

        if columnID == "strategy" && !rule.isSection && !rule.strategy.isEmpty {
            let label = CenteredPillLabel(labelWithString: rule.strategy)
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            label.toolTip = rule.strategyReferenceError ?? rule.strategy
            label.wantsLayer = true
            label.layer?.cornerRadius = 11
            label.layer?.borderWidth = 1
            if rule.strategyReferenceError != nil {
                label.textColor = MD3.warning
                label.layer?.backgroundColor = MD3.warning.withAlphaComponent(0.15).cgColor
                label.layer?.borderColor = MD3.warning.withAlphaComponent(0.4).cgColor
            } else if rule.strategy.uppercased() == "DIRECT" {
                label.textColor = MD3.onSurface
                label.layer?.backgroundColor = MD3.successContainer.cgColor
                label.layer?.borderColor = MD3.success.withAlphaComponent(0.3).cgColor
            } else if rule.strategy.uppercased() == "REJECT" {
                label.textColor = MD3.onSurface
                label.layer?.backgroundColor = MD3.errorContainer.cgColor
                label.layer?.borderColor = MD3.error.withAlphaComponent(0.3).cgColor
            } else {
                label.textColor = MD3.onSurface
                label.layer?.backgroundColor = MD3.primary.withAlphaComponent(0.16).cgColor
                label.layer?.borderColor = MD3.primary.withAlphaComponent(0.35).cgColor
            }
            let container = NSView()
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                label.heightAnchor.constraint(equalToConstant: 22),
                label.widthAnchor.constraint(greaterThanOrEqualToConstant: 50)
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
        label.font = rule.isSection ? .systemFont(ofSize: 13, weight: .bold) : .systemFont(ofSize: 12)
        label.textColor = columnID == "strategy" && rule.strategyReferenceError != nil ? MD3.warning :
            (rule.isSection ? MD3.onSurface : (columnID == "id" || columnID == "count" ? MD3.onSurfaceVariant : MD3.onSurface))
        label.toolTip = (columnID == "strategy" ? rule.strategyReferenceError : rule.referenceError) ?? text
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
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
