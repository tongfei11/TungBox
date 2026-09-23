import AppKit
import Foundation

enum TungBoxVersion {
    static let release = "0.3.1"
    static let build = "0224"
    static let current = "\(release)(\(build))"
    static let display = "TungBox v\(current)"
}

enum AppResources {
    static func url(forResource name: String, withExtension ext: String, subdirectory: String? = nil) -> URL? {
        let fileName = "\(name).\(ext)"
        if let resourceURL = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return resourceURL
        }
        // SwiftPM flattens processed resource folders in packaged bundles.
        // Keep the named-folder lookup above for layouts that preserve folders,
        // then check the module bundle root used by the shipped app.
        if subdirectory != nil,
           let resourceURL = Bundle.module.url(forResource: name, withExtension: ext) {
            return resourceURL
        }

        var directories: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            directories.append(resourceURL)
            directories.append(resourceURL.appendingPathComponent("TungBox_TungBox.bundle", isDirectory: true))
        }
        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            directories.append(executableDirectory)
            directories.append(executableDirectory.appendingPathComponent("TungBox_TungBox.bundle", isDirectory: true))
        }
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let buildDirectories = [
            ".build/arm64-apple-macosx/debug",
            ".build/arm64-apple-macosx/release",
            ".build/x86_64-apple-macosx/debug",
            ".build/x86_64-apple-macosx/release"
        ]
        for buildDirectory in buildDirectories {
            directories.append(currentDirectory
                .appendingPathComponent(buildDirectory, isDirectory: true)
                .appendingPathComponent("TungBox_TungBox.bundle", isDirectory: true))
        }

        for directory in directories {
            let candidates = [
                subdirectory.map { directory.appendingPathComponent($0, isDirectory: true).appendingPathComponent(fileName) },
                directory.appendingPathComponent(fileName),
                directory.appendingPathComponent("Tray", isDirectory: true).appendingPathComponent(fileName)
            ].compactMap { $0 }

            for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
