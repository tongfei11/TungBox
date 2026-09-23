import Foundation

enum RuleSetRuntime {
    enum CachePreparationAction: Equatable, Sendable {
        case decompileLocal
        case download
        case waitForConnection
    }

    struct LocalizationResult {
        var config: [String: Any]
        var remoteSources: [String: URL]
        var didChange: Bool
    }

    static let builtInTags: Set<String> = [
        "geosite-private",
        "geosite-cn",
        "geoip-cn",
        "geosite-geolocation-!cn"
    ]

    static func safeFileName(for tag: String) -> String {
        tag.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        }.map(String.init).joined()
    }

    static func installedURL(for tag: String, in directory: URL) -> URL {
        directory.appendingPathComponent(safeFileName(for: tag)).appendingPathExtension("srs")
    }

    static func installBundledRuleSets(from bundledDirectory: URL, to installedDirectory: URL) throws {
        try FileManager.default.createDirectory(at: installedDirectory, withIntermediateDirectories: true)
        for tag in builtInTags {
            let fileName = safeFileName(for: tag) + ".srs"
            let source = bundledDirectory.appendingPathComponent(fileName)
            let destination = installedDirectory.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: source.path),
                  !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    static func needsRefresh(tag: String, fileURL: URL, now: Date = Date()) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date else { return true }
        let interval: TimeInterval = tag == "geosite-private" ? 7 * 86_400 : 86_400
        return now.timeIntervalSince(modifiedAt) >= interval
    }

    static func cachePreparationAction(hasLocalSRS: Bool, hasConnected: Bool) -> CachePreparationAction {
        if hasLocalSRS { return .decompileLocal }
        return hasConnected ? .download : .waitForConnection
    }

    static func localizeBuiltInRuleSets(in config: [String: Any], ruleSetDirectory: URL) -> LocalizationResult {
        guard var route = config["route"] as? [String: Any],
              var ruleSets = route["rule_set"] as? [[String: Any]] else {
            return LocalizationResult(config: config, remoteSources: [:], didChange: false)
        }

        var remoteSources: [String: URL] = [:]
        var didChange = false
        for index in ruleSets.indices {
            guard let tag = ruleSets[index]["tag"] as? String,
                  builtInTags.contains(tag),
                  (ruleSets[index]["type"] as? String) == "remote",
                  let urlText = ruleSets[index]["url"] as? String,
                  let remoteURL = URL(string: urlText) else { continue }
            let localURL = installedURL(for: tag, in: ruleSetDirectory)
            guard FileManager.default.fileExists(atPath: localURL.path) else { continue }

            remoteSources[tag] = remoteURL
            ruleSets[index]["type"] = "local"
            ruleSets[index]["path"] = localURL.path
            ruleSets[index].removeValue(forKey: "url")
            ruleSets[index].removeValue(forKey: "download_detour")
            ruleSets[index].removeValue(forKey: "update_interval")
            didChange = true
        }

        guard didChange else {
            return LocalizationResult(config: config, remoteSources: remoteSources, didChange: false)
        }
        route["rule_set"] = ruleSets
        var localizedConfig = config
        localizedConfig["route"] = route
        return LocalizationResult(config: localizedConfig, remoteSources: remoteSources, didChange: true)
    }
}

enum RuleSearch {
    static func matches(
        type: String,
        value: String,
        strategy: String,
        note: String,
        isSection: Bool,
        query: String
    ) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        return isSection
            || type.lowercased().contains(normalized)
            || value.lowercased().contains(normalized)
            || strategy.lowercased().contains(normalized)
            || note.lowercased().contains(normalized)
    }
}
