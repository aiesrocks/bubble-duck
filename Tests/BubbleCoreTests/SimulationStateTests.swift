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
