// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import BubbleCore

@Suite("SimColor")
struct SimColorTests {
    @Test("lerp at t=0 returns start color")
    func lerpAtZero() {
        let a = SimColor(r: 0, g: 0, b: 0)
        let b = SimColor(r: 1, g: 1, b: 1)
        #expect(a.lerp(to: b, t: 0) == a)
    }

    @Test("lerp at t=1 returns end color")
    func lerpAtOne() {
        let a = SimColor(r: 0, g: 0, b: 0)
        let b = SimColor(r: 1, g: 1, b: 1)
        #expect(a.lerp(to: b, t: 1) == b)
    }

    @Test("lerp at midpoint averages components")
    func lerpAtHalf() {
        let a = SimColor(r: 0, g: 0, b: 0)
        let b = SimColor(r: 1, g: 1, b: 1)
        let mid = a.lerp(to: b, t: 0.5)
        #expect(abs(mid.r - 0.5) < 0.0001)
        #expect(abs(mid.g - 0.5) < 0.0001)
        #expect(abs(mid.b - 0.5) < 0.0001)
    }

    @Test("lerp clamps t outside 0...1")
    func lerpClampsT() {
        let a = SimColor(r: 0, g: 0, b: 0)
        let b = SimColor(r: 1, g: 1, b: 1)
        #expect(a.lerp(to: b, t: -1) == a)
        #expect(a.lerp(to: b, t: 2) == b)
    }

    @Test("hex init parses 0xRRGGBB into 0...1 components")
    func hexInit() {
        let c = SimColor(hex: 0xFF8040)
        #expect(abs(c.r - 1.0) < 0.001)
        #expect(abs(c.g - 128.0 / 255.0) < 0.001)
        #expect(abs(c.b - 64.0 / 255.0) < 0.001)
        #expect(c.a == 1.0)
    }
}

@Suite("Color Theme — sky (time-of-day)")
struct ColorThemeSkyTests {
    @Test("sky at midnight matches skyNight")
    func skyAtMidnight() {
        let theme = ColorTheme()
        #expect(theme.skyColor(timeOfDay: 0.0) == theme.skyNight)
    }

    @Test("sky at dawn matches skyDawn")
    func skyAtDawn() {
        let theme = ColorTheme()
        #expect(theme.skyColor(timeOfDay: 0.25) == theme.skyDawn)
    }

    @Test("sky at noon matches skyNoon")
    func skyAtNoon() {
        let theme = ColorTheme()
        #expect(theme.skyColor(timeOfDay: 0.5) == theme.skyNoon)
    }

    @Test("sky at dusk matches skyDusk")
    func skyAtDusk() {
        let theme = ColorTheme()
        #expect(theme.skyColor(timeOfDay: 0.75) == theme.skyDusk)
    }

    @Test("sky at end-of-day wraps back to skyNight")
    func skyAtEndOfDay() {
        let theme = ColorTheme()
        #expect(theme.skyColor(timeOfDay: 1.0) == theme.skyNight)
    }

    @Test("sky between anchors is a strict lerp")
    func skyBetweenAnchors() {
        let theme = ColorTheme()
        // Halfway between dawn (0.25) and noon (0.5) is 0.375.
        let c = theme.skyColor(timeOfDay: 0.375)
        let expected = theme.skyDawn.lerp(to: theme.skyNoon, t: 0.5)
        #expect(abs(c.r - expected.r) < 1e-9)
        #expect(abs(c.g - expected.g) < 1e-9)
        #expect(abs(c.b - expected.b) < 1e-9)
    }

    @Test("sky time outside 0...1 wraps cleanly")
    func skyWrapsOutsideUnitInterval() {
        let theme = ColorTheme()
        // 1.25 normalized is 0.25 → dawn
        #expect(theme.skyColor(timeOfDay: 1.25) == theme.skyDawn)
        // -0.25 normalized is 0.75 → dusk
        #expect(theme.skyColor(timeOfDay: -0.25) == theme.skyDusk)
    }

    @Test("uniform sky anchors yield a constant sky regardless of time")
    func uniformAnchorsKillTimeOfDay() {
        var theme = ColorTheme()
        let locked = SimColor(r: 0.5, g: 0.3, b: 0.7)
        theme.skyDawn = locked
        theme.skyNoon = locked
        theme.skyDusk = locked
        theme.skyNight = locked
        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(theme.skyColor(timeOfDay: t) == locked)
        }
    }
}

@Suite("Color Theme — water (swap pressure)")
struct ColorThemeWaterTests {
    @Test("liquid color matches noSwap endpoint at swapUsage=0")
    func liquidColorAtNoSwap() {
        let theme = ColorTheme()
        #expect(theme.liquidColor(swapUsage: 0) == theme.liquidNoSwap)
    }

