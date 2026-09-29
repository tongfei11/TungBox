import Foundation
import XCTest
@testable import TungBox

final class RemoteContentSecurityTests: XCTestCase {
    func testBoundedAccumulatorAcceptsLimitAndRejectsDeclaredOrStreamedOverflow() throws {
        var exact = BoundedDataAccumulator(maxBytes: 4)
        try exact.acceptExpectedLength(4)
        try exact.append(Data([1, 2]))
        try exact.append(Data([3, 4]))
        XCTAssertEqual(exact.data.count, 4)

        var declared = BoundedDataAccumulator(maxBytes: 4)
        XCTAssertThrowsError(try declared.acceptExpectedLength(5)) { error in
            XCTAssertEqual(error as? SecurityLimitError, .responseTooLarge(limit: 4))
        }

        var streamed = BoundedDataAccumulator(maxBytes: 4)
        try streamed.append(Data([1, 2, 3]))
        XCTAssertThrowsError(try streamed.append(Data([4, 5]))) { error in
            XCTAssertEqual(error as? SecurityLimitError, .responseTooLarge(limit: 4))
        }
        XCTAssertEqual(streamed.data, Data([1, 2, 3]))
    }

    func testURLSessionDelegateReturnsLimitErrorWithoutDeadlocking() throws {
        let url = URL(string: "https://example.com/subscription")!
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: url)

        let declaredDelegate = BoundedURLSessionDelegate(maxBytes: 4)
        let oversizedResponse = URLResponse(
            url: url,
            mimeType: "application/octet-stream",
            expectedContentLength: 5,
            textEncodingName: nil
        )
        var disposition: URLSession.ResponseDisposition?
        declaredDelegate.urlSession(session, dataTask: task, didReceive: oversizedResponse) {
            disposition = $0
        }
        XCTAssertEqual(disposition, .cancel)
        XCTAssertThrowsError(try declaredDelegate.wait(timeout: 0.1)) { error in
            XCTAssertEqual(error as? SecurityLimitError, .responseTooLarge(limit: 4))
        }

        let streamedDelegate = BoundedURLSessionDelegate(maxBytes: 4)
        let unknownLengthResponse = URLResponse(
            url: url,
            mimeType: "application/octet-stream",
            expectedContentLength: -1,
            textEncodingName: nil
        )
        streamedDelegate.urlSession(session, dataTask: task, didReceive: unknownLengthResponse) { _ in }
        streamedDelegate.urlSession(session, dataTask: task, didReceive: Data([1, 2, 3]))
        streamedDelegate.urlSession(session, dataTask: task, didReceive: Data([4, 5]))
        XCTAssertThrowsError(try streamedDelegate.wait(timeout: 0.1)) { error in
            XCTAssertEqual(error as? SecurityLimitError, .responseTooLarge(limit: 4))
        }
    }

    func testYAMLDepthBoundary() throws {
        func nestedYAML(depth: Int) -> String {
            (0..<depth).map { String(repeating: " ", count: $0 * 2) + "k\($0):" }.joined(separator: "\n")
                + "\n" + String(repeating: " ", count: depth * 2) + "value: ok"
        }

        XCTAssertNotNil(try SubscriptionFormatParser.parseYAMLDocument(nestedYAML(depth: SecurityLimits.yamlMaxDepth)))
        XCTAssertThrowsError(try SubscriptionFormatParser.parseYAMLDocument(nestedYAML(depth: SecurityLimits.yamlMaxDepth + 1))) { error in
            XCTAssertEqual(error as? SecurityLimitError, .yamlTooDeep(limit: SecurityLimits.yamlMaxDepth))
        }
    }

    func testYAMLRejectsOversizedLineAndDocument() {
        let longLine = "key: " + String(repeating: "a", count: SecurityLimits.yamlMaxLineBytes)
        XCTAssertThrowsError(try SubscriptionFormatParser.parseYAMLDocument(longLine)) { error in
            XCTAssertEqual(error as? SecurityLimitError, .yamlLineTooLong(limit: SecurityLimits.yamlMaxLineBytes))
        }

        let oversized = String(repeating: "a", count: SecurityLimits.subscriptionBytes + 1)
        XCTAssertThrowsError(try SubscriptionFormatParser.parseYAMLDocument(oversized)) { error in
            XCTAssertEqual(error as? SecurityLimitError, .responseTooLarge(limit: SecurityLimits.subscriptionBytes))
        }
    }

    func testYAMLRejectsTooManyStructuralNodes() {
        let yaml = (0...SecurityLimits.yamlMaxNodes).map { "k\($0): v" }.joined(separator: "\n")
        XCTAssertThrowsError(try SubscriptionFormatParser.parseYAMLDocument(yaml)) { error in
            XCTAssertEqual(error as? SecurityLimitError, .yamlTooComplex(limit: SecurityLimits.yamlMaxNodes))
        }
    }

    func testSingleLineFlowSequenceCannotBypassNodeBudget() {
        let yaml = "values: [" + Array(repeating: "a", count: SecurityLimits.yamlMaxNodes).joined(separator: ",") + "]"
        XCTAssertThrowsError(try SubscriptionFormatParser.parseYAMLDocument(yaml)) { error in
            XCTAssertEqual(error as? SecurityLimitError, .yamlTooComplex(limit: SecurityLimits.yamlMaxNodes))
        }
    }

    func testClashParserRejectsTooManyProxyNodes() {
        let proxies = Array(repeating: "  - {}", count: SecurityLimits.maxProxyNodes + 1).joined(separator: "\n")
        let yaml = "proxies:\n\(proxies)\nproxy-groups:\n  - {name: all, type: select, proxies: []}"

        XCTAssertThrowsError(try SubscriptionFormatParser.parseClashProxiesWithSummary(yaml)) { error in
            XCTAssertEqual(error as? SecurityLimitError, .tooManyProxyNodes(limit: SecurityLimits.maxProxyNodes))
        }
    }

    func testRemoteLoaderRejectsNonHTTPURLWithoutReadingIt() {
        XCTAssertThrowsError(
            try BoundedRemoteDataLoader.fetch(url: URL(fileURLWithPath: "/tmp/should-not-be-read"), maxBytes: 4)
        ) { error in
            XCTAssertEqual(error as? SecurityLimitError, .invalidRemoteURL)
        }
    }
}
