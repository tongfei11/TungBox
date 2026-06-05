import Foundation

enum TunServiceStatus {
    case notInstalled
    case installedRunning
    case installedIdle
    case abnormal(String)

    var displayText: String {
        switch self {
        case .notInstalled:
            return "未安装"
        case .installedRunning:
            return "已安装并运行"
        case .installedIdle:
            return "已安装，等待随代理开启"
        case .abnormal(let message):
            return "异常：\(message)"
        }
    }

    var isInstalled: Bool {
        switch self {
        case .notInstalled:
            return false
        default:
            return true
        }
    }

    var isRunning: Bool {
        if case .installedRunning = self { return true }
        return false
    }

    var isUsable: Bool {
        switch self {
        case .installedRunning, .installedIdle:
            return true
        default:
            return false
        }
    }

    var shouldReinstall: Bool {
        if case .abnormal = self { return true }
        return false
    }
}

enum TunServiceManager {
    static let label = "com.tung.tungbox.tun"
    static let installDirectoryPath = "/Library/Application Support/TungBox"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    static let scriptPath = "\(installDirectoryPath)/tun-service.sh"
    static let corePath = "\(installDirectoryPath)/sing-box"
    static let configPath = "\(installDirectoryPath)/tun-daemon.json"
    static let cachePath = "\(installDirectoryPath)/cache.db"
    static let flagPath = "\(installDirectoryPath)/tun-enabled"
    static let pidPath = "\(installDirectoryPath)/tun-service.pid"
    static let logPath = "\(installDirectoryPath)/tun-service.log"
    static let stdoutPath = "\(installDirectoryPath)/tun-service.out.log"
    static let stderrPath = "\(installDirectoryPath)/tun-service.err.log"
    static let legacyStdoutPath = "/tmp/\(label).out.log"
    static let legacyStderrPath = "/tmp/\(label).err.log"
    static let requestHeartbeatTimeout: TimeInterval = 30

    static var logURL: URL {
        URL(fileURLWithPath: logPath)
    }

