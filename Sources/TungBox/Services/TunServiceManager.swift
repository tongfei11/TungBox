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
}

enum TunServiceManager {
    static let label = "com.tung.tungbox.tun"
    static let installDirectoryPath = "/Library/Application Support/TungBox"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    static let scriptPath = "\(installDirectoryPath)/tun-service.sh"
    static let corePath = "\(installDirectoryPath)/sing-box"
    static let pidPath = "\(installDirectoryPath)/tun-service.pid"
    static let logPath = "\(installDirectoryPath)/tun-service.log"

    static var logURL: URL {
        URL(fileURLWithPath: logPath)
    }

    static func status(store: Store) -> TunServiceStatus {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            return .notInstalled
        }
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return .abnormal("服务脚本缺失")
        }
        guard FileManager.default.isExecutableFile(atPath: corePath) else {
            return .abnormal("Core 路径错误")
        }
        if let pid = activeSingBoxPID(store: store), Darwin.kill(pid, 0) == 0 {
            return .installedRunning
        }
        return .installedIdle
    }

    static func activeSingBoxPID(store: Store) -> Int32? {
        guard let text = try? String(contentsOfFile: pidPath).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(text),
              Darwin.kill(pid, 0) == 0 else {
            return nil
        }
        return pid
    }

    static func install(store: Store) throws {
        guard FileManager.default.isExecutableFile(atPath: store.coreBinaryURL.path) else {
            throw NSError.user("请先在 Core 管理中导入或安装 sing-box Core。")
        }
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("\(label).sh")
        try writeServiceScript(store: store, to: tempScript)
        let plist = launchDaemonPlist(scriptPath: scriptPath)
        let tempPlist = FileManager.default.temporaryDirectory.appendingPathComponent("\(label).plist")
        try plist.write(to: tempPlist, atomically: true, encoding: .utf8)
        let command = [
            "mkdir -p \(shellQuote(installDirectoryPath))",
            "cp \(shellQuote(tempScript.path)) \(shellQuote(scriptPath))",
            "cp \(shellQuote(store.coreBinaryURL.path)) \(shellQuote(corePath))",
            "cp \(shellQuote(tempPlist.path)) \(shellQuote(plistPath))",
            "touch \(shellQuote(logPath))",
            "chown root:wheel \(shellQuote(scriptPath)) \(shellQuote(corePath)) \(shellQuote(logPath)) \(shellQuote(plistPath))",
            "chmod 755 \(shellQuote(installDirectoryPath))",
            "chmod 755 \(shellQuote(scriptPath)) \(shellQuote(corePath))",
            "chmod 644 \(shellQuote(logPath))",
            "chmod 644 \(shellQuote(plistPath))",
            "launchctl bootout system/\(label) >/dev/null 2>&1 || true",
            "launchctl bootstrap system \(shellQuote(plistPath))",
            "launchctl enable system/\(label)"
        ].joined(separator: "; ")
        let result = runAppleScript(command)
        try? FileManager.default.removeItem(at: tempScript)
        try? FileManager.default.removeItem(at: tempPlist)
        if result.status != 0 {
            throw NSError.user(result.output.isEmpty ? "安装 TUN 服务失败" : result.output)
        }
    }

    static func uninstall(store: Store) throws {
        try disable(store: store)
        let command = [
            "launchctl bootout system/\(label) >/dev/null 2>&1 || true",
            "rm -f \(shellQuote(plistPath)) \(shellQuote(scriptPath)) \(shellQuote(corePath)) \(shellQuote(pidPath)) \(shellQuote(logPath))"
        ].joined(separator: "; ")
        let result = runAppleScript(command)
        if result.status != 0 {
            throw NSError.user(result.output.isEmpty ? "卸载 TUN 服务失败" : result.output)
        }
    }

    static func enable(store: Store, configText: String) throws {
        guard status(store: store).isInstalled else {
            throw NSError.user("TUN 服务未安装。请先到 设置 > TUN 设置 安装 TUN 服务。")
        }
        try configText.write(to: store.tunConfigURL, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: store.tunEnabledFlagURL.path, contents: Data(), attributes: nil)
    }

    static func disable(store: Store) throws {
        try? FileManager.default.removeItem(at: store.tunEnabledFlagURL)
    }

    private static func writeServiceScript(store: Store, to url: URL) throws {
        let script = """
        #!/bin/sh
        CORE=\(shellQuote(corePath))
        CONFIG=\(shellQuote(store.tunConfigURL.path))
        FLAG=\(shellQuote(store.tunEnabledFlagURL.path))
        PIDFILE=\(shellQuote(pidPath))
        LOG=\(shellQuote(logPath))
        CHILD=""

        cleanup() {
          if [ -n "$CHILD" ] && kill -0 "$CHILD" >/dev/null 2>&1; then
            kill "$CHILD" >/dev/null 2>&1 || true
            wait "$CHILD" >/dev/null 2>&1 || true
          fi
          rm -f "$PIDFILE"
          exit 0
        }
        trap cleanup TERM INT

        echo "$(date '+%Y-%m-%d %H:%M:%S') TUN service started" >> "$LOG"
        while true; do
          if [ -f "$FLAG" ] && [ -x "$CORE" ] && [ -f "$CONFIG" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') starting sing-box TUN" >> "$LOG"
            "$CORE" run -c "$CONFIG" >> "$LOG" 2>&1 &
            CHILD=$!
            echo "$CHILD" > "$PIDFILE"
            while kill -0 "$CHILD" >/dev/null 2>&1; do
              if [ ! -f "$FLAG" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') stopping sing-box TUN" >> "$LOG"
                kill "$CHILD" >/dev/null 2>&1 || true
                wait "$CHILD" >/dev/null 2>&1 || true
                break
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
          <string>/tmp/\(label).out.log</string>
          <key>StandardErrorPath</key>
          <string>/tmp/\(label).err.log</string>
        </dict>
        </plist>
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
