// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import BubbleCore

@Suite("Simulation Config")
struct SimulationConfigTests {
    @Test("default config matches the wmbubble-inspired defaults")
    func defaultsMatchWmbubble() {
        let c = SimulationConfig.default
        #expect(c.maxBubbles == 100)
        #expect(c.gravity == 0.001)
        #expect(c.rippleStrength == 0.005)
        #expect(c.volatility == 1.0)
        #expect(c.viscosity == 0.98)
        #expect(c.speedLimit == 1.0)
        #expect(c.duckEnabled)
    }

    @Test("config round-trips through JSON")
    func roundTripsThroughJSON() throws {
        var c = SimulationConfig()
        c.maxBubbles = 42
        c.gravity = 0.002
        c.duckEnabled = false
        c.theme.skyDawn = SimColor(r: 0.1, g: 0.2, b: 0.3)

        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(SimulationConfig.self, from: data)

        #expect(decoded == c)
    }

    @Test("SimColor round-trips through JSON")
    func simColorRoundTrips() throws {
        let c = SimColor(r: 0.25, g: 0.5, b: 0.75, a: 1.0)
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(SimColor.self, from: data)
        #expect(decoded == c)
    }

    @Test("ColorTheme round-trips through JSON")
    func colorThemeRoundTrips() throws {
        var t = ColorTheme()
        t.duckBody = SimColor(r: 1, g: 0, b: 0)
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(ColorTheme.self, from: data)
        #expect(decoded == t)
    }
}
