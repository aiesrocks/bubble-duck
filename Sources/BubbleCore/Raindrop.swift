// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — raindrops that fall from the sky during high disk I/O
// (aiesrocks/bubble-duck#10).

import Foundation

/// A single falling raindrop. Spawned at y = 1.0 (top of canvas), falls
/// toward the water surface; removed on contact and replaced with a small
/// ripple + downward water displacement.
public struct Raindrop: Sendable, Equatable {
    /// Horizontal position, 0...1.
    public var x: Double
    /// Vertical position, 0 at water-tank bottom → 1 at canvas top.
    public var y: Double
    /// Per-frame fall speed (decremented from y each step). Mild randomness
    /// per drop so the rain doesn't look mechanical.
    public var fallSpeed: Double

    public init(x: Double, y: Double, fallSpeed: Double) {
        self.x = x
        self.y = y
        self.fallSpeed = fallSpeed
    }
}
