// SPDX-License-Identifier: GPL-2.0-or-later

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

@Suite("Color Theme")
struct ColorThemeTests {
    @Test("air color matches noSwap endpoint at swapUsage=0")
    func airColorAtNoSwap() {
        let theme = ColorTheme()
        #expect(theme.airColor(swapUsage: 0) == theme.airNoSwap)
    }

    @Test("air color matches maxSwap endpoint at swapUsage=1")
    func airColorAtMaxSwap() {
        let theme = ColorTheme()
        #expect(theme.airColor(swapUsage: 1) == theme.airMaxSwap)
    }

    @Test("air color shifts redder as swap increases")
    func airColorShiftsRed() {
        let theme = ColorTheme()
        let noSwap = theme.airColor(swapUsage: 0)
        let fullSwap = theme.airColor(swapUsage: 1)
        #expect(fullSwap.r > noSwap.r)
    }

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
