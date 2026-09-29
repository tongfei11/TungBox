import Foundation
import XCTest
@testable import TungBox

private final class LocalAPIAuthURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let status = authorization == nil ? 401 : (authorization == "Bearer test-secret" ? 200 : 401)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LocalAPIAuthenticationTests: XCTestCase {
    func testSecretsAreDistinctStableAndOwnerOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let userURL = root.appendingPathComponent("user-api-secret")
        let tunURL = root.appendingPathComponent("tun-api-secret")
        let userSecret = try LocalAPISecret.loadOrCreate(at: userURL)
        let tunSecret = try LocalAPISecret.loadOrCreate(at: tunURL)
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        let filePermissions = try FileManager.default.attributesOfItem(atPath: userURL.path)[.posixPermissions] as? NSNumber

        XCTAssertEqual(userSecret.count, 64)
        XCTAssertNotEqual(userSecret, tunSecret)
        XCTAssertEqual(try LocalAPISecret.loadOrCreate(at: userURL), userSecret)
        XCTAssertEqual(directoryPermissions?.intValue, 0o700)
        XCTAssertEqual(filePermissions?.intValue, 0o600)
        XCTAssertEqual(LocalAPISecret.secret(forPort: 9090, userSecret: userSecret, tunSecret: tunSecret), userSecret)
        XCTAssertEqual(LocalAPISecret.secret(forPort: TungBoxConfig.tunDaemonClashPort, userSecret: userSecret, tunSecret: tunSecret), tunSecret)
    }

    func testSecretLoaderRejectsSymbolicLink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("target")
        let link = root.appendingPathComponent("secret")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("0".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(try LocalAPISecret.loadOrCreate(at: link))
    }

    func testPersistentConfigOmitsSecretAndRuntimeConfigInjectsIt() throws {
        let secret = String(repeating: "a", count: 64)
        let source: [String: Any] = [
            "experimental": [
                "clash_api": [
                    "external_controller": "127.0.0.1:9090",
                    "default_mode": "Rule",
                    "secret": "must-not-persist"
                ]
            ]
        ]

        let persistent = LocalAPIConfiguration.removingSecret(from: source)
        let persistentData = try JSONSerialization.data(withJSONObject: persistent)
        XCTAssertFalse(String(decoding: persistentData, as: UTF8.self).contains("secret"))

        let runtime = LocalAPIConfiguration.authenticated(
            persistent,
            listen: "127.0.0.1:9090",
            secret: secret
        )
        let clashAPI = (runtime["experimental"] as? [String: Any])?["clash_api"] as? [String: Any]
        XCTAssertEqual(clashAPI?["secret"] as? String, secret)
    }

    func testEveryClashAPIMethodUsesBearerAuthorization() throws {
        for method in ["GET", "PUT", "DELETE"] {
            let request = try ClashAPI.makeRequest(
                path: "/connections",
                method: method,
                port: 9090,
                secret: "test-secret"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-secret")
        }
    }

    func testAuthenticationProbeRejectsMissingAndWrongTokensButAcceptsCorrectToken() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LocalAPIAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)

        try await ClashAPI.verifyAuthentication(port: 9090, secret: "test-secret", session: session)

        let wrong = try ClashAPI.makeRequest(path: "/proxies", port: 9090, secret: "wrong-secret")
        let (_, response) = try await session.data(for: wrong)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401)
    }

    func testTunRequestConfigRemainsOwnerOnlyAfterRewrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(baseURL: root)
        try Data("old".utf8).write(to: store.tunRequestConfigURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.tunRequestConfigURL.path)

        try TunServiceManager.writeRequestConfig("new", store: store)

        let permissions = try FileManager.default.attributesOfItem(atPath: store.tunRequestConfigURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertEqual(try String(contentsOf: store.tunRequestConfigURL, encoding: .utf8), "new")
    }

    func testStoreRemovesStaleRuntimeConfigs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = Store(baseURL: root)
        let legacy = root.appendingPathComponent("run_profile.json")
        let current = root.appendingPathComponent("run-1234.json")
        let userFile = root.appendingPathComponent("profile.json")
        try Data().write(to: legacy)
        try Data().write(to: current)
        try Data().write(to: userFile)

        _ = Store(baseURL: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: userFile.path))
    }
}
