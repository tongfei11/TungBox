import Foundation

enum AppUpdater {
    static let latestReleaseURL = URL(string: "https://github.com/tongfei11/TungBox/releases/latest")!
    static let releasesFeedURL = URL(string: "https://github.com/tongfei11/TungBox/releases.atom")!

    static func latestRelease() async throws -> AppRelease {
        do {
            return try await latestReleaseFromFeed()
        } catch {
            let release = try await latestReleaseFromRedirect()
            return release
        }
    }

    static func isNewer(_ release: AppRelease) -> Bool {
        Runner.compareVersions(TungBoxVersion.release, release.version) == .orderedAscending
    }

    private static func latestReleaseFromFeed() async throws -> AppRelease {
        let data = try await fetchData(from: releasesFeedURL, accept: "application/atom+xml,text/xml,*/*")
        guard let entry = ReleaseFeedParser.parse(data: data) else {
            throw NSError.user("无法识别应用更新发布说明")
        }

        let tag = entry.tag ?? releaseTag(from: entry.url) ?? entry.title
        let version = normalizeVersion(tag)
        guard !version.isEmpty else {
            throw NSError.user("无法识别最新应用版本")
        }

        return AppRelease(
            version: version,
            tag: tag,
            name: entry.title.isEmpty ? "TungBox \(version)" : entry.title,
            body: htmlToPlainText(entry.content),
            htmlURL: entry.url,
            publishedAt: entry.updated
        )
    }

    private static func latestReleaseFromRedirect() async throws -> AppRelease {
        let tag = try await latestReleaseTag()
        let version = normalizeVersion(tag)
        guard !version.isEmpty else {
            throw NSError.user("无法识别最新应用版本")
        }

        let htmlURL = URL(string: "https://github.com/tongfei11/TungBox/releases/tag/\(tag)")!
        return AppRelease(
            version: version,
            tag: tag,
            name: "TungBox \(version)",
            body: "",
            htmlURL: htmlURL,
            publishedAt: nil
        )
    }

    private static func latestReleaseTag() async throws -> String {
        do {
            return try await latestReleaseTag(method: "HEAD")
        } catch {
            return try await latestReleaseTag(method: "GET")
        }
    }

    private static func latestReleaseTag(method: String) async throws -> String {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("TungBox/\(TungBoxVersion.current)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,*/*", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)

        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            let hint: String
            switch http.statusCode {
            case 403:
                hint = "GitHub 访问受限，可能触发频率限制"
            case 404:
                hint = "未找到 TungBox Release"
            case 500...599:
                hint = "GitHub 服务暂时不可用"
            default:
                hint = "请检查网络连接"
            }
            throw NSError.user("应用更新检查失败 (HTTP \(http.statusCode))：\(hint)")
        }

        guard let resolvedURL = response.url,
              let tag = releaseTag(from: resolvedURL) else {
            throw NSError.user("无法识别最新应用版本")
        }
        return tag
    }

    private static func fetchData(from url: URL, accept: String) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("TungBox/\(TungBoxVersion.current)", forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError.user("应用更新检查失败 (HTTP \(http.statusCode))")
        }
        return data
    }

    private static func normalizeVersion(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private static func releaseTag(from url: URL) -> String? {
        let components = url.pathComponents
        if let index = components.firstIndex(of: "tag"),
           components.indices.contains(index + 1) {
            return components[index + 1]
        }

        let text = url.absoluteString
        guard let range = text.range(of: #"/releases/tag/([^/?#]+)"#, options: .regularExpression) else {
            return nil
        }
        return String(text[range].split(separator: "/").last ?? "")
    }

    private static func htmlToPlainText(_ html: String) -> String {
        var text = html
        let replacements = [
            (#"</h[1-6]>"#, "\n\n"),
            (#"<h[1-6][^>]*>"#, ""),
            (#"</p>"#, "\n\n"),
            (#"<p[^>]*>"#, ""),
            (#"<br\s*/?>"#, "\n"),
            (#"</li>"#, "\n"),
            (#"<li[^>]*>"#, "• "),
            (#"</?(ul|ol)[^>]*>"#, "\n")
        ]
        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " "
        ]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private struct ReleaseFeedEntry {
    var title: String = ""
    var content: String = ""
    var url: URL = AppUpdater.latestReleaseURL
    var tag: String?
    var updated: Date?
}

private final class ReleaseFeedParser: NSObject, XMLParserDelegate {
    private var entries: [ReleaseFeedEntry] = []
    private var currentEntry: ReleaseFeedEntry?
    private var currentElement = ""
    private var textBuffer = ""

    static func parse(data: Data) -> ReleaseFeedEntry? {
        let delegate = ReleaseFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.entries.first
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        textBuffer = ""

        if elementName == "entry" {
            currentEntry = ReleaseFeedEntry()
        } else if elementName == "link",
                  currentEntry != nil,
                  attributeDict["rel"] == "alternate",
                  let href = attributeDict["href"],
                  let url = URL(string: href) {
            currentEntry?.url = url
            currentEntry?.tag = AppUpdater.releaseTagForFeed(from: url)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard currentEntry != nil else { return }
        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "title":
            currentEntry?.title = value
        case "content":
            currentEntry?.content = value
        case "updated":
            currentEntry?.updated = ISO8601DateFormatter().date(from: value)
        case "entry":
            if let currentEntry {
                entries.append(currentEntry)
            }
            currentEntry = nil
        default:
            break
        }

        textBuffer = ""
        currentElement = ""
    }
}

private extension AppUpdater {
    static func releaseTagForFeed(from url: URL) -> String? {
        releaseTag(from: url)
    }
}
