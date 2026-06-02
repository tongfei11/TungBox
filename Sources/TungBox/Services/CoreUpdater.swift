import Foundation

enum CoreUpdater {
    static let stableLatestURL = URL(string: "https://github.com/SagerNet/sing-box/releases/latest")!
    static let releaseBaseURL = URL(string: "https://github.com/SagerNet/sing-box/releases/download")!
    static let testOldVersion = "1.12.22"

    static func latestStableRelease() async throws -> CoreRelease {
        let tag = try await latestStableTag()
        return try await release(version: tag)
    }

    static func release(version: String) async throws -> CoreRelease {
        let rawVersion = version.hasPrefix("v") ? String(version.dropFirst()) : version
        guard !rawVersion.isEmpty else {
            throw NSError.user("sing-box 版本号无效")
        }

        let tag = "v\(rawVersion)"
        let arch = platformAssetArch()
        let assetName = "sing-box-\(rawVersion)-darwin-\(arch).tar.gz"
        let downloadURL = releaseBaseURL
            .appendingPathComponent(tag)
            .appendingPathComponent(assetName)

        return CoreRelease(version: rawVersion, tag: tag, assetName: assetName, downloadURL: downloadURL)
    }

    static func install(_ release: CoreRelease, to coreBinaryURL: URL) async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TungBoxCore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let archiveURL = tempDirectory.appendingPathComponent(release.assetName)
        let data = try await fetchData(from: release.downloadURL)
        try data.write(to: archiveURL, options: .atomic)

        let extractDirectory = tempDirectory.appendingPathComponent("extract", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        try run("/usr/bin/tar", args: ["-xzf", archiveURL.path, "-C", extractDirectory.path])

        guard let binaryURL = findExtractedBinary(in: extractDirectory) else {
            throw NSError.user("下载包中没有找到 sing-box 可执行文件")
        }

        let coreDirectory = coreBinaryURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: coreDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: coreBinaryURL.path) {
            try FileManager.default.removeItem(at: coreBinaryURL)
        }
        try FileManager.default.copyItem(at: binaryURL, to: coreBinaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: coreBinaryURL.path)
    }

    private static func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.setValue("TungBox/\(TungBoxVersion.current)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream,*/*", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let hint: String
            switch http.statusCode {
            case 404: hint = "版本不存在，请确认版本号正确"
            case 403: hint = "访问被 GitHub 拒绝，可能触发了频率限制"
            case 500...599: hint = "GitHub 服务器错误，请稍后重试"
            default: hint = "请检查网络连接后重试"
            }
            throw NSError.user("下载失败 (HTTP \(http.statusCode))：\(hint)")
        }
        return data
    }

    private static func latestStableTag() async throws -> String {
        var request = URLRequest(url: stableLatestURL, timeoutInterval: 15)
        request.httpMethod = "HEAD"
        request.setValue("TungBox/\(TungBoxVersion.current)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)

        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw NSError.user("检查更新失败：HTTP \(http.statusCode)")
        }

        guard let resolvedURL = response.url,
              let tag = releaseTag(from: resolvedURL) else {
            throw NSError.user("无法识别 sing-box 最新版本")
        }
        return tag
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

    private static func platformAssetArch() -> String {
        #if arch(arm64)
        return "arm64"
        #else
        return "amd64"
        #endif
    }

    private static func run(_ binary: String, args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            throw NSError.user(output.isEmpty ? "执行 \(binary) 失败" : output)
        }
    }

    private static func findExtractedBinary(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator where url.lastPathComponent == "sing-box" {
            return url
        }
        return nil
    }
}
