// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — macOS system metrics collection

import Foundation
import Darwin

/// Reads CPU, memory, and swap metrics from macOS kernel APIs.
/// Equivalent to wmbubble's sys_linux.c but using Mach host_statistics.
@MainActor
final class SystemMetrics {
    private var previousCPUInfo: host_cpu_load_info?
    private var cpuSamples: [Double] = []
    private let maxSamples = 16  // matches wmbubble's default sample count

    struct Snapshot: Sendable {
        var cpuLoad: Double      // 0.0...1.0
        var memoryUsage: Double  // 0.0...1.0
        var swapUsage: Double    // 0.0...1.0
        var loadAverage1: Double = 0.0
        var loadAverage5: Double = 0.0
        var loadAverage15: Double = 0.0
        var memoryUsedBytes: UInt64 = 0
        var memoryTotalBytes: UInt64 = 0
        var swapUsedBytes: UInt64 = 0
        var swapTotalBytes: UInt64 = 0
    }

    func read() -> Snapshot {
        let (memUsage, memUsed, memTotal) = readMemoryDetailed()
        let (swapUsage, swapUsed, swapTotal) = readSwapDetailed()
        let loadAvgs = readLoadAverages()
        return Snapshot(
            cpuLoad: readCPU(),
            memoryUsage: memUsage,
            swapUsage: swapUsage,
            loadAverage1: loadAvgs.0,
            loadAverage5: loadAvgs.1,
            loadAverage15: loadAvgs.2,
            memoryUsedBytes: memUsed,
            memoryTotalBytes: memTotal,
            swapUsedBytes: swapUsed,
            swapTotalBytes: swapTotal
        )
    }

    // MARK: - CPU (from host_statistics, like wmbubble reads /proc/stat)

    private func readCPU() -> Double {
        var cpuLoadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(
                    mach_host_self(),
                    HOST_CPU_LOAD_INFO,
                    intPtr,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        defer { previousCPUInfo = cpuLoadInfo }

        guard let prev = previousCPUInfo else { return 0 }

        let userDelta = Double(cpuLoadInfo.cpu_ticks.0 - prev.cpu_ticks.0)
        let systemDelta = Double(cpuLoadInfo.cpu_ticks.1 - prev.cpu_ticks.1)
        let idleDelta = Double(cpuLoadInfo.cpu_ticks.2 - prev.cpu_ticks.2)
        let niceDelta = Double(cpuLoadInfo.cpu_ticks.3 - prev.cpu_ticks.3)

        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
        guard totalDelta > 0 else { return 0 }

        let activeDelta = userDelta + systemDelta + niceDelta
        let instantCPU = activeDelta / totalDelta

        // Rolling average like wmbubble's sample buffer
        cpuSamples.append(instantCPU)
        if cpuSamples.count > maxSamples {
            cpuSamples.removeFirst()
        }

        return cpuSamples.reduce(0, +) / Double(cpuSamples.count)
    }

    // MARK: - Load Averages (like wmbubble reads /proc/loadavg)

    private func readLoadAverages() -> (Double, Double, Double) {
        var loadavg = [Double](repeating: 0, count: 3)
        getloadavg(&loadavg, 3)
        return (loadavg[0], loadavg[1], loadavg[2])
    }

    // MARK: - Memory (from vm_statistics64, like wmbubble reads /proc/meminfo)

    private func readMemoryDetailed() -> (usage: Double, used: UInt64, total: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    intPtr,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return (0, 0, 0) }

        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize

        let totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        guard totalMemory > 0 else { return (0, 0, 0) }

        let used = active + wired + compressed
        return (min(1.0, used / totalMemory), UInt64(used), UInt64(totalMemory))
    }

    // MARK: - Swap (from sysctl, macOS equivalent)

    private func readSwapDetailed() -> (usage: Double, used: UInt64, total: UInt64) {
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)
        guard result == 0 else { return (0, 0, 0) }
        guard swapUsage.xsu_total > 0 else { return (0, 0, 0) }
        return (Double(swapUsage.xsu_used) / Double(swapUsage.xsu_total),
                swapUsage.xsu_used, swapUsage.xsu_total)
    }
}
