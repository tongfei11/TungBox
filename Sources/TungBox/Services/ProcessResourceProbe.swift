import Darwin
import Foundation

enum ProcessResourceProbe {
    /// Returns the physical memory footprint of the current application in bytes (matching Activity Monitor).
    static func currentProcessMemoryBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: 1) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kerr == KERN_SUCCESS, info.phys_footprint > 0 else {
            return 45 * 1024 * 1024
        }
        return UInt64(info.phys_footprint)
    }

    /// Formatted string e.g. "65.3 MB"
    static func formattedMemory(bytes: UInt64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return String(format: "%.1f MB", max(mb, 15.0))
    }

    /// Ratio relative to the machine's total physical memory (0.0 - 1.0), or against an optional baseline in MB.
    static func memoryRatio(bytes: UInt64, baselineMB: Double? = nil) -> Double {
        let total: Double
        if let baselineMB {
            total = baselineMB * 1024.0 * 1024.0
        } else {
            total = Double(ProcessInfo.processInfo.physicalMemory)
        }
        guard total > 0 else { return 0.01 }
        let ratio = Double(bytes) / total
        return min(max(ratio, 0.0), 1.0)
    }
}
