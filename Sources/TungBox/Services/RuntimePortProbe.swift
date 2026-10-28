import Darwin
import Foundation

/// Blocking port probes and existing holder cleanup. Runtime scheduling and
/// startup retries remain with the caller; tests replace every OS operation.
struct RuntimePortProbe: Sendable {
    enum BindResult: Equatable, Sendable {
        case available
        case socketFailure(Int32)
        case bindFailure(Int32)

        var isAvailable: Bool { self == .available }

        func description(port: Int) -> String {
            switch self {
            case .available: return "\(port): 可 bind"
            case .socketFailure(let code):
                return "\(port): socket() 失败 errno=\(code)(\(String(cString: strerror(code))))"
            case .bindFailure(let code):
                return "\(port): bind 失败 errno=\(code)(\(String(cString: strerror(code))))"
            }
        }
    }

    struct Operations: Sendable {
        let connect: @Sendable (Int) -> Bool
        let bind: @Sendable (Int) -> BindResult
        let command: @Sendable (String, [String], TimeInterval) -> String
        let signal: @Sendable (Int32, Int32) -> Int32
        let currentPID: @Sendable () -> Int32
        let now: @Sendable () -> Date
        let sleep: @Sendable (TimeInterval) -> Void
    }

    private let operations: Operations

    init() {
        self.init(operations: Operations(
            connect: Self.connectLocalTCPPort,
            bind: Self.bindLocalTCPPort,
            command: { SystemCommand.run($0, args: $1, timeoutSeconds: $2) },
            signal: { Darwin.kill($0, $1) },
            currentPID: { getpid() },
            now: { Date() },
            sleep: { Thread.sleep(forTimeInterval: $0) }
        ))
    }

    init(operations: Operations) { self.operations = operations }

    func waitForLocalTCPPortFree(_ port: Int, timeout: TimeInterval) -> Bool {
        let deadline = operations.now().addingTimeInterval(timeout)
        while operations.now() < deadline {
            if !canConnectLocalTCPPort(port) {
                return true
            }
            operations.sleep(0.1)
        }
        return !canConnectLocalTCPPort(port)
    }

    func waitForLocalTCPPortsFree(_ ports: [Int], timeout: TimeInterval) -> Bool {
        let deadline = operations.now().addingTimeInterval(timeout)
        while operations.now() < deadline {
            if ports.allSatisfy({ canBindLocalTCPPort($0) }) {
                return true
            }
            operations.sleep(0.1)
        }
        return ports.allSatisfy { canBindLocalTCPPort($0) }
    }

    func canBindLocalTCPPort(_ port: Int) -> Bool {
        operations.bind(port).isAvailable
    }

    func bindFailureReason(_ port: Int) -> String {
        operations.bind(port).description(port: port)
    }

    func killSingBoxHoldersOfPorts(_ ports: [Int]) {
        for port in ports {
            // NO `-sTCP:LISTEN` filter: a sing-box that bound the port but FATAL'd
            // before listen() (or is mid-exit) still HOLDS the bound socket and
            // causes EADDRINUSE, yet shows no LISTEN state. Match any TCP socket on
            // the port; we only kill processes whose command is sing-box.
            let pidList = operations.command("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-t"], 2)
            for token in pidList.split(whereSeparator: { $0 == "\n" || $0 == " " || $0 == "\t" }) {
                guard let pid = Int32(token) else { continue }
                let cmd = operations.command("/bin/ps", ["-p", "\(pid)", "-o", "command="], 2)
                guard cmd.contains("sing-box") else { continue }
                _ = operations.signal(pid, SIGKILL)
            }
        }
    }

    func portHoldersDescription(_ ports: [Int]) -> String {
        var holders: [String] = []
        for port in ports {
            let out = operations.command("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)"], 2)
            for line in out.split(separator: "\n").dropFirst().prefix(3) {
                let cols = line.split(separator: " ", omittingEmptySubsequences: true)
                if cols.count >= 3 {
                    holders.append("\(port):\(cols[0])(pid \(cols[1]),uid \(cols[2]))")
                }
            }
        }
        let reasons = ports.map { bindFailureReason($0) }.joined(separator: ", ")
        // Our own open file-descriptor count — to catch fd exhaustion (EMFILE).
        let myFD = operations.command("/usr/sbin/lsof", ["-p", "\(operations.currentPID())"], 2)
            .split(separator: "\n").count
        let who = holders.isEmpty ? "无监听者" : holders.joined(separator: "; ")
        return "\(who)；bind 探测=[\(reasons)]；本进程fd=\(myFD)"
    }

    func waitForLocalTCPPort(_ port: Int, timeout: TimeInterval) -> Bool {
        let deadline = operations.now().addingTimeInterval(timeout)
        while operations.now() < deadline {
            if canConnectLocalTCPPort(port) {
                return true
            }
            operations.sleep(0.1)
        }
        return false
    }

    func canConnectLocalTCPPort(_ port: Int) -> Bool {
        operations.connect(port)
    }

    // Preserve IPv4 loopback probing and SO_REUSEADDR, matching the existing gate.
    private static func bindLocalTCPPort(_ port: Int) -> BindResult {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 {
            let e = errno
            return .socketFailure(e)
        }
        defer { Darwin.close(fd) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let rc = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc == 0 { return .available }
        let e = errno
        return .bindFailure(e)
    }

    private static func connectLocalTCPPort(_ port: Int) -> Bool {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
