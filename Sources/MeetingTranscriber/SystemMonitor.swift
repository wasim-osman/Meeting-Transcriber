import Darwin
import IOKit
import Foundation

// Samples process CPU% and system GPU% on a 1.5 s interval while work is running.
@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var cpuPercent: Double = 0   // % per core (100 = 1 full core)
    @Published private(set) var gpuPercent: Double? = nil // 0–100 from IOAccelerator

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cpuPercent = 0
        gpuPercent = nil
    }

    private func refresh() {
        cpuPercent = Self.processCPU()
        gpuPercent = Self.gpuUtilization()
    }

    // ── Process CPU (sum across all threads) ──────────────────────────────────
    // Returns percent where 100 = one full CPU core utilised.
    private static func processCPU() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else { return 0 }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: threads)),
                vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_act_t>.size)
            )
        }

        var total = 0.0
        let flavor = thread_flavor_t(THREAD_BASIC_INFO)
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size
                                               / MemoryLayout<integer_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    thread_info(threads[i], flavor, $0, &count)
                }
            }
            // TH_FLAGS_IDLE = 0x2; TH_USAGE_SCALE = 1000
            if kr == KERN_SUCCESS, (info.flags & 0x2) == 0 {
                total += Double(info.cpu_usage) / 1000.0 * 100.0
            }
        }
        return total
    }

    // ── GPU utilisation via IOKit IOAccelerator ────────────────────────────────
    // Returns 0–100 or nil if no accelerator is found.
    private static func gpuUtilization() -> Double? {
        let matchDict = IOServiceMatching("IOAccelerator")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iter) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iter) }

        var result: Double? = nil
        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service) }
            var propRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propRef,
                                                 kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = propRef?.takeRetainedValue() as? [String: Any],
               let perf  = props["PerformanceStatistics"] as? [String: Any],
               let util  = perf["Device Utilization %"] as? Int {
                result = Double(util)
            }
            service = IOIteratorNext(iter)
        }
        return result
    }
}
