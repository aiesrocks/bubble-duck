// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — the single always-on text readout drawn on the tile

import Foundation

/// What the tile's always-on text shows.
///
/// There is exactly one such readout — the slot wmbubble used for its CPU
/// digits. Picking a Claude source puts that value *in place of* the CPU
/// percentage rather than adding a second line of text to a 128pt tile.
public enum TileReadoutSource: String, Sendable, Equatable, Codable, CaseIterable {
    case none = "Off"
    case cpuPercent = "CPU %"
    case memoryPercent = "Memory %"
    case claudeFiveHourUsage = "Claude 5h usage"
    case claudeFiveHourCountdown = "Claude 5h reset countdown"
    case claudeFiveHourUsageAndCountdown = "Claude 5h usage + countdown"
    case claudeWeeklyUsage = "Claude weekly usage"

    /// True for the sources that need a Claude usage reading.
    public var needsClaudeUsage: Bool {
        switch self {
        case .none, .cpuPercent, .memoryPercent:
            return false
        case .claudeFiveHourUsage, .claudeFiveHourCountdown,
             .claudeFiveHourUsageAndCountdown, .claudeWeeklyUsage:
            return true
        }
    }
}

/// Where the readout sits on the tile.
public enum TileReadoutPosition: String, Sendable, Equatable, Codable, CaseIterable {
    case top = "Top"
    case center = "Center"
    case bottom = "Bottom"
    /// Top or bottom, whichever the floating agent is not currently sitting
    /// in. A full tank floats the agent up into the top band, an empty one
    /// parks it on the floor — see `TileReadoutPlacement`.
    case auto = "Auto (avoid agent)"
}

/// Geometry for the `.auto` readout position: which end of the tile the text
/// should sit at so the floating agent doesn't sit on top of it.
///
/// The agent rides the water surface, so this tracks the water level without
/// reading it: a full tank pushes the agent into the top band and the text
/// drops to the bottom; an empty tank parks the agent on the floor and the
/// text moves up.
public enum TileReadoutPlacement {
    /// Tile-fraction gap the renderer leaves at the top/bottom edge.
    public static let edgeInset: Double = 0.03
    /// Extra breathing room demanded between agent silhouette and text band.
    public static let clearance: Double = 0.02

    /// Height of one line of readout text as a fraction of the tile. Mirrors
    /// the renderer: font size is `tile * fontScale`, and the system font's
    /// line height runs roughly 1.25x the point size.
    public static func textHeight(fontScale: Double) -> Double {
        max(0.04, min(0.40, fontScale)) * 1.25
    }

    /// Decide which end the auto-positioned readout sits at; true means top.
    ///
    /// Only *collisions* move the text. While the agent is clear of both
    /// bands the current side is kept, which leaves a wide dead zone in the
    /// middle so per-frame ripple wobble can't flip the text every other
    /// frame. If the agent fouls both bands (very large agent) the text stays
    /// put rather than oscillating.
    ///
    /// `agentY` is the agent's origin in 0...1 tile coordinates and
    /// `agentExtent` how far its silhouette reaches either side of that.
    public static func resolveIsTop(currentIsTop: Bool, agentY: Double,
                                    agentExtent: Double, fontScale: Double) -> Bool {
        let band = textHeight(fontScale: fontScale)
        let bottomBandTop = edgeInset + band + clearance
        let topBandBottom = 1 - edgeInset - band - clearance
        let foulsBottom = agentY - agentExtent < bottomBandTop
        let foulsTop = agentY + agentExtent > topBandBottom

        if currentIsTop {
            return !(foulsTop && !foulsBottom)
        }
        return foulsBottom && !foulsTop
    }
}

/// How the readout's text color is chosen.
public enum TileReadoutColorMode: String, Sendable, Equatable, Codable, CaseIterable {
    /// Always the user's picked `color`.
    case custom = "Custom"
    /// Derived per frame from whatever the text overlays — a gentle inverse
    /// of the sky, the water, or the blend of both where the text straddles
    /// the surface. Keeps the readout legible as the tank fills and the sky
    /// moves through the day, without re-picking a color.
    case autoInverse = "Auto (inverse of background)"
}

