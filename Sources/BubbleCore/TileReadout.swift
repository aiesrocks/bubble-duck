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
}

/// Content and styling for the tile's always-on text.
public struct TileReadoutConfig: Sendable, Equatable, Codable {
    public var source: TileReadoutSource = .cpuPercent

    /// Text color.
    public var color: SimColor = TileReadoutConfig.defaultColor
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
        case source, color, opacity, fontScale, position, backdrop, outline
        case dimWhenIdle, hideClaudeWhenLow
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TileReadoutConfig()
        source      = try c.decodeIfPresent(TileReadoutSource.self, forKey: .source) ?? d.source
        color       = try c.decodeIfPresent(SimColor.self, forKey: .color)      ?? d.color
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
