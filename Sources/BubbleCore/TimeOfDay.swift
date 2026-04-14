// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — pure helpers for the day/night sky cycle (aiesrocks/bubble-duck#3).

import Foundation

/// Maps wall-clock time into a 0...1 cycle value consumed by
/// `ColorTheme.skyColor(timeOfDay:)`.
///
/// - 0.0  = midnight (maps to `skyNight`)
/// - 0.25 = 6am (maps to `skyDawn`)
/// - 0.5  = noon (maps to `skyNoon`)
/// - 0.75 = 6pm (maps to `skyDusk`)
/// - 1.0  = midnight again (wraps to `skyNight`)
public enum TimeOfDay {
    /// Fraction-of-day for the given `date` in `calendar`'s local time zone.
    /// Returned value is in `[0.0, 1.0)`.
    public static func fraction(from date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let h = Double(parts.hour ?? 0)
        let m = Double(parts.minute ?? 0) / 60.0
        let s = Double(parts.second ?? 0) / 3600.0
        let raw = (h + m + s) / 24.0
        // Guard against calendar weirdness (negative / >=1 values) — clamp
        // into [0, 1). The skyColor blend also normalizes, but being
        // defensive here keeps test expectations tight.
        if raw < 0 { return 0 }
        if raw >= 1.0 { return raw.truncatingRemainder(dividingBy: 1.0) }
        return raw
    }
}
