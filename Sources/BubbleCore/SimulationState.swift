// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — based on wmbubble by Johan Walles, Merlin Hughes, and timecop

import Foundation

/// Combined simulation state tying water, bubbles, and system metrics together.
public struct SimulationState: Sendable {
    public var water: WaterSimulation
    public var bubbleSystem: BubbleSystem
    public var duck: DuckState
    public var overlay: OverlayState

    /// Active surface ripples (aiesrocks/bubble-duck#4). Spawned on bubble
    /// pops and agent edge bounces; aged + culled each simulation step.
    public var ripples: [RippleRing] = []

    /// Active raindrops (aiesrocks/bubble-duck#10). Spawn rate is driven
    /// by `rainIntensity`; drops fall until they hit the water surface, at
    /// which point they're removed and produce a small displacement + ripple.
    public var raindrops: [Raindrop] = []

    /// Rain spawn intensity 0...1, typically normalized from disk IOPS by
    /// the macOS layer. 0 → no rain, 1 → roughly a drop per frame (max).
    public var rainIntensity: Double = 0.0

    /// Hard cap on concurrent raindrops so a sustained IOPS burst can't
    /// create a runaway particle count.
    public static let maxRaindrops: Int = 80

    /// User-facing configuration (physics knobs, features, colors).
    /// Mutating this directly has no effect; call `apply(_:)` to push changes
    /// into the sub-systems.
    public private(set) var config: SimulationConfig

    /// Honors the system accessibility "Reduce Motion" preference
    /// (aiesrocks/bubble-duck#15). When true:
    ///   - Bubble spawning is suppressed (existing bubbles finish rising and pop)
    ///   - The agent stops drifting / bobbing / blinking, just follows water level
    ///   - Water still moves toward its memory target so the level tracks RAM
    /// Driven from the macOS layer via NSWorkspace notifications.
    public var reduceMotion: Bool = false

    // Current system metrics (0.0...1.0)
    public var cpuLoad: Double = 0.0
    public var memoryUsage: Double = 0.0
    public var swapUsage: Double = 0.0

    /// Fraction-of-day used to blend between the theme's four sky anchors
    /// (aiesrocks/bubble-duck#3). 0 = midnight, 0.25 = dawn, 0.5 = noon,
    /// 0.75 = dusk. Updated from the macOS layer once per metrics tick via
    /// `TimeOfDay.fraction(from:)`.
    public var timeOfDay: Double = 0.5

    /// Battery fraction 0...1, or nil if no battery is present
    /// (desktop Mac / external source). The renderer applies
    /// `BatteryTint.apply(to:batteryFraction:)` to the water color when
    /// this is non-nil (aiesrocks/bubble-duck#17).
    public var batteryFraction: Double? = nil

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
        // Update water target from memory usage — runs in every mode so the
        // water level still tracks RAM even with Reduce Motion on.
        water.targetLevel = memoryUsage

        // Bubble spawning is motion → skip when Reduce Motion is on.
        if !reduceMotion {
            if let col = bubbleSystem.maybeSpawn(cpuLoad: cpuLoad, columnCount: water.columnCount) {
                water.displace(column: col, amount: -bubbleSystem.rippleStrength)
            }
            // Rain spawn (aiesrocks/bubble-duck#10): probability per frame
            // equals rainIntensity, capped at maxRaindrops concurrent drops.
            if rainIntensity > 0,
               raindrops.count < SimulationState.maxRaindrops,
               Double.random(in: 0..<1) < rainIntensity {
                raindrops.append(Raindrop(
                    x: Double.random(in: 0.04...0.96),
                    y: 1.0,
                    fallSpeed: Double.random(in: 0.020...0.030)
                ))
            }
        }

        // Step raindrops (both modes — existing drops continue to fall even
        // after Reduce Motion toggles on, so there's no sudden pop).
        stepRaindrops()

        // Step existing bubbles in both modes so any currently on-screen
        // bubbles finish rising and naturally drain the tank.
        let popped = bubbleSystem.step(waterLevels: water.levels)
        for col in popped {
            water.displace(column: col, amount: bubbleSystem.rippleStrength)
            if !reduceMotion {
                // Surface ring at the pop point
                let xFrac = (Double(col) + 0.5) / Double(water.columnCount)
                let yFrac = water.levels[col]
                ripples.append(RippleRing(x: xFrac, y: yFrac))
            }
        }

        // Step water physics so levels smoothly track their memory target.
        water.step()

        // Agent motion: full step normally, pure water-following when
        // Reduce Motion is on (no drift, no bob, no blink, no splash, no sleep update).
        if reduceMotion {
            duck.followWater(waterLevels: water.levels)
        } else if let splashColumn = duck.step(waterLevels: water.levels, cpuLoad: cpuLoad) {
            let surface = water.levels[splashColumn]
            bubbleSystem.spawnBurst(x: duck.x, nearSurface: surface, count: 3)
            water.displace(column: splashColumn, amount: -bubbleSystem.rippleStrength * 0.6)
            // Agent splashes generate a slightly larger ring
            ripples.append(RippleRing(x: duck.x, y: surface, maxRadius: 0.11))
        }

