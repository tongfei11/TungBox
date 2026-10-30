import CryptoKit
import Foundation
import XCTest
@testable import TungBox

final class CoreAppSessionTests: XCTestCase {
    func testInvalidConfigCleansPrivateRunDirectoryWithoutLaunching() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let binary = root.appendingPathComponent("fixture")
        let config = root.appendingPathComponent("invalid.json")
        let cache = root.appendingPathComponent("cache")
        try Data("not executed".utf8).write(to: binary)
        try Data("invalid JSON".utf8).write(to: config)
        XCTAssertThrowsError(try CoreAppSession.start(binary: binary, config: config,
            workingDirectory: root, cacheDirectory: cache, onOutput: { _ in }, onExit: {}))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cache.path).filter { $0.hasPrefix("run-") }, [])
    }

    func testBundlePreservesExecutableBytesAndRefreshesAfterUpdate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let binary = root.appendingPathComponent("original")
        try Data("first fixture executable".utf8).write(to: binary)
        let cache = root.appendingPathComponent("cache")
        let app = try CoreAppBundle.prepare(binary: binary, directory: cache)
        let copy = app.appendingPathComponent("Contents/MacOS/sing-box")
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: binary))
        try Data("updated fixture executable".utf8).write(to: binary)
        XCTAssertEqual(try CoreAppBundle.prepare(binary: binary, directory: cache), app)
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: binary))
        let permissions = try FileManager.default.attributesOfItem(atPath: cache.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o700)
        let info = try XCTUnwrap(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil
        ) as? [String: Any])
        XCTAssertEqual(info["LSUIElement"] as? Bool, true)
        XCTAssertNotEqual(CoreAppBundle.identifier(in: cache), CoreAppBundle.identifier(in: root))
    }

    func testOfficialCoreAppLaunchMatchesProcessRulesStreamsLogsAndRestarts() throws {
        guard let core = ProcessInfo.processInfo.environment["TUNGBOX_TEST_CORE"] else {
            throw XCTSkip("设置 TUNGBOX_TEST_CORE 可验证官方 Core 后台应用启动；只使用隔离本地端口")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TungBox-CoreApp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // One disposable local HTTP service; it never accesses the Internet.
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-u", "-c", """
        from http.server import HTTPServer,BaseHTTPRequestHandler
        class H(BaseHTTPRequestHandler):
          def do_GET(self):
            self.send_response(200);self.send_header('Content-Length','2');self.end_headers();self.wfile.write(b'OK')
          def log_message(self,*args):pass
        s=HTTPServer(('127.0.0.1',0),H)
        print(s.server_port,flush=True)
        s.serve_forever()
        """]
        let startup = Pipe()
        server.standardOutput = startup
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer { server.terminate(); server.waitUntilExit() }
        let line = String(decoding: startup.fileHandleForReading.availableData, as: UTF8.self)
        let target = try XCTUnwrap(Int(line.trimmingCharacters(in: .whitespacesAndNewlines)))
        let config = root.appendingPathComponent("input.json")
        let cache = root.appendingPathComponent("core-app")
        let sourceHash = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: core)))
        let events = LockedValue("")
        let exits = LockedValue(0)
        // Reserve a random proxy port with Python, without probing any live app ports.
        let reserve = Process()
        reserve.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        reserve.arguments = ["-c", "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()"]
        let portOutput = Pipe()
        reserve.standardOutput = portOutput
        try reserve.run()
        let proxy = try XCTUnwrap(Int(String(decoding: portOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        reserve.waitUntilExit()
        let json: [String: Any] = [
            "log": ["level": "debug", "timestamp": true],
            "inbounds": [["type": "mixed", "tag": "fixture", "listen": "127.0.0.1", "listen_port": proxy]],
            "outbounds": [["type": "direct", "tag": "process-matched"], ["type": "direct", "tag": "fallback"]],
            "route": ["rules": [["process_name": "curl", "outbound": "process-matched"]], "final": "fallback"],
            "experimental": ["cache_file": ["enabled": true]]
        ]
        let original = try ConfigCodec.render(json)
        try original.write(to: config, atomically: true, encoding: .utf8)
        for round in 0..<2 {
            let before = events.get().count
            let session = try CoreAppSession.start(binary: URL(fileURLWithPath: core), config: config,
                workingDirectory: root, cacheDirectory: cache,
                onOutput: { text in events.mutate { $0 += text } },
                onExit: { exits.mutate { $0 += 1 } })
            defer { session.stop() }
            XCTAssertTrue(session.isRunning)
            let deadline = Date().addingTimeInterval(4)
            while !String(events.get().dropFirst(before)).contains("tcp server started"), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            for _ in 0..<3 {
                let client = Process()
                client.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                client.arguments = ["--silent", "--show-error", "--max-time", "3", "--noproxy", "", "--proxy", "http://127.0.0.1:\(proxy)", "http://127.0.0.1:\(target)/"]
                let response = Pipe()
                client.standardOutput = response
                client.standardError = FileHandle.nullDevice
                try client.run()
                let body = response.fileHandleForReading.readDataToEndOfFile()
                client.waitUntilExit()
                XCTAssertEqual(client.terminationStatus, 0)
                XCTAssertEqual(String(decoding: body, as: UTF8.self), "OK")
            }
            session.stop()
            XCTAssertFalse(session.isRunning)
            let logs = String(events.get().dropFirst(before))
            XCTAssertEqual(logs.components(separatedBy: "outbound/direct[process-matched]: outbound connection").count - 1, 3, logs)
            XCTAssertFalse(logs.contains("failed to search process"), logs)
            XCTAssertEqual(exits.get(), round + 1)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cache.path).filter { $0.hasPrefix("run-") }, [])
        }
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("cache.db").path))
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: core))), sourceHash)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: CoreAppBundle.url(in: cache).appendingPathComponent("Contents/MacOS/sing-box"))), sourceHash)
    }
}
