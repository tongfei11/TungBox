import Foundation
import XCTest
@testable import TungBox

final class RuntimeModeAPITests: XCTestCase {
    func testHotModeSwitchUpdatesBothCoresWithoutDelayRequests() async throws {
        let stub = ModeAPIStub()
        let session = makeSession(stub)
        defer { session.invalidateAndCancel(); ModeAPIStubRegistry.shared.remove(stub.id) }
        for port in [9090, 9091] {
            try await ClashAPI.setModeAndCloseConnections("Global", port: port, session: session)
        }
        let requests = stub.requests
        XCTAssertEqual(requests.map(\.method), ["PATCH", "GET", "DELETE", "PATCH", "GET", "DELETE"])
        XCTAssertEqual(requests.map(\.path), ["/configs", "/configs", "/connections", "/configs", "/configs", "/connections"])
        XCTAssertEqual(requests.map(\.port), [9090, 9090, 9090, 9091, 9091, 9091])
        XCTAssertEqual(requests.filter { $0.method == "PATCH" }.map(\.mode), ["Global", "Global"])
        XCTAssertTrue(requests.allSatisfy(\.authenticated))
    }

    func testRejectedModePatchDoesNotCloseConnections() async {
        let stub = ModeAPIStub(rejectPatch: true)
        let session = makeSession(stub)
        defer { session.invalidateAndCancel(); ModeAPIStubRegistry.shared.remove(stub.id) }
        do {
            try await ClashAPI.setModeAndCloseConnections("Global", port: 9090, session: session)
            XCTFail("拒绝模式请求时应报错")
        } catch {}
        XCTAssertEqual(stub.requests.map(\.method), ["PATCH"])
    }

    func testReadbackDetectsSilentlyIgnoredModeChange() async {
        let stub = ModeAPIStub(ignorePatch: true)
        let session = makeSession(stub)
        defer { session.invalidateAndCancel(); ModeAPIStubRegistry.shared.remove(stub.id) }
        do {
            try await ClashAPI.setModeAndCloseConnections("Global", port: 9091, session: session)
            XCTFail("Core 未应用模式时不能显示成功")
        } catch {}
        XCTAssertEqual(stub.requests.map(\.method), ["PATCH", "GET"])
    }

    func testConnectionCleanupFailureKeepsSuccessfullyAppliedMode() async throws {
        let stub = ModeAPIStub(rejectCleanup: true)
        let session = makeSession(stub)
        defer { session.invalidateAndCancel(); ModeAPIStubRegistry.shared.remove(stub.id) }
        try await ClashAPI.setModeAndCloseConnections("Direct", port: 9090, session: session)
        XCTAssertEqual(stub.requests.map(\.method), ["PATCH", "GET", "DELETE"])
    }

    private func makeSession(_ stub: ModeAPIStub) -> URLSession {
        ModeAPIStubRegistry.shared.add(stub)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ModeAPIURLProtocol.self]
        config.httpAdditionalHeaders = ["X-TungBox-Test": stub.id.uuidString]
        return URLSession(configuration: config)
    }
}

private final class ModeAPIStub: @unchecked Sendable {
    struct Request {
        let method: String
        let path: String
        let port: Int
        let mode: String?
        let authenticated: Bool
    }
    let id = UUID()
    private let lock = NSLock()
    private var recorded: [Request] = []
    private var currentMode = "Rule"
    private let rejectPatch: Bool
    private let ignorePatch: Bool
    private let rejectCleanup: Bool

    init(rejectPatch: Bool = false, ignorePatch: Bool = false, rejectCleanup: Bool = false) {
        self.rejectPatch = rejectPatch
        self.ignorePatch = ignorePatch
        self.rejectCleanup = rejectCleanup
    }

    var requests: [Request] { lock.withLock { recorded } }

    func response(for request: URLRequest) -> (Int, Data) {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        }
        let mode = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["mode"] as? String
        return lock.withLock {
            recorded.append(Request(method: request.httpMethod ?? "GET", path: request.url!.path,
                                    port: request.url!.port!, mode: mode,
                                    authenticated: request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true))
            switch request.httpMethod {
            case "PATCH":
                if rejectPatch { return (401, Data("rejected".utf8)) }
                if !ignorePatch, let mode { currentMode = mode }
                return (204, Data())
            case "DELETE": return (rejectCleanup ? 503 : 204, Data())
            default: return (200, try! JSONSerialization.data(withJSONObject: ["mode": currentMode]))
            }
        }
    }
}

private final class ModeAPIStubRegistry: @unchecked Sendable {
    static let shared = ModeAPIStubRegistry()
    private let lock = NSLock()
    private var stubs: [UUID: ModeAPIStub] = [:]
    func add(_ stub: ModeAPIStub) { lock.withLock { stubs[stub.id] = stub } }
    func remove(_ id: UUID) { _ = lock.withLock { stubs.removeValue(forKey: id) } }
    func get(_ id: UUID) -> ModeAPIStub? { lock.withLock { stubs[id] } }
}

private final class ModeAPIURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let header = request.value(forHTTPHeaderField: "X-TungBox-Test"), let id = UUID(uuidString: header),
              let stub = ModeAPIStubRegistry.shared.get(id) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = stub.response(for: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
