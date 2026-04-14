// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — based on wmbubble by Johan Walles, Merlin Hughes, and timecop

import Foundation

/// Combined simulation state tying water, bubbles, and system metrics together.
public struct SimulationState: Sendable {
    public var water: WaterSimulation
    public var bubbleSystem: BubbleSystem
    public var duck: DuckState

    // Current system metrics (0.0...1.0)
    public var cpuLoad: Double = 0.0
    public var memoryUsage: Double = 0.0
    public var swapUsage: Double = 0.0

    /// Size of the rendering canvas in points
    public let canvasSize: Int

    public init(canvasSize: Int = 256) {
        self.canvasSize = canvasSize
        // Use fewer columns than pixels for smoother waves
        let columnCount = canvasSize / 4
        self.water = WaterSimulation(columnCount: columnCount)
        self.bubbleSystem = BubbleSystem()
        self.duck = DuckState()
    }

    /// Advance the simulation by one frame.
    public mutating func step() {
        // Update water target from memory usage
        water.targetLevel = memoryUsage

        // Maybe spawn bubbles based on CPU
        if let col = bubbleSystem.maybeSpawn(cpuLoad: cpuLoad, columnCount: water.columnCount) {
            water.displace(column: col, amount: -bubbleSystem.rippleStrength)
        }

        // Step bubbles, get popped columns
        let popped = bubbleSystem.step(waterLevels: water.levels)
        for col in popped {
            water.displace(column: col, amount: bubbleSystem.rippleStrength)
        }

        // Step water physics
        water.step()

        // Step duck
        duck.step(waterLevels: water.levels)
    }
}

/// The rubber duck that floats on the water surface.
public struct DuckState: Sendable {
    public var x: Double = 0.5        // 0.0...1.0 horizontal position
    public var y: Double = 0.5        // vertical position (follows water)
    public var velocityX: Double = 0.001
    public var bobAngle: Double = 0.0 // for gentle bobbing
    public var isUpsideDown: Bool = false
    public var enabled: Bool = true

    public init() {}

    public mutating func step(waterLevels: [Double]) {
        guard enabled, !waterLevels.isEmpty else { return }

        // Drift horizontally
        x += velocityX
        if x > 0.85 || x < 0.15 {
            velocityX = -velocityX
        }

        // Follow water surface
        let col = min(Int(x * Double(waterLevels.count)), waterLevels.count - 1)
        y = waterLevels[col]

        // Bob gently
        bobAngle += 0.05
        if bobAngle > .pi * 2 { bobAngle -= .pi * 2 }

        // Flip upside down if water is very high (>95%)
        isUpsideDown = y > 0.95
    }
}
