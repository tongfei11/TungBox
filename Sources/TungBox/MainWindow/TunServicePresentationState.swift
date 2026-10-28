import Foundation

/// Keeps asynchronous service checks and the one-time upgrade prompt consistent.
struct TunServicePresentationState {
    private(set) var status: TunServiceStatus?
    private(set) var operationID = UUID()
    private var requestID = UUID()
    private var didPresentUpdate = false

    mutating func beginOperation() {
        operationID = UUID()
        _ = beginCheck()
    }

    mutating func beginCheck() -> UUID {
        requestID = UUID()
        return requestID
    }

    @discardableResult
    mutating func accept(_ status: TunServiceStatus, requestID: UUID) -> Bool {
        guard self.requestID == requestID else { return false }
        self.status = status
        return true
    }

    mutating func claimUpdatePrompt(canPresent: Bool, force: Bool = false) -> Bool {
        guard status?.needsUpdate == true, canPresent, force || !didPresentUpdate else { return false }
        didPresentUpdate = true
        return true
    }

    func homeStatusText(tunEnabled: Bool) -> String {
        if status?.needsUpdate == true { return "TUN 服务：需要更新" }
        guard tunEnabled else { return "TUN 权限：未启用" }
        guard let status else { return "TUN 服务：正在检查..." }
        // Process liveness changes independently of this installation snapshot.
        if status.isUsable { return "TUN 服务：已安装，随代理开启" }
        return "TUN 服务：\(status.displayText)"
    }
}
