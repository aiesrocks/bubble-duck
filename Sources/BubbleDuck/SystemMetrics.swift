// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — macOS system metrics collection

import Foundation
import Darwin
import IOKit
import IOKit.ps
import BubbleCore

/// Reads CPU, memory, and swap metrics from macOS kernel APIs.
/// Equivalent to wmbubble's sys_linux.c but using Mach host_statistics.
@MainActor
final class SystemMetrics {
    private var previousCPUInfo: host_cpu_load_info?
    private var cpuSamples: [Double] = []
    private let maxSamples = 16  // matches wmbubble's default sample count

    // Previous readings for delta-based metrics
    private var prevNetBytes: (UInt64, UInt64) = (0, 0)
    private var prevDiskOps: (UInt64, UInt64) = (0, 0)
    private var prevTime: CFAbsoluteTime = 0

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
        // Agent speed metrics
        var networkBytesPerSec: Double = 0   // total in+out bytes/sec
        var diskIOPS: Double = 0             // total read+write ops/sec
        var gpuUtilization: Double = 0       // 0.0...1.0

        // Memory pressure (aiesrocks/bubble-duck#22):
        // (active + wired + compressed + swapUsed) / totalPhysical.
        // Values > 1.0 mean the system is paging. Preferred signal for
        // color-driven "system under stress" indicators since it reflects
        // real-time pressure (unlike raw swapUsage, which doesn't clear).
        var memoryTightness: Double = 0
        var memoryPressureZone: MemoryPressure.Zone = .healthy

