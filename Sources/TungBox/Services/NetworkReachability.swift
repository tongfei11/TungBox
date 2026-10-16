import Foundation
import Network

/// Monitors the primary network interface (Wi-Fi, Ethernet, Cellular, Offline).
@MainActor
final class NetworkReachability {
    static let shared = NetworkReachability()

    enum InterfaceType: String {
        case wifi = "Wi-Fi"
        case ethernet = "以太网"
        case cellular = "蜂窝网络"
        case offline = "未连接"
    }

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.tungbox.networkreachability")
    private(set) var currentType: InterfaceType = .wifi
    var onInterfaceChanged: ((InterfaceType) -> Void)?

    init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let newType: InterfaceType
                if path.status != .satisfied {
                    newType = .offline
                } else if path.usesInterfaceType(.wifi) {
                    newType = .wifi
                } else if path.usesInterfaceType(.wiredEthernet) {
                    newType = .ethernet
                } else if path.usesInterfaceType(.cellular) {
                    newType = .cellular
                } else {
                    newType = .wifi
                }
                if self.currentType != newType {
                    self.currentType = newType
                    self.onInterfaceChanged?(newType)
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
