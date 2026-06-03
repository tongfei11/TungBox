import Foundation

enum AppUpdater {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/tongfei11/TungBox/releases/latest")!

    static func latestRelease() async throws -> AppRelease {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.setValue("TungBox/\(TungBoxVersion.current)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
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

        let payload = try JSONDecoder.githubRelease.decode(GitHubReleasePayload.self, from: data)
        let version = normalizeVersion(payload.tagName)
        guard !version.isEmpty else {
            throw NSError.user("无法识别最新应用版本")
        }

        return AppRelease(
            version: version,
            tag: payload.tagName,
            name: payload.name ?? payload.tagName,
            body: payload.body ?? "",
            htmlURL: payload.htmlURL,
            publishedAt: payload.publishedAt
        )
    }

    static func isNewer(_ release: AppRelease) -> Bool {
        Runner.compareVersions(TungBoxVersion.release, release.version) == .orderedAscending
    }

    private static func normalizeVersion(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }
}

private extension JSONDecoder {
    static var githubRelease: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