        // Battery fraction 0...1 (aiesrocks/bubble-duck#17). nil when the
        // machine has no battery (desktop Mac) so the renderer can skip
        // tinting rather than falling back to some arbitrary default.
        var batteryFraction: Double? = nil
    }

    func read() -> Snapshot {
        let (memUsage, memUsed, memTotal, memComponents) = readMemoryDetailed()
        let (swapUsage, swapUsed, swapTotal) = readSwapDetailed()
        let loadAvgs = readLoadAverages()
        let (netBps, diskOps) = readDeltaMetrics()

        let tightness = MemoryPressure.tightness(
            active: memComponents.active,
            wired: memComponents.wired,
            compressed: memComponents.compressed,
            swapUsed: swapUsed,
            totalPhysical: memTotal
        )

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
            swapTotalBytes: swapTotal,
            networkBytesPerSec: netBps,
            diskIOPS: diskOps,
            gpuUtilization: readGPUUtilization(),
            memoryTightness: tightness,
            memoryPressureZone: MemoryPressure.zone(for: tightness),
            batteryFraction: readBatteryFraction()
        )
    }

    // MARK: - Battery (IOPS power-source info)

    /// Returns the battery's current-capacity fraction (0...1), or `nil` on
    /// desktop Macs with no battery. Reads `IOPSCopyPowerSourcesInfo` —
    /// same API Activity Monitor uses, no entitlements required.
    private func readBatteryFraction() -> Double? {
        guard let infoRef = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return nil
        }
        guard let sourcesRef = IOPSCopyPowerSourcesList(infoRef)?.takeRetainedValue() else {
            return nil
        }
        let sources = sourcesRef as [CFTypeRef]
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(infoRef, source)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }
            // Only count internal batteries — ignore UPS / external sources.
            guard (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else {
                continue
            }
            guard let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let maxCap = desc[kIOPSMaxCapacityKey] as? Int,
                  maxCap > 0 else {
                continue
            }
            return min(1.0, max(0.0, Double(current) / Double(maxCap)))
        }
        return nil
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

        // Use safeDelta so a wrap of natural_t (UInt32) tick counters —
        // possible on long uptimes or sleep/wake cycles — doesn't trap
        // on `current - prev` overflow (aiesrocks/bubble-duck#23).
        let userDelta   = Double(MetricsDelta.safeDelta(current: cpuLoadInfo.cpu_ticks.0, prev: prev.cpu_ticks.0))
        let systemDelta = Double(MetricsDelta.safeDelta(current: cpuLoadInfo.cpu_ticks.1, prev: prev.cpu_ticks.1))
        let idleDelta   = Double(MetricsDelta.safeDelta(current: cpuLoadInfo.cpu_ticks.2, prev: prev.cpu_ticks.2))
        let niceDelta   = Double(MetricsDelta.safeDelta(current: cpuLoadInfo.cpu_ticks.3, prev: prev.cpu_ticks.3))

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

    struct MemoryComponents {
        var active: UInt64
        var wired: UInt64
        var compressed: UInt64
    }

    private func readMemoryDetailed() -> (usage: Double, used: UInt64, total: UInt64, components: MemoryComponents) {
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

        let emptyComponents = MemoryComponents(active: 0, wired: 0, compressed: 0)
        guard result == KERN_SUCCESS else { return (0, 0, 0, emptyComponents) }

        let pageSize = UInt64(vm_kernel_page_size)
        let activeBytes = UInt64(stats.active_count) * pageSize
        let wiredBytes = UInt64(stats.wire_count) * pageSize
        let compressedBytes = UInt64(stats.compressor_page_count) * pageSize

        let totalMemory = ProcessInfo.processInfo.physicalMemory
        guard totalMemory > 0 else { return (0, 0, 0, emptyComponents) }

        let used = activeBytes + wiredBytes + compressedBytes
        let usage = min(1.0, Double(used) / Double(totalMemory))
        let components = MemoryComponents(
            active: activeBytes,
            wired: wiredBytes,
            compressed: compressedBytes
        )
        return (usage, used, totalMemory, components)
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

    // MARK: - Delta-based metrics (network bytes/sec, disk IOPS)

    private func readDeltaMetrics() -> (networkBytesPerSec: Double, diskIOPS: Double) {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = prevTime > 0 ? now - prevTime : 1.0
        defer { prevTime = now }

        // Network bytes/sec — counters can rewind on Wi-Fi reconnect, sleep/
        // wake, or interface reaping under memory pressure (the
        // aiesrocks/bubble-duck#23 crash). MetricsDelta.rate treats a
        // rewind as zero for that tick instead of trapping on UInt64
        // overflow, and computes the delta in Double space so the sum
        // can never overflow.
        let netBytes = readNetworkBytes()
        let netBps = prevNetBytes.0 > 0
            ? MetricsDelta.rate(
                currentA: netBytes.0, prevA: prevNetBytes.0,
                currentB: netBytes.1, prevB: prevNetBytes.1,
                elapsed: elapsed
            )
            : 0
        prevNetBytes = netBytes

        // Disk IOPS — same shape, same vulnerability if a disk driver is
        // reaped between samples.
        let diskOps = readDiskOps()
        let iops = prevDiskOps.0 > 0
            ? MetricsDelta.rate(
                currentA: diskOps.0, prevA: prevDiskOps.0,
                currentB: diskOps.1, prevB: prevDiskOps.1,
                elapsed: elapsed
            )
            : 0
        prevDiskOps = diskOps

        return (netBps, iops)
    }

    // MARK: - Network I/O (cumulative bytes via sysctl NET_RT_IFLIST2)

    private func readNetworkBytes() -> (bytesIn: UInt64, bytesOut: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: Int = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0 else { return (0, 0) }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, UInt32(mib.count), &buf, &len, nil, 0) == 0 else { return (0, 0) }

        var totalIn: UInt64 = 0, totalOut: UInt64 = 0, offset = 0
        while offset < len {
            let msgPtr = buf.withUnsafeBufferPointer {
                UnsafeRawPointer($0.baseAddress! + offset)
            }
            let ifm = msgPtr.assumingMemoryBound(to: if_msghdr2.self).pointee
            if Int32(ifm.ifm_type) == RTM_IFINFO2 {
                totalIn += ifm.ifm_data.ifi_ibytes
                totalOut += ifm.ifm_data.ifi_obytes
            }
            offset += Int(ifm.ifm_msglen)
        }
        return (totalIn, totalOut)
    }

    // MARK: - Disk IOPS (cumulative ops via IOKit IOBlockStorageDriver)

    private func readDiskOps() -> (reads: UInt64, writes: UInt64) {
        var totalReads: UInt64 = 0, totalWrites: UInt64 = 0
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return (0, 0) }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, matching, &iterator
        ) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            guard let props = IORegistryEntryCreateCFProperty(
                service, "Statistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { continue }
            if let r = props["Operations (Read)"] as? UInt64 { totalReads += r }
            if let w = props["Operations (Write)"] as? UInt64 { totalWrites += w }
        }
        return (totalReads, totalWrites)
    }

    // MARK: - GPU Utilization (via IOKit IOAccelerator)

    private func readGPUUtilization() -> Double {
        guard let matching = IOServiceMatching("IOAccelerator") else { return 0 }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, matching, &iterator
        ) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            guard let props = IORegistryEntryCreateCFProperty(
                service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { continue }
            if let util = props["Device Utilization %"] as? Int {
                return Double(util) / 100.0
            }
        }
        return 0
    }
}
