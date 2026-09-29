import Foundation
import XCTest
@testable import TungBox

final class CoreUpdateSecurityTests: XCTestCase {
    func testArchiveMustMatchEmbeddedTrustedDigestBeforeExtraction() throws {
        XCTAssertEqual(
            CoreUpdater.trustedSHA256(version: "1.14.0", architecture: "arm64"),
            "a150c94012ff768b7261939cd236b9c8554127f45137230295d23a5660225cc9"
        )
        XCTAssertNil(CoreUpdater.trustedSHA256(version: "1.14.2", architecture: "arm64"))
        XCTAssertNil(CoreUpdater.trustedSHA256(version: "1.12.22", architecture: "arm64"))
        XCTAssertNil(CoreUpdater.trustedSHA256(version: "1.14.1", architecture: "arm64"))

        let data = Data("trusted archive".utf8)
        let digest = CoreArtifactTrust.sha256Hex(data)
        XCTAssertNoThrow(try CoreUpdater.verifyArchiveIntegrity(data, expectedSHA256: digest))
        XCTAssertThrowsError(try CoreUpdater.verifyArchiveIntegrity(data + Data([0]), expectedSHA256: digest))
    }

    func testTrustBindsVersionTagArchitectureAssetNameAndOfficialURL() throws {
        let trusted = CoreRelease(
            version: "1.14.0",
            tag: "v1.14.0",
            assetName: "sing-box-1.14.0-darwin-arm64.tar.gz",
            downloadURL: URL(string: "https://github.com/SagerNet/sing-box/releases/download/v1.14.0/sing-box-1.14.0-darwin-arm64.tar.gz")!
        )
        XCTAssertNoThrow(try CoreUpdater.validateTrustedRelease(trusted, architecture: "arm64"))

        let wrongTag = CoreRelease(version: trusted.version, tag: "v1.12.22", assetName: trusted.assetName, downloadURL: trusted.downloadURL)
        XCTAssertThrowsError(try CoreUpdater.validateTrustedRelease(wrongTag, architecture: "arm64"))

        let renamed = CoreRelease(version: trusted.version, tag: trusted.tag, assetName: "payload.tar.gz", downloadURL: trusted.downloadURL)
        XCTAssertThrowsError(try CoreUpdater.validateTrustedRelease(renamed, architecture: "arm64"))

        let redirected = CoreRelease(
            version: trusted.version,
            tag: trusted.tag,
            assetName: trusted.assetName,
            downloadURL: URL(string: "https://example.com/\(trusted.assetName)")!
        )
        XCTAssertThrowsError(try CoreUpdater.validateTrustedRelease(redirected, architecture: "arm64"))
        XCTAssertThrowsError(try CoreUpdater.validateTrustedRelease(trusted, architecture: "amd64"))
    }

    func testUnlistedCompatiblePatchPassesIdentityPolicy() async throws {
        let release = try await CoreUpdater.release(version: "1.14.1")
        XCTAssertEqual(release.version, "1.14.1")
        XCTAssertNoThrow(try CoreUpdater.validateReleaseIdentity(release, architecture: platformArchitecture))
    }

    func testCurrent114PatchIsInstallableBut115RemainsBlocked() async throws {
        let release = try await CoreUpdater.release(version: "1.14.2")
        XCTAssertNoThrow(try CoreUpdater.validateReleaseIdentity(release, architecture: platformArchitecture))

        do {
            _ = try await CoreUpdater.release(version: "1.15.0")
            XCTFail("1.15.x 不应进入当前兼容范围")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("暂未确认兼容"))
        }
    }

    func testOfficialReleaseDigestParserRequiresExactAssetAndSHA256() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "assets": [[
                "name": "sing-box-1.13.9-darwin-arm64.tar.gz",
                "digest": "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
            ]]
        ])
        XCTAssertEqual(
            try CoreUpdater.officialAssetSHA256(from: data, assetName: "sing-box-1.13.9-darwin-arm64.tar.gz"),
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        )
        XCTAssertThrowsError(try CoreUpdater.officialAssetSHA256(from: data, assetName: "other.tar.gz"))
    }

    func testArchivePathsCannotEscapeExtractionDirectory() throws {
        XCTAssertNoThrow(try CoreUpdater.validateArchiveEntryPaths(["sing-box-1.14.0/", "sing-box-1.14.0/sing-box"]))
        XCTAssertThrowsError(try CoreUpdater.validateArchiveEntryPaths(["../../Library/LaunchDaemons/payload"]))
        XCTAssertThrowsError(try CoreUpdater.validateArchiveEntryPaths(["/tmp/payload"]))
    }

    private var platformArchitecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "amd64"
        #endif
    }
}
