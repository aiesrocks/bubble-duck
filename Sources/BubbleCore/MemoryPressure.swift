// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — platform-free memory-pressure formulas

import Foundation

/// Pure memory-pressure calculations, kept platform-free so they're
/// testable without a Mac. Called from `SystemMetrics` on the macOS side
/// with values pulled from `vm_statistics64` + `vm.swapusage` + physical RAM.
///
/// Rationale (see aiesrocks/bubble-duck#22): raw `swap_used / swap_total` is
/// a poor real-time signal on macOS because swap doesn't clear until reboot,
/// making it a "lifetime swap used" metric rather than "how stressed are we
/// right now". A tightness ratio `(used + swap) / total` better reflects
/// actual memory pressure, and matches the shape of what Activity Monitor's
/// "Memory Pressure" graph shows.
public enum MemoryPressure {
    /// Memory tightness as a continuous 0...(>1) ratio.
    /// Page cache / purgeable pages are deliberately excluded — they're
    /// freeable under pressure, so counting them as "used" would produce
    /// false warnings. Matches the convention of Activity Monitor, top, vm_stat.
    ///
    /// Values > 1.0 indicate the system is using more memory than physical
    /// RAM (via compression + swap) — i.e., paging is actively happening.
    public static func tightness(
        active: UInt64,
        wired: UInt64,
        compressed: UInt64,
        swapUsed: UInt64,
        totalPhysical: UInt64
    ) -> Double {
        guard totalPhysical > 0 else { return 0 }
        let used = active &+ wired &+ compressed &+ swapUsed
        return Double(used) / Double(totalPhysical)
    }

    /// Named bands for the color gradient / overlay text.
    public enum Zone: Sendable, Equatable {
        case healthy    // tightness < 0.70
        case warning    // 0.70 <= tightness <= 0.90
        case critical   // tightness > 0.90
    }

    public static func zone(for tightness: Double) -> Zone {
        if tightness > 0.90 { return .critical }
        if tightness >= 0.70 { return .warning }
        return .healthy
    }
}
