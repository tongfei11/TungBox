import AppKit
import CryptoKit
import Darwin
import Foundation

/// macOS 27 can hide the PCB table from a GUI app's CLI children. Launch the
/// original executable as a background application instead, using Launch Services.
/// Its bytes/signature are preserved; no entitlement or elevated service is added.
enum CoreAppBundle {
    static let executableName = "sing-box"

    static func url(in directory: URL) -> URL {
        directory.appendingPathComponent("CoreRuntime.app", isDirectory: true)
    }

    static func identifier(in directory: URL) -> String {
        let digest = SHA256.hash(data: Data(directory.standardizedFileURL.path.utf8))
        return "com.tung.tungbox.core." + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func prepare(binary: URL, directory: URL) throws -> URL {
        let manager = FileManager.default
        let app = url(in: directory)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let executables = contents.appendingPathComponent("MacOS", isDirectory: true)
        try manager.createDirectory(at: executables, withIntermediateDirectories: true)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let destination = executables.appendingPathComponent(executableName)
        let original = try Data(contentsOf: binary, options: .mappedIfSafe)
        let digest = SHA256.hash(data: original)
        let cached = try? Data(contentsOf: destination, options: .mappedIfSafe)
        if cached.map({ SHA256.hash(data: $0) != digest }) ?? true {
            let temporary = executables.appendingPathComponent(".core-\(UUID().uuidString)")
            defer { try? manager.removeItem(at: temporary) }
            try manager.copyItem(at: binary.resolvingSymlinksInPath(), to: temporary)
            let copied = try Data(contentsOf: temporary, options: .mappedIfSafe)
            guard SHA256.hash(data: copied) == digest else { throw NSError.user("后台 Core 复制校验失败") }
            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: destination)
            }
        }
        // Changing the executable's mode does not alter its code signature.
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        let info: [String: Any] = [
            "CFBundleIdentifier": identifier(in: directory),
            "CFBundleExecutable": executableName,
            "CFBundleName": "TungBox Core",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
            "LSUIElement": true,
            "LSMinimumSystemVersion": "13.0",
            "NSLocalNetworkUsageDescription": "TungBox Core 需要连接本地代理、DNS 和局域网服务。"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        return app
    }
}

/// A private FIFO transports Core logs without an ever-growing intermediate file.
private final class CoreLogFIFO: @unchecked Sendable {
    let url: URL
    private let descriptor: Int32
    private let source: DispatchSourceRead
    private let queue = DispatchQueue(label: "com.tungbox.core-app-log")
    private var pending = Data()
    private let onOutput: @Sendable (String) -> Void
    private let closed = LockedValue(false)

    init(url: URL, onOutput: @escaping @Sendable (String) -> Void) throws {
        self.url = url
        self.onOutput = onOutput
        guard mkfifo(url.path, 0o600) == 0 else { throw NSError.user("无法建立后台 Core 日志管道：\(errno)") }
        // Hold both ends to avoid EOF while Launch Services is starting the writer.
        let fd = Darwin.open(url.path, O_RDWR | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            try? FileManager.default.removeItem(at: url)
            throw NSError.user("无法读取后台 Core 日志管道：\(errno)")
        }
        descriptor = fd
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
    }

    private func drain() {
        var bytes = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            guard count > 0 else { break }
            pending.append(contentsOf: bytes.prefix(count))
            if let end = pending.lastIndex(of: 0x0a) {
                let length = pending.distance(from: pending.startIndex, to: end) + 1
                onOutput(String(decoding: pending.prefix(length), as: UTF8.self))
                pending.removeFirst(length)
            }
            if pending.count > 200_000 {
                onOutput(String(decoding: pending, as: UTF8.self))
                pending.removeAll(keepingCapacity: true)
            }
        }
    }

    func finish() {
        var first = false
        closed.mutate { value in
            guard !value else { return }
            value = true
            first = true
        }
        guard first else { return }
        queue.sync {
            drain()
            if !pending.isEmpty { onOutput(String(decoding: pending, as: UTF8.self)) }
            pending.removeAll()
            source.cancel()
        }
        try? FileManager.default.removeItem(at: url)
    }

    deinit { finish() }
}

