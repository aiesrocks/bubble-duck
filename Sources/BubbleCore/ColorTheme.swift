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

/// Color theme matching wmbubble's configurable color scheme.
/// Colors interpolate between noSwap and maxSwap variants based on swap usage.
public struct ColorTheme: Sendable, Equatable, Codable {
    public var airNoSwap: SimColor
    public var airMaxSwap: SimColor
    public var liquidNoSwap: SimColor
    public var liquidMaxSwap: SimColor

    public var duckBody: SimColor
    public var duckBill: SimColor
    public var duckEye: SimColor

    public var bubbleColor: SimColor

    public init() {
        // wmbubble defaults
        airNoSwap = SimColor(hex: 0x2030C0)     // deep blue air
        airMaxSwap = SimColor(hex: 0xC02030)     // red-shifted when swapping
        liquidNoSwap = SimColor(hex: 0x3040E0)   // lighter blue water
        liquidMaxSwap = SimColor(hex: 0xE04030)   // red water when swapping
        duckBody = SimColor(hex: 0xF0D000)       // yellow
        duckBill = SimColor(hex: 0xE09000)        // orange
        duckEye = SimColor(hex: 0x202020)         // dark
        bubbleColor = SimColor(r: 1.0, g: 1.0, b: 1.0, a: 0.6)
    }

    /// Get the current air color interpolated by swap usage (0.0...1.0).
    public func airColor(swapUsage: Double) -> SimColor {
        airNoSwap.lerp(to: airMaxSwap, t: swapUsage)
    }

    /// Get the current liquid color interpolated by swap usage (0.0...1.0).
    public func liquidColor(swapUsage: Double) -> SimColor {
        liquidNoSwap.lerp(to: liquidMaxSwap, t: swapUsage)
    }
}
