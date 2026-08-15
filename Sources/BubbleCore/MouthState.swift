// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — occasional mouth/beak animation for floating agents

import Foundation

/// Per-species mouth timing. A duck's bill snaps; a hippo hangs its jaw open
/// and leaves it there, which is most of what makes a hippo gape read as a
/// hippo gape rather than a fast yawn.
public struct MouthProfile: Sendable, Equatable {
    /// Seconds for one complete open → hold → close.
    public var duration: Double
    /// Progress fraction where the hold begins (the open easing ends).
    public var holdStart: Double
    /// Progress fraction where the hold ends (the close easing begins).
    public var holdEnd: Double
    /// Seconds between spontaneous opens.
    public var intervalRange: ClosedRange<Double>

    public init(duration: Double, holdStart: Double, holdEnd: Double,
                intervalRange: ClosedRange<Double>) {
        self.duration = duration
        self.holdStart = holdStart
        self.holdEnd = holdEnd
        self.intervalRange = intervalRange
    }

    /// Quick open, short hold — bills, beaks, small mouths.
    public static let standard = MouthProfile(
        duration: 0.9, holdStart: 0.30, holdEnd: 0.65, intervalRange: 7.0...16.0
    )

    /// Slow, wide, and held for a long beat. Hippos gape for several seconds
    /// at a time, so the hold is most of the animation.
    public static let hippo = MouthProfile(
        duration: 3.6, holdStart: 0.14, holdEnd: 0.82, intervalRange: 6.0...14.0
    )

    /// A frog's mouth is most of its face; it opens wide but briefly.
    public static let frog = MouthProfile(
        duration: 1.1, holdStart: 0.25, holdEnd: 0.55, intervalRange: 5.0...12.0
    )
}

public extension AgentType {
    /// How this character's mouth behaves. Characters without a mouth in
    /// their silhouette (otter, turtle, origami boat) never animate one, so
    /// their profile is only a placeholder.
    var mouthProfile: MouthProfile {
        switch self {
        case .hippo: return .hippo
        case .frog:  return .frog
        default:     return .standard
        }
    }
}

/// Animates an agent's mouth or beak. Sibling of `BlinkState`, but shaped
/// differently: a blink is a fast symmetric squash, while a mouth *opens*,
/// holds for a beat, and closes. That hold is what makes a hippo yawn read as
/// a yawn rather than a twitch.
///
/// Envelope over `profile.duration`:
///   0 → holdStart   ease open
///   holdStart → holdEnd  hold wide
///   holdEnd → 1     ease closed
public struct MouthState: Sendable, Equatable {
    /// 0 = shut, 1 = fully open. Renderers scale their own mouth geometry.
    public private(set) var openness: Double

    /// Seconds remaining before the next spontaneous open.
    public private(set) var timeUntilOpen: Double

    /// Progress through the current open/hold/close, 0...1. Zero = idle.
    public private(set) var progress: Double

    /// Species timing. Swapping this mid-animation is safe — progress is a
    /// fraction, so the current open simply finishes on the new schedule.
    public var profile: MouthProfile

    /// Kept for callers that want the stock cadence without a profile.
    public static let defaultIntervalRange: ClosedRange<Double> = MouthProfile.standard.intervalRange

    public init(initialInterval: Double = 5.0, profile: MouthProfile = .standard) {
        self.openness = 0.0
        self.timeUntilOpen = initialInterval
        self.progress = 0.0
        self.profile = profile
    }

    /// Open now, wherever the idle countdown had got to. Used to make agents
    /// react to something rather than only to their own timer.
    public mutating func trigger() {
        guard progress <= 0 else { return }   // already mid-animation
        progress = 0.0001
    }

    /// True while the mouth is animating.
    public var isOpening: Bool { progress > 0 }

    /// Advance by `deltaTime` seconds. `nextInterval` supplies the next idle
    /// gap when an animation completes; tests inject a deterministic closure.
    public mutating func step(
        deltaTime: Double,
        nextInterval: (() -> Double)? = nil
    ) {
        guard progress > 0 else {
            timeUntilOpen -= deltaTime
            if timeUntilOpen <= 0 { progress = 0.0001 }
            return
        }

        progress += deltaTime / profile.duration
        if progress >= 1.0 {
            progress = 0.0
            openness = 0.0
            let next = nextInterval?() ?? Double.random(in: profile.intervalRange)
            timeUntilOpen = max(0.05, next)
            return
        }
        openness = MouthState.envelope(progress, profile: profile)
    }

    /// Open/hold/close curve, smoothstepped on both edges so nothing snaps.
    public static func envelope(_ progress: Double,
                                profile: MouthProfile = .standard) -> Double {
        let p = max(0, min(1, progress))
        let start = max(0.001, profile.holdStart)
        let end = min(0.999, max(start + 0.001, profile.holdEnd))
        if p < start { return smoothstep(p / start) }
        if p < end { return 1.0 }
        return smoothstep(1.0 - (p - end) / (1.0 - end))
    }

    private static func smoothstep(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return x * x * (3 - 2 * x)
    }
}
