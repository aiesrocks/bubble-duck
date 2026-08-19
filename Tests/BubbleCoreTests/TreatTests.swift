// SPDX-License-Identifier: GPL-2.0-or-later

import Testing
@testable import BubbleCore

@Suite("Treats")
struct TreatTests {

    // MARK: - Species mapping

    @Test("every species gets a treat and a way of dealing with it")
    func everySpeciesMapped() {
        for agent in AgentType.allCases {
            // Compiles by construction; assert the pairings that carry meaning.
            let kind = agent.treatKind
            let behavior = agent.treatBehavior
            switch behavior {
            case .tongue:
                #expect(kind == .insect, "only an insect gets caught with a tongue")
            case .splash:
                #expect(kind == .rock, "only a rock gets thrown at something that can't eat")
            case .eaten:
                #expect(kind != .rock, "nobody eats a rock")
            }
        }
    }

    @Test("the mouthless species take a splash instead of a meal")
    func mouthlessSpeciesSplash() {
        #expect(AgentType.rubberDuck.treatBehavior == .splash)
        #expect(AgentType.origamiBoat.treatBehavior == .splash)
    }

    @Test("each species is thrown the right thing")
    func kindsPerSpecies() {
        #expect(AgentType.hippo.treatKind == .watermelon)
        #expect(AgentType.mandarinDuck.treatKind == .pellet)
        #expect(AgentType.otter.treatKind == .fish)
        #expect(AgentType.penguin.treatKind == .fish)
        #expect(AgentType.frog.treatKind == .insect)
        #expect(AgentType.turtle.treatKind == .lettuce)
    }

