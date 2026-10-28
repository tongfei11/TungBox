import Darwin
import Foundation

/// The existing bounded subprocess execution, shared by system operations.
enum SystemCommand {
    static func run(_ binary: String, args: [String], timeoutSeconds: TimeInterval = 3) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
        } catch {
            return error.localizedDescription
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            proc.waitUntilExit()
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            if proc.isRunning {
                proc.terminate()
                Thread.sleep(forTimeInterval: 0.2)
                if proc.isRunning {
                    _ = Darwin.kill(proc.processIdentifier, SIGKILL)
                }
            }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
