// SPDX-License-Identifier: GPL-2.0-or-later

import Testing
@testable import BubbleCore

@Suite("Duck State")
struct DuckStateTests {
    @Test("duck y follows water level under its x position")
    func duckFollowsWater() {
        var duck = DuckState()
        duck.x = 0.5
        let levels = Array(repeating: 0.3, count: 16)
        duck.step(waterLevels: levels)
        #expect(abs(duck.y - 0.3) < 0.001)
    }

    @Test("duck flips upside-down when water exceeds 0.95")
    func duckFlipsWhenFull() {
        var duck = DuckState()
        duck.x = 0.5
        let levels = Array(repeating: 0.98, count: 16)
        duck.step(waterLevels: levels)
        #expect(duck.isUpsideDown)
    }

    @Test("duck stays upright at normal water level")
    func duckUpright() {
        var duck = DuckState()
        duck.x = 0.5
        let levels = Array(repeating: 0.5, count: 16)
        duck.step(waterLevels: levels)
        #expect(!duck.isUpsideDown)
    }

    @Test("duck reverses at the right edge")
    func duckBouncesRight() {
        var duck = DuckState()
        duck.x = 0.86
        duck.velocityX = 0.01
        let levels = Array(repeating: 0.5, count: 16)
        duck.step(waterLevels: levels)
        #expect(duck.velocityX < 0)
    }

    @Test("duck reverses at the left edge")
    func duckBouncesLeft() {
        var duck = DuckState()
        duck.x = 0.14
        duck.velocityX = -0.01
        let levels = Array(repeating: 0.5, count: 16)
        duck.step(waterLevels: levels)
        #expect(duck.velocityX > 0)
    }

    @Test("disabled duck does not move")
    func disabledDuckDoesNotMove() {
        var duck = DuckState()
        duck.enabled = false
        let originalX = duck.x
        let originalY = duck.y
        let levels = Array(repeating: 0.8, count: 16)
        duck.step(waterLevels: levels)
        #expect(duck.x == originalX)
        #expect(duck.y == originalY)
    }

    @Test("empty water levels are handled safely")
    func emptyWaterLevels() {
        var duck = DuckState()
        // should not crash or mutate y into NaN
        duck.step(waterLevels: [])
    }

    @Test("bob angle wraps around 2π")
    func bobAngleWraps() {
        var duck = DuckState()
        duck.bobAngle = 2 * .pi - 0.01
        let levels = Array(repeating: 0.5, count: 16)
        duck.step(waterLevels: levels)
        #expect(duck.bobAngle < 2 * .pi)
        #expect(duck.bobAngle >= 0)
    }

    @Test("step advances the blink idle countdown")
    func stepAdvancesBlink() {
        var duck = DuckState()
        let levels = Array(repeating: 0.5, count: 16)
        let before = duck.blink.timeUntilBlink
        duck.step(waterLevels: levels)
        #expect(duck.blink.timeUntilBlink < before)
    }

    @Test("step returns splash column when bouncing at right edge")
    func stepReturnsSplashRight() {
        var duck = DuckState()
        duck.x = 0.84
        duck.velocityX = 0.02  // ensure we cross 0.85 in a single step
        let levels = Array(repeating: 0.5, count: 16)
        let splash = duck.step(waterLevels: levels)
        #expect(splash != nil)
    }

    @Test("step returns splash column when bouncing at left edge")
    func stepReturnsSplashLeft() {
        var duck = DuckState()
        duck.x = 0.16
        duck.velocityX = -0.02
        let levels = Array(repeating: 0.5, count: 16)
        let splash = duck.step(waterLevels: levels)
        #expect(splash != nil)
    }

    @Test("no splash on a normal middle-of-tank step")
    func noSplashMidTank() {
        var duck = DuckState()
        duck.x = 0.5
        duck.velocityX = 0.01
        let levels = Array(repeating: 0.5, count: 16)
        let splash = duck.step(waterLevels: levels)
        #expect(splash == nil)
    }
}
