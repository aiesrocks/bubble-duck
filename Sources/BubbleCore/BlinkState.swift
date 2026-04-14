// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — occasional-blink animation state for floating agents

import Foundation

/// Animates an agent's eyelids. Each agent owns one `BlinkState` that
/// ticks every simulation frame. Rendering scales the eye's vertical
/// extent by `openness` so a blink reads as a natural squash.
///
/// Timing: after an idle interval (seconds), a ~150ms cosine squash
/// drops `openness` to 0 and back to 1, then a new random idle interval
/// is picked via the closure passed to `step`. Tests inject a
/// deterministic closure; production uses the default RNG.
public struct BlinkState: Sendable, Equatable {
    /// Eyelid openness: 0 = fully closed, 1 = fully open.
    /// Rendering multiplies the eye's height by this (clamped so the
    /// eye never mathematically vanishes — a thin line remains).
    public private(set) var openness: Double

    /// Seconds remaining in the idle phase before the next blink.
    /// Non-positive means a blink has started or is due this frame.
    public private(set) var timeUntilBlink: Double

    /// Progress through the current blink, 0.0...1.0. When zero, the
    /// agent is idle (not blinking). Reaching 1.0 ends the blink and
    /// picks the next idle interval.
    public private(set) var blinkProgress: Double

    /// Duration of a single blink animation, in seconds.
    public static let blinkDuration: Double = 0.15

    /// Typical blink interval range used by the default `nextInterval`.
    public static let defaultIntervalRange: ClosedRange<Double> = 3.0...6.5

    public init(initialInterval: Double = 2.0) {
        self.openness = 1.0
        self.timeUntilBlink = initialInterval
        self.blinkProgress = 0.0
    }

    /// Advance by `deltaTime` seconds. When a blink finishes, the next
    /// idle interval is provided by `nextInterval`. The default draws
    /// uniformly from `defaultIntervalRange` via the system RNG, which
    /// is fine for production but non-deterministic for tests; tests
    /// should pass a closure that returns a fixed value.
    public mutating func step(
        deltaTime: Double,
        nextInterval: () -> Double = { Double.random(in: BlinkState.defaultIntervalRange) }
    ) {
        if blinkProgress > 0 {
            blinkProgress += deltaTime / Self.blinkDuration
            if blinkProgress >= 1.0 {
                // Blink complete — snap open, queue next interval.
                blinkProgress = 0.0
                openness = 1.0
                timeUntilBlink = max(0.05, nextInterval())
            } else {
                // Smooth cosine sweep: open → closed → open.
                openness = 0.5 + 0.5 * cos(blinkProgress * 2 * .pi)
            }
        } else {
            timeUntilBlink -= deltaTime
            if timeUntilBlink <= 0 {
                // Start a blink next step — give it a non-zero progress
                // so we're in the "blinking" branch; the tiny initial
                // value corresponds to ~fully-open for one frame.
                blinkProgress = 0.0001
                openness = 1.0
            }
        }
    }
}
