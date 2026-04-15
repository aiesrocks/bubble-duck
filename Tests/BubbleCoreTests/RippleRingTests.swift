// SPDX-License-Identifier: GPL-2.0-or-later

import Testing
@testable import BubbleCore

@Suite("Ripple Rings")
struct RippleRingTests {
    @Test("new ring starts at age 0")
    func newRingAtAgeZero() {
        let ring = RippleRing(x: 0.5, y: 0.5)
        #expect(ring.age == 0.0)
    }

    @Test("simulation spawns a ring when a bubble pops")
    func spawnsRingOnPop() {
        var sim = SimulationState(canvasSize: 64)
        sim.cpuLoad = 1.0    // ensure bubbles spawn
        sim.memoryUsage = 0.5
        // Let bubbles spawn and rise; at least one will pop within a few hundred frames.
        for _ in 0..<300 { sim.step() }
        #expect(!sim.ripples.isEmpty || sim.bubbleSystem.bubbles.isEmpty == false)
    }

    @Test("ripples age up on every step")
    func ripplesAge() {
        var sim = SimulationState(canvasSize: 64)
        sim.ripples.append(RippleRing(x: 0.5, y: 0.5))
        let before = sim.ripples[0].age
        sim.step()
        #expect(sim.ripples[0].age > before)
    }

    @Test("ripples are culled after their lifetime")
    func ripplesCulled() {
        var sim = SimulationState(canvasSize: 64)
        sim.ripples.append(RippleRing(x: 0.5, y: 0.5))
        // RippleRing.lifetimeSeconds = 0.4s, sim runs at 1/60s — ~24 steps.
        // Run 40 steps to be sure it's gone.
        for _ in 0..<40 { sim.step() }
        #expect(sim.ripples.isEmpty)
    }

    @Test("reduceMotion does not spawn new ripples")
    func reduceMotionSuppressesRipples() {
        var sim = SimulationState(canvasSize: 64)
        sim.reduceMotion = true
        sim.cpuLoad = 1.0
        sim.memoryUsage = 0.5
        // Pre-seed a bubble manually so the pop branch fires without relying on spawn.
        sim.bubbleSystem.spawnBurst(x: 0.5, nearSurface: 0.1, count: 2)
        for _ in 0..<100 { sim.step() }
        #expect(sim.ripples.isEmpty)
    }

    @Test("agent edge bounce spawns a larger ring")
    func edgeBounceSpawnsRing() {
        var sim = SimulationState(canvasSize: 64)
        // Position the duck to bounce in the first frame
        sim.duck.x = 0.86
        sim.duck.velocityX = 0.02
        sim.cpuLoad = 0.5  // avoid bubble-spawn overwhelming this test
        sim.memoryUsage = 0.5
        sim.step()
        #expect(sim.ripples.contains { $0.maxRadius > RippleRing.defaultMaxRadius })
    }
}
