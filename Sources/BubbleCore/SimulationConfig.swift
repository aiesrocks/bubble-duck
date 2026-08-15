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

    /// Size multiplier applied on top of each character's own tuned scale —
    /// a hippo stays bigger than a rubber duck at any setting. 1.0 is stock.
    public var agentSizeScale: Double = 1.0

    /// Clamp applied when the multiplier reaches the simulation, so a bad
    /// persisted value can't produce an agent larger than the tile.
    public static let agentSizeRange: ClosedRange<Double> = 0.4...2.5

    /// Which metric drives the agent's drift speed.
    public var speedMetric: SpeedMetric = .networkIO

    /// Show rain driven by disk IOPS.
    public var rainEnabled: Bool = true

    // MARK: - Bubbles

    /// Which metric drives the bubble spawn rate.
    public var bubbleMetric: BubbleMetric = .cpuLoad

    /// Keep the tank deep enough for the agent to float in.
    ///
    /// Agents are drawn as partially submerged — the hippo is only a head
    /// dome, because the water is supposed to hide the rest of it. A water
    /// level near zero (a freshly reset Claude 5-hour window, where memory
    /// usage never went) leaves nothing to hide it and the agent appears to
    /// hover. With this on, the level never drops below what the agent needs
    /// to sit in; the readout and overlays still report the true figure.
    /// Turn it off for a strictly literal tank, where the agent instead rests
    /// on the floor of an empty one.
    public var keepAgentAfloat: Bool = true

    /// React when the cursor moves onto the Dock tile. Off by default: macOS
    /// gives Dock tiles no hover events, so this requires Accessibility
    /// permission to locate the tile — a real trade for a cosmetic reaction.
    public var hoverReactionEnabled: Bool = false

    // MARK: - Power

    /// Power consumption mode — controls frame rate and visual fidelity.
    public var powerMode: PowerMode = .auto

    // MARK: - Claude usage

    /// Claude Code subscription usage: which visuals it drives and how often
    /// the reading is refreshed.
    public var claudeUsage: ClaudeUsageConfig = ClaudeUsageConfig()

    // MARK: - Tile readout

    /// The single always-on text on the tile — what it shows and how it looks.
    public var tileReadout: TileReadoutConfig = TileReadoutConfig()

    // MARK: - Colors

    public var theme: ColorTheme = ColorTheme()

    public init() {}

    // MARK: - Codable

    // Hand-rolled so a config saved before the Claude usage feature still
    // decodes: every key is optional and falls back to the property default.
    private enum CodingKeys: String, CodingKey {
        case maxBubbles, gravity, rippleStrength, volatility, viscosity, speedLimit
        case duckEnabled, agentType, agentSizeScale, speedMetric, rainEnabled
        case keepAgentAfloat, hoverReactionEnabled, bubbleMetric
        case powerMode, claudeUsage, tileReadout, theme
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SimulationConfig()
        maxBubbles     = try c.decodeIfPresent(Int.self,    forKey: .maxBubbles)     ?? d.maxBubbles
        gravity        = try c.decodeIfPresent(Double.self, forKey: .gravity)        ?? d.gravity
        rippleStrength = try c.decodeIfPresent(Double.self, forKey: .rippleStrength) ?? d.rippleStrength
        volatility     = try c.decodeIfPresent(Double.self, forKey: .volatility)     ?? d.volatility
        viscosity      = try c.decodeIfPresent(Double.self, forKey: .viscosity)      ?? d.viscosity
        speedLimit     = try c.decodeIfPresent(Double.self, forKey: .speedLimit)     ?? d.speedLimit
        duckEnabled    = try c.decodeIfPresent(Bool.self,   forKey: .duckEnabled)    ?? d.duckEnabled
        agentType      = try c.decodeIfPresent(AgentType.self,   forKey: .agentType)   ?? d.agentType
        agentSizeScale = try c.decodeIfPresent(Double.self, forKey: .agentSizeScale)   ?? d.agentSizeScale
        speedMetric    = try c.decodeIfPresent(SpeedMetric.self, forKey: .speedMetric) ?? d.speedMetric
        rainEnabled    = try c.decodeIfPresent(Bool.self,   forKey: .rainEnabled)    ?? d.rainEnabled
        keepAgentAfloat = try c.decodeIfPresent(Bool.self, forKey: .keepAgentAfloat) ?? d.keepAgentAfloat
        bubbleMetric   = try c.decodeIfPresent(BubbleMetric.self, forKey: .bubbleMetric) ?? d.bubbleMetric
        hoverReactionEnabled = try c.decodeIfPresent(Bool.self, forKey: .hoverReactionEnabled) ?? d.hoverReactionEnabled
        powerMode      = try c.decodeIfPresent(PowerMode.self, forKey: .powerMode)   ?? d.powerMode
        claudeUsage    = try c.decodeIfPresent(ClaudeUsageConfig.self, forKey: .claudeUsage) ?? d.claudeUsage
        tileReadout    = try c.decodeIfPresent(TileReadoutConfig.self, forKey: .tileReadout) ?? d.tileReadout
        theme          = try c.decodeIfPresent(ColorTheme.self, forKey: .theme)      ?? d.theme
    }

    /// Factory for the stock wmbubble-inspired defaults.
    public static var `default`: SimulationConfig { SimulationConfig() }
}