    @Test("flight is timed to land while the mouth is still open")
    func flightLandsDuringGape() {
        for agent in AgentType.allCases where agent.treatBehavior == .eaten {
            let profile = agent.mouthProfile
            let flight = agent.treatFlightTime
            #expect(flight >= profile.holdStart * profile.duration,
                    "\(agent) would arrive before the mouth is open")
            #expect(flight <= profile.holdEnd * profile.duration,
                    "\(agent) would arrive after the mouth has shut")
        }
    }

    // MARK: - Arc

    @Test("the arc starts at the origin and ends at the target")
    func arcEndpoints() {
        let start = Treat.arcPosition(originX: 0.1, originY: 1.0, targetX: 0.7, targetY: 0.4,
                                      progress: 0, arcHeight: 0.07)
        #expect(abs(start.x - 0.1) < 1e-9)
        #expect(abs(start.y - 1.0) < 1e-9)

        let end = Treat.arcPosition(originX: 0.1, originY: 1.0, targetX: 0.7, targetY: 0.4,
                                    progress: 1, arcHeight: 0.07)
        #expect(abs(end.x - 0.7) < 1e-9)
        #expect(abs(end.y - 0.4) < 1e-9)
    }

    @Test("the arc bulges above the straight line at its midpoint")
    func arcBulges() {
        let mid = Treat.arcPosition(originX: 0.0, originY: 1.0, targetX: 1.0, targetY: 0.0,
                                    progress: 0.5, arcHeight: 0.07)
        #expect(abs(mid.y - (0.5 + 0.07)) < 1e-9)
    }

    // MARK: - Flight and arrival

    /// Fly a treat until it reports an event, up to a generous frame budget.
    private func fly(_ treat: inout Treat, target: (x: Double, y: Double),
                     maxFrames: Int = 600) -> (event: Treat.Event?, frames: Int) {
        for frame in 1...maxFrames {
            if let event = treat.step(deltaTime: 1.0 / 60.0,
                                      targetX: target.x, targetY: target.y) {
                return (event, frame)
            }
        }
        return (nil, maxFrames)
    }

    private func makeTreat(_ agent: AgentType, originX: Double = -0.08) -> Treat {
        Treat(kind: agent.treatKind, behavior: agent.treatBehavior,
              originX: originX, originY: 1.02,
              flightTime: agent.treatFlightTime, arcHeight: 0.07, spinRate: 3.0)
    }

    @Test("an eaten treat arrives at the mouth and is spent")
    func eatenArrives() {
        var treat = makeTreat(.hippo)
        let target = (x: 0.62, y: 0.48)
        let result = fly(&treat, target: target)
        #expect(result.event == .arrived)
        #expect(treat.phase == .done)
        #expect(abs(treat.x - target.x) < 1e-6)
        #expect(abs(treat.y - target.y) < 1e-6)
    }

    @Test("arrival happens on schedule, not early or late")
    func arrivalTiming() {
        var treat = makeTreat(.penguin)
        let expected = Int((AgentType.penguin.treatFlightTime * 60.0).rounded(.up))
        let result = fly(&treat, target: (x: 0.5, y: 0.5))
        // One frame of slack: accumulating dt/flightTime can leave progress a
        // rounding error short on the frame that should have finished it.
        #expect(result.frames >= expected)
        #expect(result.frames <= expected + 1)
    }

    @Test("a treat spins on the way in")
    func treatSpins() {
        var treat = makeTreat(.turtle)
        _ = treat.step(deltaTime: 1.0 / 60.0, targetX: 0.5, targetY: 0.5)
        #expect(treat.spin != 0)
    }

    @Test("a treat homes on a target that moved mid-flight")
    func treatHomesOnMovedTarget() {
        var treat = makeTreat(.mandarinDuck)
        // Half the flight aimed one way, the rest at a target that drifted.
        for _ in 0..<8 {
            _ = treat.step(deltaTime: 1.0 / 60.0, targetX: 0.30, targetY: 0.50)
        }
        let moved = (x: 0.75, y: 0.42)
        _ = fly(&treat, target: moved)
        #expect(abs(treat.x - moved.x) < 1e-6)
        #expect(abs(treat.y - moved.y) < 1e-6)
    }

    // MARK: - Tongue

    @Test("an insect hovers, then gets struck, then is gone")
    func insectHoversThenIsCaught() {
        var treat = makeTreat(.frog)
        let target = (x: 0.55, y: 0.5)

        let arrival = fly(&treat, target: target)
        #expect(arrival.event == .arrived)
        #expect(treat.phase == .hovering)

        let strike = fly(&treat, target: target)
        #expect(strike.event == .strike)
        #expect(treat.phase == .caught)
        // Hovered for about the advertised duration.
        #expect(abs(Double(strike.frames) / 60.0 - Treat.hoverDuration) < 0.05)

        let finish = fly(&treat, target: target)
        #expect(finish.event == .finished)
        #expect(treat.phase == .done)
    }

    @Test("the tongue reaches out and comes back")
    func tongueExtendsAndRetracts() {
        var treat = makeTreat(.frog)
        let target = (x: 0.55, y: 0.5)
        _ = fly(&treat, target: target)   // arrive
        _ = fly(&treat, target: target)   // strike

        #expect(treat.tongueReach < 0.2, "the tongue starts in the mouth")

        var peak = 0.0
        while treat.phase == .caught {
            peak = max(peak, treat.tongueReach)
            _ = treat.step(deltaTime: 1.0 / 60.0, targetX: target.x, targetY: target.y)
        }
        #expect(peak > 0.95, "the tongue should reach the insect")
        #expect(treat.tongueReach == 0, "and be back in the mouth when it's over")
    }

    @Test("the insect ends up at the frog's mouth, not where it was hovering")
    func insectRidesTongueHome() {
        var treat = makeTreat(.frog)
        let target = (x: 0.55, y: 0.5)
        _ = fly(&treat, target: target)
        _ = fly(&treat, target: target)
        let hovered = (x: treat.x, y: treat.y)

        while treat.phase == .caught {
            _ = treat.step(deltaTime: 1.0 / 60.0, targetX: target.x, targetY: target.y)
        }
        #expect(abs(treat.x - target.x) < 1e-6)
        #expect(abs(treat.y - target.y) < 1e-6)
        #expect(abs(hovered.x - target.x) > 1e-6, "it hovered away from the mouth first")
    }

    // MARK: - Crumbs

    @Test("a crumb falls and expires")
    func crumbExpires() {
        var crumb = TreatCrumb(kind: .watermelon, x: 0.5, y: 0.5, vx: 0.1, vy: 0.2)
        var frames = 0
        while crumb.age < 1.0 && frames < 600 {
            crumb.step(deltaTime: 1.0 / 60.0)
            frames += 1
        }
        #expect(crumb.age >= 1.0)
        #expect(abs(Double(frames) / 60.0 - TreatCrumb.lifetimeSeconds) < 0.05)
        #expect(crumb.vy < 0.2, "gravity should have pulled it down")
    }
}

@Suite("Startle")
struct StartleTests {

    @Test("a startled agent hops and comes back down")
    func hopReturnsToRest() {
        var duck = DuckState()
        duck.startle(strength: 1.0)
        #expect(duck.hopVelocity > 0)

        var peak = 0.0
        for _ in 0..<200 {
            duck.stepStartle(deltaTime: 1.0 / 60.0)
            peak = max(peak, duck.hopOffset)
        }
        #expect(peak > 0.01, "the hop should be visible")
        #expect(peak < 0.10, "but not launch it off the tile")
        #expect(duck.hopOffset == 0)
        #expect(duck.hopVelocity == 0)
    }

