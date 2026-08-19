// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — treats lobbed at the floating agent when the user pokes the tile

import Foundation

/// What gets thrown. One kind per species, chosen so no two read alike at
/// Dock size: a red wedge, a grey lump, a brown pellet, a silver fish, a
/// dark insect, a green leaf.
public enum TreatKind: String, Sendable, Equatable, Codable, CaseIterable {
    case watermelon
    case rock
    case pellet
    case fish
    case insect
    case lettuce
}

/// How the agent deals with what was thrown at it.
public enum TreatBehavior: String, Sendable, Equatable, Codable, CaseIterable {
    /// Arcs straight into the open mouth, which then snaps shut. Crumbs fly.
    case eaten
    /// Hovers in front of the agent until its tongue fires out and takes it.
    case tongue
    /// Nobody's eating this. It hits the water alongside the agent, which
    /// gets startled by the splash.
    case splash
}

/// A point relative to the agent's origin, in canvas fractions at
/// `sizeScale == 1`. Multiplied by the user's size multiplier at use time.
public struct TreatAnchor: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public extension AgentType {
    /// What this species gets thrown at it.
    var treatKind: TreatKind {
        switch self {
        case .hippo: return .watermelon
        case .rubberDuck, .origamiBoat: return .rock
        case .mandarinDuck: return .pellet
        case .otter, .penguin: return .fish
        case .frog: return .insect
        case .turtle: return .lettuce
        }
    }

    /// What happens when it arrives. A rubber duck is a bath toy and an
    /// origami boat is a folded sheet of paper — neither has a mouth, so
    /// their rock lands in the water beside them instead.
    var treatBehavior: TreatBehavior {
        switch self {
        case .rubberDuck, .origamiBoat: return .splash
        case .frog: return .tongue
        default: return .eaten
        }
    }

    /// Where the treat is headed, as an offset from the agent's origin.
    ///
    /// These mirror the renderer's per-species geometry: each is that
    /// character's `agentScale` times its mouth position in agent-local
    /// units, with the renderer's fixed `-0.1` vertical shift folded in. The
    /// two `.splash` species instead point at open water off their side.
    var treatAnchor: TreatAnchor {
        switch self {
        case .rubberDuck:   return TreatAnchor(x: 0.34, y: -0.03)
        case .origamiBoat:  return TreatAnchor(x: 0.24, y: -0.04)
        case .mandarinDuck: return TreatAnchor(x: 0.180, y: 0.026)
        case .otter:        return TreatAnchor(x: 0.150, y: -0.012)
        case .turtle:       return TreatAnchor(x: 0.180, y: -0.015)
        case .frog:         return TreatAnchor(x: 0.143, y: 0.007)
        case .hippo:        return TreatAnchor(x: 0.190, y: -0.034)
        case .penguin:      return TreatAnchor(x: 0.007, y: 0.078)
        }
    }

    /// Seconds of flight, tuned so the treat lands while the mouth is at
    /// full gape. A hippo's slow yawn gets a longer lob than a duck's snap;
    /// the floor keeps the fastest bills from getting a treat that teleports.
    var treatFlightTime: Double {
        switch treatBehavior {
        case .eaten:  return max(0.5, mouthProfile.holdStart * mouthProfile.duration)
        case .splash: return 0.55
        case .tongue: return 0.70
        }
    }
}

/// Something in flight, hovering, or being swallowed. One at a time — the
/// simulation refuses to launch a second while one is still airborne.
public struct Treat: Sendable, Equatable {
    public enum Phase: String, Sendable, Equatable {
        /// Following the lob arc toward the agent.
        case flying
        /// Insect only: fluttering in front of the frog, waiting to be taken.
        case hovering
        /// Insect only: stuck to the tongue, riding it back to the mouth.
        case caught
        /// Spent. The simulation culls it on the frame it reaches this.
        case done
    }

    /// Things the simulation has to react to. Nil on an ordinary frame.
    public enum Event: Sendable, Equatable {
        /// Reached the target point — eat it, splash it, or start hovering.
        case arrived
        /// The frog's tongue fires.
        case strike
        /// Nothing left to draw.
        case finished
    }

    public var kind: TreatKind
    public var behavior: TreatBehavior
    public private(set) var phase: Phase = .flying

    /// Launch point, canvas fraction.
    public var originX: Double
    public var originY: Double

    /// Live position for the renderer, canvas fraction.
    public private(set) var x: Double
    public private(set) var y: Double

    /// Where the insect stopped to hover — the tongue reaches for this.
    public private(set) var captureX: Double = 0
    public private(set) var captureY: Double = 0

    /// 0…1 along the lob arc.
    public private(set) var progress: Double = 0
    public var flightTime: Double
    /// How far above the straight line the arc bulges at its midpoint.
    public var arcHeight: Double
    /// Rotation for the renderer, radians.
    public private(set) var spin: Double = 0
    public var spinRate: Double

    /// Seconds of hovering left before the tongue fires.
    public private(set) var hoverRemaining: Double = 0
    /// 0…1 through the tongue strike, out and back.
    public private(set) var catchProgress: Double = 0
    /// Free-running clock for the insect's wing flutter.
    public private(set) var flutter: Double = 0

