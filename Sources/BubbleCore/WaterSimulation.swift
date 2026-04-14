// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — based on wmbubble by Johan Walles, Merlin Hughes, and timecop

import Foundation

/// Water column simulation using a spring model, ported from wmbubble's do_water_sim().
/// Each column has a water level that responds to memory usage and bubble interactions.
public struct WaterSimulation: Sendable {
    public let columnCount: Int

    /// Water levels in 0.0...1.0 range (fraction of tank height)
    public private(set) var levels: [Double]
    /// Velocity of each column
    private var velocities: [Double]

    // Physics parameters (matching wmbubble defaults)
    public var volatility: Double = 1.0
    public var viscosity: Double = 0.98
    public var speedLimit: Double = 1.0

    /// Target water level (driven by memory usage, 0.0...1.0)
    public var targetLevel: Double = 0.5

    public init(columnCount: Int) {
        self.columnCount = columnCount
        self.levels = Array(repeating: 0.5, count: columnCount)
        self.velocities = Array(repeating: 0.0, count: columnCount)
    }

    /// Advance the water simulation by one step.
    /// Port of wmbubble's spring-model wave propagation.
    public mutating func step() {
        for i in 0..<columnCount {
            // Force toward target level
            var force = (targetLevel - levels[i]) * volatility * 0.01

            // Forces from neighboring columns (spring coupling)
            if i > 0 {
                force += (levels[i - 1] - levels[i]) * volatility * 0.005
            }
            if i < columnCount - 1 {
                force += (levels[i + 1] - levels[i]) * volatility * 0.005
            }

            velocities[i] += force
            velocities[i] *= viscosity

            // Clamp velocity
            velocities[i] = max(-speedLimit * 0.01, min(speedLimit * 0.01, velocities[i]))
        }

        for i in 0..<columnCount {
            levels[i] += velocities[i]
            levels[i] = max(0.0, min(1.0, levels[i]))
        }
    }

    /// Displace the water surface at a column (used when bubbles pop or are created).
    public mutating func displace(column: Int, amount: Double) {
        guard column >= 0, column < columnCount else { return }
        velocities[column] += amount
    }
}