    @Test("a startled agent rolls and settles level again")
    func tiltSettles() {
        var duck = DuckState()
        duck.startle(strength: 1.0)

        var peak = 0.0
        for _ in 0..<300 {
            duck.stepStartle(deltaTime: 1.0 / 60.0)
            peak = max(peak, abs(duck.tiltAngle))
        }
        #expect(peak > 0.05, "the roll should be visible")
        #expect(peak < 0.6, "but it shouldn't capsize")
        #expect(duck.tiltAngle == 0)
        #expect(duck.tiltVelocity == 0)
    }

    @Test("repeated startles don't pump the agent off the tile")
    func startleDoesNotAccumulate() {
        var duck = DuckState()
        for _ in 0..<10 {
            duck.startle(strength: 1.0)
        }
        var single = DuckState()
        single.startle(strength: 1.0)
        #expect(duck.hopVelocity == single.hopVelocity)
        #expect(duck.tiltVelocity == single.tiltVelocity)
    }

    @Test("an undisturbed agent stays put")
    func restingAgentDoesNothing() {
        var duck = DuckState()
        for _ in 0..<60 { duck.stepStartle(deltaTime: 1.0 / 60.0) }
        #expect(duck.hopOffset == 0)
        #expect(duck.tiltAngle == 0)
    }
}

@Suite("Throwing treats")
struct ThrowTreatTests {

    private func state(agent: AgentType) -> SimulationState {
        var state = SimulationState()
        var config = SimulationConfig()
        config.agentType = agent
        config.treatsEnabled = true
        state.apply(config)
        return state
    }

    @Test("poking throws exactly one treat")
    func pokeThrowsOne() {
        var sim = state(agent: .hippo)
        let threw1 = sim.throwTreat()
        #expect(threw1)
        #expect(sim.treats.count == 1)
        #expect(sim.treats[0].kind == .watermelon)
    }

    @Test("poking again while one is airborne doesn't throw a second")
    func noSecondTreatMidFlight() {
        var sim = state(agent: .hippo)
        let threw2 = sim.throwTreat()
        #expect(threw2)
        let threw3 = sim.throwTreat()
        #expect(threw3 == false)
        #expect(sim.treats.count == 1)
    }

    @Test("the throw comes from the side the agent isn't on")
    func throwComesFromTheFarSide() {
        var left = state(agent: .turtle)
        left.duck.x = 0.2
        let threw4 = left.throwTreat()
        #expect(threw4)
        #expect(left.treats[0].originX > 1.0)

        var right = state(agent: .turtle)
        right.duck.x = 0.8
        let threw5 = right.throwTreat()
        #expect(threw5)
        #expect(right.treats[0].originX < 0.0)
    }

    @Test("an eater opens its mouth on the throw")
    func eaterOpensOnThrow() {
        var sim = state(agent: .penguin)
        let threw6 = sim.throwTreat()
        #expect(threw6)
        #expect(sim.duck.mouth.isOpening)
    }

    @Test("a splash species keeps its mouth shut until the rock lands")
    func splashSpeciesWaitsToReact() {
        var sim = state(agent: .rubberDuck)
        let threw7 = sim.throwTreat()
        #expect(threw7)
        #expect(sim.duck.mouth.isOpening == false)
    }

    @Test("poking wakes a sleeping agent even when treats are off")
    func pokeAlwaysWakes() {
        var sim = state(agent: .hippo)
        var config = sim.config
        config.treatsEnabled = false
        sim.apply(config)
        sim.duck.sleepiness = 1.0

        let threw8 = sim.throwTreat()
        #expect(threw8 == false)
        #expect(sim.treats.isEmpty)
        #expect(sim.duck.sleepiness == 0)
        #expect(sim.duck.mouth.isOpening, "it should still react to the poke")
    }

    @Test("Reduce Motion and Lowest power suppress treats")
    func motionModesSuppressTreats() {
        var reduced = state(agent: .otter)
        reduced.reduceMotion = true
        let threw9 = reduced.throwTreat()
        #expect(threw9 == false)
        #expect(reduced.treats.isEmpty)

        var lowest = state(agent: .otter)
        lowest.effectivePowerMode = .lowest
        let threw10 = lowest.throwTreat()
        #expect(threw10 == false)
        #expect(lowest.treats.isEmpty)
    }

    @Test("a hidden agent can't be fed")
    func noAgentNoTreat() {
        var sim = state(agent: .otter)
        sim.duck.enabled = false
        let threw11 = sim.throwTreat()
        #expect(threw11 == false)
        #expect(sim.treats.isEmpty)
    }

    // MARK: - Targets

