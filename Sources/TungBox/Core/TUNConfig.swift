import Foundation

/// 用户可配置的 TUN inbound 设置。基础项（协议栈 / MTU / 严格路由 / 路由排除）覆盖
/// 95% 调参场景；高级项（端点独立 NAT / 包含/排除接口）默认折叠。
///
/// 不暴露的字段（理由）：
/// - `auto_route` / `auto_detect_interface` —— 关掉等于 TUN 罢工
/// - `interface_name` —— TungBox 固定 utun29/utun99，避免和 daemon 冲突
/// - `address` / `udp_timeout` —— 没人需要改，默认就够
/// - DNS 劫持 —— 已在路由规则里硬编码 `protocol: dns, action: hijack-dns`
enum TUNConfig {

    enum Stack: String, CaseIterable {
        case system
        case gvisor
        case mixed

        var displayName: String {
            switch self {
            case .system: return "System"
            case .gvisor: return "GVisor"
            case .mixed:  return "Mixed"
            }
        }
    }

    // MARK: - 默认值

    static let defaultStack: Stack = .mixed
    static let defaultMTU = 9000
    static let defaultStrictRoute = false
    static let defaultEndpointIndependentNAT = false
    static let defaultRouteExclude: [String] = [
        "10.0.0.0/8",
        "100.64.0.0/10",
        "127.0.0.0/8",
        "169.254.0.0/16",
        "172.16.0.0/12",
        "192.168.0.0/16",
        "::1/128",
        "fc00::/7",
        "fe80::/10"
    ]
    static let defaultIncludeInterface: [String] = []
    static let defaultExcludeInterface: [String] = []

    // MARK: - UserDefaults 键

    private static let kStack = "tunStack"
    private static let kMTU = "tunMTU"
    private static let kStrictRoute = "tunStrictRoute"
    private static let kEIN = "tunEndpointIndependentNAT"
    private static let kRouteExclude = "tunRouteExclude"
    private static let kIncludeIface = "tunIncludeInterface"
    private static let kExcludeIface = "tunExcludeInterface"

    // MARK: - 存取

    static var stack: Stack {
        get {
            if let raw = UserDefaults.standard.string(forKey: kStack),
               let v = Stack(rawValue: raw) {
                return v
            }
            return defaultStack
        }
        set {
            if newValue == defaultStack {
                UserDefaults.standard.removeObject(forKey: kStack)
            } else {
                UserDefaults.standard.set(newValue.rawValue, forKey: kStack)
            }
        }
    }

    static var mtu: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: kMTU)
            return v > 0 ? v : defaultMTU
        }
        set {
            if newValue == defaultMTU || newValue <= 0 {
                UserDefaults.standard.removeObject(forKey: kMTU)
            } else {
                UserDefaults.standard.set(newValue, forKey: kMTU)
            }
        }
    }

    static var strictRoute: Bool {
        get {
            if let v = UserDefaults.standard.object(forKey: kStrictRoute) as? Bool {
                return v
            }
            return defaultStrictRoute
        }
        set {
            if newValue == defaultStrictRoute {
                UserDefaults.standard.removeObject(forKey: kStrictRoute)
            } else {
                UserDefaults.standard.set(newValue, forKey: kStrictRoute)
            }
        }
    }

    static var endpointIndependentNAT: Bool {
        get {
            if let v = UserDefaults.standard.object(forKey: kEIN) as? Bool {
                return v
            }
            return defaultEndpointIndependentNAT
        }
        set {
            if newValue == defaultEndpointIndependentNAT {
                UserDefaults.standard.removeObject(forKey: kEIN)
            } else {
                UserDefaults.standard.set(newValue, forKey: kEIN)
            }
        }
    }

    static var routeExclude: [String] {
        get {
            if let arr = UserDefaults.standard.array(forKey: kRouteExclude) as? [String] {
                return arr
            }
            return defaultRouteExclude
        }
        set {
            let cleaned = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if cleaned == defaultRouteExclude {
                UserDefaults.standard.removeObject(forKey: kRouteExclude)
            } else {
                UserDefaults.standard.set(cleaned, forKey: kRouteExclude)
            }
        }
    }

    static var includeInterface: [String] {
        get { UserDefaults.standard.array(forKey: kIncludeIface) as? [String] ?? defaultIncludeInterface }
        set {
            let cleaned = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if cleaned.isEmpty {
                UserDefaults.standard.removeObject(forKey: kIncludeIface)
            } else {
                UserDefaults.standard.set(cleaned, forKey: kIncludeIface)
            }
        }
    }

    static var excludeInterface: [String] {
        get { UserDefaults.standard.array(forKey: kExcludeIface) as? [String] ?? defaultExcludeInterface }
        set {
            let cleaned = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if cleaned.isEmpty {
                UserDefaults.standard.removeObject(forKey: kExcludeIface)
            } else {
                UserDefaults.standard.set(cleaned, forKey: kExcludeIface)
            }
        }
    }

    static func resetAll() {
        [kStack, kMTU, kStrictRoute, kEIN, kRouteExclude, kIncludeIface, kExcludeIface]
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    /// 把用户设置注入一个 sing-box TUN inbound dict（已包含 type / tag / address /
    /// interface_name / auto_route）。改字段在 setTunEnabled 主体外做，方便复用。
    static func applyUserFields(to inbound: [String: Any]) -> [String: Any] {
        var out = inbound
        out["stack"] = stack.rawValue
        out["mtu"] = mtu
        out["strict_route"] = strictRoute
        out["endpoint_independent_nat"] = endpointIndependentNAT
        out["route_exclude_address"] = routeExclude
        let inc = includeInterface
        if !inc.isEmpty { out["include_interface"] = inc } else { out.removeValue(forKey: "include_interface") }
        let exc = excludeInterface
        if !exc.isEmpty { out["exclude_interface"] = exc } else { out.removeValue(forKey: "exclude_interface") }
        return out
    }
}
