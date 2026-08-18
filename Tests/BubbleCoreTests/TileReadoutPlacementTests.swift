// SPDX-License-Identifier: GPL-2.0-or-later

import Testing
@testable import BubbleCore

@Suite("Tile readout auto placement")
struct TileReadoutPlacementTests {
    let fontScale = 0.14      // default: a band of 0.175 of the tile
    let extent = DuckState.baseMinimumY   // 0.12, a stock-sized agent

    private func isTop(_ current: Bool, agentY: Double, extent: Double? = nil) -> Bool {
        TileReadoutPlacement.resolveIsTop(currentIsTop: current, agentY: agentY,
                                          agentExtent: extent ?? self.extent,
                                          fontScale: fontScale)
    }

    @Test("agent floating high pushes the readout to the bottom")
    func highWaterGoesBottom() {
        #expect(isTop(true, agentY: 0.95) == false)
        #expect(isTop(false, agentY: 0.95) == false)
    }

    @Test("agent resting low pushes the readout to the top")
    func lowWaterGoesTop() {
        #expect(isTop(false, agentY: 0.12) == true)
        #expect(isTop(true, agentY: 0.12) == true)
    }

    @Test("agent in the middle leaves the readout where it is")
    func midWaterIsSticky() {
        #expect(isTop(false, agentY: 0.5) == false)
        #expect(isTop(true, agentY: 0.5) == true)
    }

    @Test("an agent tall enough to foul both bands does not oscillate")
    func bothBandsFouledStaysPut() {
        #expect(isTop(true, agentY: 0.5, extent: 0.45) == true)
        #expect(isTop(false, agentY: 0.5, extent: 0.45) == false)
    }

    @Test("larger text bands move the switch points outward")
    func biggerTextSwitchesSooner() {
        // At fontScale 0.14 an agent at 0.35 clears the bottom band; at 0.30
        // the band reaches up past it and the text has to move.
        #expect(TileReadoutPlacement.resolveIsTop(currentIsTop: false, agentY: 0.35,
                                                  agentExtent: extent, fontScale: 0.14) == false)
        #expect(TileReadoutPlacement.resolveIsTop(currentIsTop: false, agentY: 0.35,
                                                  agentExtent: extent, fontScale: 0.30) == true)
    }
}

@Suite("Tile readout auto position in the simulation")
struct TileReadoutAutoPositionTests {
    private func simulation(waterLevel: Double) -> SimulationState {
        var cfg = SimulationConfig()
        cfg.tileReadout.position = .auto
        var sim = SimulationState(canvasSize: 64, config: cfg)
        sim.memoryUsage = waterLevel
        sim.reduceMotion = true   // agent just follows the water, no drift/bob
        // Let the water reach its target and the agent settle onto it.
        for _ in 0..<600 { sim.step() }
        return sim
    }

    @Test("a full tank puts the readout at the bottom")
    func fullTankBottom() {
        #expect(simulation(waterLevel: 0.95).resolvedTileReadoutPosition == .bottom)
    }

    @Test("an empty tank puts the readout at the top")
    func emptyTankTop() {
        #expect(simulation(waterLevel: 0.0).resolvedTileReadoutPosition == .top)
    }

    @Test("a fixed position is passed through untouched")
    func fixedPositionUnchanged() {
        var cfg = SimulationConfig()
        cfg.tileReadout.position = .center
        var sim = SimulationState(canvasSize: 64, config: cfg)
        sim.memoryUsage = 0.95
        for _ in 0..<200 { sim.step() }
        #expect(sim.resolvedTileReadoutPosition == .center)
    }

    @Test("with the agent off, auto stays at the bottom")
    func agentDisabledStaysBottom() {
        var cfg = SimulationConfig()
        cfg.tileReadout.position = .auto
        var sim = SimulationState(canvasSize: 64, config: cfg)
        sim.duck.enabled = false
        sim.memoryUsage = 0.0
        for _ in 0..<600 { sim.step() }
        #expect(sim.resolvedTileReadoutPosition == .bottom)
    }
}