    /// How long an insect dangles in front of the frog before it's taken.
    public static let hoverDuration: Double = 1.0
    /// Seconds for the tongue to go out, stick, and come back.
    public static let tongueDuration: Double = 0.36
    /// Fraction of the strike spent reaching out; the rest is the return.
    public static let tongueOutFraction: Double = 0.45

    public init(kind: TreatKind, behavior: TreatBehavior,
                originX: Double, originY: Double,
                flightTime: Double, arcHeight: Double, spinRate: Double) {
        self.kind = kind
        self.behavior = behavior
        self.originX = originX
        self.originY = originY
        self.x = originX
        self.y = originY
        self.flightTime = flightTime
        self.arcHeight = arcHeight
        self.spinRate = spinRate
    }

    /// The lob: a straight line from origin to target with a sine bulge, so
    /// the throw reads as thrown rather than dragged. Solved per frame
    /// against the *current* target, which is how a treat still lands in the
    /// mouth of an agent that drifted during the throw.
    public static func arcPosition(originX: Double, originY: Double,
                                   targetX: Double, targetY: Double,
                                   progress: Double, arcHeight: Double) -> (x: Double, y: Double) {
        let p = max(0, min(1, progress))
        return (x: originX + (targetX - originX) * p,
                y: originY + (targetY - originY) * p + arcHeight * sin(.pi * p))
    }

    /// How far the tongue is extended, 0 (in the mouth) … 1 (touching the
    /// insect). Zero outside the strike.
    public var tongueReach: Double {
        guard phase == .caught else { return 0 }
        let out = Treat.tongueOutFraction
        if catchProgress < out { return smoothstep(catchProgress / out) }
        return smoothstep(1.0 - (catchProgress - out) / (1.0 - out))
    }

    /// Advance one frame. `targetX`/`targetY` are the agent's current mouth
    /// (or splash) point in canvas fractions — recomputed by the caller each
    /// frame because the agent keeps drifting.
    @discardableResult
    public mutating func step(deltaTime: Double,
                              targetX: Double, targetY: Double) -> Event? {
        switch phase {
        case .flying:
            spin += spinRate * deltaTime
            progress = min(1.0, progress + deltaTime / max(0.01, flightTime))
            let pos = Treat.arcPosition(originX: originX, originY: originY,
                                        targetX: targetX, targetY: targetY,
                                        progress: progress, arcHeight: arcHeight)
            x = pos.x
            y = pos.y
            guard progress >= 1.0 else { return nil }
            if behavior == .tongue {
                phase = .hovering
                hoverRemaining = Treat.hoverDuration
                captureX = x
                captureY = y
            } else {
                phase = .done
            }
            return .arrived

        case .hovering:
            flutter += deltaTime
            hoverRemaining -= deltaTime
            // Drift with the frog rather than hanging in dead space, plus a
            // small erratic flutter so it reads as alive.
            captureX = targetX
            captureY = targetY
            x = captureX + sin(flutter * 9.0) * 0.014
            y = captureY + sin(flutter * 13.0) * 0.018
            guard hoverRemaining <= 0 else { return nil }
            captureX = x
            captureY = y
            phase = .caught
            catchProgress = 0
            return .strike

        case .caught:
            flutter += deltaTime
            catchProgress += deltaTime / Treat.tongueDuration
            if catchProgress >= 1.0 {
                catchProgress = 1.0
                phase = .done
                // Land exactly on the mouth rather than wherever the last
                // whole frame happened to leave it.
                x = targetX
                y = targetY
                return .finished
            }
            // Stays put while the tongue reaches for it, then rides the tip
            // home. `tongueReach` is 1 at the moment of contact, so the two
            // halves meet without a jump.
            if catchProgress < Treat.tongueOutFraction {
                x = captureX
                y = captureY
            } else {
                let reach = tongueReach
                x = targetX + (captureX - targetX) * reach
                y = targetY + (captureY - targetY) * reach
            }
            return nil

        case .done:
            return .finished
        }
    }

    private func smoothstep(_ t: Double) -> Double {
        let v = max(0, min(1, t))
        return v * v * (3 - 2 * v)
    }
}

/// A scrap flung loose when the agent bites down. Purely decorative, dies
/// in about half a second.
public struct TreatCrumb: Sendable, Equatable {
    public var kind: TreatKind
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    /// 0…1; culled at 1.
    public var age: Double = 0

    /// Seconds a crumb lives.
    public static let lifetimeSeconds: Double = 0.55
    /// Downward pull, canvas fractions per second squared.
    public static let gravity: Double = 1.6

    public init(kind: TreatKind, x: Double, y: Double, vx: Double, vy: Double) {
        self.kind = kind
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
    }

    public mutating func step(deltaTime: Double) {
        vy -= TreatCrumb.gravity * deltaTime
        x += vx * deltaTime
        y += vy * deltaTime
        age = min(1.0, age + deltaTime / TreatCrumb.lifetimeSeconds)
    }
}
