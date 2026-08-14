// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — Claude Code subscription usage (5-hour / 7-day windows)

import Foundation

/// One rate-limit window as reported by Claude Code.
///
/// Claude Code hands these numbers to its status-line command on stdin
/// (`rate_limits.five_hour` / `rate_limits.seven_day`). They are server-side,
/// account-wide figures — Claude Code owns the auth and the fetch, BubbleDuck
/// only reads what it wrote out. See `scripts/bubbleduck-statusline.sh`.
public struct ClaudeUsageWindow: Sendable, Equatable, Codable {
    /// Percentage of the limit consumed, 0...100, as last reported.
    public var usedPercentage: Double
    /// When this window rolls over.
    public var resetsAt: Date

    public init(usedPercentage: Double, resetsAt: Date) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    /// Usage percentage corrected for rollover. Once `resetsAt` has passed,
    /// the window has restarted and the last reported figure is void — the
    /// honest answer is 0, not the stale number. Clamped to 0...100.
    public func percentage(now: Date = Date()) -> Double {
        guard now < resetsAt else { return 0 }
        return max(0, min(100, usedPercentage))
    }

    /// Seconds until this window rolls over; 0 once it already has.
    public func timeUntilReset(now: Date = Date()) -> TimeInterval {
        max(0, resetsAt.timeIntervalSince(now))
    }

    /// True once the reset moment has passed — the reported percentage no
    /// longer describes the live window and the *next* reset time is unknown
    /// until Claude Code reports again.
    public func hasRolledOver(now: Date = Date()) -> Bool {
        now >= resetsAt
    }
}

/// A single reading of Claude Code's reported subscription limits.
///
/// Decoded from the JSON the status-line wrapper writes:
/// ```json
/// {"updated_at": 1786676000,
///  "five_hour": {"used_percentage": 42.1, "resets_at": 1786690000},
///  "seven_day": {"used_percentage": 61.0, "resets_at": 1787200000}}
/// ```
/// Both windows are optional: Claude Code only populates `rate_limits` for
/// subscribers, after the first API response of an *interactive* session.
public struct ClaudeUsageSnapshot: Sendable, Equatable, Codable {
    public var fiveHour: ClaudeUsageWindow?
    public var sevenDay: ClaudeUsageWindow?
    /// When the status-line wrapper wrote this reading.
    public var updatedAt: Date

    public init(fiveHour: ClaudeUsageWindow? = nil,
                sevenDay: ClaudeUsageWindow? = nil,
                updatedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.updatedAt = updatedAt
    }

    /// Age of this reading in seconds.
    public func age(now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(updatedAt))
    }

    /// True when no interactive Claude Code session has refreshed the file
    /// recently, so the percentages are last-known rather than live.
    /// The *reset times* stay valid regardless — they're absolute instants.
    public func isStale(now: Date = Date(), staleAfter: TimeInterval) -> Bool {
        age(now: now) > staleAfter
    }

    // MARK: - Codable (snake_case + epoch-seconds timestamps)

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case updatedAt = "updated_at"
    }

    private enum WindowKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let epoch = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
        self.updatedAt = Date(timeIntervalSince1970: epoch)
        self.fiveHour = try ClaudeUsageSnapshot.decodeWindow(c, key: .fiveHour)
        self.sevenDay = try ClaudeUsageSnapshot.decodeWindow(c, key: .sevenDay)
    }

    private static func decodeWindow(_ c: KeyedDecodingContainer<CodingKeys>,
                                     key: CodingKeys) throws -> ClaudeUsageWindow? {
        // `jq` emits an explicit null when Claude Code omitted the window.
        guard let inner = try? c.nestedContainer(keyedBy: WindowKeys.self, forKey: key),
              let percent = try inner.decodeIfPresent(Double.self, forKey: .usedPercentage),
              let resets = try inner.decodeIfPresent(Double.self, forKey: .resetsAt)
        else { return nil }
        return ClaudeUsageWindow(usedPercentage: percent,
                                 resetsAt: Date(timeIntervalSince1970: resets))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(updatedAt.timeIntervalSince1970, forKey: .updatedAt)
        try encodeWindow(fiveHour, into: &c, key: .fiveHour)
        try encodeWindow(sevenDay, into: &c, key: .sevenDay)
    }

    private func encodeWindow(_ window: ClaudeUsageWindow?,
                              into c: inout KeyedEncodingContainer<CodingKeys>,
                              key: CodingKeys) throws {
        guard let window else { return }
        var inner = c.nestedContainer(keyedBy: WindowKeys.self, forKey: key)
        try inner.encode(window.usedPercentage, forKey: .usedPercentage)
        try inner.encode(window.resetsAt.timeIntervalSince1970, forKey: .resetsAt)
    }
}