final class CoreAppSession: @unchecked Sendable {
    private let application: NSRunningApplication
    private let launcher: Process
    private let logPipe: CoreLogFIFO
    private let runDirectory: URL
    private let finished = LockedValue(false)
    private let onExit: @Sendable () -> Void

    var pid: Int32 { application.processIdentifier }
    var isRunning: Bool {
        guard !finished.get(), !application.isTerminated else { return false }
        // NSRunningApplication termination notifications depend on the main run
        // loop. Runtime handoff must wait for the process itself off that thread.
        return Darwin.kill(pid, 0) == 0 || errno == EPERM
    }

    private init(application: NSRunningApplication, launcher: Process, logPipe: CoreLogFIFO,
                 runDirectory: URL, onExit: @escaping @Sendable () -> Void) {
        self.application = application
        self.launcher = launcher
        self.logPipe = logPipe
        self.runDirectory = runDirectory
        self.onExit = onExit
    }

    static func start(binary: URL, config: URL, workingDirectory: URL, cacheDirectory: URL,
                      onOutput: @escaping @Sendable (String) -> Void,
                      onExit: @escaping @Sendable () -> Void) throws -> CoreAppSession {
        let manager = FileManager.default
        let app = try CoreAppBundle.prepare(binary: binary, directory: cacheDirectory)
        let run = cacheDirectory.appendingPathComponent("run-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: run, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var didStart = false
        defer { if !didStart { try? manager.removeItem(at: run) } }
        let pipe = try CoreLogFIFO(url: run.appendingPathComponent("core-log.fifo"), onOutput: onOutput)
        defer { if !didStart { pipe.finish() } }
        guard var json = ConfigCodec.parseObject(from: try String(contentsOf: config, encoding: .utf8)) else {
            pipe.finish()
            throw NSError.user("后台 Core 配置不是有效 JSON")
        }
        var log = json["log"] as? [String: Any] ?? [:]
        log["output"] = pipe.url.path
        json["log"] = log
        let runtime = run.appendingPathComponent("config.json")
        try ConfigCodec.render(json).write(to: runtime, atomically: true, encoding: .utf8)
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launcher.arguments = ["-g", "-n", "-W", "--stdout", pipe.url.path, "--stderr", pipe.url.path,
                              "--env", "ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true",
                              app.path, "--args", "-D", workingDirectory.path, "run", "-c", runtime.path]
        launcher.standardOutput = FileHandle.nullDevice
        launcher.standardError = FileHandle.nullDevice
        try launcher.run()
        let deadline = Date().addingTimeInterval(5)
        let identifier = CoreAppBundle.identifier(in: cacheDirectory)
        var application: NSRunningApplication?
        while Date() < deadline, launcher.isRunning {
            application = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .first {
                    !$0.isTerminated && Darwin.kill($0.processIdentifier, 0) == 0
                        && $0.bundleURL?.resolvingSymlinksInPath() == app.resolvingSymlinksInPath()
                }
            if application != nil { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard let application else {
            launcher.terminate()
            pipe.finish()
            throw NSError.user("后台 Core 应用未能启动，请检查官方 Core 文件和系统启动提示")
        }
        let session = CoreAppSession(application: application, launcher: launcher, logPipe: pipe, runDirectory: run, onExit: onExit)
        launcher.terminationHandler = { [weak session] _ in session?.finish() }
        didStart = true
        if !launcher.isRunning { session.finish() }
        return session
    }

    @discardableResult
    func stop() -> Bool {
        if isRunning {
            Darwin.kill(pid, SIGTERM)
            waitForExit(timeout: 0.6)
            if isRunning {
                Darwin.kill(pid, SIGKILL)
                waitForExit(timeout: 1.5)
            }
        }
        // Keep the FIFO, config and control handle if the kernel has not yet
        // completed termination. A later stop/exit notification can finish it.
        guard !isRunning else { return false }
        finish()
        return true
    }

    private func waitForExit(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    }

    private func finish() {
        var first = false
        finished.mutate { value in
            guard !value else { return }
            value = true
            first = true
        }
        guard first else { return }
        logPipe.finish()
        try? FileManager.default.removeItem(at: runDirectory)
        onExit()
    }

    deinit { stop() }
}
