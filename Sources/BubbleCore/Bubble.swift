// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — based on wmbubble by Johan Walles, Merlin Hughes, and timecop

import Foundation

/// A single bubble rising through the water tank.
public struct Bubble: Sendable {
    public var x: Double      // 0.0...1.0 normalized position
    public var y: Double      // 0.0...1.0 (0 = bottom, 1 = top)
    public var dy: Double     // vertical velocity
    public var size: Double   // radius in normalized coords

    public init(x: Double, y: Double, size: Double = 0.02) {
        self.x = x
        self.y = y
        self.dy = 0.0
        self.size = size
    }
}

/// Manages a collection of bubbles. Bubble creation rate is tied to CPU load,
/// matching wmbubble's behavior where rand() % 101 <= loadPercentage.
public struct BubbleSystem: Sendable {
    public private(set) var bubbles: [Bubble] = []
    public var maxBubbles: Int = 100
    public var gravity: Double = 0.001    // upward acceleration per step
    public var rippleStrength: Double = 0.005

    public init() {}

    /// Possibly spawn a new bubble based on CPU load (0.0...1.0).
    /// Returns the column index if a bubble was created (for water displacement).
    @discardableResult
    public mutating func maybeSpawn(cpuLoad: Double, columnCount: Int) -> Int? {
        guard bubbles.count < maxBubbles else { return nil }

        guard cpuLoad > 0 else { return nil }
        let spawnChance = cpuLoad * 100.0
        let roll = Double(Int.random(in: 0...100))
        guard roll <= spawnChance else { return nil }

        let x = Double.random(in: 0.05...0.95)
        let bubble = Bubble(x: x, y: 0.0, size: Double.random(in: 0.015...0.035))
        bubbles.append(bubble)

        let column = Int(x * Double(columnCount))
        return min(column, columnCount - 1)
    }

    /// Spawn a burst of small bubbles near a surface point — used by the
    /// agent-edge-bounce splash (aiesrocks/bubble-duck#6). Respects
    /// `maxBubbles`; if the tank is full the burst silently shrinks.
    @discardableResult
    public mutating func spawnBurst(x: Double, nearSurface surface: Double, count: Int) -> Int {
        let slots = max(0, maxBubbles - bubbles.count)
        let n = min(slots, count)
        guard n > 0 else { return 0 }
        for _ in 0..<n {
            let bx = min(0.99, max(0.01, x + Double.random(in: -0.04...0.04)))
            // Start just below the water surface so the burst rises visibly.
            let by = max(0.0, min(1.0, surface - Double.random(in: 0.02...0.06)))
            bubbles.append(Bubble(x: bx, y: by, size: Double.random(in: 0.008...0.018)))
        }
        return n
    }

    /// Advance all bubbles. Returns columns where bubbles popped (reached surface).
    public mutating func step(waterLevels: [Double]) -> [Int] {
        var poppedColumns: [Int] = []
        let columnCount = waterLevels.count

        var i = 0
        while i < bubbles.count {
            bubbles[i].dy += gravity
            bubbles[i].y += bubbles[i].dy

            // Check if bubble reached water surface
            let col = min(Int(bubbles[i].x * Double(columnCount)), columnCount - 1)
            let surfaceLevel = waterLevels[col]

            if bubbles[i].y >= surfaceLevel {
                poppedColumns.append(col)
                // Remove by swap with last (wmbubble technique)
                bubbles[i] = bubbles[bubbles.count - 1]
                bubbles.removeLast()
            } else {
                i += 1
            }
        }

        return poppedColumns
    }
}
