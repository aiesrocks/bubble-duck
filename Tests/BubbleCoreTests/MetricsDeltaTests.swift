// SPDX-License-Identifier: GPL-2.0-or-later

import Testing
@testable import BubbleCore

@Suite("Metrics Delta")
struct MetricsDeltaTests {
    // MARK: - safeDelta

    @Test("safeDelta returns current - prev for monotonically increasing counter")
    func safeDeltaMonotonic() {
        #expect(MetricsDelta.safeDelta(current: UInt64(100), prev: UInt64(50)) == 50)
    }

    @Test("safeDelta returns 0 when counter is unchanged")
    func safeDeltaUnchanged() {
        #expect(MetricsDelta.safeDelta(current: UInt64(50), prev: UInt64(50)) == 0)
    }

    @Test("safeDelta returns 0 when counter resets backwards (does not trap)")
    func safeDeltaCounterReset() {
        // This is the exact crash scenario from #23: the previous tick
        // saw a large counter; the current tick reads a smaller one
        // because the network interface was reset / disk driver reaped.
        #expect(MetricsDelta.safeDelta(current: UInt64(30), prev: UInt64(80)) == 0)
    }

    @Test("safeDelta handles UInt64 boundary without trapping")
    func safeDeltaAtUInt64Boundary() {
        // current much smaller than prev — would have wrapped to ~UInt64.max
        // with `&-`, then trapped on the subsequent addition. Helper returns 0.
        #expect(MetricsDelta.safeDelta(current: UInt64(0), prev: UInt64.max) == 0)
        // current = max, prev = 0 — straightforward delta of max
        #expect(MetricsDelta.safeDelta(current: UInt64.max, prev: UInt64(0)) == UInt64.max)
    }

    @Test("safeDelta is generic over unsigned integer widths (UInt32 covers CPU ticks)")
    func safeDeltaUInt32() {
        // CPU tick counters are natural_t (UInt32). Same bug shape.
        #expect(MetricsDelta.safeDelta(current: UInt32(10), prev: UInt32(20)) == 0)
        #expect(MetricsDelta.safeDelta(current: UInt32(100), prev: UInt32(20)) == 80)
    }

    // MARK: - rate

    @Test("rate computes (a + b) / elapsed for normal monotonic counters")
    func rateBasic() {
        let r = MetricsDelta.rate(
            currentA: 1_000, prevA: 0,
            currentB: 2_000, prevB: 0,
            elapsed: 1.0
        )
        #expect(r == 3_000)
    }

    @Test("rate is zero on counter reset (does not trap)")
    func rateOnCounterReset() {
        // Both counters went backwards — the original crash scenario.
        let r = MetricsDelta.rate(
            currentA: 0, prevA: 5_000_000,
            currentB: 0, prevB: 8_000_000,
            elapsed: 1.0
        )
        #expect(r == 0)
    }

    @Test("rate is zero when only one counter resets")
    func rateOnPartialReset() {
        // A reset, B continues normally — A contributes 0, B contributes 100.
        let r = MetricsDelta.rate(
            currentA: 0,   prevA: 1_000,
            currentB: 200, prevB: 100,
            elapsed: 1.0
        )
        #expect(r == 100)
    }

    @Test("rate divides by elapsed seconds")
    func rateDividesByElapsed() {
        let r = MetricsDelta.rate(
            currentA: 600, prevA: 0,
            currentB: 0,   prevB: 0,
            elapsed: 2.0
        )
        #expect(r == 300)
    }

    @Test("rate returns 0 when elapsed is zero")
    func rateZeroElapsed() {
        let r = MetricsDelta.rate(
            currentA: 1_000, prevA: 0,
            currentB: 1_000, prevB: 0,
            elapsed: 0
        )
        #expect(r == 0)
    }

    @Test("rate returns 0 when elapsed is negative (defensive)")
    func rateNegativeElapsed() {
        let r = MetricsDelta.rate(
            currentA: 1_000, prevA: 0,
            currentB: 1_000, prevB: 0,
            elapsed: -1.0
        )
        #expect(r == 0)
    }

    @Test("rate handles maximum-value counters without overflow")
    func rateExtremeValues() {
        // Both deltas near UInt64.max — sum in Double space, no overflow.
        let r = MetricsDelta.rate(
            currentA: UInt64.max, prevA: 0,
            currentB: UInt64.max, prevB: 0,
            elapsed: 1.0
        )
        // The value is huge but finite (about 3.7e19) — what matters is
        // we didn't trap. Verify it's positive and finite.
        #expect(r > 0)
        #expect(r.isFinite)
    }
}