        // Age ripples and cull any that have expired. Skipped under Reduce
        // Motion so any rings present before the toggle die off naturally
        // without new ones being spawned.
        if !reduceMotion {
            let dt = 1.0 / 60.0
            let increment = dt / RippleRing.lifetimeSeconds
            var i = 0
            while i < ripples.count {
                ripples[i].age += increment
                if ripples[i].age >= 1.0 {
                    ripples.remove(at: i)
                } else {
                    i += 1
                }
            }
        }

        // Animate overlay alpha
        overlay.stepAlpha()
    }

    /// Move every active raindrop down by its fall speed; a drop that
    /// reaches its column's water surface is removed and produces a small
    /// displacement + surface ring. Called unconditionally so existing
    /// drops finish falling even after Reduce Motion toggles on.
    private mutating func stepRaindrops() {
        var i = 0
        while i < raindrops.count {
            raindrops[i].y -= raindrops[i].fallSpeed
            let xFrac = raindrops[i].x
            let col = min(Int(xFrac * Double(water.columnCount)), water.columnCount - 1)
            let surface = water.levels[col]
            if raindrops[i].y <= surface {
                water.displace(column: col, amount: -0.003)
                if !reduceMotion {
                    ripples.append(RippleRing(x: xFrac, y: surface, maxRadius: 0.04))
                }
                raindrops.remove(at: i)
            } else {
                i += 1
            }
        }
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

    /// Idle-sleep progress (aiesrocks/bubble-duck#5). Climbs while CPU is
    /// below `idleCPUThreshold`, drops fast when CPU spikes again. Fully
    /// asleep (1.0) forces eyes shut via `effectiveEyelidOpenness` and
    /// invites the "Z" sprite in the renderer.
    public var sleepiness: Double = 0.0

    // MARK: - Sleep tuning (constants, not user-facing config yet)

    /// CPU load below which the system is "idle". Per aiesrocks/bubble-duck#5
    /// (user feedback on the issue bumped this from 5% to 10%).
    public static let idleCPUThreshold: Double = 0.10
    /// Wall-clock seconds of continuous idle before the agent is fully asleep.
    public static let secondsToFullSleep: Double = 30.0
    /// Wake-up happens ~10× faster than sleep build-up so a CPU spike
    /// visibly pops the eyes open within a few frames.
    public static let wakeFactor: Double = 10.0

    /// Base drift speed (gentle idle movement)
    private let baseSpeed: Double = 0.0005
    /// Maximum additional speed from the metric
    private let maxExtraSpeed: Double = 0.004

    public init() {}

    /// Effective eyelid openness combining blink animation and sleepiness.
    /// 1.0 = fully open, 0.0 = fully closed. The renderer uses this
    /// (via `fillEye` / `fillEyeGlint`) so sleepy eyes ride on top of the
    /// normal blink machinery.
    public var effectiveEyelidOpenness: Double {
        let sleepAttenuation = DuckState.smoothstep(from: 0.5, to: 1.0, value: sleepiness)
        return blink.openness * (1.0 - sleepAttenuation)
    }

    /// Smoothstep easing between `from` and `to` (returns 0 below `from`,
    /// 1 above `to`, smooth cubic curve in between).
    public static func smoothstep(from: Double, to: Double, value: Double) -> Double {
        guard to > from else { return 0 }
        let t = max(0, min(1, (value - from) / (to - from)))
        return t * t * (3 - 2 * t)
    }

    /// Advance the duck by one frame. Returns the water-column index where
    /// the agent just bounced off an edge, or `nil` if no bounce this frame.
    /// Callers can use the bounce column to trigger a splash / ripple.
    ///
    /// `cpuLoad` feeds the idle-sleep animation — below `idleCPUThreshold`
    /// sleepiness rises toward 1.0; above it, sleepiness drops rapidly.
    @discardableResult
    public mutating func step(waterLevels: [Double], cpuLoad: Double = 0.0) -> Int? {
        guard enabled, !waterLevels.isEmpty else { return nil }

        // Update sleepiness before motion so the blink animation's next step
        // sees a consistent state. Fixed 1/60 dt matches the rest of the sim.
        let dt = 1.0 / 60.0
        if cpuLoad < DuckState.idleCPUThreshold {
            sleepiness = min(1.0, sleepiness + dt / DuckState.secondsToFullSleep)
        } else {
            sleepiness = max(0.0, sleepiness - DuckState.wakeFactor * dt / DuckState.secondsToFullSleep)
        }

        // Drift speed = base + metric-driven extra
        let currentSpeed = baseSpeed + speedFactor * maxExtraSpeed
        let direction: Double = velocityX >= 0 ? 1 : -1
        velocityX = direction * currentSpeed

        x += velocityX
        var splashColumn: Int? = nil
        if x > 0.85 || x < 0.15 {
            velocityX = -velocityX
            splashColumn = min(Int(x * Double(waterLevels.count)), waterLevels.count - 1)
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

        return splashColumn
    }

    /// Update only the agent's vertical position to track the water surface,
    /// without drifting, bobbing, or blinking. Used when the system
    /// accessibility "Reduce Motion" preference is on (aiesrocks/bubble-duck#15).
    public mutating func followWater(waterLevels: [Double]) {
        guard enabled, !waterLevels.isEmpty else { return }
        let col = min(Int(x * Double(waterLevels.count)), waterLevels.count - 1)
        y = waterLevels[col]
        isUpsideDown = y > 0.95
    }
}
