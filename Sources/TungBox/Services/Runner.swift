import Foundation

final class Runner: @unchecked Sendable {
    private var process: Process?
    private var outputPipe: Pipe?
    private var elevatedPID: Int32?
    private let store: Store
    
    private let testQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.tungbox.testQueue"
        q.maxConcurrentOperationCount = 4
        return q
    }()
    var onOutput: ((String) -> Void)?
    var isRunning: Bool {
        if process?.isRunning == true { return true }
        if let elevatedPID, isProcessRunning(elevatedPID) { return true }
        return false
    }
    var pid: Int32? {
        if let proc = process, proc.isRunning { return proc.processIdentifier }
        if let elevatedPID, isProcessRunning(elevatedPID) { return elevatedPID }
        return nil
    }

    var isElevatedRunning: Bool {
        guard let elevatedPID else { return false }
        return isProcessRunning(elevatedPID)
    }

    init(store: Store) {
        self.store = store
    }

    private func isProcessRunning(_ pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    func findSingBox() -> String? {
        let optionalCandidates: [String?] = [
            store.coreBinaryURL.path,
            Bundle.main.resourceURL?.appendingPathComponent("sing-box").path,
            Bundle.main.resourceURL?.appendingPathComponent("Core/sing-box").path,
            "/opt/homebrew/bin/sing-box",
            "/usr/local/bin/sing-box",
            "/usr/bin/sing-box",
            "/opt/homebrew/bin/singbox",
            "/usr/local/bin/singbox"
        ]
        let candidates = optionalCandidates.compactMap { $0 }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let envResult = runAndWait("/usr/bin/env", ["bash", "-lc", "command -v sing-box || command -v singbox"])
        let path = envResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if envResult.status == 0, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    func version() -> String? {
        guard let binary = findSingBox() else { return nil }
        let result = runAndWait(binary, ["version"])
        guard result.status == 0 else { return nil }
        return result.output.components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func versionResult() -> (status: Int32, output: String)? {
        guard let binary = findSingBox() else { return nil }
        return runAndWait(binary, ["version"])
    }

    func installedVersionNumber() -> String? {
        guard let text = version() else { return nil }
        return Runner.extractVersion(from: text)
    }

    static func extractVersion(from text: String) -> String? {
        let pattern = #"\d+\.\d+\.\d+(?:[-.][A-Za-z0-9]+)*"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: "-").first?.split(separator: ".").compactMap { Int($0) } ?? []
        let right = rhs.split(separator: "-").first?.split(separator: ".").compactMap { Int($0) } ?? []
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    func check(config: URL) throws -> String {
        guard let binary = findSingBox() else {
            throw NSError.user("找不到 sing-box。请先安装：brew install sing-box")
        }
        let actualConfig = preprocessConfig(at: config)
        let result = runAndWait(binary, ["check", "-c", actualConfig.path])
        if result.status != 0 {
            throw NSError.user(result.output.isEmpty ? "配置检查失败" : result.output)
        }
        return result.output.isEmpty ? "配置检查通过" : result.output
    }

    func format(config: URL) throws -> String {
        guard let binary = findSingBox() else {
            throw NSError.user("找不到 sing-box。请先安装：brew install sing-box")
        }
        let result = runAndWait(binary, ["format", "-w", "-c", config.path])
        if result.status != 0 {
            throw NSError.user(result.output.isEmpty ? "格式化失败" : result.output)
        }
        return result.output.isEmpty ? "格式化完成" : result.output
    }

    func start(config: URL, elevated: Bool = false) throws {
        if isRunning { return }
        guard let binary = findSingBox() else {
            throw NSError.user("找不到 sing-box。请先安装：brew install sing-box")
        }

        if elevated {
            try startElevated(binary: binary, config: config)
            return
        }

        let actualConfig = preprocessConfig(at: config, allowTun: false)

        let process = Process()
        process.currentDirectoryURL = store.baseURL
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["run", "-c", actualConfig.path]
        var env = ProcessInfo.processInfo.environment
        env["ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER"] = "true"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.onOutput?(text) }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.onOutput?("\n[sing-box exited: \(proc.terminationStatus)]\n")
            }
        }

        try process.run()
        self.process = process
        outputPipe = pipe
    }

    private func startElevated(binary: String, config: URL) throws {
        let actualConfig = preprocessConfig(at: config, allowTun: true)
        let command = [
            "cd \(shellQuote(store.baseURL.path))",
            "nohup env ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true \(shellQuote(binary)) run -c \(shellQuote(actualConfig.path)) >> \(shellQuote(store.logURL.path)) 2>&1 & echo $!"
        ].joined(separator: "; ")
        let appleScript = "do shell script \"\(appleScriptString(command))\" with administrator privileges"
        let result = runAndWait("/usr/bin/osascript", ["-e", appleScript])
        if result.status != 0 {
            throw NSError.user(result.output.isEmpty ? "管理员授权启动失败" : result.output)
        }
        let pidText = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(pidText) else {
            throw NSError.user("管理员启动成功但无法读取 sing-box PID：\(pidText)")
        }
        elevatedPID = pid
        DispatchQueue.main.async { [weak self] in
            self?.onOutput?("[TUN] 已通过管理员权限启动 sing-box，PID \(pid)\n")
        }
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
            self.process = nil
            outputPipe?.fileHandleForReading.readabilityHandler = nil
            outputPipe = nil
        }
        if let elevatedPID, isProcessRunning(elevatedPID) {
            let command = "kill \(elevatedPID) 2>/dev/null || true"
            let appleScript = "do shell script \"\(appleScriptString(command))\" with administrator privileges"
            _ = runAndWait("/usr/bin/osascript", ["-e", appleScript])
        }
        elevatedPID = nil
    }

    func stopStaleUserProcesses() {
        let binary = store.coreBinaryURL.path
        let configDirectory = store.baseURL.path
        let output = runAndWait("/bin/ps", ["-axo", "pid=,command="], timeoutSeconds: 2).output
        for line in output.components(separatedBy: .newlines) {
            guard line.contains(binary),
                  line.contains(" run "),
                  line.contains(" -c "),
                  line.contains(configDirectory),
                  !line.contains(TunServiceManager.configPath) else {
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let pidText = trimmed.split(separator: " ").first,
                  let pid = Int32(pidText),
                  isProcessRunning(pid) else {
                continue
            }
            Darwin.kill(pid, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(700)) { [weak self] in
                guard let self, self.isProcessRunning(pid) else { return }
                Darwin.kill(pid, SIGKILL)
            }
        }
    }

    func urlTest(config: URL, outbound: String, testURL: String) async throws -> String {
        guard let binary = findSingBox() else {
            throw NSError.user("找不到 sing-box。请先安装：brew install sing-box")
        }
        let actualConfig = preprocessTestConfig(at: config)
        let start = Date()
        
        let result: (status: Int32, output: String) = try await withCheckedThrowingContinuation { continuation in
            testQueue.addOperation { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError.user("Runner has been deallocated"))
                    return
                }
                let res = self.runAndWait(binary, [
                    "tools", "fetch",
                    "-c", actualConfig.path,
                    "-o", outbound,
                    testURL
                ], timeoutSeconds: 3)
                continuation.resume(returning: res)
            }
        }
        
        if result.status != 0 {
            let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError.user(message.isEmpty ? "节点延迟测试超时或失败" : message)
        }
        return "\(Int(Date().timeIntervalSince(start) * 1000)) ms"
    }


    private func runAndWait(_ binary: String, _ args: [String], timeoutSeconds: UInt32? = nil) -> (status: Int32, output: String) {
        let process = Process()
        process.currentDirectoryURL = store.baseURL
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args

        // Remove proxy environment variables to guarantee direct connection without interference
        var env = ProcessInfo.processInfo.environment
        let proxyKeys = ["http_proxy", "https_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"]
        for key in proxyKeys {
            env.removeValue(forKey: key)
        }
        env["ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER"] = "true"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()

            if let timeout = timeoutSeconds {
                let semaphore = DispatchSemaphore(value: 0)
                let deadline = DispatchTime.now() + .seconds(Int(timeout))

                DispatchQueue.global().async {
                    process.waitUntilExit()
                    semaphore.signal()
                }

                if semaphore.wait(timeout: deadline) == .timedOut {
                    if process.isRunning {
                        process.terminate()
                        // Give it a brief moment to clean up
                        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
                            if process.isRunning {
                                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                            }
                        }
                    }
                    return (143, "操作超时 (\(timeout)s)")
                }
            } else {
                process.waitUntilExit()
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (1, error.localizedDescription)
        }
    }

    private func preprocessConfig(at url: URL, allowTun: Bool = false) -> URL {
        if getuid() == 0 || allowTun {
            return url
        }
        
        guard let data = try? Data(contentsOf: url),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return url
        }
        
        // Auto-fix any compatibility issues (like network: grpc) on the fly
        let (fixedJson, _) = ConfigCompatibilityChecker.autoFix(config: json)
        json = fixedJson
        
        var inbounds = json["inbounds"] as? [[String: Any]] ?? []
        let hasTun = inbounds.contains { ($0["type"] as? String) == "tun" }
        if !hasTun {
            return url
        }
        
        inbounds = inbounds.filter { ($0["type"] as? String) != "tun" }
        if inbounds.isEmpty {
            inbounds.append([
                "type": "mixed",
                "tag": "mixed-in",
                "listen": "127.0.0.1",
                "listen_port": 7890
            ])
        }
        json["inbounds"] = inbounds
        
        let tempURL = url.deletingLastPathComponent().appendingPathComponent("run_" + url.lastPathComponent)
        if let outData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? outData.write(to: tempURL)
            DispatchQueue.main.async { [weak self] in
                self?.onOutput?("[TungBox] 检测到当前运行非管理员权限，已自动将配置中的 TUN 模式转换为本地混合代理模式运行。\n")
            }
            return tempURL
        }
        return url
    }

    private func preprocessTestConfig(at url: URL) -> URL {
        guard let data = try? Data(contentsOf: url),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return url
        }
        
        // Auto-fix any compatibility issues (like network: grpc) on the fly
        let (fixedJson, _) = ConfigCompatibilityChecker.autoFix(config: json)
        json = fixedJson
        
        json.removeValue(forKey: "experimental")
        json.removeValue(forKey: "inbounds")
        
        let dnsServerTag = "dns-direct-cn"
        
        // 1. Simplify route: force final to direct, enable auto_detect_interface to bypass virtual TUN interfaces
        let simplifiedRoute: [String: Any] = [
            "final": "direct",
            "auto_detect_interface": true,
            "default_domain_resolver": dnsServerTag
        ]
        json["route"] = simplifiedRoute
        
        // 2. Simplify dns: inject reliable direct public DNS servers and remove all detour fields
        let fallbackDNSServers: [[String: Any]] = [
            ["tag": "dns-direct-cn", "type": "udp", "server": "223.5.5.5", "server_port": 53],
            ["tag": "dns-direct-en", "type": "udp", "server": "8.8.8.8", "server_port": 53]
        ]
        
        if var dns = json["dns"] as? [String: Any] {
            dns.removeValue(forKey: "rules")
            dns.removeValue(forKey: "rule_set")
            var newServers = fallbackDNSServers
            if var servers = dns["servers"] as? [[String: Any]] {
                for i in servers.indices {
                    servers[i].removeValue(forKey: "detour")
                }
                newServers.append(contentsOf: servers)
            }
            dns["servers"] = newServers
            dns["final"] = dnsServerTag
            json["dns"] = dns
        } else {
            json["dns"] = [
                "servers": fallbackDNSServers,
                "final": dnsServerTag,
                "strategy": "prefer_ipv4"
            ]
        }
        
        // 3. Filter out virtual/test outbounds to prevent background startup storm during testing,
        // and set domain_resolver for proxy outbounds.
        if var outbounds = json["outbounds"] as? [[String: Any]] {
            let virtualTypes: Set<String> = ["direct", "block", "dns", "selector", "urltest", "url-test", "fallback"]
            // Filter out selectors, urltests, and fallbacks to prevent background testing storm at startup
            outbounds = outbounds.filter { outbound in
                guard let type = outbound["type"] as? String else { return false }
                let typeLower = type.lowercased()
                return !["selector", "urltest", "url-test", "fallback"].contains(typeLower)
            }
            
            // Inject domain_resolver to use the direct public DNS for all physical proxy outbounds
            for i in outbounds.indices {
                if let type = outbounds[i]["type"] as? String,
                   !virtualTypes.contains(type.lowercased()) {
                    outbounds[i]["domain_resolver"] = dnsServerTag
                }
            }
            json["outbounds"] = outbounds
        }
        
        let tempURL = url.deletingLastPathComponent().appendingPathComponent("test_" + url.lastPathComponent)
        if let outData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? outData.write(to: tempURL)
            return tempURL
        }
        return url
    }
}
