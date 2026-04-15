// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — minimal metrics reader for the widget extension.
//
// The main-app SystemMetrics lives in the BubbleDuck executable target, so
// the widget can't link against it. This is a small standalone reader that
// covers the subset the widget actually needs (no per-frame CPU delta math,
// no network / disk / GPU — widgets refresh every few minutes and can't
// afford the state needed for delta-based metrics anyway).

#if os(macOS)
import Foundation
import Darwin
import BubbleCore

struct WidgetMetrics {
    /// Reads the current system state and returns a fresh WidgetSnapshot.
    /// Safe to call from anywhere; does a handful of syscalls and returns.
    func read() -> WidgetSnapshot {
        let (memUsage, tightness) = readMemory()
        let swap = readSwap()
        let loadAvg = readLoadAverage()
        // Widgets can't do per-sample CPU delta tracking cleanly, so
        // derive CPU load from the 1-minute load average, clamped. Gives
        // a reasonable "busy-ness" signal for the widget's single-frame use.
        let cpuProxy = min(1.0, max(0.0, loadAvg / Double(ProcessInfo.processInfo.activeProcessorCount)))
        return WidgetSnapshot(
            date: Date(),
            cpuLoad: cpuProxy,
            memoryUsage: memUsage,
            swapUsage: swap,
            loadAverage1: loadAvg,
            memoryTightness: tightness,
            memoryPressureZone: MemoryPressure.zone(for: tightness)
        )
    }

    // MARK: - Memory

    private func readMemory() -> (usage: Double, tightness: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return (0, 0) }
        let used = active + wired + compressed
        let usage = min(1.0, Double(used) / Double(total))

        // Tightness also needs swap used
        let swapUsedBytes: UInt64 = readSwapUsedBytes()
        let tightness = MemoryPressure.tightness(
            active: active,
            wired: wired,
            compressed: compressed,
            swapUsed: swapUsedBytes,
            totalPhysical: total
        )
        return (usage, tightness)
    }

    // MARK: - Swap

    private func readSwap() -> Double {
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)
        guard result == 0, swapUsage.xsu_total > 0 else { return 0 }
        return Double(swapUsage.xsu_used) / Double(swapUsage.xsu_total)
    }

    private func readSwapUsedBytes() -> UInt64 {
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)
        guard result == 0 else { return 0 }
        return swapUsage.xsu_used
    }

    // MARK: - Load average

    private func readLoadAverage() -> Double {
        var loadavg = [Double](repeating: 0, count: 3)
        getloadavg(&loadavg, 3)
        return loadavg[0]
    }
}
#endif
