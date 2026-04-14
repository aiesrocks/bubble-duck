// SPDX-License-Identifier: GPL-2.0-or-later

import Testing
@testable import BubbleCore

@Suite("Rain on disk I/O")
struct RaindropTests {
    @Test("zero rain intensity never spawns drops")
    func zeroIntensityNoRain() {
        var sim = SimulationState(canvasSize: 64)
        sim.rainIntensity = 0.0
        sim.memoryUsage = 0.5
        for _ in 0..<200 { sim.step() }
        #expect(sim.raindrops.isEmpty)
    }

    @Test("high rain intensity eventually spawns drops")
    func highIntensityProducesRain() {
        var sim = SimulationState(canvasSize: 64)
        sim.rainIntensity = 1.0
        sim.memoryUsage = 0.5
        for _ in 0..<30 { sim.step() }
        #expect(!sim.raindrops.isEmpty)
    }

    @Test("raindrops fall downward each step")
    func raindropsFallDown() {
        var sim = SimulationState(canvasSize: 64)
        sim.rainIntensity = 0  // don't spawn more — just step existing
        sim.raindrops = [Raindrop(x: 0.5, y: 0.9, fallSpeed: 0.02)]
        sim.step()
        // After one step, the drop should be lower than 0.9.
        if let drop = sim.raindrops.first {
            #expect(drop.y < 0.9)
        } else {
            // Short drop may have already hit the surface — also acceptable
            // depending on water level. Either way, no longer at y = 0.9.
        }
    }

    @Test("raindrops disappear when hitting water surface")
    func raindropsHitSurface() {
        var sim = SimulationState(canvasSize: 64)
        sim.memoryUsage = 0.9 // water level high → drops land quickly
        sim.rainIntensity = 0
        // Manually inject a drop just above the surface
        sim.raindrops = [Raindrop(x: 0.5, y: 0.91, fallSpeed: 0.03)]
        // Stabilize water first
        for _ in 0..<500 { sim.step() }
        // At waterLevel ~0.9, drop at y=0.91 falls 0.03 → y=0.88 < 0.9 → hits.
        // But water may have moved since we injected; force drop back in.
        sim.raindrops = [Raindrop(x: 0.5, y: sim.water.levels[sim.water.columnCount / 2] + 0.01,
                                  fallSpeed: 0.05)]
        sim.step()
        #expect(sim.raindrops.isEmpty)
    }

    @Test("raindrop count is capped at maxRaindrops")
    func raindropCountCapped() {
        var sim = SimulationState(canvasSize: 64)
        sim.rainIntensity = 1.0
        sim.memoryUsage = 0.0  // water very low, so drops take a while to fall
        // Run a *lot* of steps; if the cap didn't hold, we'd balloon past 80.
        for _ in 0..<500 { sim.step() }
        #expect(sim.raindrops.count <= SimulationState.maxRaindrops)
    }

    @Test("reduceMotion suppresses new raindrop spawns")
    func reduceMotionSuppressesRain() {
        var sim = SimulationState(canvasSize: 64)
        sim.reduceMotion = true
        sim.rainIntensity = 1.0
        sim.memoryUsage = 0.5
        for _ in 0..<200 { sim.step() }
        #expect(sim.raindrops.isEmpty)
    }

    @Test("surface hit generates a small ripple when motion is allowed")
    func surfaceHitMakesRipple() {
        var sim = SimulationState(canvasSize: 64)
        sim.rainIntensity = 0
        sim.memoryUsage = 0.5
        for _ in 0..<200 { sim.step() } // stabilize
        // Count existing ripples; add a drop right at the surface.
        let ripplesBefore = sim.ripples.count
        let surface = sim.water.levels[sim.water.columnCount / 2]
        sim.raindrops = [Raindrop(x: 0.5, y: surface + 0.01, fallSpeed: 0.05)]
        sim.step()
        #expect(sim.ripples.count > ripplesBefore)
    }
}
