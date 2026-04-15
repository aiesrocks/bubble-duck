// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — battery-driven color tinting (aiesrocks/bubble-duck#17).
//
// Platform-free so the formula itself is testable without a Mac. The macOS
// layer pulls battery fraction via IOPSCopyPowerSourcesInfo and passes it
// into `apply(to:batteryFraction:)` when rendering the water color.

import Foundation

public enum BatteryTint {
    /// Thresholds approved on aiesrocks/bubble-duck#17:
    ///   > 20%   → normal
    ///   10–20% → warning (desaturate + warm amber shift)
    ///   ≤ 10%  → critical ("end of the world" — heavy red apocalypse)
    public enum Zone: Sendable, Equatable {
        case normal
        case warning
        case critical
    }

    /// Zone classifier for a battery fraction (0...1).
    public static func zone(for batteryFraction: Double) -> Zone {
        if batteryFraction > 0.20 { return .normal }
        if batteryFraction > 0.10 { return .warning }
        return .critical
    }

    /// The "warning" amber base color (20–10%) — muted gold.
    public static let warningAmber = SimColor(r: 0.95, g: 0.55, b: 0.15)

    /// The "critical" apocalyptic red (≤10%).
    public static let apocalypseRed = SimColor(r: 0.95, g: 0.08, b: 0.08)

    /// Apply battery-state tinting on top of a base color (typically the
    /// water color after the swap lerp has been applied).
    ///
    /// - Normal zone: `color` is returned unchanged.
    /// - Warning zone: progressive desaturation + amber lerp as the battery
    ///   drops from 20% toward 10%.
    /// - Critical zone: aggressive lerp toward apocalyptic red, ramping
    ///   from 10% toward 0%.
    public static func apply(to color: SimColor, batteryFraction: Double) -> SimColor {
        switch zone(for: batteryFraction) {
        case .normal:
            return color

        case .warning:
            // progress ∈ [0, 1]: 0 at exactly 20%, 1 just above 10%.
            let progress = clamp01((0.20 - batteryFraction) / 0.10)
            let desatAmount = 0.30 + 0.30 * progress      // 30–60% desat
            let amberWeight = 0.20 + 0.15 * progress       // 20–35% amber
            return desaturate(color, by: desatAmount)
                .lerp(to: warningAmber, t: amberWeight)

        case .critical:
            // severity ∈ [0, 1]: 0 at exactly 10%, 1 at 0% — the lower the
            // battery, the more the water skews toward blood red.
            let severity = clamp01((0.10 - batteryFraction) / 0.10)
            let redWeight = 0.60 + 0.35 * severity         // 60–95% red
            return color.lerp(to: apocalypseRed, t: redWeight)
        }
    }

    // MARK: - Internal helpers

    static func desaturate(_ c: SimColor, by amount: Double) -> SimColor {
        let t = clamp01(amount)
        let gray = (c.r + c.g + c.b) / 3.0
        return SimColor(
            r: c.r + (gray - c.r) * t,
            g: c.g + (gray - c.g) * t,
            b: c.b + (gray - c.b) * t,
            a: c.a
        )
    }

    private static func clamp01(_ v: Double) -> Double {
        max(0, min(1, v))
    }
}
