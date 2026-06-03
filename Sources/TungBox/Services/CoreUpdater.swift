import CryptoKit
import Foundation

enum CoreUpdater {
    static let stableLatestURL = URL(string: "https://github.com/SagerNet/sing-box/releases/latest")!
    static let releaseBaseURL = URL(string: "https://github.com/SagerNet/sing-box/releases/download")!
    static let testOldVersion = "1.12.22"
    static let pinnedLatestVersion = "1.13.12"

    private static let trustedSHA256: [String: [String: String]] = [
        "1.13.12": [
            "arm64": "43eef86f0ea4a79c3696974f397a963c46a457ee46d1ffac9aa913944a5fc986",
            "amd64": "f3275316451bf1983bc059599c69c8ed0232d53a619d15cfd535f95cc9a4477a"
        ],
        "1.12.22": [
            "arm64": "974d924c36af92a9aecab5e630555764aa665fb8210e58a48c01faec5d55de0f",
            "amd64": "950072cf2f1e0d4aa216116e0b1f9f7542aa953c1487b55516ea9d04bd73bbc6"
        ],
        "1.11.10": [
            "arm64": "577ab24957f3530458042c8087e6817c276b4b03bee55c72fcb0ce3226652a43",
            "amd64": "ddecca3aa83bfc831e6de120e44fe26924e2eed978538e8c216dabdc838e733d"
        ]
    ]

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
        guard let expectedSHA256 = trustedSHA256[rawVersion]?[arch] else {
            throw NSError.user("暂不支持安装未校验的 sing-box Core \(rawVersion)（\(arch)）。请等待 TungBox 更新可信摘要后再安装。")
        }
        let assetName = "sing-box-\(rawVersion)-darwin-\(arch).tar.gz"
        let downloadURL = releaseBaseURL
            .appendingPathComponent(tag)
            .appendingPathComponent(assetName)

        return CoreRelease(
            version: rawVersion,
            tag: tag,
            assetName: assetName,
            downloadURL: downloadURL,
            sha256: expectedSHA256
        )
    }

    static func install(_ release: CoreRelease, to coreBinaryURL: URL) async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TungBoxCore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let archiveURL = tempDirectory.appendingPathComponent(release.assetName)
        let data = try await fetchData(from: release.downloadURL)
        try verifySHA256(data: data, expected: release.sha256, version: release.version)
        try data.write(to: archiveURL, options: .atomic)

        let extractDirectory = tempDirectory.appendingPathComponent("extract", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        try run("/usr/bin/tar", args: ["-xzf", archiveURL.path, "-C", extractDirectory.path])

        guard let binaryURL = findExtractedBinary(in: extractDirectory) else {
            throw NSError.user("下载包中没有找到 sing-box 可执行文件")
        }
        try verifyExtractedBinary(at: binaryURL, expectedVersion: release.version)

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

    private static func verifySHA256(data: Data, expected: String, version: String) throws {
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest.lowercased() == expected.lowercased() else {
            throw NSError.user("sing-box Core \(version) 下载校验失败：SHA256 不匹配。")
        }
    }

    private static func verifyExtractedBinary(at url: URL, expectedVersion: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)

        let process = Process()
        process.executableURL = url
        process.arguments = ["version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0,
              output.contains("sing-box version \(expectedVersion)") || output.contains("version \(expectedVersion)") else {
            throw NSError.user("sing-box Core 版本校验失败：期望 \(expectedVersion)，实际输出 \(output.prefix(160))")
        }
    }
}
