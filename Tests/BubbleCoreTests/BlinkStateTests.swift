// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import BubbleCore

@Suite("Blink State")
struct BlinkStateTests {
    @Test("starts fully open")
    func startsOpen() {
        let b = BlinkState()
        #expect(b.openness == 1.0)
        #expect(b.blinkProgress == 0.0)
    }

    @Test("idle countdown decrements without triggering a blink early")
    func idleCountdownDecrements() {
        var b = BlinkState(initialInterval: 1.0)
        b.step(deltaTime: 0.5, nextInterval: { 99 })
        #expect(b.openness == 1.0)
        #expect(b.blinkProgress == 0.0)
        #expect(abs(b.timeUntilBlink - 0.5) < 1e-9)
    }

    @Test("blink starts once idle time reaches zero")
    func blinkStartsAtZero() {
        var b = BlinkState(initialInterval: 0.1)
        b.step(deltaTime: 0.2, nextInterval: { 99 })
        #expect(b.blinkProgress > 0)
    }

    @Test("openness drops below 0.5 mid-blink")
    func closesMidBlink() {
        var b = BlinkState(initialInterval: 0.0)
        // Kick off the blink and advance to the midpoint (~75 ms in).
        b.step(deltaTime: 0.0, nextInterval: { 99 })
        b.step(deltaTime: BlinkState.blinkDuration / 2, nextInterval: { 99 })
        #expect(b.openness < 0.5)
    }

    @Test("returns to fully open after blink completes")
    func opensAfterBlink() {
        var b = BlinkState(initialInterval: 0.0)
        b.step(deltaTime: 0.0, nextInterval: { 99 })
        // Overshoot the blink duration so we land past progress >= 1.
        b.step(deltaTime: BlinkState.blinkDuration * 1.5, nextInterval: { 99 })
        #expect(b.openness == 1.0)
        #expect(b.blinkProgress == 0.0)
    }

    @Test("uses nextInterval closure to schedule the following blink")
    func usesNextIntervalClosure() {
        var b = BlinkState(initialInterval: 0.0)
        b.step(deltaTime: 0.0, nextInterval: { 99 })
        b.step(deltaTime: BlinkState.blinkDuration * 1.5, nextInterval: { 4.2 })
        #expect(abs(b.timeUntilBlink - 4.2) < 1e-9)
    }

    @Test("successive blinks fire at the requested cadence")
    func successiveBlinks() {
        var b = BlinkState(initialInterval: 0.0)
        var intervalsHandedOut = 0
        let interval = 0.5
        // Simulate ~3 blinks at 60fps.
        let dt = 1.0 / 60.0
        for _ in 0..<Int((interval + BlinkState.blinkDuration) * 3.5 * 60) {
            b.step(deltaTime: dt, nextInterval: {
                intervalsHandedOut += 1
                return interval
            })
        }
        #expect(intervalsHandedOut >= 3)
    }
}
