import AppKit
import Foundation

extension MainWindowController {
    
    func makeLogsView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MD3.background.cgColor
        registerThemeObserver { [weak view] in
            view?.layer?.backgroundColor = MD3.background.cgColor
        }
        
        let logTitle = NSTextField(labelWithString: "日志")
        logTitle.font = .systemFont(ofSize: 30, weight: .bold)
        logTitle.textColor = MD3.onSurface
        logTitle.translatesAutoresizingMaskIntoConstraints = false
        registerThemeObserver { [weak logTitle] in
            logTitle?.textColor = MD3.onSurface
        }

        let clearButton = MD3Button()
        clearButton.title = "清空日志"
        clearButton.style = .outlined
        clearButton.target = self
        clearButton.action = #selector(clearLogsClicked)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let logScroll = NSScrollView()
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        logScroll.hasVerticalScroller = true
        logScroll.drawsBackground = false
        logScroll.documentView = logs
        
        logs.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logs.isEditable = false
        logs.backgroundColor = .clear
        logs.textColor = MD3.onSurface
        registerThemeObserver { [weak self] in
            self?.logs.textColor = MD3.onSurface
        }
        
        let panel = MD3Panel()
        panel.type = .filled
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(logScroll)
        
        view.addSubview(logTitle)
        view.addSubview(clearButton)
        view.addSubview(panel)

        NSLayoutConstraint.activate([
            logTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            logTitle.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),

            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            clearButton.centerYAnchor.constraint(equalTo: logTitle.centerYAnchor),

            panel.leadingAnchor.constraint(equalTo: logTitle.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            panel.topAnchor.constraint(equalTo: logTitle.bottomAnchor, constant: 20),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            
            logScroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            logScroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            logScroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            logScroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12)
        ])

        return view
    }

    @objc func clearLogsClicked() {
        logs.string = ""
        refreshHomeFeatureStatus()
    }

    func appendLog(_ text: String) {
        logs.textStorage?.append(NSAttributedString(string: text))
        logs.scrollToEndOfDocument(nil)
        logStatusLabel.stringValue = "日志：\(logs.string.components(separatedBy: .newlines).filter { !$0.isEmpty }.count) 行"
    }
}
