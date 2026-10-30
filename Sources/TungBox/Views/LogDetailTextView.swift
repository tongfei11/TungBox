import AppKit

@MainActor
enum LogLevelStyle: String, CaseIterable {
    case info = "INFO", debug = "DEBUG", warn = "WARN", error = "ERROR"
    var color: NSColor {
        let hex: UInt32
        switch self {
        case .info: hex = MD3.isDark ? 0x12D8C2 : 0x007B70
        case .debug: hex = MD3.isDark ? 0x42B4FA : 0x0067AC
        case .warn: hex = MD3.isDark ? 0xF3C442 : 0x8B6000
        case .error: hex = MD3.isDark ? 0xFF6670 : 0xBB2537
        }
        return NSColor(hex: hex)
    }
    static func parse(_ value: String) -> Self {
        switch value.uppercased() {
        case "DEBUG", "TRACE": return .debug
        case "WARN", "WARNING": return .warn
        case "ERROR", "FATAL": return .error
        default: return .info
        }
    }
}

/// Display offsets map back to plain source offsets, including inserted tabs and
/// inferred INFO badges. Copy never serializes decorations or reformats the log.
@MainActor
struct LogTextPresentation {
    nonisolated static let levelKey = NSAttributedString.Key("TungBoxLogLevel")
    private static let ansi = try! NSRegularExpression(pattern: "\\u001B\\[[0-9;]*m")
    private static let timestamp = try! NSRegularExpression(pattern: #"^((?:[+-]\d{4}\s+)?\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?)\s*"#)
    private static let severity = try! NSRegularExpression(pattern: #"^(?:\[(INFO|WARN|WARNING|ERROR|DEBUG|FATAL|TRACE)\]|(INFO|WARN|WARNING|ERROR|DEBUG|FATAL|TRACE)\b)\s*"#, options: .caseInsensitive)
    private static let endpoint = try! NSRegularExpression(pattern: #"(?:[a-zA-Z0-9_-]+\.)+[a-zA-Z0-9_-]+(?::\d+)?|\[[0-9a-fA-F:]+\](?::\d+)?"#)
    private static let direction = try! NSRegularExpression(pattern: #"\b(?:inbound|outbound)(?:/[^\s:]+)?"#)
    private static let zone = try! NSRegularExpression(pattern: #"^[+-]\d{4}\s+"#)
    private static let connection = try! NSRegularExpression(pattern: #"\[(\d+)\s+\d+(?:\.\d+)?(?:ms|s|m\d+s)\]\s*"#)
    private static let outbound = try! NSRegularExpression(pattern: #"outbound/([^\s\[]+)\[(.*?)\]:"#)

    static func connectionNames(in raw: String) -> [String: String] {
        let plain = ansi.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length), withTemplate: "")
        var names: [String: String] = [:]
        for line in plain.components(separatedBy: "\n") {
            let ns = line as NSString, range = NSRange(location: 0, length: (line as NSString).length)
            guard let id = connection.firstMatch(in: line, range: range),
                  let route = outbound.firstMatch(in: line, range: range) else { continue }
            let type = ns.substring(with: route.range(at: 1))
            names[ns.substring(with: id.range(at: 1))] = type == "direct" ? "直连" : ns.substring(with: route.range(at: 2))
        }
        return names
    }
    static func level(in raw: String) -> LogLevelStyle {
        let line = ansi.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length), withTemplate: "")
        let ns = line as NSString
        let time = timestamp.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
        let rest = ns.substring(from: time.map { NSMaxRange($0.range) } ?? 0)
        guard let match = severity.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)) else { return .info }
        let range = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
        return LogLevelStyle.parse((rest as NSString).substring(with: range))
    }
    let text: NSAttributedString
    let source: String
    private let offsets: [Int]
    private let contexts: [(display: NSRange, source: NSRange)]

    init(source raw: String, connectionNames: [String: String] = [:]) {
        source = Self.ansi.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length), withTemplate: "")
        let result = NSMutableAttributedString(string: "")
        var offsets = [0]
        var contexts: [(display: NSRange, source: NSRange)] = []
        let names = connectionNames.merging(Self.connectionNames(in: source)) { _, new in new }
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 194), NSTextTab(textAlignment: .left, location: 262)]
        paragraph.headIndent = 262
        paragraph.minimumLineHeight = 21
        paragraph.paragraphSpacing = 3
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: MD3.onSurface, .paragraphStyle: paragraph]
        func append(_ value: String, sourceRange: NSRange, attributes: [NSAttributedString.Key: Any] = [:]) {
            var attrs = base
            attrs.merge(attributes) { _, new in new }
            result.append(NSAttributedString(string: value, attributes: attrs))
            let count = (value as NSString).length
            if count > 0 {
                for position in 1...count { offsets.append(sourceRange.location + position * sourceRange.length / count) }
            }
        }
        var start = 0
        let lines = source.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let ns = line as NSString
            if ns.length > 0 {
                let timeMatch = Self.timestamp.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
                let timeRange = timeMatch?.range(at: 1) ?? NSRange(location: 0, length: 0)
                let restStart = timeMatch.map { NSMaxRange($0.range) } ?? 0
                let rest = ns.substring(from: restStart)
                let levelMatch = Self.severity.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length))
                var levelRange = NSRange(location: restStart, length: 0)
                var token = "INFO"
                var level = LogLevelStyle.info
                var bodyStart = restStart
                if let match = levelMatch {
                    let group = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                    token = (rest as NSString).substring(with: group).uppercased()
                    level = LogLevelStyle.parse(token)
                    // Include brackets and the original spelling in copied text.
                    let end = group.location + group.length + (match.range(at: 1).location != NSNotFound ? 1 : 0)
                    levelRange = NSRange(location: restStart, length: end)
                    token = ns.substring(with: levelRange)
                    bodyStart = restStart + NSMaxRange(match.range)
                }
                let time = ns.substring(with: timeRange)
                let zoneRange = Self.zone.firstMatch(in: time, range: NSRange(location: 0, length: (time as NSString).length))?.range
                let visibleTime = (time as NSString).substring(from: zoneRange.map(NSMaxRange) ?? 0)
                let measuredWidth = (visibleTime as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)]).width
                let timeFont = NSFont.monospacedSystemFont(ofSize: min(10, 1630 / max(1, measuredWidth)), weight: .regular)
                let timeOffset = result.length
                append(time, sourceRange: NSRange(location: start, length: NSMaxRange(timeRange)), attributes: [.foregroundColor: MD3.onSurfaceVariant, .font: timeFont])
                if let zoneRange {
                    result.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 0.01, weight: .regular), .foregroundColor: NSColor.clear], range: NSRange(location: timeOffset, length: zoneRange.length))
                }
                append("\t", sourceRange: NSRange(location: start + NSMaxRange(timeRange), length: levelRange.location - NSMaxRange(timeRange)))
                append(token, sourceRange: NSRange(location: start + levelRange.location, length: levelRange.length), attributes: [Self.levelKey: level.rawValue, .foregroundColor: level.color, .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)])
                append("\t", sourceRange: NSRange(location: start + NSMaxRange(levelRange), length: bodyStart - NSMaxRange(levelRange)))
                let bodyOffset = result.length
                let body = ns.substring(from: bodyStart)
                var visibleBody = body
                let bodyAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: level == .warn || level == .error ? level.color : MD3.onSurface]
                if let context = Self.connection.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length)), context.range.location == 0 {
                    let id = (body as NSString).substring(with: context.range(at: 1))
                    let label = "[\(names[id] ?? "待识别")] "
                    let sourceRange = NSRange(location: start + bodyStart, length: context.range.length)
                    contexts.append((NSRange(location: result.length, length: (label as NSString).length), sourceRange))
                    append(label, sourceRange: sourceRange, attributes: bodyAttributes)
                    let rest = (body as NSString).substring(from: context.range.length)
                    visibleBody = label + rest
                    append(rest, sourceRange: NSRange(location: NSMaxRange(sourceRange), length: (rest as NSString).length), attributes: bodyAttributes)
                } else {
                    append(body, sourceRange: NSRange(location: start + bodyStart, length: ns.length - bodyStart), attributes: bodyAttributes)
                }
                for (regex, color) in [(Self.direction, LogLevelStyle.debug.color), (Self.endpoint, LogLevelStyle.info.color)] {
                    for match in regex.matches(in: visibleBody, range: NSRange(location: 0, length: (visibleBody as NSString).length)) {
                        result.addAttribute(.foregroundColor, value: color, range: NSRange(location: bodyOffset + match.range.location, length: match.range.length))
                    }
                }
            }
            start += ns.length
            if index < lines.count - 1 { append("\n", sourceRange: NSRange(location: start, length: 1)); start += 1 }
        }
        text = result
        self.offsets = offsets
        self.contexts = contexts
    }

    func copyText(in range: NSRange) -> String {
        guard range.location >= 0, range.length >= 0, range.location < offsets.count,
              range.length <= offsets.count - 1 - range.location else { return "" }
        var start = offsets[range.location], end = offsets[NSMaxRange(range)]
        for context in contexts where NSIntersectionRange(context.display, range).length > 0 {
            start = min(start, context.source.location)
            end = max(end, NSMaxRange(context.source))
        }
        return (source as NSString).substring(with: NSRange(location: start, length: end - start))
    }

    func sourceRange(for range: NSRange) -> NSRange {
        guard range.location >= 0, range.length >= 0, range.location < offsets.count,
              range.length <= offsets.count - 1 - range.location else { return NSRange(location: 0, length: 0) }
        return NSRange(location: offsets[range.location], length: offsets[NSMaxRange(range)] - offsets[range.location])
    }
    func displayRange(for source: NSRange) -> NSRange {
        func lowerBound(_ value: Int) -> Int {
            var low = 0, high = offsets.count - 1
            while low < high {
                let middle = (low + high) / 2
                if offsets[middle] < value { low = middle + 1 } else { high = middle }
            }
            return low
        }
        let start = lowerBound(source.location), end = lowerBound(NSMaxRange(source))
        return NSRange(location: start, length: end - start)
    }
}