    @Test("liquid color matches maxSwap endpoint at swapUsage=1")
    func liquidColorAtMaxSwap() {
        let theme = ColorTheme()
        #expect(theme.liquidColor(swapUsage: 1) == theme.liquidMaxSwap)
    }

    @Test("liquid color shifts redder as swap increases")
    func liquidColorShiftsRed() {
        let theme = ColorTheme()
        let noSwap = theme.liquidColor(swapUsage: 0)
        let fullSwap = theme.liquidColor(swapUsage: 1)
        #expect(fullSwap.r > noSwap.r)
    }
}

@Suite("Color Theme — Codable migration")
struct ColorThemeMigrationTests {
    @Test("current-schema themes round-trip through JSON")
    func roundTripsCurrentSchema() throws {
        var theme = ColorTheme()
        theme.skyDawn = SimColor(r: 0.1, g: 0.2, b: 0.3)
        theme.liquidMaxSwap = SimColor(r: 0.9, g: 0.1, b: 0.1)
        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(ColorTheme.self, from: data)
        #expect(decoded == theme)
    }

    @Test("legacy air/swap JSON migrates to sky anchors without losing user intent")
    func migratesLegacyAirFields() throws {
        // Craft a pre-#3 payload with only airNoSwap / airMaxSwap set.
        let legacy: [String: Any] = [
            "airNoSwap":  ["r": 0.1, "g": 0.2, "b": 0.8, "a": 1.0],
            "airMaxSwap": ["r": 0.9, "g": 0.2, "b": 0.1, "a": 1.0],
            "liquidNoSwap":  ["r": 0.2, "g": 0.3, "b": 0.9, "a": 1.0],
            "liquidMaxSwap": ["r": 0.9, "g": 0.2, "b": 0.1, "a": 1.0],
            "duckBody": ["r": 0.94, "g": 0.82, "b": 0.0,  "a": 1.0],
            "duckBill": ["r": 0.88, "g": 0.56, "b": 0.0,  "a": 1.0],
            "duckEye":  ["r": 0.13, "g": 0.13, "b": 0.13, "a": 1.0],
            "bubbleColor": ["r": 1, "g": 1, "b": 1, "a": 0.6]
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(ColorTheme.self, from: data)

        // Legacy airNoSwap should land on skyNoon (the "calm" anchor);
        // airMaxSwap should land on skyDusk (the "warm stressed" anchor).
        #expect(decoded.skyNoon == SimColor(r: 0.1, g: 0.2, b: 0.8))
        #expect(decoded.skyDusk == SimColor(r: 0.9, g: 0.2, b: 0.1))
        // Water anchors pass through unchanged.
        #expect(decoded.liquidNoSwap == SimColor(r: 0.2, g: 0.3, b: 0.9))
    }

    @Test("empty JSON object yields factory defaults")
    func emptyJsonIsDefaults() throws {
        let data = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(ColorTheme.self, from: data)
        #expect(decoded == ColorTheme())
    }

    @Test("encoder does not emit legacy airNoSwap / airMaxSwap keys")
    func encodingOmitsLegacyKeys() throws {
        let data = try JSONEncoder().encode(ColorTheme())
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(!json.contains("airNoSwap"))
        #expect(!json.contains("airMaxSwap"))
    }
}

@Suite("Time Of Day")
struct TimeOfDayTests {
    private func date(hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 14
        components.hour = hour
        components.minute = minute
        components.second = second
        return cal.date(from: components)!
    }

    @Test("midnight is 0.0")
    func midnightIsZero() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let frac = TimeOfDay.fraction(from: date(hour: 0), calendar: cal)
        #expect(abs(frac - 0.0) < 1e-9)
    }

    @Test("6am is 0.25")
    func sixAMIsQuarter() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let frac = TimeOfDay.fraction(from: date(hour: 6), calendar: cal)
        #expect(abs(frac - 0.25) < 1e-9)
    }

    @Test("noon is 0.5")
    func noonIsHalf() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let frac = TimeOfDay.fraction(from: date(hour: 12), calendar: cal)
        #expect(abs(frac - 0.5) < 1e-9)
    }

    @Test("6pm is 0.75")
    func sixPMIsThreeQuarters() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let frac = TimeOfDay.fraction(from: date(hour: 18), calendar: cal)
        #expect(abs(frac - 0.75) < 1e-9)
    }

    @Test("seconds contribute finely to the fraction")
    func secondsContribute() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let frac = TimeOfDay.fraction(from: date(hour: 12, minute: 30, second: 0), calendar: cal)
        // 12h30m = 12.5h / 24h = 0.52083...
        #expect(abs(frac - (12.5 / 24.0)) < 1e-9)
    }
}
