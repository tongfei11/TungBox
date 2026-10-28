import Foundation
import XCTest
@testable import TungBox

final class RuntimeSelectorAPITests: XCTestCase {
    func testBothPortsConfirmEncodedGroupAndRequestedNodeBeforeCleanup() async throws {
        let stub = SelectorAPIStub()
        let session = makeSession(stub)
        defer { session.invalidateAndCancel(); SelectorAPIRegistry.shared.remove(stub.id) }
        let group = "全局/A ?#%&=+"
        for port in [9090, 9091] {
            try await ClashAPI.selectProxyAndCloseConnections(group: group, node: "NodeB", port: port, session: session)
        }
        XCTAssertEqual(stub.requests.map(\.method), ["PUT", "GET", "DELETE", "PUT", "GET", "DELETE"])
        XCTAssertEqual(stub.requests.map(\.port), [9090, 9090, 9090, 9091, 9091, 9091])
        let encoded = "/proxies/%E5%85%A8%E5%B1%80%2FA%20%3F%23%25%26%3D%2B"
        for request in stub.requests where request.method != "DELETE" {
            XCTAssertEqual(request.path, encoded)
            XCTAssertNil(request.query)
            XCTAssertNil(request.fragment)
        }
        XCTAssertEqual(stub.requests.filter { $0.method == "PUT" }.map(\.node), ["NodeB", "NodeB"])
    }

    func testIgnoredPUTFailsReadbackWithoutClosingConnections() async throws {
        let stub = SelectorAPIStub(ignorePUT: true)
        let session = makeSession(stub)
        defer { session.invalidateAndCancel(); SelectorAPIRegistry.shared.remove(stub.id) }
        do {
            try await ClashAPI.selectProxyAndCloseConnections(group: "全局", node: "NodeB", port: 9091, session: session)
            XCTFail("An accepted but ignored PUT must fail confirmation")
        } catch { XCTAssertTrue(error.localizedDescription.contains("未应用")) }
        XCTAssertEqual(stub.requests.map(\.method), ["PUT", "GET"])
    }

    func testRejectedPUTDoesNotReadBackOrCloseConnections() async throws {
        let stub = SelectorAPIStub(rejectPUT: true)
        let session = makeSession(stub)
        defer { session.invalidateAndCancel(); SelectorAPIRegistry.shared.remove(stub.id) }
        do {
            try await ClashAPI.selectProxyAndCloseConnections(group: "节点选择", node: "NodeB", port: 9090, session: session)
            XCTFail("A rejected PUT must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("rejected")) }
        XCTAssertEqual(stub.requests.map(\.method), ["PUT"])
    }

    func testCleanupFailureKeepsConfirmedSelectionSuccessful() async throws {
        let stub = SelectorAPIStub(rejectCleanup: true)
        let session = makeSession(stub)
        defer { session.invalidateAndCancel(); SelectorAPIRegistry.shared.remove(stub.id) }
        try await ClashAPI.selectProxyAndCloseConnections(group: "节点选择", node: "NodeB", port: 9090, session: session)
        XCTAssertEqual(stub.requests.map(\.method), ["PUT", "GET", "DELETE"])
    }

    private func makeSession(_ stub: SelectorAPIStub) -> URLSession {
        SelectorAPIRegistry.shared.add(stub)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SelectorAPIURLProtocol.self]
        config.httpAdditionalHeaders = ["X-TungBox-Selector-Test": stub.id.uuidString]
        return URLSession(configuration: config)
    }
}

private final class SelectorAPIStub: @unchecked Sendable {
    struct Request {
        let method: String
        let path: String
        let port: Int
        let query: String?
        let fragment: String?
        let node: String?
    }
    let id = UUID()
    private let lock = NSLock()
    private var recorded: [Request] = []
    private var selectedByPort: [Int: String] = [:]
    private let rejectPUT: Bool
    private let ignorePUT: Bool
    private let rejectCleanup: Bool

    init(rejectPUT: Bool = false, ignorePUT: Bool = false, rejectCleanup: Bool = false) {
        self.rejectPUT = rejectPUT
        self.ignorePUT = ignorePUT
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
        let node = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["name"] as? String
        return lock.withLock {
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let port = request.url!.port!
            recorded.append(Request(method: request.httpMethod ?? "GET", path: components.percentEncodedPath,
                port: port, query: components.query, fragment: components.fragment, node: node))
            switch request.httpMethod {
            case "PUT":
                if rejectPUT { return (400, Data("rejected".utf8)) }
                if !ignorePUT, let node { selectedByPort[port] = node }
                return (204, Data())
            case "DELETE": return (rejectCleanup ? 503 : 204, Data())
            default: return (200, try! JSONSerialization.data(withJSONObject: ["now": selectedByPort[port] ?? "自动选择"]))
            }
        }
    }
}

private final class SelectorAPIRegistry: @unchecked Sendable {
    static let shared = SelectorAPIRegistry()
    private let lock = NSLock()
    private var stubs: [UUID: SelectorAPIStub] = [:]
    func add(_ stub: SelectorAPIStub) { lock.withLock { stubs[stub.id] = stub } }
    func remove(_ id: UUID) { _ = lock.withLock { stubs.removeValue(forKey: id) } }
    func get(_ id: UUID) -> SelectorAPIStub? { lock.withLock { stubs[id] } }
}

private final class SelectorAPIURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let header = request.value(forHTTPHeaderField: "X-TungBox-Selector-Test"), let id = UUID(uuidString: header),
              let stub = SelectorAPIRegistry.shared.get(id) else {
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