final class LogDetailLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawLogDecorations(forGlyphRange: glyphsToShow, at: origin)
        // Selection is drawn last so native text selection remains visible.
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawLogDecorations(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, let container = textContainers.first else { return }
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(LogTextPresentation.levelKey, in: visible) { value, range, _ in
            guard let name = value as? String,
                  let color = storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? .monospacedSystemFont(ofSize: 10, weight: .semibold)
            let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let baseline = fragment.minY + location(forGlyphAt: glyphs.location).y + origin.y
            rect.origin.y = baseline - font.ascender
            rect.size.height = font.ascender - font.descender
            if name == "WARN" || name == "ERROR" {
                let paragraph = (storage.string as NSString).paragraphRange(for: range)
                let rowGlyphs = glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
                let rows = boundingRect(forGlyphRange: rowGlyphs, in: container)
                color.withAlphaComponent(0.07).setFill()
                NSBezierPath(roundedRect: NSRect(x: origin.x, y: origin.y + rows.minY - 2, width: container.containerSize.width, height: rows.height + 4), xRadius: 6, yRadius: 6).fill()
            }
            color.withAlphaComponent(0.15).setFill()
            rect = rect.insetBy(dx: -7, dy: -2)
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX - 17, y: rect.midY - 3, width: 6, height: 6)).fill()
        }
    }
}

