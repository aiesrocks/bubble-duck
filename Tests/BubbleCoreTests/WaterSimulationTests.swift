// SPDX-License-Identifier: GPL-2.0-or-later

import Testing
@testable import BubbleCore

@Suite("Water Simulation")
struct WaterSimulationTests {
    @Test("Water level converges to target")
    func waterConvergesToTarget() {
        var water = WaterSimulation(columnCount: 16)
        water.targetLevel = 0.8

        // Run many steps
        for _ in 0..<500 {
            water.step()
        }

        // All columns should be near target
        for level in water.levels {
            #expect(abs(level - 0.8) < 0.05)
        }
    }

    @Test("Displacement creates ripple")
    func displacementCreatesRipple() {
        var water = WaterSimulation(columnCount: 16)
        water.targetLevel = 0.5

        // Stabilize
        for _ in 0..<200 { water.step() }

        // Displace center column
        water.displace(column: 8, amount: 0.1)
        water.step()

        // Center should differ from neighbors
        let center = water.levels[8]
        let neighbor = water.levels[6]
        #expect(center != neighbor)
    }
}

@Suite("Bubble System")
struct BubbleSystemTests {
    @Test("No bubbles spawn at zero CPU")
    func noBubblesAtZeroCPU() {
        var system = BubbleSystem()
        for _ in 0..<100 {
            system.maybeSpawn(cpuLoad: 0.0, columnCount: 64)
        }
        #expect(system.bubbles.isEmpty)
    }

    @Test("Bubbles spawn at full CPU")
    func bubblesSpawnAtFullCPU() {
        var system = BubbleSystem()
        for _ in 0..<10 {
            system.maybeSpawn(cpuLoad: 1.0, columnCount: 64)
        }
        #expect(!system.bubbles.isEmpty)
    }

    @Test("Respects max bubbles")
    func respectsMaxBubbles() {
        var system = BubbleSystem()
        system.maxBubbles = 5
        for _ in 0..<100 {
            system.maybeSpawn(cpuLoad: 1.0, columnCount: 64)
        }
        #expect(system.bubbles.count <= 5)
    }

    @Test("spawnBurst adds the requested number of bubbles when space exists")
    func burstAddsRequestedCount() {
        var system = BubbleSystem()
        let before = system.bubbles.count
        let added = system.spawnBurst(x: 0.5, nearSurface: 0.5, count: 3)
        #expect(added == 3)
        #expect(system.bubbles.count == before + 3)
    }

    @Test("spawnBurst respects maxBubbles cap")
    func burstRespectsMaxBubbles() {
        var system = BubbleSystem()
        system.maxBubbles = 4
        // Pre-fill to 3
        _ = system.spawnBurst(x: 0.5, nearSurface: 0.5, count: 3)
        #expect(system.bubbles.count == 3)
        // Request 5 more — should only add 1 more (to reach cap of 4)
        let added = system.spawnBurst(x: 0.5, nearSurface: 0.5, count: 5)
        #expect(added == 1)
        #expect(system.bubbles.count == 4)
    }

    @Test("spawnBurst at full tank adds nothing")
    func burstAtFullTankAddsNothing() {
        var system = BubbleSystem()
        system.maxBubbles = 2
        _ = system.spawnBurst(x: 0.5, nearSurface: 0.5, count: 2)
        let added = system.spawnBurst(x: 0.5, nearSurface: 0.5, count: 3)
        #expect(added == 0)
    }
}
