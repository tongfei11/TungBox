import Foundation

enum SecurityLimits {
    static let subscriptionBytes = 16 * 1024 * 1024
    static let ruleSetBytes = 64 * 1024 * 1024
    static let coreArchiveBytes = 128 * 1024 * 1024
    static let yamlMaxDepth = 64
    static let yamlMaxNodes = 100_000
    static let yamlMaxLineBytes = 1024 * 1024
    static let maxProxyNodes = 20_000
    static let subscriptionTrafficMax: Int64 = 1 << 60
    static let earliestSubscriptionExpiry = Date(timeIntervalSince1970: 946_684_800)
    static let latestSubscriptionExpiry = Date(timeIntervalSince1970: 4_102_444_800)
}

enum SecurityLimitError: Error, Equatable, LocalizedError {
    case responseTooLarge(limit: Int)
    case yamlTooDeep(limit: Int)
    case yamlTooComplex(limit: Int)
    case yamlLineTooLong(limit: Int)
    case tooManyProxyNodes(limit: Int)
    case invalidRemoteURL

    var errorDescription: String? {
        switch self {
        case .responseTooLarge(let limit): return "远程内容超过安全上限（\(limit / 1024 / 1024) MiB）"
        case .yamlTooDeep(let limit): return "订阅 YAML 嵌套超过安全上限（\(limit) 层）"
        case .yamlTooComplex(let limit): return "订阅 YAML 节点数超过安全上限（\(limit)）"
        case .yamlLineTooLong(let limit): return "订阅 YAML 单行超过安全上限（\(limit) 字节）"
        case .tooManyProxyNodes(let limit): return "订阅节点数超过安全上限（\(limit)）"
        case .invalidRemoteURL: return "远程地址必须是 http 或 https URL"
        }
    }
}

struct BoundedDataAccumulator {
    let maxBytes: Int
    private(set) var data = Data()

    mutating func acceptExpectedLength(_ length: Int64) throws {
        guard length < 0 || length <= Int64(maxBytes) else {
            throw SecurityLimitError.responseTooLarge(limit: maxBytes)
        }
    }

    mutating func append(_ chunk: Data) throws {
        guard chunk.count <= maxBytes - data.count else {
            throw SecurityLimitError.responseTooLarge(limit: maxBytes)
        }
        data.append(chunk)
    }
}

final class BoundedURLSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var accumulator: BoundedDataAccumulator
    private var response: URLResponse?
    private var result: Result<(Data, URLResponse), Error>?
    private let completion = DispatchSemaphore(value: 0)

    init(maxBytes: Int) {
        accumulator = BoundedDataAccumulator(maxBytes: maxBytes)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        do {
            lock.lock()
            do {
                try accumulator.acceptExpectedLength(response.expectedContentLength)
                self.response = response
                lock.unlock()
                completionHandler(.allow)
            } catch {
                lock.unlock()
                throw error
            }
        } catch {
            finish(.failure(error))
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            lock.lock()
            do {
                try accumulator.append(data)
                lock.unlock()
            } catch {
                lock.unlock()
                throw error
            }
        } catch {
            finish(.failure(error))
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
            return
        }
        lock.lock()
        let response = self.response
        let data = accumulator.data
        lock.unlock()
        guard let response else {
            finish(.failure(NSError.user("远程服务器没有返回有效响应")))
            return
        }
        finish(.success((data, response)))
    }

    private func finish(_ value: Result<(Data, URLResponse), Error>) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = value
        lock.unlock()
        completion.signal()
    }

    func wait(timeout: TimeInterval) throws -> (Data, URLResponse) {
        guard completion.wait(timeout: .now() + timeout) == .success else {
            throw NSError.user("下载超时，请检查网络后重试")
        }
        lock.lock()
        let result = self.result
        lock.unlock()
        guard let result else { throw NSError.user("下载没有返回结果") }
        return try result.get()
    }
}

enum BoundedRemoteDataLoader {
    static func fetch(
        request: URLRequest,
        configuration: URLSessionConfiguration,
        maxBytes: Int,
        timeout: TimeInterval
    ) throws -> (Data, URLResponse) {
        let delegate = BoundedURLSessionDelegate(maxBytes: maxBytes)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()
        defer {
            task.cancel()
            session.invalidateAndCancel()
        }
        return try delegate.wait(timeout: timeout)
    }

    static func fetch(url: URL, maxBytes: Int, timeout: TimeInterval = 60) throws -> Data {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw SecurityLimitError.invalidRemoteURL
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let (data, response) = try fetch(
            request: request,
            configuration: configuration,
            maxBytes: maxBytes,
            timeout: timeout + 5
        )
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError.user("下载失败：HTTP \(http.statusCode)")
        }
        return data
    }
}