@MainActor
final class LogDetailTextView: NSTextView {
    private(set) var presentation = LogTextPresentation(source: "")
    private var connectionNames: [String: String] = [:]
    var copyableText: String { presentation.source }

    init() {
        let storage = NSTextStorage()
        let layout = LogDetailLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        isRichText = false
        textContainerInset = NSSize(width: 12, height: 8)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setLogText(_ text: String, connectionNames: [String: String]? = nil) {
        let selection = presentation.sourceRange(for: selectedRange())
        let previousSource = presentation.source
        if let connectionNames { self.connectionNames = connectionNames }
        presentation = LogTextPresentation(source: text, connectionNames: self.connectionNames)
        textStorage?.setAttributedString(presentation.text)
        if presentation.source.hasPrefix(previousSource) {
            setSelectedRange(presentation.displayRange(for: selection))
        } else {
            setSelectedRange(NSRange(location: 0, length: 0))
        }
    }
    override func copy(_ sender: Any?) {
        guard !selectedPlainText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        _ = writeSelection(to: NSPasteboard.general, type: .string)
    }
    private var selectedPlainText: String {
        selectedRanges.map { presentation.copyText(in: $0.rangeValue) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override func writeSelection(to pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string else { return false }
        let text = selectedPlainText
        guard !text.isEmpty else { return false }
        return pasteboard.setString(text, forType: .string)
    }
}
