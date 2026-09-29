import CryptoKit
import Foundation
import XCTest
@testable import TungBox

final class TunInstallSecurityTests: XCTestCase {
    func testVerifiedCopyPreservesDigestBoundContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original = Data("trusted".utf8)
        try original.write(to: source)
        let digest = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", TunServiceManager.verifiedCopyCommand(
            sourcePath: source.path,
            destinationPath: destination.path,
            expectedSHA256: digest
        )]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(try Data(contentsOf: destination), original)
    }

    func testVerifiedCopyRejectsSourceChangedAfterDigestWasBound() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original = Data("original".utf8)
        try original.write(to: source)
        let digest = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        try Data("replaced".utf8).write(to: source)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", TunServiceManager.verifiedCopyCommand(
            sourcePath: source.path,
            destinationPath: destination.path,
            expectedSHA256: digest
        )]
        try process.run()
        process.waitUntilExit()

        XCTAssertNotEqual(process.terminationStatus, 0)
    }

    func testPrivilegedStagingCleanupHandlesSpacesAndRunsOnFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TungBox staging \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", TunServiceManager.privilegedStagingPrelude(path: root.path) + "\nfalse"]
        try process.run()
        process.waitUntilExit()

        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