    static func status(store: Store) -> TunServiceStatus {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            if hasInstalledArtifacts() {
                return .abnormal("服务文件残留，请重新安装 TUN 服务")
            }
            return .notInstalled
        }
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return .abnormal("服务脚本缺失")
        }
        guard FileManager.default.isExecutableFile(atPath: corePath) else {
            return .abnormal("Core 路径错误")
        }
        guard installedServiceDefinitionIsCurrent() else {
            return .abnormal("服务版本过旧，请重新安装 TUN 服务")
        }
        guard launchDaemonIsLoaded() else {
            return .abnormal("服务未加载，请重新安装 TUN 服务")
        }
        if let pid = activeSingBoxPID(store: store), Darwin.kill(pid, 0) == 0 {
            return .installedRunning
        }
        if let residue = networkResidueDescription() {
            return .abnormal("检测到 TUN 路由残留：\(residue)")
        }
        return .installedIdle
    }

    private static func hasInstalledArtifacts() -> Bool {
        [
            scriptPath,
            corePath,
            configPath,
            flagPath,
            pidPath,
            logPath,
            stdoutPath,
            stderrPath
        ].contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static func launchDaemonIsLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/\(label)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func activeSingBoxPID(store: Store) -> Int32? {
        guard let text = try? String(contentsOfFile: pidPath).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(text),
              Darwin.kill(pid, 0) == 0 else {
            return nil
        }
        return pid
    }

    static func hasEnableRequest(store: Store) -> Bool {
        FileManager.default.fileExists(atPath: store.tunRequestFlagURL.path)
            && FileManager.default.fileExists(atPath: store.tunRequestConfigURL.path)
            && requestHeartbeatIsFresh(store: store)
    }

    static func hasRequestFiles(store: Store) -> Bool {
        FileManager.default.fileExists(atPath: store.tunRequestFlagURL.path)
            || FileManager.default.fileExists(atPath: store.tunRequestConfigURL.path)
            || FileManager.default.fileExists(atPath: store.tunRequestHeartbeatURL.path)
    }

    static func waitUntilStopped(store: Store, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !hasRequestFiles(store: store), activeSingBoxPID(store: store) == nil, !hasNetworkResidue() {
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return !hasRequestFiles(store: store) && activeSingBoxPID(store: store) == nil && !hasNetworkResidue()
    }

    static func install(store: Store) throws {
        guard FileManager.default.isExecutableFile(atPath: store.coreBinaryURL.path) else {
            throw NSError.user("请先在 Core 管理中导入或安装 sing-box Core。")
        }
        try? FileManager.default.removeItem(at: store.tunRequestFlagURL)
        try? FileManager.default.removeItem(at: store.tunRequestConfigURL)
        try? FileManager.default.removeItem(at: store.tunRequestHeartbeatURL)
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("\(label).sh")
        try writeServiceScript(store: store, to: tempScript)
        let plist = launchDaemonPlist(scriptPath: scriptPath)
        let tempPlist = FileManager.default.temporaryDirectory.appendingPathComponent("\(label).plist")
        try plist.write(to: tempPlist, atomically: true, encoding: .utf8)
        let command = [
            "launchctl bootout system/\(label) >/dev/null 2>&1 || true",
            "launchctl enable system/\(label) >/dev/null 2>&1 || true",
            "mkdir -p \(shellQuote(installDirectoryPath))",
            "cp \(shellQuote(tempScript.path)) \(shellQuote(scriptPath))",
            "cp \(shellQuote(store.coreBinaryURL.path)) \(shellQuote(corePath))",
            "cp \(shellQuote(tempPlist.path)) \(shellQuote(plistPath))",
            "rm -f \(shellQuote(flagPath)) \(shellQuote(legacyStdoutPath)) \(shellQuote(legacyStderrPath))",
            "touch \(shellQuote(logPath)) \(shellQuote(stdoutPath)) \(shellQuote(stderrPath))",
            "chown root:wheel \(shellQuote(installDirectoryPath)) \(shellQuote(scriptPath)) \(shellQuote(corePath)) \(shellQuote(logPath)) \(shellQuote(stdoutPath)) \(shellQuote(stderrPath)) \(shellQuote(plistPath))",
            "chmod 755 \(shellQuote(installDirectoryPath))",
            "chmod 755 \(shellQuote(scriptPath)) \(shellQuote(corePath))",
            "chmod 644 \(shellQuote(logPath)) \(shellQuote(stdoutPath)) \(shellQuote(stderrPath))",
            "chmod 644 \(shellQuote(plistPath))",
            "xattr -c \(shellQuote(scriptPath)) \(shellQuote(corePath)) \(shellQuote(plistPath)) >/dev/null 2>&1 || true",
            "launchctl bootstrap system \(shellQuote(plistPath))",
            "launchctl enable system/\(label)",
            "launchctl kickstart -k system/\(label) >/dev/null 2>&1 || true",
            "launchctl print system/\(label) >/dev/null"
        ]
        let commandText = command.joined(separator: "\n")
        let result = runAppleScript(commandText)
        try? FileManager.default.removeItem(at: tempScript)
        try? FileManager.default.removeItem(at: tempPlist)
        if result.status != 0 {
            throw NSError.user(result.output.isEmpty ? "安装 TUN 服务失败" : result.output)
        }
    }

    static func uninstall(store: Store) throws {
        try? FileManager.default.removeItem(at: store.tunRequestFlagURL)
        try? FileManager.default.removeItem(at: store.tunRequestConfigURL)
        try? FileManager.default.removeItem(at: store.tunRequestHeartbeatURL)
        let command = [
            "rm -f \(shellQuote(flagPath))",
            stopChildCommand(),
            "launchctl disable system/\(label) >/dev/null 2>&1 || true",
            "launchctl bootout system/\(label) >/dev/null 2>&1 || true",
            "pkill -TERM -f \(shellQuote(scriptPath)) >/dev/null 2>&1 || true",
            "sleep 0.3",
            "pkill -KILL -f \(shellQuote(scriptPath)) >/dev/null 2>&1 || true",
            "rm -f \(shellQuote(plistPath)) \(shellQuote(scriptPath)) \(shellQuote(corePath)) \(shellQuote(configPath)) \(shellQuote(flagPath)) \(shellQuote(pidPath)) \(shellQuote(logPath)) \(shellQuote(stdoutPath)) \(shellQuote(stderrPath)) \(shellQuote(legacyStdoutPath)) \(shellQuote(legacyStderrPath))",
            "rmdir \(shellQuote(installDirectoryPath)) >/dev/null 2>&1 || true"
        ].joined(separator: "; ")
        let result = runAppleScript(command)
        if result.status != 0 {
            throw NSError.user(result.output.isEmpty ? "卸载 TUN 服务失败" : result.output)
        }
    }

    static func reload(store: Store) throws {
        guard status(store: store).isUsable else {
            throw NSError.user("TUN 服务未安装。请先安装 TUN 服务。")
        }
        let command = [
            "launchctl kickstart -k system/\(label) >/dev/null 2>&1",
            "launchctl bootout system/\(label) >/dev/null 2>&1 || true; launchctl bootstrap system \(shellQuote(plistPath)); launchctl enable system/\(label)"
        ].joined(separator: " || ")
        let result = runAppleScript(command)
        if result.status != 0 {
            throw NSError.user(result.output.isEmpty ? "重载 TUN 服务失败" : result.output)
        }
    }

    static func enable(store: Store, configText: String) throws {
        guard status(store: store).isUsable else {
            throw NSError.user("TUN 服务未安装。请先到 设置 > TUN 设置 安装 TUN 服务。")
        }
        try ensureRouteIsSafeToStart(store: store)
        try configText.write(to: store.tunRequestConfigURL, atomically: true, encoding: .utf8)
        refreshRequestHeartbeat(store: store)
        if !FileManager.default.fileExists(atPath: store.tunRequestFlagURL.path) {
            FileManager.default.createFile(atPath: store.tunRequestFlagURL.path, contents: Data())
        }
        refreshRequestHeartbeat(store: store)
        // Wake the daemon immediately so it picks up the flag without polling delay.
        // kickstart on a system daemon needs root but we only write user-owned files,
        // so the daemon polls and picks them up on its next 1s loop iteration.
        // Launchctl kickstart without admin privs will fail → just let the poll loop handle it.
    }

    static func disable(store: Store) throws {
        try? FileManager.default.removeItem(at: store.tunRequestFlagURL)
        try? FileManager.default.removeItem(at: store.tunRequestConfigURL)
        try? FileManager.default.removeItem(at: store.tunRequestHeartbeatURL)
    }

    static func refreshRequestHeartbeat(store: Store) {
        if !FileManager.default.fileExists(atPath: store.tunRequestHeartbeatURL.path) {
            FileManager.default.createFile(atPath: store.tunRequestHeartbeatURL.path, contents: Data())
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: store.tunRequestHeartbeatURL.path)
    }

    private static func requestHeartbeatIsFresh(store: Store) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: store.tunRequestHeartbeatURL.path),
              let modifiedAt = attrs[.modificationDate] as? Date else {
            return false
        }
        return Date().timeIntervalSince(modifiedAt) <= requestHeartbeatTimeout
    }

    static func hasNetworkResidue() -> Bool {
        networkResidueDescription() != nil
    }

    static func networkResidueDescription() -> String? {
        let interfaceNames = runProcessAndGetOutput("/sbin/ifconfig", args: ["-l"])
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
            .filter { $0.hasPrefix("utun") }

        for interface in interfaceNames {
            let ifconfig = runProcessAndGetOutput("/sbin/ifconfig", args: [interface])
            guard ifconfig.contains("inet 172.19.0.1") else { continue }
            return "\(interface) 172.19.0.1"
        }

        let routes = runProcessAndGetOutput("/usr/sbin/netstat", args: ["-rn", "-f", "inet"])
        if routes.contains("172.19.0.1") {
            return "路由表仍包含 172.19.0.1"
        }
        return nil
    }

    private static func ensureRouteIsSafeToStart(store: Store) throws {
        if activeSingBoxPID(store: store) != nil { return }
        guard let detail = externalTunDefaultRouteDescription() else { return }
        throw NSError.user("检测到系统网络已经被其它 TUN/VPN 接管（\(detail)）。为避免影响 Surge 等代理软件，TungBox 暂不启动 TUN。请改用系统代理模式，或先关闭其它 TUN/VPN 后再试。")
    }

    private static func externalTunDefaultRouteDescription() -> String? {
        let route = runProcessAndGetOutput("/sbin/route", args: ["-n", "get", "default"])
        guard let interface = route
            .components(separatedBy: .newlines)
            .compactMap({ line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("interface:") else { return nil }
                return trimmed
                    .replacingOccurrences(of: "interface:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            })
            .first,
            interface.hasPrefix("utun")
        else {
            return nil
        }

        let ifconfig = runProcessAndGetOutput("/sbin/ifconfig", args: [interface])
        guard ifconfig.contains("inet 198.18.") else { return nil }
        let address = firstIPv4Address(in: ifconfig)
        return [interface, address].compactMap { $0 }.joined(separator: " ")
    }

    private static func firstIPv4Address(in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
            if let index = parts.firstIndex(of: "inet"), parts.indices.contains(index + 1) {
                return parts[index + 1]
            }
        }
        return nil
    }

    private static func writeServiceScript(store: Store, to url: URL) throws {
        let script = """
        #!/bin/sh
        CORE=\(shellQuote(corePath))
        CONFIG=\(shellQuote(configPath))
        FLAG=\(shellQuote(flagPath))
        REQUEST_CONFIG=\(shellQuote(store.tunRequestConfigURL.path))
        REQUEST_FLAG=\(shellQuote(store.tunRequestFlagURL.path))
        REQUEST_HEARTBEAT=\(shellQuote(store.tunRequestHeartbeatURL.path))
        PIDFILE=\(shellQuote(pidPath))
        LOG=\(shellQuote(logPath))
        CHILD=""
        SCRIPT_VERSION="2026-06-tun-safe-stop-v8"
        REQUEST_MAX_AGE=30

        is_safe_root_file() {
          path="$1"
          [ -L "$path" ] && return 1
          [ -f "$path" ] || return 1
          [ "$(stat -f '%Su' "$path" 2>/dev/null)" = "root" ] || return 1
          [ -z "$(find "$path" -prune \\( -perm -002 -o -perm -020 \\) -print 2>/dev/null)" ] || return 1
          return 0
        }

        has_request() {
          [ -L "$REQUEST_FLAG" ] && return 1
          [ -L "$REQUEST_CONFIG" ] && return 1
          [ -L "$REQUEST_HEARTBEAT" ] && return 1
          [ -f "$REQUEST_FLAG" ] || return 1
          [ -f "$REQUEST_CONFIG" ] || return 1
          [ -f "$REQUEST_HEARTBEAT" ] || return 1
          heartbeat_mtime="$(stat -f '%m' "$REQUEST_HEARTBEAT" 2>/dev/null || echo 0)"
          now="$(date '+%s')"
          case "$heartbeat_mtime" in ''|*[!0-9]*) return 1 ;; esac
          [ $((now - heartbeat_mtime)) -le "$REQUEST_MAX_AGE" ] || return 1
          return 0
        }

        request_is_stale() {
          [ -f "$REQUEST_FLAG" ] || [ -f "$REQUEST_CONFIG" ] || [ -f "$REQUEST_HEARTBEAT" ] || return 1
          [ -f "$REQUEST_FLAG" ] || return 0
          [ -f "$REQUEST_CONFIG" ] || return 0
          [ -f "$REQUEST_HEARTBEAT" ] || return 0
          heartbeat_mtime="$(stat -f '%m' "$REQUEST_HEARTBEAT" 2>/dev/null || echo 0)"
          now="$(date '+%s')"
          case "$heartbeat_mtime" in ''|*[!0-9]*) return 0 ;; esac
          [ $((now - heartbeat_mtime)) -gt "$REQUEST_MAX_AGE" ]
        }

        route_safe_to_start() {
          iface="$(/sbin/route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
          case "$iface" in
            utun*)
              if /sbin/ifconfig "$iface" 2>/dev/null | grep -q 'inet 198\\.18\\.'; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') refusing TUN start: default route already uses $iface 198.18.x" >> "$LOG"
                return 1
              fi
              ;;
          esac
          return 0
        }

        is_tungbox_tun_interface() {
          ifconfig_text="$(/sbin/ifconfig "$1" 2>/dev/null || true)"
          echo "$ifconfig_text" | grep -Eq 'inet 172\\.19\\.0\\.1'
        }

        has_tungbox_tun_interface() {
          for ifname in $(/sbin/ifconfig -l 2>/dev/null | tr ' ' '\\n' | grep '^utun'); do
            if is_tungbox_tun_interface "$ifname"; then
              return 0
            fi
          done
          return 1
        }

        sync_requested_config() {
          has_request || return 1
          if ! "$CORE" check -c "$REQUEST_CONFIG" >> "$LOG" 2>&1; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') requested TUN config check failed" >> "$LOG"
            return 1
          fi
          cp "$REQUEST_CONFIG" "$CONFIG"
          chown root:wheel "$CONFIG"
          chmod 600 "$CONFIG"
          touch "$FLAG"
          chown root:wheel "$FLAG"
          chmod 600 "$FLAG"
          return 0
        }

        clean_routes() {
          echo "$(date '+%Y-%m-%d %H:%M:%S') cleaning up TUN routes" >> "$LOG"
          cleaned=0
          for ifname in $(/sbin/ifconfig -l 2>/dev/null | tr ' ' '\\n' | grep '^utun'); do
            is_tungbox_tun_interface "$ifname" || continue
            cleaned=1
            /sbin/route -n delete -net 0.0.0.0/1 -ifscope "$ifname" 2>/dev/null || true
            /sbin/route -n delete -net 0.0.0.0/1 -iface "$ifname" 2>/dev/null || true
            /sbin/route -n delete -net 128.0.0.0/1 -ifscope "$ifname" 2>/dev/null || true
            /sbin/route -n delete -net 128.0.0.0/1 -iface "$ifname" 2>/dev/null || true
            /sbin/route -n delete -net default -iface "$ifname" 2>/dev/null || true
          done

          [ "$cleaned" -eq 1 ] || {
            echo "$(date '+%Y-%m-%d %H:%M:%S') route cleanup skipped: no TungBox TUN interface" >> "$LOG"
            return 0
          }

          /usr/sbin/networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | while IFS= read -r svc; do
            case "$svc" in \\**) continue ;; esac
            if /usr/sbin/networksetup -getinfo "$svc" 2>/dev/null | grep -q '^IP address'; then
              /usr/sbin/networksetup -renewdhcp "$svc" 2>/dev/null || true
              break
            fi
          done
          echo "$(date '+%Y-%m-%d %H:%M:%S') route cleanup done" >> "$LOG"
        }

        shutdown_child() {
          if [ -n "$CHILD" ] && kill -0 "$CHILD" >/dev/null 2>&1; then
            # Give sing-box time to clean up routes itself first
            kill -TERM "$CHILD" >/dev/null 2>&1 || true
            sleep 2
            if kill -0 "$CHILD" >/dev/null 2>&1; then
              echo "$(date '+%Y-%m-%d %H:%M:%S') sing-box not exiting, force killing" >> "$LOG"
              kill -KILL "$CHILD" >/dev/null 2>&1 || true
              wait "$CHILD" >/dev/null 2>&1 || true
            else
              wait "$CHILD" >/dev/null 2>&1 || true
            fi
          elif [ -f "$PIDFILE" ]; then
            PID="$(cat "$PIDFILE" 2>/dev/null || true)"
            case "$PID" in
              ''|*[!0-9]*) ;;
              *)
                if kill -0 "$PID" >/dev/null 2>&1; then
                  kill -TERM "$PID" >/dev/null 2>&1 || true
                  sleep 2
                  if kill -0 "$PID" >/dev/null 2>&1; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') stale sing-box not exiting, force killing" >> "$LOG"
                    kill -KILL "$PID" >/dev/null 2>&1 || true
                  fi
                fi
                ;;
            esac
          fi
          clean_routes
          CHILD=""
          rm -f "$PIDFILE"
        }

        cleanup() {
          shutdown_child
          exit 0
        }
        trap cleanup TERM INT

        echo "$(date '+%Y-%m-%d %H:%M:%S') TUN service started" >> "$LOG"
        while true; do
          if ! has_request; then
            if request_is_stale; then
              echo "$(date '+%Y-%m-%d %H:%M:%S') removing stale TUN request" >> "$LOG"
              rm -f "$REQUEST_FLAG" "$REQUEST_CONFIG" "$REQUEST_HEARTBEAT"
            fi
            if [ -f "$FLAG" ] || [ -f "$PIDFILE" ] || has_tungbox_tun_interface; then
              shutdown_child
            fi
            rm -f "$FLAG"
            sleep 1
            continue
          fi

          if ! route_safe_to_start; then
            rm -f "$FLAG" "$PIDFILE" "$REQUEST_FLAG" "$REQUEST_CONFIG" "$REQUEST_HEARTBEAT"
            sleep 2
            continue
          fi

          if sync_requested_config && is_safe_root_file "$FLAG" && is_safe_root_file "$CONFIG" && [ -x "$CORE" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') starting sing-box TUN" >> "$LOG"
            "$CORE" run -c "$CONFIG" >> "$LOG" 2>&1 &
            CHILD=$!
            echo "$CHILD" > "$PIDFILE"
            while kill -0 "$CHILD" >/dev/null 2>&1; do
              if ! has_request; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') stopping sing-box TUN" >> "$LOG"
                rm -f "$FLAG"
                shutdown_child
                break
              fi
              if [ "$REQUEST_CONFIG" -nt "$CONFIG" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') reloading sing-box TUN config" >> "$LOG"
                if sync_requested_config; then
                  shutdown_child
                  break
                fi
              fi
              sleep 1
            done
            rm -f "$PIDFILE"
            CHILD=""
            sleep 1
          else
            rm -f "$PIDFILE"
            sleep 2
          fi
        done
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func launchDaemonPlist(scriptPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>/bin/sh</string>
            <string>\(xmlEscape(scriptPath))</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>\(xmlEscape(stdoutPath))</string>
          <key>StandardErrorPath</key>
          <string>\(xmlEscape(stderrPath))</string>
        </dict>
        </plist>
        """
    }

    private static func installedServiceDefinitionIsCurrent() -> Bool {
        guard let script = try? String(contentsOfFile: scriptPath),
              let plist = try? String(contentsOfFile: plistPath) else {
            return false
        }
        return script.contains(configPath)
            && script.contains(flagPath)
            && script.contains("REQUEST_CONFIG=")
            && script.contains("REQUEST_FLAG=")
            && script.contains("REQUEST_HEARTBEAT=")
            && script.contains("request_is_stale")
            && script.contains("sync_requested_config")
            && script.contains("route_safe_to_start")
            && script.contains("is_tungbox_tun_interface")
            && script.contains("has_tungbox_tun_interface")
            && script.contains("shutdown_child")
            && script.contains("clean_routes")
            && script.contains("2026-06-tun-safe-stop-v8")
            && plist.contains(stdoutPath)
            && plist.contains(stderrPath)
    }

    private static func stopChildCommand() -> String {
        """
        if [ -f \(shellQuote(pidPath)) ]; then PID=$(cat \(shellQuote(pidPath)) 2>/dev/null || true); case "$PID" in ''|*[!0-9]*) ;; *) kill -TERM "$PID" >/dev/null 2>&1 || true; sleep 2; kill -KILL "$PID" >/dev/null 2>&1 || true ;; esac; fi
        for ifname in $(/sbin/ifconfig -l 2>/dev/null | tr ' ' '\\n' | grep '^utun'); do if /sbin/ifconfig "$ifname" 2>/dev/null | grep -Eq 'inet 172\\.19\\.0\\.1'; then /sbin/route -n delete -net 0.0.0.0/1 -ifscope "$ifname" 2>/dev/null || true; /sbin/route -n delete -net 0.0.0.0/1 -iface "$ifname" 2>/dev/null || true; /sbin/route -n delete -net 128.0.0.0/1 -ifscope "$ifname" 2>/dev/null || true; /sbin/route -n delete -net 128.0.0.0/1 -iface "$ifname" 2>/dev/null || true; /sbin/route -n delete -net default -iface "$ifname" 2>/dev/null || true; fi; done
        /usr/sbin/networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | while IFS= read -r svc; do case "$svc" in \\**) continue ;; esac; if /usr/sbin/networksetup -getinfo "$svc" 2>/dev/null | grep -q '^IP address'; then /usr/sbin/networksetup -renewdhcp "$svc" 2>/dev/null || true; break; fi; done
        """
    }

    private static func runAppleScript(_ command: String) -> (status: Int32, output: String) {
        let appleScript = "do shell script \"\(appleScriptString(command))\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (1, error.localizedDescription)
        }
    }

    private static func runProcessAndGetOutput(_ binary: String, args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
