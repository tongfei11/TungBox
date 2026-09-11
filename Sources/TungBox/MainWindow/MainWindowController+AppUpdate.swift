import AppKit
import Foundation

struct MarkdownParser {
    static func toHTML(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var html = ""
        var inList = false
        var inCodeBlock = false
        var inTable = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 1. Code block fence
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    html += "</code></pre>\n"
                    inCodeBlock = false
                } else {
                    if inTable { html += "</table>\n"; inTable = false }
                    if inList { html += "</ul>\n"; inList = false }
                    html += "<pre><code>"
                    inCodeBlock = true
                }
                continue
            }
            
            if inCodeBlock {
                html += escapeHTML(line) + "\n"
                continue
            }
            
            // 2. Table row
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                if inList { html += "</ul>\n"; inList = false }
                
                // Skip table delimiter row: | --- | --- |
                if trimmed.contains("---") {
                    continue
                }
                
                let cells = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if !inTable {
                    html += "<table>\n"
                    inTable = true
                    html += "  <tr>\n"
                    for cell in cells {
                        html += "    <th>\(parseInline(cell))</th>\n"
                    }
                    html += "  </tr>\n"
                } else {
                    html += "  <tr>\n"
                    for cell in cells {
                        html += "    <td>\(parseInline(cell))</td>\n"
                    }
                    html += "  </tr>\n"
                }
                continue
            } else if inTable {
                html += "</table>\n"
                inTable = false
            }
            
            // 3. Unordered list item
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !inList {
                    html += "<ul>\n"
                    inList = true
                }
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                html += "  <li>\(parseInline(content))</li>\n"
                continue
            } else if inList {
                html += "</ul>\n"
                inList = false
            }
            
            // 4. Headers
            if trimmed.hasPrefix("## ") {
                let content = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                html += "<h2>\(parseInline(content))</h2>\n"
                continue
            } else if trimmed.hasPrefix("### ") {
                let content = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                html += "<h3>\(parseInline(content))</h3>\n"
                continue
            } else if trimmed.hasPrefix("# ") {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                html += "<h1>\(parseInline(content))</h1>\n"
                continue
            }
            
            // 5. Empty line
            if trimmed.isEmpty {
                html += "<br>\n"
                continue
            }
            
            // 6. Normal paragraph
            html += "<p>\(parseInline(line))</p>\n"
        }
        
        // Close any open tags
        if inCodeBlock { html += "</code></pre>\n" }
        if inTable { html += "</table>\n" }
        if inList { html += "</ul>\n" }
        
        return html
    }
    
    private static func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
    
    private static func parseInline(_ string: String) -> String {
        var result = string
        
        // Parse bold: **text**
        result = replaceMarkdown(result, pattern: "**", openTag: "<strong>", closeTag: "</strong>")
        
        // Parse code: `code`
        result = replaceMarkdown(result, pattern: "`", openTag: "<code>", closeTag: "</code>")
        
        // Parse links: [text](url)
        result = parseLinks(result)
        
        return result
    }
    
    private static func replaceMarkdown(_ string: String, pattern: String, openTag: String, closeTag: String) -> String {
        let parts = string.components(separatedBy: pattern)
        guard parts.count > 1 else { return string }
        var result = ""
        for (index, part) in parts.enumerated() {
            result += part
            if index < parts.count - 1 {
                result += (index % 2 == 0) ? openTag : closeTag
            }
        }
        return result
    }
    
    private static func parseLinks(_ string: String) -> String {
        var result = ""
        var index = string.startIndex
        
        while index < string.endIndex {
            if string[index...].hasPrefix("[") {
                let rest = string[index...]
                if let closeBracketIndex = rest.firstIndex(of: "]") {
                    let nextIndex = string.index(after: closeBracketIndex)
                    if nextIndex < string.endIndex && string[nextIndex] == "(" {
                        if let closeParenIndex = string[nextIndex...].firstIndex(of: ")") {
                            let textRange = string.index(after: index)..<closeBracketIndex
                            let urlRange = string.index(after: nextIndex)..<closeParenIndex
                            let text = String(string[textRange])
                            let url = String(string[urlRange])
                            result += "<a href=\"\(url)\">\(text)</a>"
                            index = string.index(after: closeParenIndex)
                            continue
                        }
                    }
                }
            }
            result.append(string[index])
            index = string.index(after: index)
        }
        
        return result
    }
}

extension MainWindowController {
    func checkAppUpdateInBackground() {
        if case .checking = appUpdateCheckState {
            return
        }

        appUpdateCheckState = .checking

        Task {
            do {
                let release = try await AppUpdater.latestRelease()
                await MainActor.run { [weak self] in
                    self?.handleAppUpdateCheck(release)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.appUpdateCheckState = .failed(error.localizedDescription)
                    self?.appVersionFooter.showsNewBadge = false
                    self?.appendLog("[TungBox] 应用更新检查失败：\(error.localizedDescription)\n")
                }
            }
        }
    }

