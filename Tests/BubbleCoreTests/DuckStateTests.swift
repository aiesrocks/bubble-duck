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

    // MARK: - Idle sleep (aiesrocks/bubble-duck#5)

    @Test("sleepiness climbs when CPU is below the idle threshold")
    func sleepinessClimbsWhenIdle() {
        var duck = DuckState()
        let levels = Array(repeating: 0.5, count: 16)
        for _ in 0..<60 {
            duck.step(waterLevels: levels, cpuLoad: 0.02)
        }
        #expect(duck.sleepiness > 0.0)
    }

    @Test("sleepiness stays 0 when CPU is above the idle threshold")
    func sleepinessStaysZeroUnderLoad() {
        var duck = DuckState()
        let levels = Array(repeating: 0.5, count: 16)
        for _ in 0..<60 {
            duck.step(waterLevels: levels, cpuLoad: 0.5)
        }
        #expect(duck.sleepiness == 0.0)
    }

    @Test("sleepiness drops rapidly on a CPU spike")
    func sleepinessDropsOnSpike() {
        var duck = DuckState()
        duck.sleepiness = 1.0
        let levels = Array(repeating: 0.5, count: 16)
        // A single step at high CPU should already noticeably reduce sleepiness
        duck.step(waterLevels: levels, cpuLoad: 0.8)
        #expect(duck.sleepiness < 1.0)
    }

    @Test("sleepiness reaches 1.0 after ~30s of idle")
    func sleepinessReachesFullAfter30s() {
        var duck = DuckState()
        let levels = Array(repeating: 0.5, count: 16)
        // 31s worth of 1/60s steps → enough to saturate
        for _ in 0..<Int(31 * 60) {
            duck.step(waterLevels: levels, cpuLoad: 0.0)
        }
        #expect(duck.sleepiness == 1.0)
    }

    @Test("effective eyelid openness is unaffected at low sleepiness")
    func effectiveOpennessAwake() {
        var duck = DuckState()
        duck.sleepiness = 0.0
        // blink.openness defaults to 1.0
        #expect(duck.effectiveEyelidOpenness == 1.0)
    }

    @Test("effective eyelid openness collapses when fully asleep")
    func effectiveOpennessAsleep() {
        var duck = DuckState()
        duck.sleepiness = 1.0
        #expect(duck.effectiveEyelidOpenness == 0.0)
    }

    @Test("idle threshold matches the approved spec (10%)")
    func idleThresholdMatchesSpec() {
        #expect(DuckState.idleCPUThreshold == 0.10)
    }
}
