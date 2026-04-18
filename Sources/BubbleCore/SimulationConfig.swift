// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — user-configurable simulation parameters

import Foundation

/// Power consumption mode. Controls frame rate and which visual effects
/// are active. "Auto" adapts frame rate to activity and defers to the
/// system's Low Power Mode setting.
public enum PowerMode: String, Sendable, Equatable, Codable, CaseIterable {
    case smoothest = "Smoothest"
    case auto = "Auto"
    case low = "Low"
    case lowest = "Lowest"
}

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

    // MARK: - Floating Agent

    /// Show a floating agent on the water surface.
    public var duckEnabled: Bool = true

    /// Which character floats on the water.
    public var agentType: AgentType = .rubberDuck

    /// Which metric drives the agent's drift speed.
    public var speedMetric: SpeedMetric = .networkIO

    /// Show rain driven by disk IOPS.
    public var rainEnabled: Bool = true

    // MARK: - Power

    /// Power consumption mode — controls frame rate and visual fidelity.
    public var powerMode: PowerMode = .auto

    // MARK: - Colors

    public var theme: ColorTheme = ColorTheme()

    public init() {}

    /// Factory for the stock wmbubble-inspired defaults.
    public static var `default`: SimulationConfig { SimulationConfig() }
}
