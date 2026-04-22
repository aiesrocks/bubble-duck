// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — based on wmbubble by Johan Walles, Merlin Hughes, and timecop

import Foundation

/// RGB color with components in 0.0...1.0 range.
public struct SimColor: Sendable, Equatable, Codable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init(hex: UInt32) {
        self.r = Double((hex >> 16) & 0xFF) / 255.0
        self.g = Double((hex >> 8) & 0xFF) / 255.0
        self.b = Double(hex & 0xFF) / 255.0
        self.a = 1.0
    }

    /// Linearly interpolate between two colors.
    public func lerp(to other: SimColor, t: Double) -> SimColor {
        let t = max(0, min(1, t))
        return SimColor(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t,
            a: a + (other.a - a) * t
        )
    }
}

/// Configurable color palette for the simulation.
///
/// Semantic mapping (aiesrocks/bubble-duck#3):
///   - **Water level** → memory usage (unchanged; handled by WaterSimulation)
///   - **Water color** → swap pressure, via `liquidColor(swapUsage:)`
///   - **Sky color**   → local time of day, via `skyColor(timeOfDay:)`
///
/// "Theme overrules" falls out for free — a user who wants a static sky
/// sets all four sky anchors to the same color; a user who wants water
/// color that never reacts to swap sets `liquidNoSwap == liquidMaxSwap`.
public struct ColorTheme: Sendable, Equatable, Codable {
    // Sky (time-of-day blending anchors)
    public var skyDawn: SimColor
    public var skyNoon: SimColor
    public var skyDusk: SimColor
    public var skyNight: SimColor

    // Water (swap-pressure anchors)
    public var liquidNoSwap: SimColor
    public var liquidMaxSwap: SimColor

    // Agent
    public var duckBody: SimColor
    public var duckBill: SimColor
    public var duckEye: SimColor

    // Other
    public var bubbleColor: SimColor

    public init() {
        self.skyDawn = ColorTheme.defaultSkyDawn
        self.skyNoon = ColorTheme.defaultSkyNoon
        self.skyDusk = ColorTheme.defaultSkyDusk
        self.skyNight = ColorTheme.defaultSkyNight
        self.liquidNoSwap = ColorTheme.defaultLiquidNoSwap
        self.liquidMaxSwap = ColorTheme.defaultLiquidMaxSwap
        self.duckBody = ColorTheme.defaultDuckBody
        self.duckBill = ColorTheme.defaultDuckBill
        self.duckEye = ColorTheme.defaultDuckEye
        self.bubbleColor = ColorTheme.defaultBubbleColor
    }

    public init(
        skyDawn: SimColor, skyNoon: SimColor, skyDusk: SimColor, skyNight: SimColor,
        liquidNoSwap: SimColor, liquidMaxSwap: SimColor,
        duckBody: SimColor, duckBill: SimColor, duckEye: SimColor,
        bubbleColor: SimColor
    ) {
        self.skyDawn = skyDawn
        self.skyNoon = skyNoon
        self.skyDusk = skyDusk
        self.skyNight = skyNight
        self.liquidNoSwap = liquidNoSwap
        self.liquidMaxSwap = liquidMaxSwap
        self.duckBody = duckBody
        self.duckBill = duckBill
        self.duckEye = duckEye
        self.bubbleColor = bubbleColor
    }

    // MARK: - Built-in defaults (exposed for use by preset themes in #11)

    public static let defaultSkyDawn  = SimColor(hex: 0xD9778A)   // warm pink sunrise
    public static let defaultSkyNoon  = SimColor(hex: 0x00FFFF)   // Aqua (Pencils palette)
    public static let defaultSkyDusk  = SimColor(hex: 0xA85A4E)   // orange-mauve sunset
    public static let defaultSkyNight = SimColor(hex: 0x0D1440)   // deep navy
    public static let defaultLiquidNoSwap  = SimColor(hex: 0x0000FF)   // Blueberry (Pencils palette)
    public static let defaultLiquidMaxSwap = SimColor(hex: 0xE04030)
    public static let defaultDuckBody = SimColor(hex: 0xF0D000)
    public static let defaultDuckBill = SimColor(hex: 0xE09000)
    public static let defaultDuckEye  = SimColor(hex: 0x202020)
    public static let defaultBubbleColor = SimColor(r: 1.0, g: 1.0, b: 1.0, a: 0.6)

    // MARK: - Color lookups

    /// Sky color at the current fraction-of-day (0 = midnight, 0.25 = dawn,
    /// 0.5 = noon, 0.75 = dusk). Smooth blending between the four anchors so
    /// the sky glides through the day rather than popping.
    public func skyColor(timeOfDay: Double) -> SimColor {
        // Normalize into [0, 1)
        var t = timeOfDay.truncatingRemainder(dividingBy: 1.0)
        if t < 0 { t += 1.0 }

        // Night holds from 7PM to 5AM, then a 1-hour transition into
        // dawn at 6AM. Daytime anchors (dawn/noon/dusk) are unchanged.
        //   5/24 ≈ 0.2083 = 5AM (night ends, dawn transition starts)
        //   6/24 = 0.25    = 6AM (dawn)
        //  12/24 = 0.5     = noon
        //  18/24 = 0.75    = 6PM (dusk)
        //  19/24 ≈ 0.7917  = 7PM (fully night)
        let stops: [(pos: Double, color: SimColor)] = [
            (0.0,         skyNight),   // midnight — night
            (5.0 / 24.0,  skyNight),   // 5AM — still night
            (0.25,        skyDawn),    // 6AM — dawn
            (0.5,         skyNoon),    // noon
            (0.75,        skyDusk),    // 6PM — dusk
            (19.0 / 24.0, skyNight),   // 7PM — fully night
            (1.0,         skyNight)    // midnight — wraps
        ]
        for i in 0..<(stops.count - 1) {
            let a = stops[i]
            let b = stops[i + 1]
            if t >= a.pos && t <= b.pos {
                let localT = (t - a.pos) / (b.pos - a.pos)
                return a.color.lerp(to: b.color, t: localT)
            }
        }
        return skyNoon
    }

