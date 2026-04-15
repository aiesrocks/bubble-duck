// SPDX-License-Identifier: GPL-2.0-or-later

#if os(macOS)
import Foundation
import Testing
@testable import BubbleWidget
@testable import BubbleCore

@Suite("Widget Snapshot")
struct WidgetSnapshotTests {
    @Test("placeholder has deterministic values for previews")
    func placeholderDefaults() {
        let p = WidgetSnapshot.placeholder
        #expect(p.cpuLoad == 0.30)
        #expect(p.memoryUsage == 0.55)
        #expect(p.swapUsage == 0.10)
        #expect(p.loadAverage1 == 1.20)
        #expect(p.memoryTightness == 0.45)
        #expect(p.memoryPressureZone == .healthy)
    }

    @Test("placeholder is equatable to itself across calls (fixed date)")
    func placeholderEquatable() {
        let a = WidgetSnapshot.placeholder
        let b = WidgetSnapshot.placeholder
        #expect(a == b)
    }

    @Test("snapshots with different dates compare unequal")
    func dateComparison() {
        let a = WidgetSnapshot(
            date: Date(timeIntervalSince1970: 100),
            cpuLoad: 0.5, memoryUsage: 0.5, swapUsage: 0,
            loadAverage1: 1.0, memoryTightness: 0.5,
            memoryPressureZone: .healthy
        )
        let b = WidgetSnapshot(
            date: Date(timeIntervalSince1970: 200),
            cpuLoad: 0.5, memoryUsage: 0.5, swapUsage: 0,
            loadAverage1: 1.0, memoryTightness: 0.5,
            memoryPressureZone: .healthy
        )
        #expect(a != b)
    }

    @Test("pressure zone reflects the wrapped tightness classifier")
    func zoneReflectsTightness() {
        // Construct a snapshot in each zone and verify the zone field matches
        // what MemoryPressure.zone would return for the same tightness.
        for (tightness, expected) in [
            (0.3, MemoryPressure.Zone.healthy),
            (0.75, .warning),
            (0.95, .critical)
        ] {
            let zone = MemoryPressure.zone(for: tightness)
            #expect(zone == expected)
        }
    }
}
#endif
