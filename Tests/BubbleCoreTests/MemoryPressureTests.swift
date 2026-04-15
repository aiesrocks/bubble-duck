// SPDX-License-Identifier: GPL-2.0-or-later

import Testing
@testable import BubbleCore

@Suite("Memory Pressure")
struct MemoryPressureTests {
    @Test("tightness is (active + wired + compressed + swap) / total")
    func basicFormula() {
        // 4 + 1 + 0.5 + 0.5 = 6 GB used on 16 GB system
        let t = MemoryPressure.tightness(
            active: 4_000_000_000,
            wired: 1_000_000_000,
            compressed: 500_000_000,
            swapUsed: 500_000_000,
            totalPhysical: 16_000_000_000
        )
        let expected = 6_000_000_000.0 / 16_000_000_000.0
        #expect(abs(t - expected) < 1e-9)
    }

    @Test("empty system is 0.0")
    func emptySystem() {
        let t = MemoryPressure.tightness(
            active: 0, wired: 0, compressed: 0, swapUsed: 0,
            totalPhysical: 16_000_000_000
        )
        #expect(t == 0.0)
    }

    @Test("overcommitted system exceeds 1.0")
    func overcommitted() {
        // Used (15 GB) + swap (5 GB) = 20 GB on 16 GB physical
        let t = MemoryPressure.tightness(
            active: 10_000_000_000,
            wired: 2_000_000_000,
            compressed: 3_000_000_000,
            swapUsed: 5_000_000_000,
            totalPhysical: 16_000_000_000
        )
        #expect(t > 1.0)
    }

    @Test("zero total physical returns 0 (no div-by-zero)")
    func zeroTotal() {
        let t = MemoryPressure.tightness(
            active: 1, wired: 1, compressed: 1, swapUsed: 1,
            totalPhysical: 0
        )
        #expect(t == 0.0)
    }

    @Test("zone classification honors boundary convention")
    func zoneBoundaries() {
        #expect(MemoryPressure.zone(for: 0.0) == .healthy)
        #expect(MemoryPressure.zone(for: 0.5) == .healthy)
        #expect(MemoryPressure.zone(for: 0.6999) == .healthy)
        // 0.70 inclusive → warning
        #expect(MemoryPressure.zone(for: 0.70) == .warning)
        #expect(MemoryPressure.zone(for: 0.85) == .warning)
        // 0.90 inclusive → warning
        #expect(MemoryPressure.zone(for: 0.90) == .warning)
        // > 0.90 → critical
        #expect(MemoryPressure.zone(for: 0.9001) == .critical)
        #expect(MemoryPressure.zone(for: 2.0) == .critical)
    }
}
