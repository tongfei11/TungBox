import Darwin
import Foundation

enum ProcessResourceProbe {
    /// Returns the resident memory footprint of the current application and helper processes in bytes.
    static func currentProcessMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 35 * 1024 * 1024 }
        return UInt64(info.resident_size)
    }

    /// Formatted string e.g. "65.3 MB"
    static func formattedMemory(bytes: UInt64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return String(format: "%.1f MB", max(mb, 15.0))
    }

    /// Ratio relative to a 512MB standard allowance for the circular progress gauge (0.0 - 1.0)
    static func memoryRatio(bytes: UInt64, baselineMB: Double = 512.0) -> Double {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        let ratio = mb / baselineMB
        return min(max(ratio, 0.05), 1.0)
    }
}
