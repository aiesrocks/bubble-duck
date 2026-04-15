// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — counter-aware delta helpers (aiesrocks/bubble-duck#23).
//
// macOS network / disk / CPU counters can move *backwards* between samples:
// Wi-Fi disconnect & reconnect, sleep/wake, drivers being reaped under
// memory pressure, USB devices unplugged mid-enumeration, etc. A naive
// `current - prev` then traps with "arithmetic overflow" the moment that
// happens; the original code in SystemMetrics used `&-` which silently
// wrapped to a near-UInt64.max value and overflowed on the next addition.
//
// `MetricsDelta` provides a single tiny helper that treats counter
// rewinds as "no information this tick" (delta = 0) instead of crashing.

import Foundation

public enum MetricsDelta {
    /// Counter-aware delta. Returns `current - prev` when the counter is
    /// monotonically increasing, or `0` when it has gone backwards (which
    /// indicates a counter reset rather than a real negative delta).
    @inlinable
    public static func safeDelta<T: UnsignedInteger>(current: T, prev: T) -> T {
        current >= prev ? current - prev : 0
    }

    /// Per-second rate from a pair of (current, prev) counters summed
    /// together (e.g. bytes-in + bytes-out, reads + writes), divided by
    /// elapsed seconds. Safe against:
    ///   * Counter rewinds — handled by `safeDelta`
    ///   * Non-positive elapsed — returns 0 instead of dividing by zero
    /// Returns 0 when no useful rate can be computed.
    @inlinable
    public static func rate(
        currentA: UInt64, prevA: UInt64,
        currentB: UInt64, prevB: UInt64,
        elapsed: Double
    ) -> Double {
        guard elapsed > 0 else { return 0 }
        let dA = Double(safeDelta(current: currentA, prev: prevA))
        let dB = Double(safeDelta(current: currentB, prev: prevB))
        return (dA + dB) / elapsed
    }
}
