import Foundation

/// Decisions shared by the generic dialog and runtime failure notices. Match the
/// error code, including wrapped errors, rather than localized English text.
enum ErrorPresentation {
    static func isTimeout(_ error: Error) -> Bool {
        var current = error as NSError
        var visited = Set<ObjectIdentifier>()
        for _ in 0..<16 {
            guard visited.insert(ObjectIdentifier(current)).inserted else { return false }
            if current.domain == NSURLErrorDomain && current.code == NSURLErrorTimedOut { return true }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
            current = underlying
        }
        return false
    }

    enum RuntimeOperation {
        case tunStart, systemProxyStart, systemProxyStop, tunControlVerification, modeSynchronization

        var title: String {
            switch self {
            case .tunStart, .tunControlVerification: return "TUN 启动失败"
            case .systemProxyStart: return "系统代理启动失败"
            case .systemProxyStop: return "系统代理关闭失败"
            case .modeSynchronization: return "出站模式同步失败"
            }
        }
    }

    struct RuntimeFailure {
        let message: String
        let presentsDialog: Bool
    }

    static func runtimeFailure(_ error: Error, operation: RuntimeOperation, allowDialog: Bool = true) -> RuntimeFailure {
        let timeout = isTimeout(error)
        let detail: String
        if operation == .tunControlVerification {
            detail = timeout
                ? "本地控制接口 9091 响应超时，已停止 TUN。请查看 TUN 日志后重试。"
                : "本地控制接口 9091 校验失败，已停止 TUN。\(error.localizedDescription)"
        } else {
            detail = timeout ? "操作等待响应超时，请查看日志后重试。" : error.localizedDescription
        }
        return RuntimeFailure(message: "\(operation.title)：\(detail)", presentsDialog: allowDialog && !timeout)
    }
}
