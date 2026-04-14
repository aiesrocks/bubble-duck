// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — based on wmbubble by Johan Walles, Merlin Hughes, and timecop

import Foundation

/// Combined simulation state tying water, bubbles, and system metrics together.
public struct SimulationState: Sendable {
    public var water: WaterSimulation
    public var bubbleSystem: BubbleSystem
    public var duck: DuckState
    public var overlay: OverlayState

    /// User-facing configuration (physics knobs, features, colors).
    /// Mutating this directly has no effect; call `apply(_:)` to push changes
    /// into the sub-systems.
    public private(set) var config: SimulationConfig

    // Current system metrics (0.0...1.0)
    public var cpuLoad: Double = 0.0
    public var memoryUsage: Double = 0.0
    public var swapUsage: Double = 0.0

    /// Size of the rendering canvas in points
    public let canvasSize: Int

    public init(canvasSize: Int = 256, config: SimulationConfig = .default) {
        self.canvasSize = canvasSize
        // Use fewer columns than pixels for smoother waves
        let columnCount = canvasSize / 4
        self.water = WaterSimulation(columnCount: columnCount)
        self.bubbleSystem = BubbleSystem()
        self.duck = DuckState()
        self.overlay = OverlayState()
        self.config = config
        apply(config)
    }

    /// Push a new configuration into the water / bubble / duck sub-systems.
    /// Safe to call any time — sub-system *state* (levels, bubbles, positions)
    /// is preserved; only the tunable parameters are overwritten.
    public mutating func apply(_ config: SimulationConfig) {
        self.config = config
        water.volatility = config.volatility
        water.viscosity = config.viscosity
        water.speedLimit = config.speedLimit
        bubbleSystem.maxBubbles = config.maxBubbles
        bubbleSystem.gravity = config.gravity
        bubbleSystem.rippleStrength = config.rippleStrength
        duck.enabled = config.duckEnabled
    }

    /// Advance the simulation by one frame.
    public mutating func step() {
        // Update water target from memory usage
        water.targetLevel = memoryUsage

        // Maybe spawn bubbles based on CPU
        if let col = bubbleSystem.maybeSpawn(cpuLoad: cpuLoad, columnCount: water.columnCount) {
            water.displace(column: col, amount: -bubbleSystem.rippleStrength)
        }

        // Step bubbles, get popped columns
        let popped = bubbleSystem.step(waterLevels: water.levels)
        for col in popped {
            water.displace(column: col, amount: bubbleSystem.rippleStrength)
        }

        // Step water physics
        water.step()

        // Step duck
        duck.step(waterLevels: water.levels)

        // Animate overlay alpha
        overlay.stepAlpha()
    }
}

/// The floating agent that sits on the water surface.
/// Speed is driven by a configurable system metric (network, disk, GPU).
public struct DuckState: Sendable {
    public var x: Double = 0.5        // 0.0...1.0 horizontal position
    public var y: Double = 0.5        // vertical position (follows water)
    public var velocityX: Double = 0.001
    public var bobAngle: Double = 0.0 // for gentle bobbing
    public var isUpsideDown: Bool = false
    public var enabled: Bool = true

    /// Speed factor driven by the chosen metric (0.0...1.0).
    /// 0 = gentle drift, 1 = zipping across.
    public var speedFactor: Double = 0.0

    /// Eyelid animation state. Each new agent gets a randomized initial
    /// interval so blinks don't sync when the agent type is swapped.
    public var blink: BlinkState = BlinkState(initialInterval: Double.random(in: 1.0...3.5))

    /// Base drift speed (gentle idle movement)
    private let baseSpeed: Double = 0.0005
    /// Maximum additional speed from the metric
    private let maxExtraSpeed: Double = 0.004

    public init() {}

    public mutating func step(waterLevels: [Double]) {
        guard enabled, !waterLevels.isEmpty else { return }

        // Drift speed = base + metric-driven extra
        let currentSpeed = baseSpeed + speedFactor * maxExtraSpeed
        let direction: Double = velocityX >= 0 ? 1 : -1
        velocityX = direction * currentSpeed

        x += velocityX
        if x > 0.85 || x < 0.15 {
            velocityX = -velocityX
        }

        // Follow water surface
        let col = min(Int(x * Double(waterLevels.count)), waterLevels.count - 1)
        y = waterLevels[col]

        // Bob gently — faster bobbing when moving faster
        bobAngle += 0.03 + speedFactor * 0.07
        if bobAngle > .pi * 2 { bobAngle -= .pi * 2 }

        // Flip upside down if water is very high (>95%)
        isUpsideDown = y > 0.95

        // Advance eyelid animation at the fixed simulation step rate.
        blink.step(deltaTime: 1.0 / 60.0)
    }
}
