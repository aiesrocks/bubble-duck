// SPDX-License-Identifier: GPL-2.0-or-later

import Testing
@testable import BubbleCore

@Suite("Simulation State")
struct SimulationStateTests {
    @Test("stepping many frames does not crash")
    func stepDoesNotCrash() {
        var sim = SimulationState(canvasSize: 64)
        sim.cpuLoad = 0.5
        sim.memoryUsage = 0.7
        sim.swapUsage = 0.1
        for _ in 0..<200 { sim.step() }
    }

    @Test("water target follows memory usage")
    func waterTargetFollowsMemory() {
        var sim = SimulationState(canvasSize: 64)
        sim.memoryUsage = 0.75
        sim.step()
        #expect(sim.water.targetLevel == 0.75)
    }

    @Test("column count is canvasSize / 4")
    func canvasSizeColumnCount() {
        let sim = SimulationState(canvasSize: 256)
        #expect(sim.water.columnCount == 64)
    }

    @Test("full CPU eventually spawns bubbles")
    func highCPUProducesBubbles() {
        var sim = SimulationState(canvasSize: 64)
        sim.cpuLoad = 1.0
        sim.memoryUsage = 0.5
        // CPU=1.0 means every step has a chance to spawn; 100 steps is plenty
        for _ in 0..<100 { sim.step() }
        #expect(!sim.bubbleSystem.bubbles.isEmpty)
    }

    @Test("zero CPU never spawns bubbles")
    func zeroCPUNoBubbles() {
        var sim = SimulationState(canvasSize: 64)
        sim.cpuLoad = 0.0
        sim.memoryUsage = 0.5
        for _ in 0..<200 { sim.step() }
        #expect(sim.bubbleSystem.bubbles.isEmpty)
    }

    @Test("apply(config) propagates to water, bubble, and duck subsystems")
    func applyPropagates() {
        var sim = SimulationState(canvasSize: 64)
        var cfg = SimulationConfig()
        cfg.maxBubbles = 7
        cfg.gravity = 0.005
        cfg.rippleStrength = 0.01
        cfg.volatility = 0.5
        cfg.viscosity = 0.9
        cfg.speedLimit = 2.0
        cfg.duckEnabled = false

        sim.apply(cfg)

        #expect(sim.config == cfg)
        #expect(sim.bubbleSystem.maxBubbles == 7)
        #expect(sim.bubbleSystem.gravity == 0.005)
        #expect(sim.bubbleSystem.rippleStrength == 0.01)
        #expect(sim.water.volatility == 0.5)
        #expect(sim.water.viscosity == 0.9)
        #expect(sim.water.speedLimit == 2.0)
        #expect(sim.duck.enabled == false)
    }

    @Test("init applies provided config")
    func initAppliesConfig() {
        var cfg = SimulationConfig()
        cfg.maxBubbles = 3
        cfg.duckEnabled = false
        let sim = SimulationState(canvasSize: 64, config: cfg)
        #expect(sim.bubbleSystem.maxBubbles == 3)
        #expect(sim.duck.enabled == false)
    }

    @Test("water converges toward memory target over time")
    func waterConvergesToMemory() {
        var sim = SimulationState(canvasSize: 64)
        sim.memoryUsage = 0.9
        sim.cpuLoad = 0.0 // keep bubbles out of the way
        for _ in 0..<1000 { sim.step() }
        let avg = sim.water.levels.reduce(0, +) / Double(sim.water.levels.count)
        #expect(abs(avg - 0.9) < 0.1)
    }
}
