import Foundation
import XCTest
@testable import TungBox

final class ExternalIPServiceTests: XCTestCase {
    func testSuccessfulResultIsCachedUntilForcedRefresh() async {
        let fetcher = IPFetchStub()
        let service = ExternalIPService(fetch: { await fetcher.fetch() })
        let first = Task { await service.getExternalIP() }
        await fetcher.waitForRequest(1)
        await fetcher.complete(1, with: "192.0.2.1")
        let firstIP = await first.value
        let cachedIP = await service.getExternalIP()
        XCTAssertEqual(firstIP, "192.0.2.1")
        XCTAssertEqual(cachedIP, "192.0.2.1")
        let count = await fetcher.count
        XCTAssertEqual(count, 1)

        let forced = Task { await service.getExternalIP(force: true) }
        await fetcher.waitForRequest(2)
        await fetcher.complete(2, with: "192.0.2.2")
        let forcedIP = await forced.value
        XCTAssertEqual(forcedIP, "192.0.2.2")
    }

    func testLateOldRouteCannotOverwriteLatestRouteOrClearItsRequest() async {
        let fetcher = IPFetchStub()
        let service = ExternalIPService(fetch: { await fetcher.fetch() })
        let old = Task { await service.getExternalIP(force: true) }
        await fetcher.waitForRequest(1)
        let latest = Task { await service.getExternalIP(force: true) }
        await fetcher.waitForRequest(2)
        await fetcher.complete(2, with: "192.0.2.2")
        let latestIP = await latest.value
        // Deliberately simulate a transport that delivers after cancellation.
        await fetcher.complete(1, with: "192.0.2.1")
        let oldIP = await old.value
        let cachedIP = await service.getExternalIP()
        XCTAssertEqual(latestIP, "192.0.2.2")
        XCTAssertNil(oldIP)
        XCTAssertEqual(cachedIP, "192.0.2.2")
    }

    func testCancelledCallerDoesNotCacheLateResponse() async {
        let fetcher = IPFetchStub()
        let service = ExternalIPService(fetch: { await fetcher.fetch() })
        let request = Task { await service.getExternalIP() }
        await fetcher.waitForRequest(1)
        request.cancel()
        await fetcher.complete(1, with: "192.0.2.1")
        let result = await request.value
        let cachedIP = await service.cachedIP
        XCTAssertNil(result)
        XCTAssertNil(cachedIP)

        let next = Task { await service.getExternalIP() }
        await fetcher.waitForRequest(2)
        await fetcher.complete(2, with: "192.0.2.2")
        let nextIP = await next.value
        XCTAssertEqual(nextIP, "192.0.2.2")
    }

    func testFailureCooldownSuppressesAutomaticRetriesButNotManualRefresh() async {
        let clock = IPTestClock()
        let fetcher = IPFetchStub()
        let service = ExternalIPService(fetch: { await fetcher.fetch() }, now: { clock.now })
        let first = Task { await service.getExternalIP() }
        await fetcher.waitForRequest(1)
        await fetcher.complete(1, with: nil)
        let firstIP = await first.value
        XCTAssertNil(firstIP)

        clock.advance(10)
        let cooledDownIP = await service.getExternalIP()
        let count = await fetcher.count
        XCTAssertNil(cooledDownIP)
        XCTAssertEqual(count, 1)

        let forced = Task { await service.getExternalIP(force: true) }
        await fetcher.waitForRequest(2)
        await fetcher.complete(2, with: nil)
        _ = await forced.value
        clock.advance(31)
        let retry = Task { await service.getExternalIP() }
        await fetcher.waitForRequest(3)
        await fetcher.complete(3, with: "192.0.2.3")
        let retryIP = await retry.value
        XCTAssertEqual(retryIP, "192.0.2.3")
    }
}

private actor IPFetchStub {
    private(set) var count = 0
    private var pending: [Int: CheckedContinuation<String?, Never>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func fetch() async -> String? {
        count += 1
        let request = count
        return await withCheckedContinuation { continuation in
            pending[request] = continuation
            let ready = waiters.filter { $0.0 <= count }
            waiters.removeAll { $0.0 <= count }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForRequest(_ target: Int) async {
        guard count < target else { return }
        await withCheckedContinuation { waiters.append((target, $0)) }
    }

    func complete(_ request: Int, with value: String?) {
        pending.removeValue(forKey: request)?.resume(returning: value)
    }
}

private final class IPTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1000)
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value.addTimeInterval(seconds) } }
}