    /// Water color driven by memory tightness (0...1+).
    /// Remapped to match MemoryPressure zones:
    ///   - healthy (< 0.70): stays blue (t = 0)
    ///   - warning (0.70 - 0.90): blue → red transition
    ///   - critical (> 0.90): fully red
    public func liquidColor(swapUsage: Double) -> SimColor {
        let t: Double
        if swapUsage < 0.70 {
            t = 0  // healthy — pure blue
        } else if swapUsage < 0.90 {
            t = (swapUsage - 0.70) / 0.20  // warning — 0...1 ramp
        } else {
            t = 1.0  // critical — pure red
        }
        return liquidNoSwap.lerp(to: liquidMaxSwap, t: t)
    }

    // MARK: - Codable (handles migration from the pre-#3 air/swap schema)

    private enum CodingKeys: String, CodingKey {
        // Current
        case skyDawn, skyNoon, skyDusk, skyNight
        case liquidNoSwap, liquidMaxSwap
        case duckBody, duckBill, duckEye
        case bubbleColor
        // Deprecated — still decoded for backward compatibility. Never
        // encoded; migrating decoders map these to `skyNoon` / `skyDusk`.
        case airNoSwap, airMaxSwap
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Prefer new sky anchors; fall back to legacy `airNoSwap` / `airMaxSwap`
        // if a saved theme from before #3 is loaded. If none are present,
        // use the factory defaults.
        if let dawn = try c.decodeIfPresent(SimColor.self, forKey: .skyDawn) {
            self.skyDawn = dawn
            self.skyNoon  = try c.decodeIfPresent(SimColor.self, forKey: .skyNoon)  ?? ColorTheme.defaultSkyNoon
            self.skyDusk  = try c.decodeIfPresent(SimColor.self, forKey: .skyDusk)  ?? ColorTheme.defaultSkyDusk
            self.skyNight = try c.decodeIfPresent(SimColor.self, forKey: .skyNight) ?? ColorTheme.defaultSkyNight
        } else if let legacyNoSwap = try c.decodeIfPresent(SimColor.self, forKey: .airNoSwap),
                  let legacyMaxSwap = try c.decodeIfPresent(SimColor.self, forKey: .airMaxSwap) {
            // Map the old two-color swap-driven air palette into a plausible
            // four-anchor day palette: keep the user's "calm" color for noon
            // and "stressed" color for dusk; interpolate dawn & darken night.
            self.skyNoon  = legacyNoSwap
            self.skyDusk  = legacyMaxSwap
            self.skyDawn  = legacyNoSwap.lerp(to: SimColor(r: 1.0, g: 0.78, b: 0.70), t: 0.4)
            self.skyNight = SimColor(
                r: legacyNoSwap.r * 0.30,
                g: legacyNoSwap.g * 0.30,
                b: legacyNoSwap.b * 0.45,
                a: legacyNoSwap.a
            )
        } else {
            self.skyDawn  = ColorTheme.defaultSkyDawn
            self.skyNoon  = ColorTheme.defaultSkyNoon
            self.skyDusk  = ColorTheme.defaultSkyDusk
            self.skyNight = ColorTheme.defaultSkyNight
        }

        self.liquidNoSwap  = try c.decodeIfPresent(SimColor.self, forKey: .liquidNoSwap)  ?? ColorTheme.defaultLiquidNoSwap
        self.liquidMaxSwap = try c.decodeIfPresent(SimColor.self, forKey: .liquidMaxSwap) ?? ColorTheme.defaultLiquidMaxSwap
        self.duckBody = try c.decodeIfPresent(SimColor.self, forKey: .duckBody) ?? ColorTheme.defaultDuckBody
        self.duckBill = try c.decodeIfPresent(SimColor.self, forKey: .duckBill) ?? ColorTheme.defaultDuckBill
        self.duckEye  = try c.decodeIfPresent(SimColor.self, forKey: .duckEye)  ?? ColorTheme.defaultDuckEye
        self.bubbleColor = try c.decodeIfPresent(SimColor.self, forKey: .bubbleColor) ?? ColorTheme.defaultBubbleColor
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(skyDawn,  forKey: .skyDawn)
        try c.encode(skyNoon,  forKey: .skyNoon)
        try c.encode(skyDusk,  forKey: .skyDusk)
        try c.encode(skyNight, forKey: .skyNight)
        try c.encode(liquidNoSwap,  forKey: .liquidNoSwap)
        try c.encode(liquidMaxSwap, forKey: .liquidMaxSwap)
        try c.encode(duckBody, forKey: .duckBody)
        try c.encode(duckBill, forKey: .duckBill)
        try c.encode(duckEye,  forKey: .duckEye)
        try c.encode(bubbleColor, forKey: .bubbleColor)
    }
}
