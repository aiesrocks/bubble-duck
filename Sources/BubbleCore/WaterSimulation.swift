// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — based on wmbubble by Johan Walles, Merlin Hughes, and timecop

import Foundation

/// Water column simulation using a spring model, ported from wmbubble's do_water_sim().
/// Each column has a water level that responds to memory usage and bubble interactions.
///
/// The average water level always equals `targetLevel` (memory usage).
/// Ripples from bubbles and rain are cosmetic perturbations around that
/// baseline — they create waves but cannot drift the overall level away
/// from the true memory reading.
public struct WaterSimulation: Sendable {
    public let columnCount: Int

    /// Water levels in 0.0...1.0 range (fraction of tank height)
    public private(set) var levels: [Double]
    /// Per-column ripple offset (positive = above baseline, negative = below)
    private var rippleOffsets: [Double]
    /// Velocity of each column's ripple
    private var velocities: [Double]

    // Physics parameters (matching wmbubble defaults)
    public var volatility: Double = 1.0
    public var viscosity: Double = 0.98
    public var speedLimit: Double = 1.0

    /// Target water level (driven by memory usage, 0.0...1.0)
    public var targetLevel: Double = 0.5

    /// Smoothed baseline that eases toward targetLevel for visual polish.
    private var smoothedTarget: Double = 0.5

    public init(columnCount: Int) {
        self.columnCount = columnCount
        self.levels = Array(repeating: 0.5, count: columnCount)
        self.rippleOffsets = Array(repeating: 0.0, count: columnCount)
        self.velocities = Array(repeating: 0.0, count: columnCount)
    }

    /// Advance the water simulation by one step.
    public mutating func step() {
        // Smoothly ease toward the target (avoids instant jumps when
        // memory changes, but converges within ~1 second at 60fps).
        smoothedTarget += (targetLevel - smoothedTarget) * 0.08

        // Simulate ripple physics — offsets oscillate around zero
        for i in 0..<columnCount {
            // Restoring force pulls ripple back to zero (flat surface)
            var force = -rippleOffsets[i] * volatility * 0.06

            // Spring coupling with neighbors creates wave propagation
            if i > 0 {
                force += (rippleOffsets[i - 1] - rippleOffsets[i]) * volatility * 0.005
            }
            if i < columnCount - 1 {
                force += (rippleOffsets[i + 1] - rippleOffsets[i]) * volatility * 0.005
            }

            velocities[i] += force
            velocities[i] *= viscosity

            let clamp = speedLimit * 0.03
            velocities[i] = max(-clamp, min(clamp, velocities[i]))
        }

        for i in 0..<columnCount {
            rippleOffsets[i] += velocities[i]
            // Final level = memory baseline + cosmetic ripple
            levels[i] = max(0.0, min(1.0, smoothedTarget + rippleOffsets[i]))
        }
    }

    /// Displace the water surface at a column (used when bubbles pop or are created).
    /// Only affects the ripple offset — cannot change the baseline level.
    public mutating func displace(column: Int, amount: Double) {
        guard column >= 0, column < columnCount else { return }
        velocities[column] += amount
    }
}