// MARK: - Configuration

/// What drives the water *level*.
public enum WaterLevelSource: String, Sendable, Equatable, Codable, CaseIterable {
    case memoryUsage = "Memory usage"
    case claudeFiveHour = "Claude 5-hour usage"
}

/// What drives the water *color*.
public enum WaterColorSource: String, Sendable, Equatable, Codable, CaseIterable {
    case memoryTightness = "Memory tightness"
    case claudeWeekly = "Claude weekly usage"
}

/// Everything user-tunable about the Claude usage integration.
public struct ClaudeUsageConfig: Sendable, Equatable, Codable {
    /// Which metric fills the tank.
    public var waterLevelSource: WaterLevelSource = .memoryUsage
    /// Which metric tints the water.
    public var waterColorSource: WaterColorSource = .memoryTightness

    /// How often the usage file is re-read, in seconds. Claude Code refreshes
    /// it far more often than we need; anything under a minute is wasted file
    /// I/O, so this is clamped by `effectiveRefreshSeconds`.
    public var refreshSeconds: Double = 60

    /// Hard floor on the refresh interval.
    public static let minimumRefreshSeconds: Double = 60

    /// `refreshSeconds` clamped to the minimum.
    public var effectiveRefreshSeconds: Double {
        max(ClaudeUsageConfig.minimumRefreshSeconds, refreshSeconds)
    }

    /// Path to the JSON written by the status-line wrapper. `~` is expanded
    /// by the macOS layer.
    public var usageFilePath: String = "~/.claude/bubbleduck-usage.json"

    /// Minutes without a refresh after which the percentages are considered
    /// last-known rather than live. The file only updates while an
    /// *interactive* Claude Code session is running.
    public var staleAfterMinutes: Double = 15

    /// When the reading goes stale, revert water level/color to the system
    /// metrics instead of holding a figure that may no longer be true.
    public var fallbackWhenStale: Bool = true

    /// Band edges for the weekly water color, in percent. Four thresholds →
    /// five bands (`< 25`, `< 50`, `< 75`, `< 90`, `>= 90` by default),
    /// paired with `ColorTheme.claudeWeeklyBands`.
    public var weeklyThresholds: [Double] = [25, 50, 75, 90]

    // The 5-hour reset countdown is not configured here — it is one of the
    // sources for the tile's single always-on text readout. See
    // `TileReadoutConfig` / `SimulationConfig.tileReadout`.

    public init() {}

    // MARK: - Codable

    // Every key optional so a config written by an older build (or one that
    // predates a knob added later) still decodes instead of throwing.
    private enum CodingKeys: String, CodingKey {
        case waterLevelSource, waterColorSource, refreshSeconds, usageFilePath
        case staleAfterMinutes, fallbackWhenStale, weeklyThresholds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClaudeUsageConfig()
        waterLevelSource = try c.decodeIfPresent(WaterLevelSource.self, forKey: .waterLevelSource) ?? d.waterLevelSource
        waterColorSource = try c.decodeIfPresent(WaterColorSource.self, forKey: .waterColorSource) ?? d.waterColorSource
        refreshSeconds   = try c.decodeIfPresent(Double.self, forKey: .refreshSeconds)   ?? d.refreshSeconds
        usageFilePath    = try c.decodeIfPresent(String.self, forKey: .usageFilePath)    ?? d.usageFilePath
        staleAfterMinutes = try c.decodeIfPresent(Double.self, forKey: .staleAfterMinutes) ?? d.staleAfterMinutes
        fallbackWhenStale = try c.decodeIfPresent(Bool.self,  forKey: .fallbackWhenStale)  ?? d.fallbackWhenStale
        let thresholds = try c.decodeIfPresent([Double].self, forKey: .weeklyThresholds)
        weeklyThresholds = (thresholds?.isEmpty == false) ? thresholds! : d.weeklyThresholds
    }
}

// MARK: - Formatting

public enum ClaudeUsageFormat {
    /// Compact countdown, kept as short as the tile deserves: `"4:12"` for an
    /// hour or more (clock-style, zero-padded minutes), `"48m"` below the
    /// hour where the `m` removes any doubt about the unit, `"<1m"` in the
    /// last minute, and `"—"` once the window has rolled over and no fresh
    /// reset time is known.
    public static func countdown(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return String(format: "%d:%02d", hours, minutes) }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    /// Percentage rendered as an integer with a `%` suffix.
    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}
