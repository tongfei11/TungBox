import AppKit
import XCTest
@testable import TungBox

final class LogDetailPresentationTests: XCTestCase {
    @MainActor
    func testConnectionNamesReplaceMetadataWithoutLosingRawCopyOrSelection() throws {
        let inbound = "+0800 2026-10-30 09:36:23 INFO [2203937364 0ms] inbound/mixed[mixed-in]: example.com:443\n"
        let outbound = "+0800 2026-10-30 09:36:23 INFO [2203937364 1ms] outbound/trojan[日本 03]: connected\n"
        let direct = "+0800 2026-10-30 09:36:23 INFO [42 3ms] outbound/direct[direct]: connected\n"
        let raw = inbound + outbound + direct
        let names = LogTextPresentation.connectionNames(in: raw)
        XCTAssertEqual(names["2203937364"], "日本 03")
        XCTAssertEqual(names["42"], "直连")
        XCTAssertEqual(LogTextPresentation.connectionNames(in: "INFO [17 4ms] outbound/trojan[[A] 日本 03]: connection to [2001:db8::1]:443")["17"], "[A] 日本 03")
        let presentation = LogTextPresentation(source: raw)
        XCTAssertTrue(presentation.text.string.contains("[日本 03]"))
        XCTAssertTrue(presentation.text.string.contains("[直连]"))
        XCTAssertFalse(presentation.text.string.contains("2203937364"))
        XCTAssertFalse(presentation.text.string.contains("1ms"))
        XCTAssertEqual(presentation.copyText(in: NSRange(location: 0, length: presentation.text.length)), raw)
        let zone = (presentation.text.string as NSString).range(of: "+0800")
        let font = try XCTUnwrap(presentation.text.attribute(.font, at: zone.location, effectiveRange: nil) as? NSFont)
        XCTAssertLessThan(font.pointSize, 1, "时区仅在原始复制文本中保留")
        let filtered = LogTextPresentation(source: inbound, connectionNames: names)
        XCTAssertTrue(filtered.text.string.contains("[日本 03]"))
        let view = LogDetailTextView()
        view.setLogText(inbound)
        XCTAssertTrue(view.string.contains("[待识别]"))
        view.setSelectedRange((view.string as NSString).range(of: "example.com:443"))
        view.setLogText(raw, connectionNames: names)
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "example.com:443")
        XCTAssertEqual(view.presentation.copyText(in: view.selectedRange()), "example.com:443")
    }

    @MainActor
    func testMissingTimesAreRecordedBeforeDisplayAndCopyWithoutChangingCoreTimes() {
        let date = Date(timeIntervalSince1970: 1_793_326_800)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let time = formatter.string(from: date)
        let core = "+0800 2026-10-30 09:36:23 INFO [2203937364 1ms] outbound/direct[direct]: connected"
        let raw = "[启动] 恢复状态\n\n\u{001B}[33mWARN\u{001B}[0m[0000] deprecated option\n" + core + "\n"
        let recorded = LogTimestamp.addingMissing(to: raw, at: date)
        XCTAssertEqual(recorded, "\(time) [启动] 恢复状态\n\n\(time) \u{001B}[33mWARN\u{001B}[0m[0000] deprecated option\n" + core + "\n")
        XCTAssertEqual(LogTimestamp.addingMissing(to: recorded, at: date.addingTimeInterval(60)), recorded)
        let display = LogTextPresentation(source: recorded)
        XCTAssertTrue(display.text.string.contains(time))
        XCTAssertEqual(display.copyText(in: NSRange(location: 0, length: display.text.length)), display.source)
        XCTAssertTrue(display.source.contains(core))
    }

    @MainActor
    func testFormattingAndPartialSelectionCopyKeepOriginalPlainText() {
        let source = "+0800 2026-10-30 10:20:26 INFO [42 3ms] inbound/mixed[mixed-in]: connection to example.com:443\n[节点] 🧪 测速已完成\n2026-10-30 10:20:27 [WARN] retrying request\nDEBUG connection from 127.0.0.1:56622\nFATAL dial timeout\n\n"
        let presentation = LogTextPresentation(source: source)
        XCTAssertEqual(presentation.copyText(in: NSRange(location: 0, length: presentation.text.length)), source)
        for value in ["example.com:443", "🧪 测速已完成", "connection from 127.0.0.1:56622", "retrying request"] {
            let range = (presentation.text.string as NSString).range(of: value)
            XCTAssertNotEqual(range.location, NSNotFound)
            XCTAssertEqual(presentation.copyText(in: range), value)
        }
        let start = (presentation.text.string as NSString).range(of: "[节点]").location
        let end = (presentation.text.string as NSString).range(of: "retrying request")
        XCTAssertEqual(presentation.copyText(in: NSRange(location: start, length: NSMaxRange(end) - start)),
                       "[节点] 🧪 测速已完成\n2026-10-30 10:20:27 [WARN] retrying request")
        XCTAssertEqual(presentation.copyText(in: NSRange(location: NSNotFound, length: 1)), "")
        let ansi = LogTextPresentation(source: "\u{001B}[31mERROR\u{001B}[0m timeout")
        XCTAssertEqual(ansi.source, "ERROR timeout")
        XCTAssertEqual(LogTextPresentation.level(in: "+0800 2026-10-30 10:20:26 \u{001B}[31mERROR\u{001B}[0m timeout"), .error)
        XCTAssertEqual(LogTextPresentation.level(in: "[节点] INFO 请求正文含 ERROR 字样"), .info)
        XCTAssertEqual(LogTextPresentation.level(in: "2026-10-30 10:20:26 FATAL cannot connect"), .error)
        let bracket = LogTextPresentation(source: "[WARN] retry")
        XCTAssertEqual(bracket.copyText(in: (bracket.text.string as NSString).range(of: "AR")), "AR")
    }

    @MainActor
    func testSelectionSurvivesNewLinesAndStylesRenderInBothThemes() throws {
        _ = NSApplication.shared
        let originalDark = MD3.isDark
        defer { MD3.isDark = originalDark }
        for dark in [true, false] {
            MD3.isDark = dark
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.contentView = nil; window.close() }
            let view = LogDetailTextView()
            view.frame = NSRect(x: 0, y: 0, width: 940, height: 300)
            view.backgroundColor = MD3.background
            LogTextViewLayout.configure(view)
            window.contentView = view
            let text = "+0800 2026-10-30 10:20:26.123456 INFO [节点] 节点结果已返回，开始刷新自动选择\n2026-10-30 10:20:26 DEBUG inbound connection from 127.0.0.1:56622\n2026-10-30 10:20:27 INFO outbound/trojan[日本 03]: connection to chatgpt.com:443\n2026-10-30 10:20:28 WARN retrying connection to chatgpt.com:443 (1/3)\n2026-10-30 10:20:29 ERROR dial tcp 104.18.12.190:443: i/o timeout\n[节点] 测速已完成\n"
            view.setLogText(text)
            let selection = (view.string as NSString).range(of: "chatgpt.com:443")
            view.setSelectedRange(selection)
            view.setLogText(text + "2026-10-30 10:20:30 INFO next event\n")
            XCTAssertEqual(view.selectedRange(), selection)
            XCTAssertEqual(view.presentation.copyText(in: view.selectedRange()), "chatgpt.com:443")
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            XCTAssertTrue(view.writeSelection(to: pasteboard, type: .string))
            XCTAssertEqual(pasteboard.string(forType: .string), "chatgpt.com:443")
            XCTAssertEqual(view.copyableText, text + "2026-10-30 10:20:30 INFO next event\n")
            view.setSelectedRange(NSRange(location: 0, length: 0))
            view.layoutManager?.ensureLayout(for: try XCTUnwrap(view.textContainer))
            XCTAssertFalse(view.isRichText)
            XCTAssertTrue(view.isSelectable)
            if let path = ProcessInfo.processInfo.environment["TUNGBOX_LOG_PREVIEW"] {
                let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: image)
                try XCTUnwrap(image.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: path + (dark ? "-dark.png" : "-light.png")))
            }
            view.setLogText("")
            XCTAssertTrue(view.copyableText.isEmpty)
        }
    }
}
