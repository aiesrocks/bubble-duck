// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — expanding water-surface rings spawned by bubble pops
// and agent edge bounces (aiesrocks/bubble-duck#4).

import Foundation

/// A single animated ripple ring on the water surface. Expands from 0 to
/// `maxRadius` over its lifetime while its alpha fades to zero, giving
/// classic "juice" to every bubble pop.
public struct RippleRing: Sendable, Equatable {
    /// Horizontal position in the canvas, 0...1.
    public var x: Double
    /// Vertical position (water-surface level at spawn time), 0...1.
    public var y: Double
    /// Progress through lifetime, 0 = just spawned, 1 = about to expire.
    public var age: Double
    /// Final radius of the ring at age = 1, in 0...1 canvas units.
    public var maxRadius: Double

    /// Lifetime of one ring in seconds. Short so the effect reads as a
    /// quick pop rather than a slow wave.
    public static let lifetimeSeconds: Double = 0.4
    /// Default peak radius (as a fraction of the canvas).
    public static let defaultMaxRadius: Double = 0.08

    public init(x: Double, y: Double, maxRadius: Double = defaultMaxRadius) {
        self.x = x
        self.y = y
        self.age = 0
        self.maxRadius = maxRadius
    }
}
