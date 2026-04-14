// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — user-configurable simulation parameters

import Foundation

/// All tunable knobs for the simulation: physics, features, colors.
/// Designed to be serialized (JSON) into UserDefaults by the macOS layer,
/// so kept Codable and platform-free here in BubbleCore.
public struct SimulationConfig: Sendable, Equatable, Codable {
    // MARK: - Physics (wmbubble defaults)

    /// Maximum concurrent bubbles on screen.
    public var maxBubbles: Int = 100

    /// Upward acceleration applied to each bubble per step.
    public var gravity: Double = 0.001

    /// Strength of the displacement kicked into the water surface when a
    /// bubble spawns (downward) or pops (upward).
    public var rippleStrength: Double = 0.005

    /// Spring stiffness for the water column simulation.
    public var volatility: Double = 1.0

    /// Damping applied to each column's velocity per step (0.0...1.0).
    public var viscosity: Double = 0.98

    /// Clamp on column velocity magnitude.
    public var speedLimit: Double = 1.0

    // MARK: - Features

    /// Show the rubber duck floating on the surface.
    public var duckEnabled: Bool = true

    // MARK: - Colors

    public var theme: ColorTheme = ColorTheme()

    public init() {}

    /// Factory for the stock wmbubble-inspired defaults.
    public static var `default`: SimulationConfig { SimulationConfig() }
}
