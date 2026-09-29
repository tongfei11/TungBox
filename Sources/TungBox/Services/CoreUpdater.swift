import Foundation

enum CoreUpdater {
    static let stableLatestURL = URL(string: "https://github.com/SagerNet/sing-box/releases/latest")!
    static let releaseBaseURL = URL(string: "https://github.com/SagerNet/sing-box/releases/download")!
    static let testOldVersion = "1.12.22"
    private static let trustedArchiveSHA256: [String: String] = [
        "1.14.0/darwin-arm64": "a150c94012ff768b7261939cd236b9c8554127f45137230295d23a5660225cc9",
        "1.14.0/darwin-amd64": "6cf26fc3501f3117cf781e9405cf5338f60add6da5affae39421af6800ebbcb4",
        "1.12.22/darwin-arm64": "974d924c36af92a9aecab5e630555764aa665fb8210e58a48c01faec5d55de0f",
        "1.12.22/darwin-amd64": "950072cf2f1e0d4aa216116e0b1f9f7542aa953c1487b55516ea9d04bd73bbc6"
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
        guard isCompatibleCoreVersion(rawVersion) else {
            throw NSError.user("TungBox 当前仅验证支持 sing-box Core 1.12.x、1.13.x 和 1.14.x。\(rawVersion)（\(arch)）暂未确认兼容，请等待 TungBox 官方确认支持后再安装。")
        }
        let assetName = "sing-box-\(rawVersion)-darwin-\(arch).tar.gz"
        let downloadURL = releaseBaseURL
            .appendingPathComponent(tag)
            .appendingPathComponent(assetName)

        return CoreRelease(
            version: rawVersion,
            tag: tag,
            assetName: assetName,
            downloadURL: downloadURL
        )
    }

    static func install(_ release: CoreRelease, to coreBinaryURL: URL) async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TungBoxCore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let expectedSHA256 = try validateTrustedRelease(release, architecture: platformAssetArch())
        let archiveURL = tempDirectory.appendingPathComponent(release.assetName)
        let data = try await fetchData(from: release.downloadURL)
        try verifyArchiveIntegrity(data, expectedSHA256: expectedSHA256)
        try data.write(to: archiveURL, options: .atomic)
        try validateArchiveEntryPaths(try archiveEntries(at: archiveURL))

        let extractDirectory = tempDirectory.appendingPathComponent("extract", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        try run("/usr/bin/tar", args: ["-xzf", archiveURL.path, "-C", extractDirectory.path])

        guard let binaryURL = findExtractedBinary(in: extractDirectory) else {
            throw NSError.user("下载包中没有找到 sing-box 可执行文件")
        }
        try verifyExtractedBinary(at: binaryURL, expectedVersion: release.version)

        try activatePreparedBinary(at: binaryURL, to: coreBinaryURL)
    }

    static func activatePreparedBinary(at preparedURL: URL, to coreBinaryURL: URL) throws {
        let coreDirectory = coreBinaryURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: coreDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preparedURL.path)
        if FileManager.default.fileExists(atPath: coreBinaryURL.path) {
            _ = try FileManager.default.replaceItemAt(
                coreBinaryURL,
                withItemAt: preparedURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try FileManager.default.moveItem(at: preparedURL, to: coreBinaryURL)
        }
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

    static func trustedSHA256(version: String, architecture: String) -> String? {
        trustedArchiveSHA256["\(version)/darwin-\(architecture)"]
    }

    static func validateTrustedRelease(_ release: CoreRelease, architecture: String) throws -> String {
        let expectedAssetName = "sing-box-\(release.version)-darwin-\(architecture).tar.gz"
        let expectedURL = releaseBaseURL
            .appendingPathComponent("v\(release.version)")
            .appendingPathComponent(expectedAssetName)
        guard release.tag == "v\(release.version)",
              release.assetName == expectedAssetName,
              release.downloadURL == expectedURL,
              let digest = trustedSHA256(version: release.version, architecture: architecture) else {
            throw NSError.user("Core 下载信息未匹配可信版本、架构、文件名和地址，已拒绝安装")
        }
        return digest
    }

    static func verifyArchiveIntegrity(_ data: Data, expectedSHA256: String) throws {
        let actual = CoreArtifactTrust.sha256Hex(data)
        guard actual.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            throw NSError.user("Core 下载包 SHA-256 校验失败，已拒绝解压和执行")
        }
    }

    static func validateArchiveEntryPaths(_ entries: [String]) throws {
        for entry in entries where !entry.isEmpty {
            let path = entry.hasSuffix("/") ? String(entry.dropLast()) : entry
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.hasPrefix("/"), !components.contains("..") else {
                throw NSError.user("Core 下载包包含越界路径，已拒绝解压")
            }
        }
    }

    private static func archiveEntries(at archiveURL: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tzf", archiveURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: data, encoding: .utf8) ?? ""
            throw NSError.user(output.isEmpty ? "无法读取 Core 下载包目录" : output)
        }
        return (String(data: data, encoding: .utf8) ?? "").components(separatedBy: .newlines)
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

    private static func isCompatibleCoreVersion(_ version: String) -> Bool {
        let coreVersion = version.split(separator: "-", maxSplits: 1).first ?? Substring(version)
        let components = coreVersion.split(separator: ".")
        guard components.count >= 3,
              components[0] == "1",
              let minor = Int(components[1]),
              Int(components[2]) != nil else {
            return false
        }
        return minor == 12 || minor == 13 || minor == 14
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
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let rootPath = directory.standardizedFileURL.path + "/"
        for case let url as URL in enumerator where url.lastPathComponent == "sing-box" {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  url.standardizedFileURL.path.hasPrefix(rootPath) else { continue }
            return url
        }
        return nil
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
