import CFNetwork
import Foundation

/// Blocking OS proxy operations. Scheduling, generations, logs and UI stay with the caller.
/// Commands and system settings are injected together for side-effect-free tests.
struct SystemProxyManager: Sendable {
    typealias CommandRunner = @Sendable (String, [String], TimeInterval) -> String
    typealias SettingsReader = @Sendable () -> [String: Any]?

    private let commandRunner: CommandRunner
    private let settingsReader: SettingsReader
    private let ownershipCheckTimeout: TimeInterval

    init() {
        self.init(commandRunner: { SystemCommand.run($0, args: $1, timeoutSeconds: $2) },
                  settingsReader: { CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] })
    }

    init(commandRunner: @escaping CommandRunner, settingsReader: @escaping SettingsReader, ownershipCheckTimeout: TimeInterval = 4) {
        self.commandRunner = commandRunner
        self.settingsReader = settingsReader
        self.ownershipCheckTimeout = ownershipCheckTimeout
    }

    /// Applies the same six enable commands per service. Command failures retain
    /// the existing best-effort behavior; only owned settings are disabled.
    func apply(enabled: Bool, port: Int) {
        for service in activeNetworkServices() {
            if enabled {
                _ = commandRunner("/usr/sbin/networksetup", ["-setwebproxy", service, "127.0.0.1", "\(port)"], 3)
                _ = commandRunner("/usr/sbin/networksetup", ["-setsecurewebproxy", service, "127.0.0.1", "\(port)"], 3)
                _ = commandRunner("/usr/sbin/networksetup", ["-setsocksfirewallproxy", service, "127.0.0.1", "\(port)"], 3)
                _ = commandRunner("/usr/sbin/networksetup", ["-setwebproxystate", service, "on"], 3)
                _ = commandRunner("/usr/sbin/networksetup", ["-setsecurewebproxystate", service, "on"], 3)
                _ = commandRunner("/usr/sbin/networksetup", ["-setsocksfirewallproxystate", service, "on"], 3)
            } else {
                disableIfOwned(service: service, port: port)
            }
        }
    }

    func disableIfOwned(service: String, port: Int) {
        let checks: [(getter: String, stateArg: String)] = [
            ("-getwebproxy", "-setwebproxystate"),
            ("-getsecurewebproxy", "-setsecurewebproxystate"),
            ("-getsocksfirewallproxy", "-setsocksfirewallproxystate")
        ]
        let matches = LockedValue<[String: Bool]>([:])
        let group = DispatchGroup()
        for check in checks {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let isOwned = self.proxySettingMatches(service: service, getter: check.getter, port: port)
                matches.mutate { $0[check.getter] = isOwned }
                group.leave()
            }
        }
        // A stuck networksetup query must not hold the runtime transition forever.
        _ = group.wait(timeout: .now() + ownershipCheckTimeout)

        let ownedStates = checks.filter { matches.get()[ $0.getter ] == true }
        DispatchQueue.concurrentPerform(iterations: ownedStates.count) { index in
            let stateArg = ownedStates[index].stateArg
            _ = self.commandRunner("/usr/sbin/networksetup", [stateArg, service, "off"], 3)
        }
    }

    func proxySettingMatches(service: String, getter: String, port: Int) -> Bool {
        let output = commandRunner("/usr/sbin/networksetup", [getter, service], 3)
        let lines = output.components(separatedBy: .newlines)
        let enabled = lines.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Enabled: Yes") == .orderedSame }
        let server = lines.first { $0.hasPrefix("Server:") }?
            .replacingOccurrences(of: "Server:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentPort = lines.first { $0.hasPrefix("Port:") }?
            .replacingOccurrences(of: "Port:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return enabled && isLocalProxyHost(server) && currentPort == "\(port)"
    }

    func currentStatus(expectedPort port: Int) -> (matches: Bool, hasExternalProxy: Bool, message: String) {
        guard let settings = settingsReader() else {
            return (false, false, "无法读取系统代理")
        }
        let httpEnabled = settings[kCFNetworkProxiesHTTPEnable as String] as? Int ?? 0
        let httpHost = settings[kCFNetworkProxiesHTTPProxy as String] as? String ?? "-"
        let httpPort = settings[kCFNetworkProxiesHTTPPort as String] as? Int ?? 0
        let httpsEnabled = settings[kCFNetworkProxiesHTTPSEnable as String] as? Int ?? 0
        let httpsHost = settings[kCFNetworkProxiesHTTPSProxy as String] as? String ?? "-"
        let httpsPort = settings[kCFNetworkProxiesHTTPSPort as String] as? Int ?? 0
        let httpMatches = httpEnabled == 1 && isLocalProxyHost(httpHost) && httpPort == port
        let httpsMatches = httpsEnabled == 1 && isLocalProxyHost(httpsHost) && httpsPort == port
        if httpMatches && httpsMatches {
            return (true, false, "HTTP/HTTPS 已指向 127.0.0.1:\(port)")
        }
        let httpExternal = httpEnabled == 1 && !(isLocalProxyHost(httpHost) && httpPort == port)
        let httpsExternal = httpsEnabled == 1 && !(isLocalProxyHost(httpsHost) && httpsPort == port)
        return (false, httpExternal || httpsExternal, "HTTP \(httpHost):\(httpPort) \(httpEnabled == 1 ? "开启" : "关闭")，HTTPS \(httpsHost):\(httpsPort) \(httpsEnabled == 1 ? "开启" : "关闭")，预期 127.0.0.1:\(port)")
    }

    private func isLocalProxyHost(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
    
    func activeNetworkServices() -> [String] {
        let output = commandRunner("/usr/sbin/networksetup", ["-listallnetworkservices"], 3)
        let lines = output.components(separatedBy: .newlines)
        var services: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("An asterisk") || trimmed.hasPrefix("*") {
                continue
            }
            // Skip VPN/Proxy interfaces
            if trimmed.lowercased().contains("tailscale") || trimmed.lowercased().contains("surge") || trimmed.lowercased().contains("vpn") {
                continue
            }
            services.append(trimmed)
        }
        if services.isEmpty {
            services.append("Wi-Fi")
        }
        return services
    }
}
