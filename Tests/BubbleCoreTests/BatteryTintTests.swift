// SPDX-License-Identifier: GPL-2.0-or-later

import Testing
@testable import BubbleCore

@Suite("Battery Tint")
struct BatteryTintTests {
    // A calm cyan test color used across most tests.
    private let baseColor = SimColor(r: 0.2, g: 0.4, b: 0.9)

    @Test("full battery leaves the color unchanged")
    func normalZoneNoEffect() {
        let out = BatteryTint.apply(to: baseColor, batteryFraction: 1.0)
        #expect(out == baseColor)
    }

    @Test("above 20% battery is in the normal zone")
    func normalZoneThreshold() {
        #expect(BatteryTint.zone(for: 1.0) == .normal)
        #expect(BatteryTint.zone(for: 0.50) == .normal)
        #expect(BatteryTint.zone(for: 0.21) == .normal)
    }

    @Test("exactly 20% enters the warning zone")
    func warningZoneStart() {
        #expect(BatteryTint.zone(for: 0.20) == .warning)
    }

    @Test("between 10% and 20% battery stays in warning zone")
    func warningZoneRange() {
        #expect(BatteryTint.zone(for: 0.15) == .warning)
        #expect(BatteryTint.zone(for: 0.11) == .warning)
    }

    @Test("at or below 10% is critical")
    func criticalZoneBoundary() {
        #expect(BatteryTint.zone(for: 0.10) == .critical)
        #expect(BatteryTint.zone(for: 0.05) == .critical)
        #expect(BatteryTint.zone(for: 0.0)  == .critical)
    }

    @Test("warning-zone output is less saturated than the input")
    func warningDesaturates() {
        let out = BatteryTint.apply(to: baseColor, batteryFraction: 0.15)
        // "Saturation" proxy: max-min component distance shrinks
        let inSpread  = max(baseColor.r, max(baseColor.g, baseColor.b))
                      - min(baseColor.r, min(baseColor.g, baseColor.b))
        let outSpread = max(out.r, max(out.g, out.b))
                      - min(out.r, min(out.g, out.b))
        #expect(outSpread < inSpread)
    }

    @Test("critical-zone output has strong red dominance")
    func criticalIsRed() {
        let out = BatteryTint.apply(to: baseColor, batteryFraction: 0.05)
        #expect(out.r > out.g)
        #expect(out.r > out.b)
        #expect(out.r > 0.6)
    }

    @Test("lower battery yields a redder result inside the critical zone")
    func redIntensifiesDownToZero() {
        let c1 = BatteryTint.apply(to: baseColor, batteryFraction: 0.08)
        let c2 = BatteryTint.apply(to: baseColor, batteryFraction: 0.0)
        #expect(c2.r >= c1.r)
        #expect(c2.b <= c1.b) // blue fades faster as severity climbs
    }

    @Test("desaturate helper preserves alpha and averages toward gray")
    func desaturateHelper() {
        let c = SimColor(r: 1.0, g: 0.0, b: 0.0, a: 0.7)
        let out = BatteryTint.desaturate(c, by: 1.0) // fully desaturated → gray
        #expect(abs(out.r - out.g) < 1e-9)
        #expect(abs(out.g - out.b) < 1e-9)
        #expect(out.a == 0.7)
    }
}
