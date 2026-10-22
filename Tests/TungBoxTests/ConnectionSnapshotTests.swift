import Foundation
import XCTest
@testable import TungBox

final class ConnectionSnapshotTests: XCTestCase {
    func testFetchesEachUniquePortOnceAndReturnsConnectionsAndTotals() async throws {
        let stub = ConnectionSnapshotStub(responses: [
            9090: .success(id: "p9090", upload: 120, download: 340),
            9091: .success(id: "c1", upload: 560, download: 780)
        ])
        let session = makeSession(stub)
        defer { session.invalidateAndCancel(); ConnectionSnapshotStubRegistry.shared.remove(stub.id) }

        let snapshot = try await ClashAPI.connectionSnapshot(ports: [9090, 9091, 9091], session: session)

        XCTAssertEqual(stub.requests, [9090, 9091])
        XCTAssertEqual(snapshot.connections.map(\.id), ["p9090", "p9091:c1"])
        XCTAssertEqual(snapshot.totals[9090]?.upload, 120)
        XCTAssertEqual(snapshot.totals[9090]?.download, 340)
        XCTAssertEqual(snapshot.totals[9091]?.upload, 560)
        XCTAssertEqual(snapshot.totals[9091]?.download, 780)
    }

    func testFailedPortDoesNotDiscardSuccessfulPortOrInventTotals() async throws {
        let stub = ConnectionSnapshotStub(responses: [
            9090: .failure,
            9091: .success(id: "c1", upload: 56, download: 78)
        ])
        let session = makeSession(stub)
        defer { session.invalidateAndCancel(); ConnectionSnapshotStubRegistry.shared.remove(stub.id) }

        let snapshot = try await ClashAPI.connectionSnapshot(ports: [9090, 9091], session: session)

        XCTAssertEqual(stub.requests, [9090, 9091])
        XCTAssertEqual(snapshot.connections.map(\.id), ["p9091:c1"])
        XCTAssertNil(snapshot.totals[9090])
        XCTAssertEqual(snapshot.totals[9091]?.upload, 56)
        XCTAssertEqual(snapshot.totals[9091]?.download, 78)
    }

    func testThrowsWhenEveryPortFails() async {
        let stub = ConnectionSnapshotStub(responses: [9090: .failure, 9091: .failure])
        let session = makeSession(stub)
        defer { session.invalidateAndCancel(); ConnectionSnapshotStubRegistry.shared.remove(stub.id) }

        do {
            _ = try await ClashAPI.connectionSnapshot(ports: [9090, 9091], session: session)
            XCTFail("所有端口失败时应抛错")
        } catch {
            XCTAssertEqual(stub.requests, [9090, 9091])
        }
    }

    func testNoActiveConnectionsStillPreservesLifetimeTrafficTotals() async throws {
        let stub = ConnectionSnapshotStub(responses: [9090: .idle])
        let session = makeSession(stub)
        defer { session.invalidateAndCancel(); ConnectionSnapshotStubRegistry.shared.remove(stub.id) }

        let snapshot = try await ClashAPI.connectionSnapshot(ports: [9090], session: session)

        XCTAssertTrue(snapshot.connections.isEmpty)
        XCTAssertEqual(snapshot.totals[9090]?.upload, 900)
        XCTAssertEqual(snapshot.totals[9090]?.download, 1800)
    }

    private func makeSession(_ stub: ConnectionSnapshotStub) -> URLSession {
        ConnectionSnapshotStubRegistry.shared.add(stub)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConnectionSnapshotURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Connection-Snapshot-Test": stub.id.uuidString]
        return URLSession(configuration: configuration)
    }
}

private final class ConnectionSnapshotStub: @unchecked Sendable {
    enum Response {
        case success(id: String, upload: Int, download: Int)
        case idle
        case failure
    }

    let id = UUID()
    private let responses: [Int: Response]
    private let lock = NSLock()
    private var recordedPorts: [Int] = []

    init(responses: [Int: Response]) { self.responses = responses }

    var requests: [Int] { lock.withLock { recordedPorts } }

    func response(for request: URLRequest) -> (Int, Data) {
        let port = request.url?.port ?? -1
        lock.withLock { recordedPorts.append(port) }
        guard request.httpMethod == "GET", request.url?.path == "/connections",
              let response = responses[port] else {
            return (404, Data())
        }
        switch response {
        case .failure:
            return (503, Data("unavailable".utf8))
        case .idle:
            return (200, Data(#"{"uploadTotal":900,"downloadTotal":1800,"connections":null}"#.utf8))
        case let .success(id, upload, download):
            let object: [String: Any] = [
                "uploadTotal": upload,
                "downloadTotal": download,
                "connections": [[
                    "id": id,
                    "metadata": ["network": "tcp", "host": "example.com", "destinationPort": 443, "sourceIP": "127.0.0.1"],
                    "chains": ["proxy"],
                    "rule": "domain",
                    "upload": 12,
                    "download": 34
                ]]
            ]
            return (200, (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
        }
    }
}

private final class ConnectionSnapshotStubRegistry: @unchecked Sendable {
    static let shared = ConnectionSnapshotStubRegistry()
    private let lock = NSLock()
    private var stubs: [UUID: ConnectionSnapshotStub] = [:]

    func add(_ stub: ConnectionSnapshotStub) { lock.withLock { stubs[stub.id] = stub } }
    func remove(_ id: UUID) { _ = lock.withLock { stubs.removeValue(forKey: id) } }
    func get(_ id: UUID) -> ConnectionSnapshotStub? { lock.withLock { stubs[id] } }
}

private final class ConnectionSnapshotURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let value = request.value(forHTTPHeaderField: "X-Connection-Snapshot-Test"),
              let id = UUID(uuidString: value),
              let stub = ConnectionSnapshotStubRegistry.shared.get(id) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = stub.response(for: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