    @Test("an eater's treat is aimed at its mouth")
    func eaterTargetsMouth() {
        let sim = state(agent: .hippo)
        let target = sim.treatTarget(for: .eaten, agent: .hippo)
        let anchor = AgentType.hippo.treatAnchor
        #expect(abs(target.x - (sim.duck.x + anchor.x)) < 1e-9)
        #expect(abs(target.y - (sim.duck.y + anchor.y)) < 1e-9)
    }

    @Test("the mouth target grows with the agent size setting")
    func targetScalesWithAgentSize() {
        var sim = state(agent: .hippo)
        var config = sim.config
        config.agentSizeScale = 2.0
        sim.apply(config)
        let target = sim.treatTarget(for: .eaten, agent: .hippo)
        #expect(abs(target.x - (sim.duck.x + AgentType.hippo.treatAnchor.x * 2.0)) < 1e-9)
    }

    @Test("a rock is aimed at the water, not at the toy")
    func splashTargetsWaterSurface() {
        let sim = state(agent: .rubberDuck)
        let target = sim.treatTarget(for: .splash, agent: .rubberDuck)
        #expect(abs(target.y - sim.water.level(atFraction: target.x)) < 1e-9)
    }

    @Test("an insect stops short of the frog rather than flying into it")
    func tongueTargetSitsInFront() {
        let sim = state(agent: .frog)
        let mouth = sim.treatTarget(for: .eaten, agent: .frog)
        let hover = sim.treatTarget(for: .tongue, agent: .frog)
        #expect(hover.x > mouth.x)
        #expect(hover.y > mouth.y)
    }

    @Test("targets stay on the tile even for an agent at the edge")
    func targetsStayOnTile() {
        var sim = state(agent: .hippo)
        sim.duck.x = 0.99
        let target = sim.treatTarget(for: .eaten, agent: .hippo)
        #expect(target.x <= 0.97)
    }

    // MARK: - Arrival effects, driven through the whole simulation

    /// Run the simulation until the treat is gone, or give up.
    private func runUntilTreatsClear(_ sim: inout SimulationState, maxFrames: Int = 900) -> Int {
        for frame in 1...maxFrames where sim.treats.isEmpty == false {
            sim.step()
            if sim.treats.isEmpty { return frame }
        }
        return maxFrames
    }

    @Test("swallowing shuts the mouth and scatters crumbs")
    func swallowSnapsMouthShut() {
        var sim = state(agent: .hippo)
        sim.throwTreat()
        _ = runUntilTreatsClear(&sim)
        #expect(sim.treats.isEmpty)
        #expect(sim.crumbs.isEmpty == false, "a bite should scatter something")
        // The hippo's hold runs for seconds; a swallow cuts it short.
        #expect(sim.duck.mouth.progress >= AgentType.hippo.mouthProfile.holdEnd)
    }

    @Test("crumbs are cleaned up on their own")
    func crumbsExpire() {
        var sim = state(agent: .turtle)
        sim.throwTreat()
        _ = runUntilTreatsClear(&sim)
        #expect(sim.crumbs.isEmpty == false)
        for _ in 0..<120 { sim.step() }
        #expect(sim.crumbs.isEmpty)
    }

    @Test("a landing rock startles the agent and disturbs the water")
    func rockStartlesAndSplashes() {
        var sim = state(agent: .rubberDuck)
        let ripplesBefore = sim.ripples.count
        sim.throwTreat()
        _ = runUntilTreatsClear(&sim)
        #expect(sim.treats.isEmpty)
        #expect(sim.duck.hopVelocity > 0 || sim.duck.hopOffset > 0, "the duck should jump")
        #expect(sim.duck.tiltVelocity != 0 || sim.duck.tiltAngle != 0)
        #expect(sim.ripples.count > ripplesBefore)
        #expect(sim.crumbs.isEmpty, "nobody ate the rock")
    }

    @Test("the frog's whole insect sequence runs to completion")
    func frogSequenceCompletes() {
        var sim = state(agent: .frog)
        sim.throwTreat()
        let frames = runUntilTreatsClear(&sim)
        #expect(sim.treats.isEmpty)
        let expected = AgentType.frog.treatFlightTime + Treat.hoverDuration + Treat.tongueDuration
        #expect(abs(Double(frames) / 60.0 - expected) < 0.1)
    }

    @Test("a treat in the air still finishes after Reduce Motion turns on")
    func airborneTreatFinishesUnderReduceMotion() {
        var sim = state(agent: .otter)
        sim.throwTreat()
        sim.step()
        sim.reduceMotion = true
        _ = runUntilTreatsClear(&sim)
        #expect(sim.treats.isEmpty, "it shouldn't freeze in mid-air")
    }
}