/// Content and styling for the tile's always-on text.
public struct TileReadoutConfig: Sendable, Equatable, Codable {
    public var source: TileReadoutSource = .cpuPercent

    /// Where the text color comes from.
    public var colorMode: TileReadoutColorMode = .custom

    /// Text color, used when `colorMode` is `.custom`.
    public var color: SimColor = TileReadoutConfig.defaultColor

    /// How far toward the inverse the auto color goes: 0 leaves the
    /// background color as-is (invisible), 1 is a full flip.
    public var autoInverseStrength: Double = 1.0
    /// Peak alpha, 0 = invisible, 1 = fully opaque.
    public var opacity: Double = 0.69
    /// Font size as a fraction of the tile size.
    public var fontScale: Double = 0.14
    public var position: TileReadoutPosition = .bottom
    /// Rounded dark pill behind the text, for legibility over pale water.
    public var backdrop: Bool = false
    /// Outline the glyphs in black or white (whichever contrasts with the text
    /// color). Cheap insurance against the readout vanishing into a sky or
    /// water color close to its own.
    public var outline: Bool = true
    /// wmbubble behavior: the readout sits dimmer while no overlay screen is
    /// showing, and brightens with the overlay. Off means a flat `opacity`.
    public var dimWhenIdle: Bool = true

    /// Hide the readout entirely while Claude usage is under the first weekly
    /// band edge (`ClaudeUsageConfig.weeklyThresholds.first`, 25% by default)
    /// — a budget you've barely touched doesn't need a number on the tile.
    /// Applies only to the Claude sources; CPU and memory always draw.
    public var hideClaudeWhenLow: Bool = false

    /// wmbubble's gauge digit color (#20B0AC).
    public static let defaultColor = SimColor(hex: 0x20B0AC)

    public init() {}

    // MARK: - Codable

    // Every key optional so configs written by earlier builds still decode.
    private enum CodingKeys: String, CodingKey {
        case source, colorMode, color, autoInverseStrength
        case opacity, fontScale, position, backdrop, outline
        case dimWhenIdle, hideClaudeWhenLow
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TileReadoutConfig()
        source      = try c.decodeIfPresent(TileReadoutSource.self, forKey: .source) ?? d.source
        colorMode   = try c.decodeIfPresent(TileReadoutColorMode.self, forKey: .colorMode) ?? d.colorMode
        color       = try c.decodeIfPresent(SimColor.self, forKey: .color)      ?? d.color
        autoInverseStrength = try c.decodeIfPresent(Double.self, forKey: .autoInverseStrength)
            ?? d.autoInverseStrength
        opacity     = try c.decodeIfPresent(Double.self, forKey: .opacity)      ?? d.opacity
        fontScale   = try c.decodeIfPresent(Double.self, forKey: .fontScale)    ?? d.fontScale
        position    = try c.decodeIfPresent(TileReadoutPosition.self, forKey: .position) ?? d.position
        backdrop    = try c.decodeIfPresent(Bool.self, forKey: .backdrop)       ?? d.backdrop
        outline     = try c.decodeIfPresent(Bool.self, forKey: .outline)        ?? d.outline
        dimWhenIdle = try c.decodeIfPresent(Bool.self, forKey: .dimWhenIdle)    ?? d.dimWhenIdle
        hideClaudeWhenLow = try c.decodeIfPresent(Bool.self, forKey: .hideClaudeWhenLow) ?? d.hideClaudeWhenLow
    }
}

/// What to draw for the tile readout: the text plus whether the value behind
/// it is a last-known Claude reading rather than a live one.
public struct TileReadout: Sendable, Equatable {
    public let text: String
    public let isStale: Bool

    public init(text: String, isStale: Bool) {
        self.text = text
        self.isStale = isStale
    }
}
