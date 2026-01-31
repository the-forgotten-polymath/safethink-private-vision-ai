import Foundation
import os

final class MemoryMonitor {
    static let shared = MemoryMonitor()

    private let logger = Logger(subsystem: "com.safethink", category: "memory")

    private init() {}

    var usedMemoryMB: Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576
    }

    var totalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    var memoryPressure: MemoryPressureLevel {
        let used = usedMemoryMB
        let total = totalMemoryGB * 1024
        let ratio = used / total

        if ratio > 0.8 { return .critical }
        if ratio > 0.65 { return .warning }
        return .normal
    }

    enum MemoryPressureLevel {
        case normal
        case warning
        case critical
    }

    func logMemoryUsage() {
        logger.info("Memory: \(self.usedMemoryMB, format: .fixed(precision: 1))MB / \(self.totalMemoryGB, format: .fixed(precision: 1))GB")
    }
}