    private func handleAppUpdateCheck(_ release: AppRelease) {
        latestAppRelease = release
        if AppUpdater.isNewer(release) {
            appUpdateCheckState = .available(release)
            appVersionFooter.showsNewBadge = true
            appendLog("[TungBox] 发现应用更新：\(TungBoxVersion.release) -> \(release.version)\n")
        } else {
            appUpdateCheckState = .upToDate(release)
            appVersionFooter.showsNewBadge = false
            appendLog("[TungBox] 应用已是最新版本：\(TungBoxVersion.release)\n")
        }
    }

    @objc func appVersionFooterClicked() {
        switch appUpdateCheckState {
        case .available(let release):
            showAppUpdateDialog(release)
        case .checking:
            showToast("正在检查应用更新...")
        case .upToDate:
            showToast("TungBox 已是最新版：\(TungBoxVersion.release)")
        case .failed, .notChecked:
            showToast("打开控制台时会自动检查更新")
        }
    }

    private func showAppUpdateDialog(_ release: AppRelease) {
        let bodyText = release.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteLines = bodyText.components(separatedBy: .newlines)
        
        let titleLikeLines = Set([
            release.name,
            "TungBox \(release.version)",
            release.tag,
            "v\(release.version)"
        ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        
        var displayLines = noteLines
        if let firstLine = displayLines.first, titleLikeLines.contains(firstLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            displayLines.removeFirst()
        }
        let cleanMarkdown = displayLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Compile Markdown to HTML natively
        let htmlContent = MarkdownParser.toHTML(cleanMarkdown)
        
        // Generate CSS matching MD3 theme
        let bodyColor = MD3.onSurfaceVariant.hexString
        let headerColor = MD3.onSurface.hexString
        let linkColor = MD3.primary.hexString
        let dividerColor = MD3.outlineVariant.hexString
        let codeBg = MD3.surfaceContainer.hexString
        
        let styledHtml = """
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            font-size: 13px;
            line-height: 1.6;
            color: \(bodyColor);
            background-color: transparent;
            margin: 0;
            padding: 0;
        }
        h1, h2, h3, h4, h5, h6 {
            color: \(headerColor);
            font-weight: bold;
            margin-top: 16px;
            margin-bottom: 8px;
        }
        h1 { font-size: 18px; }
        h2 { font-size: 16px; }
        h3 { font-size: 14px; }
        p {
            margin-top: 0;
            margin-bottom: 8px;
        }
        ul, ol {
            margin-top: 0;
            margin-bottom: 8px;
            padding-left: 20px;
        }
        li {
            margin-bottom: 4px;
        }
        code {
            font-family: Menlo, Monaco, Consolas, "Courier New", monospace;
            font-size: 12px;
            background-color: \(codeBg);
            padding: 2px 4px;
            border-radius: 4px;
        }
        pre {
            background-color: \(codeBg);
            padding: 8px;
            border-radius: 6px;
            overflow-x: auto;
            margin-top: 0;
            margin-bottom: 8px;
        }
        pre code {
            padding: 0;
            background-color: transparent;
            border-radius: 0;
        }
        a {
            color: \(linkColor);
            text-decoration: none;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin-top: 8px;
            margin-bottom: 12px;
        }
        th, td {
            border: 1px solid \(dividerColor);
            padding: 6px 8px;
            text-align: left;
        }
        th {
            background-color: \(codeBg);
            font-weight: bold;
        }
        blockquote {
            border-left: 4px solid \(dividerColor);
            padding-left: 12px;
            margin: 0 0 8px 0;
            color: \(bodyColor);
        }
        </style>
        </head>
        <body>
        \(htmlContent)
        </body>
        </html>
        """
        
        let notesView = NSTextView()
        notesView.isEditable = false
        notesView.isSelectable = true
        notesView.drawsBackground = false
        notesView.textContainerInset = NSSize(width: 0, height: 0)
        notesView.isVerticallyResizable = true
        notesView.isHorizontallyResizable = false
        notesView.autoresizingMask = [.width]
        notesView.textContainer?.widthTracksTextView = true
        notesView.textContainer?.containerSize = NSSize(
            width: 440,
            height: CGFloat.greatestFiniteMagnitude
        )
        notesView.minSize = NSSize(width: 0, height: 0)
        notesView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        let htmlData = styledHtml.data(using: .utf8)!
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        if let attrString = try? NSMutableAttributedString(data: htmlData, options: options, documentAttributes: nil) {
            notesView.textStorage?.setAttributedString(attrString)
        } else {
            notesView.string = cleanMarkdown
            notesView.textColor = MD3.onSurfaceVariant
            notesView.font = .systemFont(ofSize: 13)
        }

        let scroll = MD3ScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.applyThinOverlayScroller()
        scroll.verticalScrollElasticity = .allowed
        scroll.documentView = notesView
        scroll.heightAnchor.constraint(equalToConstant: 220).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 440).isActive = true

        let dialog = showMD3Dialog(
            title: "发现 TungBox 更新",
            message: "当前版本：\(TungBoxVersion.release)\n最新版本：\(release.version)",
            customView: scroll,
            confirmTitle: "打开 Release",
            cancelTitle: "稍后"
        )
        dialog.onConfirm = { [weak dialog] in
            NSWorkspace.shared.open(release.htmlURL)
            dialog?.dismiss()
        }
        dialog.onCancel = { [weak dialog] in
            dialog?.dismiss()
        }
    }
}

extension NSColor {
    var hexString: String {
        guard let rgbColor = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
