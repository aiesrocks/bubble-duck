// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest
@testable import BubbleCore

final class ClaudeUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_000_000)

    private func window(percent: Double, resetsInSeconds: Double) -> ClaudeUsageWindow {
        ClaudeUsageWindow(usedPercentage: percent,
                          resetsAt: now.addingTimeInterval(resetsInSeconds))
    }

    private func snapshot(fiveHour: ClaudeUsageWindow? = nil,
                          sevenDay: ClaudeUsageWindow? = nil,
                          ageSeconds: Double = 0) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(fiveHour: fiveHour, sevenDay: sevenDay,
                            updatedAt: now.addingTimeInterval(-ageSeconds))
    }

    // MARK: - Window semantics

    func testPercentageClampsAndPassesThrough() {
        XCTAssertEqual(window(percent: 42.4, resetsInSeconds: 3600).percentage(now: now), 42.4)
        XCTAssertEqual(window(percent: -5, resetsInSeconds: 3600).percentage(now: now), 0)
        XCTAssertEqual(window(percent: 140, resetsInSeconds: 3600).percentage(now: now), 100)
    }

    func testPercentageIsZeroAfterRollover() {
        // Past the reset instant the window has restarted: the last reported
        // figure describes a window that no longer exists.
        let expired = window(percent: 90, resetsInSeconds: -60)
        XCTAssertEqual(expired.percentage(now: now), 0)
        XCTAssertTrue(expired.hasRolledOver(now: now))
        XCTAssertEqual(expired.timeUntilReset(now: now), 0)
    }

    func testTimeUntilReset() {
        XCTAssertEqual(window(percent: 10, resetsInSeconds: 7200).timeUntilReset(now: now), 7200)
    }

    // MARK: - Staleness

    func testStalenessThreshold() {
        let fresh = snapshot(ageSeconds: 60)
        let old = snapshot(ageSeconds: 20 * 60)
        XCTAssertFalse(fresh.isStale(now: now, staleAfter: 15 * 60))
        XCTAssertTrue(old.isStale(now: now, staleAfter: 15 * 60))
    }

    // MARK: - Countdown formatting

    func testCountdownFormatting() {
        XCTAssertEqual(ClaudeUsageFormat.countdown(4 * 3600 + 12 * 60), "4:12")
        XCTAssertEqual(ClaudeUsageFormat.countdown(4 * 3600 + 5 * 60), "4:05")
        XCTAssertEqual(ClaudeUsageFormat.countdown(3600), "1:00")
        XCTAssertEqual(ClaudeUsageFormat.countdown(59 * 60), "59m")
        XCTAssertEqual(ClaudeUsageFormat.countdown(48 * 60), "48m")
        XCTAssertEqual(ClaudeUsageFormat.countdown(30), "<1m")
        XCTAssertEqual(ClaudeUsageFormat.countdown(0), ClaudeUsageFormat.unknownCountdown)
        XCTAssertEqual(ClaudeUsageFormat.countdown(-10), "--:--")
    }

    // MARK: - Weekly color bands

    func testWeeklyBandsPickTheRightColor() {
        let theme = ColorTheme()
        let thresholds: [Double] = [25, 50, 75, 90]
        let bands = ColorTheme.defaultClaudeWeeklyBands
        XCTAssertEqual(theme.claudeWeeklyColor(percent: 0,   thresholds: thresholds), bands[0])
        XCTAssertEqual(theme.claudeWeeklyColor(percent: 24.9, thresholds: thresholds), bands[0])
        XCTAssertEqual(theme.claudeWeeklyColor(percent: 25,  thresholds: thresholds), bands[1])
        XCTAssertEqual(theme.claudeWeeklyColor(percent: 60,  thresholds: thresholds), bands[2])
        XCTAssertEqual(theme.claudeWeeklyColor(percent: 89.9, thresholds: thresholds), bands[3])
        XCTAssertEqual(theme.claudeWeeklyColor(percent: 90,  thresholds: thresholds), bands[4])
        XCTAssertEqual(theme.claudeWeeklyColor(percent: 100, thresholds: thresholds), bands[4])
    }

    func testWeeklyBandsHandleUnsortedThresholds() {
        let theme = ColorTheme()
        let bands = ColorTheme.defaultClaudeWeeklyBands
        XCTAssertEqual(theme.claudeWeeklyColor(percent: 60, thresholds: [90, 25, 75, 50]), bands[2])
    }

    // MARK: - Simulation wiring

    private func state(configure: (inout SimulationConfig) -> Void) -> SimulationState {
        var config = SimulationConfig.default
        configure(&config)
        var state = SimulationState(canvasSize: 256, config: config)
        state.memoryUsage = 0.40
        state.swapUsage = 0.10
        return state
    }

    func testWaterTargetUsesMemoryByDefault() {
        let s = state { _ in }
        XCTAssertEqual(s.waterTarget(now: now), 0.40, accuracy: 1e-9)
    }

    func testWaterTargetUsesFiveHourUsageWhenSelected() {
        var s = state { $0.claudeUsage.waterLevelSource = .claudeFiveHour }
        s.claudeUsage = snapshot(fiveHour: window(percent: 72, resetsInSeconds: 3600))
        XCTAssertEqual(s.waterTarget(now: now), 0.72, accuracy: 1e-9)
    }

    func testWaterTargetFallsBackWhenNoUsageData() {
        let s = state { $0.claudeUsage.waterLevelSource = .claudeFiveHour }
        XCTAssertEqual(s.waterTarget(now: now), 0.40, accuracy: 1e-9)
    }

    func testStaleReadingFallsBackWhenConfigured() {
        var s = state {
            $0.claudeUsage.waterLevelSource = .claudeFiveHour
            $0.claudeUsage.staleAfterMinutes = 15
            $0.claudeUsage.fallbackWhenStale = true
        }
        s.claudeUsage = snapshot(fiveHour: window(percent: 72, resetsInSeconds: 3600),
                                 ageSeconds: 20 * 60)
        XCTAssertTrue(s.claudeUsageIsStale(now: now))
        XCTAssertEqual(s.waterTarget(now: now), 0.40, accuracy: 1e-9)
    }

    func testStaleReadingHeldWhenFallbackDisabled() {
        var s = state {
            $0.claudeUsage.waterLevelSource = .claudeFiveHour
            $0.claudeUsage.staleAfterMinutes = 15
            $0.claudeUsage.fallbackWhenStale = false
        }
        s.claudeUsage = snapshot(fiveHour: window(percent: 72, resetsInSeconds: 3600),
                                 ageSeconds: 20 * 60)
        XCTAssertEqual(s.waterTarget(now: now), 0.72, accuracy: 1e-9)
    }

    func testWaterColorUsesWeeklyBandsWhenSelected() {
        var s = state { $0.claudeUsage.waterColorSource = .claudeWeekly }
        s.claudeUsage = snapshot(sevenDay: window(percent: 95, resetsInSeconds: 86_400))
        XCTAssertEqual(s.waterColor(now: now), ColorTheme.defaultClaudeWeeklyBands[4])
    }

    func testWaterColorFallsBackToTightnessWithoutData() {
        let s = state { $0.claudeUsage.waterColorSource = .claudeWeekly }
        XCTAssertEqual(s.waterColor(now: now),
                       ColorTheme().liquidColor(swapUsage: 0.10))
    }

    func testStepDrivesWaterTargetFromClaudeUsage() {
        var s = state { $0.claudeUsage.waterLevelSource = .claudeFiveHour }
        s.claudeUsage = snapshot(fiveHour: window(percent: 30, resetsInSeconds: 3600))
        s.step(now: now)
        XCTAssertEqual(s.water.targetLevel, 0.30, accuracy: 1e-9)
    }

    // MARK: - Config

    func testRefreshIntervalIsFlooredAtOneMinute() {
        var config = ClaudeUsageConfig()
        config.refreshSeconds = 5
        XCTAssertEqual(config.effectiveRefreshSeconds, 60)
        config.refreshSeconds = 300
        XCTAssertEqual(config.effectiveRefreshSeconds, 300)
    }

    func testConfigDecodesWithoutClaudeSection() throws {
        // A config saved before this feature existed must still load.
        let json = Data(#"{"maxBubbles": 42, "viscosity": 0.9}"#.utf8)
        let config = try JSONDecoder().decode(SimulationConfig.self, from: json)
        XCTAssertEqual(config.maxBubbles, 42)
        XCTAssertEqual(config.viscosity, 0.9, accuracy: 1e-9)
        XCTAssertEqual(config.claudeUsage.waterLevelSource, .memoryUsage)
        XCTAssertEqual(config.claudeUsage.weeklyThresholds, [25, 50, 75, 90])
    }

    func testConfigRoundTrips() throws {
        var config = SimulationConfig.default
        config.claudeUsage.waterLevelSource = .claudeFiveHour
        config.tileReadout.source = .claudeFiveHourUsageAndCountdown
        config.tileReadout.opacity = 0.4
        config.tileReadout.backdrop = true
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SimulationConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    // MARK: - Tile readout

    func testReadoutDefaultsToCPUPercent() {
        var s = state { _ in }
        s.overlay.cpuPercent = 37
        XCTAssertEqual(s.config.tileReadout.source, .cpuPercent)
        XCTAssertEqual(s.tileReadout(now: now)?.text, "37%")
        XCTAssertEqual(s.tileReadout(now: now)?.isStale, false)
    }

    func testReadoutMemoryPercent() {
        let s = state { $0.tileReadout.source = .memoryPercent }
        XCTAssertEqual(s.tileReadout(now: now)?.text, "40%")
    }

    func testReadoutOffProducesNothing() {
        let s = state { $0.tileReadout.source = .none }
        XCTAssertNil(s.tileReadout(now: now))
    }

    func testReadoutClaudeSourcesNeedData() {
        let s = state { $0.tileReadout.source = .claudeFiveHourCountdown }
        XCTAssertNil(s.tileReadout(now: now))
    }

    func testReadoutFiveHourUsageAndCountdown() {
        var s = state { $0.tileReadout.source = .claudeFiveHourUsageAndCountdown }
        s.claudeUsage = snapshot(fiveHour: window(percent: 42, resetsInSeconds: 4 * 3600 + 12 * 60))
        XCTAssertEqual(s.tileReadout(now: now)?.text, "42% 4:12")
    }

    func testReadoutMarksStalePercentages() {
        var s = state {
            $0.tileReadout.source = .claudeFiveHourUsageAndCountdown
            $0.claudeUsage.staleAfterMinutes = 15
        }
        s.claudeUsage = snapshot(fiveHour: window(percent: 42, resetsInSeconds: 3600),
                                 ageSeconds: 30 * 60)
        let readout = s.tileReadout(now: now)
        XCTAssertEqual(readout?.text, "~42% 1:00")
        XCTAssertEqual(readout?.isStale, true)
    }

    func testReadoutAfterRolloverShowsCountdownOnly() {
        var s = state { $0.tileReadout.source = .claudeFiveHourUsageAndCountdown }
        s.claudeUsage = snapshot(fiveHour: window(percent: 100, resetsInSeconds: -60))
        XCTAssertEqual(s.tileReadout(now: now)?.text, "--:--")
    }

    func testReadoutWeeklyUsage() {
        var s = state { $0.tileReadout.source = .claudeWeeklyUsage }
        s.claudeUsage = snapshot(sevenDay: window(percent: 61, resetsInSeconds: 86_400))
        XCTAssertEqual(s.tileReadout(now: now)?.text, "61%")
    }

    // MARK: - Mouth animation

    func testMouthOpensAfterItsInterval() {
        var mouth = MouthState(initialInterval: 1.0)
        XCTAssertEqual(mouth.openness, 0)
        for _ in 0..<60 { mouth.step(deltaTime: 1.0 / 60.0, nextInterval: { 5 }) }
        XCTAssertTrue(mouth.isOpening)
        // Mid-animation it should actually be open.
        for _ in 0..<20 { mouth.step(deltaTime: 1.0 / 60.0, nextInterval: { 5 }) }
        XCTAssertGreaterThan(mouth.openness, 0.5)
    }

    func testMouthClosesAndQueuesTheNextInterval() {
        var mouth = MouthState(initialInterval: 0.01)
        // Step only until the animation completes — running on would tick the
        // freshly queued interval back down and make the assertion meaningless.
        var frames = 0
        repeat {
            mouth.step(deltaTime: 1.0 / 60.0, nextInterval: { 9 })
            frames += 1
        } while mouth.isOpening && frames < 300
        XCTAssertLessThan(frames, 300, "mouth animation never finished")
        XCTAssertEqual(mouth.openness, 0)
        XCTAssertEqual(mouth.timeUntilOpen, 9, accuracy: 1e-9)
    }

    func testHippoHoldsItsGapeFarLongerThanOtherAgents() {
        let hippo = AgentType.hippo.mouthProfile
        let duck = AgentType.rubberDuck.mouthProfile

        // Absolute seconds spent fully open, not just a bigger fraction.
        let hippoHold = (hippo.holdEnd - hippo.holdStart) * hippo.duration
        let duckHold = (duck.holdEnd - duck.holdStart) * duck.duration
        XCTAssertGreaterThan(hippoHold, duckHold * 5)
        XCTAssertGreaterThan(hippo.duration, duck.duration)
    }

    func testAgentTypeSelectsItsMouthProfile() {
        XCTAssertEqual(AgentType.hippo.mouthProfile, .hippo)
        XCTAssertEqual(AgentType.frog.mouthProfile, .frog)
        XCTAssertEqual(AgentType.penguin.mouthProfile, .standard)
    }

    func testApplyPushesTheAgentsMouthProfile() {
        var config = SimulationConfig.default
        config.agentType = .hippo
        var s = SimulationState(canvasSize: 256, config: config)
        XCTAssertEqual(s.duck.mouth.profile, .hippo)

        config.agentType = .rubberDuck
        s.apply(config)
        XCTAssertEqual(s.duck.mouth.profile, .standard)
    }

    func testHippoStaysWideOpenAcrossItsHold() {
        var mouth = MouthState(initialInterval: 0.01, profile: .hippo)
        var secondsFullyOpen = 0.0
        let dt = 1.0 / 60.0
        for _ in 0..<400 {
            mouth.step(deltaTime: dt, nextInterval: { 99 })
            if mouth.openness > 0.99 { secondsFullyOpen += dt }
        }
        // ~0.68 of 3.6s held wide.
        XCTAssertGreaterThan(secondsFullyOpen, 2.0)
    }

    func testMouthEnvelopeOpensHoldsAndCloses() {
        XCTAssertEqual(MouthState.envelope(0), 0, accuracy: 1e-9)
        XCTAssertEqual(MouthState.envelope(0.30), 1, accuracy: 1e-9)
        XCTAssertEqual(MouthState.envelope(0.50), 1, accuracy: 1e-9)   // hold
        XCTAssertEqual(MouthState.envelope(0.65), 1, accuracy: 1e-9)
        XCTAssertEqual(MouthState.envelope(1.0), 0, accuracy: 1e-9)
        XCTAssertLessThan(MouthState.envelope(0.85), 1)
    }

    func testTriggerOpensImmediatelyAndIsIgnoredMidAnimation() {
        var mouth = MouthState(initialInterval: 100)
        mouth.trigger()
        mouth.step(deltaTime: 1.0 / 60.0, nextInterval: { 5 })
        XCTAssertTrue(mouth.isOpening)

        let progressed = mouth
        mouth.trigger()   // no restart mid-yawn
        XCTAssertEqual(mouth, progressed)
    }

    func testPokeWakesTheAgentAndOpensItsMouth() {
        var duck = DuckState()
        duck.sleepiness = 1.0
        duck.react()
        XCTAssertEqual(duck.sleepiness, 0)
        XCTAssertTrue(duck.mouth.isOpening)
    }

    func testSimulationStepDrivesTheMouth() {
        var s = state { _ in }
        s.duck.react()
        let before = s.duck.mouth.openness
        for _ in 0..<15 { s.step(now: now) }
        XCTAssertGreaterThan(s.duck.mouth.openness, before)
    }

    // MARK: - Auto text color

    func testGentleInverseFlipsLightnessNotHue() {
        // Cyan sky → a dark, desaturated cyan: still legible, still in family.
        let sky = SimColor(hex: 0x00FFFF)
        let inverted = sky.gentleInverse()
        XCTAssertLessThan(inverted.luminance, 0.35)
        XCTAssertGreaterThan(inverted.b, inverted.r)   // hue side preserved
        XCTAssertGreaterThan(inverted.g, inverted.r)

        // Deep blue water → a pale blue-white.
        let water = SimColor(hex: 0x0000FF)
        let lifted = water.gentleInverse()
        XCTAssertGreaterThan(lifted.luminance, 0.6)
        XCTAssertGreaterThan(lifted.b, lifted.r)
    }

    func testGentleInverseNeverGoesFullyBlackOrWhite() {
        for hex: UInt32 in [0x000000, 0xFFFFFF, 0xE04030, 0x20B0AC] {
            let out = SimColor(hex: hex).gentleInverse()
            XCTAssertGreaterThan(out.luminance, 0.02)
            XCTAssertLessThan(out.luminance, 0.98)
        }
    }

    func testGentleInverseStrengthZeroIsIdentity() {
        let color = SimColor(hex: 0x20B0AC)
        let out = color.gentleInverse(strength: 0)
        XCTAssertEqual(out.r, color.r, accuracy: 1e-9)
        XCTAssertEqual(out.g, color.g, accuracy: 1e-9)
        XCTAssertEqual(out.b, color.b, accuracy: 1e-9)
    }

    func testReadoutBackgroundPicksSkyWaterOrBlend() {
        var s = state { _ in }
        let sky = SimColor(hex: 0x00FFFF)
        let water = SimColor(hex: 0x0000FF)

        // Empty tank: text anywhere above the floor sits on sky.
        s.water.targetLevel = 0
        for _ in 0..<200 { s.water.step() }
        XCTAssertEqual(s.tileReadoutBackground(centerY: 0.5, height: 0.1,
                                               skyColor: sky, liquidColor: water), sky)

        // Full tank: the same text sits on water.
        s.water.targetLevel = 1
        for _ in 0..<200 { s.water.step() }
        XCTAssertEqual(s.tileReadoutBackground(centerY: 0.5, height: 0.1,
                                               skyColor: sky, liquidColor: water), water)
    }

    func testReadoutBackgroundBlendsAcrossTheSurface() {
        var s = state { _ in }
        s.water.targetLevel = 0.5
        for _ in 0..<400 { s.water.step() }
        let blended = s.tileReadoutBackground(
            centerY: 0.5, height: 0.2,
            skyColor: SimColor(hex: 0x000000), liquidColor: SimColor(hex: 0xFFFFFF)
        )
        // Surface through the middle of the band → roughly half and half.
        XCTAssertEqual(blended.r, 0.5, accuracy: 0.15)
    }

    // MARK: - Theme coverage

    func testEveryPresetDefinesFiveDistinctBands() {
        for preset in ThemePresets.all {
            let bands = preset.theme.claudeWeeklyBands
            XCTAssertEqual(bands.count, 5, "\(preset.id) should define five bands")
            XCTAssertEqual(Set(bands.map { "\($0.r),\($0.g),\($0.b)" }).count, 5,
                           "\(preset.id) bands should all differ")
        }
    }

    func testDefaultPresetKeepsTheStockBands() {
        XCTAssertEqual(ThemePresets.default.theme.claudeWeeklyBands,
                       ColorTheme.defaultClaudeWeeklyBands)
    }

    func testPresetsCarryTheirOwnBands() {
        // Each preset paints the bands in its own palette rather than
        // inheriting the stock blue-to-red ramp.
        for preset in ThemePresets.all where preset.id != "default" {
            XCTAssertNotEqual(preset.theme.claudeWeeklyBands,
                              ColorTheme.defaultClaudeWeeklyBands,
                              "\(preset.id) should not reuse the default bands")
        }
    }

    func testSwitchingThemeRepaintsBandsButKeepsEdges() {
        var config = SimulationConfig.default
        config.claudeUsage.weeklyThresholds = [10, 30, 60, 80]
        config.theme = ThemePresets.lava.theme

        XCTAssertEqual(config.claudeUsage.weeklyThresholds, [10, 30, 60, 80])
        XCTAssertEqual(config.theme.claudeWeeklyColor(percent: 5, thresholds: config.claudeUsage.weeklyThresholds),
                       ThemePresets.lava.theme.claudeWeeklyBands[0])
        XCTAssertEqual(config.theme.claudeWeeklyColor(percent: 95, thresholds: config.claudeUsage.weeklyThresholds),
                       ThemePresets.lava.theme.claudeWeeklyBands[4])
    }

    func testPresetBandsSurviveExportImport() throws {
        let theme = ThemePresets.neonNight.theme
        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(ColorTheme.self, from: data)
        XCTAssertEqual(decoded.claudeWeeklyBands, theme.claudeWeeklyBands)
    }

    // MARK: - Hide while low

    func testReadoutHidesBelowFirstBandWhenEnabled() {
        var s = state {
            $0.tileReadout.source = .claudeFiveHourUsageAndCountdown
            $0.tileReadout.hideClaudeWhenLow = true
        }
        s.claudeUsage = snapshot(fiveHour: window(percent: 24, resetsInSeconds: 3600))
        XCTAssertNil(s.tileReadout(now: now))

        s.claudeUsage = snapshot(fiveHour: window(percent: 25, resetsInSeconds: 3600))
        XCTAssertEqual(s.tileReadout(now: now)?.text, "25% 1:00")
    }

    func testHideWhileLowFollowsTheConfiguredBandEdge() {
        var s = state {
            $0.tileReadout.source = .claudeFiveHourUsage
            $0.tileReadout.hideClaudeWhenLow = true
            $0.claudeUsage.weeklyThresholds = [40, 60, 80, 95]
        }
        s.claudeUsage = snapshot(fiveHour: window(percent: 30, resetsInSeconds: 3600))
        XCTAssertNil(s.tileReadout(now: now))
        s.claudeUsage = snapshot(fiveHour: window(percent: 45, resetsInSeconds: 3600))
        XCTAssertEqual(s.tileReadout(now: now)?.text, "45%")
    }

    func testHideWhileLowGatesWeeklySourceOnWeeklyUsage() {
        var s = state {
            $0.tileReadout.source = .claudeWeeklyUsage
            $0.tileReadout.hideClaudeWhenLow = true
        }
        // Five-hour is high, weekly is low — the weekly source hides.
        s.claudeUsage = snapshot(fiveHour: window(percent: 90, resetsInSeconds: 3600),
                                 sevenDay: window(percent: 10, resetsInSeconds: 86_400))
        XCTAssertNil(s.tileReadout(now: now))
    }

    func testHideWhileLowLeavesSystemSourcesAlone() {
        var s = state {
            $0.tileReadout.source = .cpuPercent
            $0.tileReadout.hideClaudeWhenLow = true
        }
        s.overlay.cpuPercent = 3
        XCTAssertEqual(s.tileReadout(now: now)?.text, "3%")
    }

    func testHideWhileLowIsOffByDefault() {
        var s = state { $0.tileReadout.source = .claudeFiveHourUsage }
        s.claudeUsage = snapshot(fiveHour: window(percent: 2, resetsInSeconds: 3600))
        XCTAssertEqual(s.tileReadout(now: now)?.text, "2%")
    }

    // MARK: - Agent floor

    func testAgentRestsOnFloorWhenTankIsEmpty() {
        // A freshly reset Claude 5-hour window is 0% used — a water level
        // memory usage never produced. The agent must not sink off-canvas.
        var duck = DuckState()
        let empty = Array(repeating: 0.0, count: 64)
        for _ in 0..<600 { duck.step(waterLevels: empty) }
        XCTAssertGreaterThanOrEqual(duck.y, duck.minimumY)
    }

    func testFollowWaterAlsoRespectsTheFloor() {
        var duck = DuckState()
        duck.followWater(waterLevels: Array(repeating: 0.0, count: 64))
        XCTAssertEqual(duck.y, DuckState.baseMinimumY)
    }

    // MARK: - Bubble metric

    func testBubblesDefaultToCPU() {
        var s = state { _ in }
        s.cpuLoad = 0.42
        XCTAssertEqual(s.config.bubbleMetric, .cpuLoad)
        XCTAssertEqual(s.bubbleIntensity(now: now), 0.42, accuracy: 1e-9)
    }

    func testBubblesFollowTheChosenMetric() {
        var s = state { $0.bubbleMetric = .gpuUtilization }
        s.cpuLoad = 0.1
        s.gpuUtilization = 0.8
        s.networkIntensity = 0.3
        s.diskIntensity = 0.6
        XCTAssertEqual(s.bubbleIntensity(now: now), 0.8, accuracy: 1e-9)

        var net = state { $0.bubbleMetric = .networkIO }
        net.networkIntensity = 0.3
        XCTAssertEqual(net.bubbleIntensity(now: now), 0.3, accuracy: 1e-9)

        var disk = state { $0.bubbleMetric = .diskIOPS }
        disk.diskIntensity = 0.6
        XCTAssertEqual(disk.bubbleIntensity(now: now), 0.6, accuracy: 1e-9)
    }

    func testBubblesFromClaudeWindows() {
        var five = state { $0.bubbleMetric = .claudeFiveHour }
        five.claudeUsage = snapshot(fiveHour: window(percent: 70, resetsInSeconds: 3600),
                                    sevenDay: window(percent: 20, resetsInSeconds: 86_400))
        XCTAssertEqual(five.bubbleIntensity(now: now), 0.70, accuracy: 1e-9)

        var weekly = state { $0.bubbleMetric = .claudeWeekly }
        weekly.claudeUsage = snapshot(fiveHour: window(percent: 70, resetsInSeconds: 3600),
                                      sevenDay: window(percent: 20, resetsInSeconds: 86_400))
        XCTAssertEqual(weekly.bubbleIntensity(now: now), 0.20, accuracy: 1e-9)
    }

    func testBubblesFallBackToCPUWithoutUsageData() {
        var s = state { $0.bubbleMetric = .claudeFiveHour }
        s.cpuLoad = 0.35
        XCTAssertEqual(s.bubbleIntensity(now: now), 0.35, accuracy: 1e-9)
    }

    // MARK: - Rain metric

    func testRainDefaultsToDiskIOPSAndMatchesTheOldRamp() {
        var s = state { _ in }
        XCTAssertEqual(s.config.rainMetric, .diskIOPS)

        // The old code was quiet below 500 IOPS and saturated at 5000, with
        // diskIntensity = iops / 5000.
        func rain(atIOPS iops: Double) -> Double {
            s.diskIntensity = min(1.0, iops / 5000)
            return s.rainSpawnIntensity(now: now)
        }
        XCTAssertEqual(rain(atIOPS: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(rain(atIOPS: 500), 0, accuracy: 1e-9)
        XCTAssertEqual(rain(atIOPS: 2750), 0.5, accuracy: 1e-9)
        XCTAssertEqual(rain(atIOPS: 5000), 1.0, accuracy: 1e-9)
        XCTAssertEqual(rain(atIOPS: 9000), 1.0, accuracy: 1e-9)
    }

    func testRainFollowsTheChosenMetric() {
        var s = state { $0.rainMetric = .diskThroughput }
        s.diskIntensity = 1.0            // ignored
        s.diskThroughputIntensity = 0.55
        XCTAssertEqual(s.rainSpawnIntensity(now: now), (0.55 - 0.1) / 0.9, accuracy: 1e-9)

        var claude = state { $0.rainMetric = .claudeWeekly }
        claude.claudeUsage = snapshot(sevenDay: window(percent: 82, resetsInSeconds: 86_400))
        XCTAssertEqual(claude.rainSpawnIntensity(now: now), (0.82 - 0.1) / 0.9, accuracy: 1e-9)
    }

    func testRainIsZeroWhenDisabled() {
        var s = state {
            $0.rainEnabled = false
            $0.rainMetric = .cpuLoad
        }
        s.cpuLoad = 1.0
        XCTAssertEqual(s.rainSpawnIntensity(now: now), 0)
    }

    func testDiskThroughputIsASeparateMetricFromIOPS() {
        var s = state { _ in }
        s.diskIntensity = 0.2
        s.diskThroughputIntensity = 0.9
        XCTAssertEqual(s.intensity(of: .diskIOPS, now: now), 0.2, accuracy: 1e-9)
        XCTAssertEqual(s.intensity(of: .diskThroughput, now: now), 0.9, accuracy: 1e-9)
    }

    // MARK: - Keeping the agent afloat

    func testEmptyTankIsFlooredToTheAgentsDraught() {
        // A freshly reset 5-hour window reads 0%, which would leave a
        // partly-submerged agent hovering over an empty tank.
        var s = state {
            $0.claudeUsage.waterLevelSource = .claudeFiveHour
            $0.keepAgentAfloat = true
        }
        s.claudeUsage = snapshot(fiveHour: window(percent: 0, resetsInSeconds: 3600))
        XCTAssertEqual(s.waterTarget(now: now), s.duck.minimumY, accuracy: 1e-9)
    }

    func testFloorScalesWithAgentSize() {
        var config = SimulationConfig.default
        config.agentSizeScale = 2.0
        config.claudeUsage.waterLevelSource = .claudeFiveHour
        var s = SimulationState(canvasSize: 256, config: config)
        s.memoryUsage = 0
        s.claudeUsage = snapshot(fiveHour: window(percent: 0, resetsInSeconds: 3600))
        XCTAssertEqual(s.waterTarget(now: now), DuckState.baseMinimumY * 2.0, accuracy: 1e-9)
    }

    func testFloorNeverRaisesARealReading() {
        var s = state {
            $0.claudeUsage.waterLevelSource = .claudeFiveHour
            $0.keepAgentAfloat = true
        }
        s.claudeUsage = snapshot(fiveHour: window(percent: 60, resetsInSeconds: 3600))
        XCTAssertEqual(s.waterTarget(now: now), 0.60, accuracy: 1e-9)
    }

    func testFloorIsOffWhenDisabledOrAgentHidden() {
        var s = state {
            $0.claudeUsage.waterLevelSource = .claudeFiveHour
            $0.keepAgentAfloat = false
        }
        s.memoryUsage = 0
        s.claudeUsage = snapshot(fiveHour: window(percent: 0, resetsInSeconds: 3600))
        XCTAssertEqual(s.waterTarget(now: now), 0, accuracy: 1e-9)

        var hidden = state {
            $0.claudeUsage.waterLevelSource = .claudeFiveHour
            $0.keepAgentAfloat = true
            $0.duckEnabled = false
        }
        hidden.memoryUsage = 0
        hidden.claudeUsage = snapshot(fiveHour: window(percent: 0, resetsInSeconds: 3600))
        XCTAssertEqual(hidden.waterTarget(now: now), 0, accuracy: 1e-9)
    }

    // MARK: - Agent size

    func testFloorGrowsWithAgentSize() {
        var duck = DuckState()
        duck.sizeScale = 2.0
        duck.followWater(waterLevels: Array(repeating: 0.0, count: 64))
        XCTAssertEqual(duck.y, DuckState.baseMinimumY * 2.0, accuracy: 1e-9)
    }

    func testApplyPushesAndClampsAgentSize() {
        var config = SimulationConfig.default
        config.agentSizeScale = 1.6
        var s = SimulationState(canvasSize: 256, config: config)
        XCTAssertEqual(s.duck.sizeScale, 1.6, accuracy: 1e-9)

        config.agentSizeScale = 99
        s.apply(config)
        XCTAssertEqual(s.duck.sizeScale, SimulationConfig.agentSizeRange.upperBound)

        config.agentSizeScale = 0
        s.apply(config)
        XCTAssertEqual(s.duck.sizeScale, SimulationConfig.agentSizeRange.lowerBound)
    }

    func testAgentSizeDefaultsToStockAndSurvivesOldConfigs() throws {
        XCTAssertEqual(SimulationConfig.default.agentSizeScale, 1.0)
        let json = Data(#"{"maxBubbles": 42}"#.utf8)
        let config = try JSONDecoder().decode(SimulationConfig.self, from: json)
        XCTAssertEqual(config.agentSizeScale, 1.0)
    }

    func testAgentStillTracksNormalWaterLevels() {
        var duck = DuckState()
        let half = Array(repeating: 0.5, count: 64)
        duck.followWater(waterLevels: half)
        XCTAssertEqual(duck.y, 0.5, accuracy: 1e-9)
    }

    func testReadoutSourcesDeclareTheirDataNeeds() {
        XCTAssertFalse(TileReadoutSource.cpuPercent.needsClaudeUsage)
        XCTAssertFalse(TileReadoutSource.memoryPercent.needsClaudeUsage)
        XCTAssertFalse(TileReadoutSource.none.needsClaudeUsage)
        XCTAssertTrue(TileReadoutSource.claudeWeeklyUsage.needsClaudeUsage)
        XCTAssertTrue(TileReadoutSource.claudeFiveHourCountdown.needsClaudeUsage)
    }

    // MARK: - Wire format written by the status-line wrapper

    func testDecodesStatuslineWrapperOutput() throws {
        let json = Data("""
        {"updated_at": 1786000000,
         "five_hour": {"used_percentage": 42.1, "resets_at": 1786010000},
         "seven_day": {"used_percentage": 61, "resets_at": 1786500000}}
        """.utf8)
        let snapshot = try JSONDecoder().decode(ClaudeUsageSnapshot.self, from: json)
        XCTAssertEqual(snapshot.updatedAt.timeIntervalSince1970, 1_786_000_000)
        XCTAssertEqual(snapshot.fiveHour?.usedPercentage, 42.1)
        XCTAssertEqual(snapshot.fiveHour?.resetsAt.timeIntervalSince1970, 1_786_010_000)
        XCTAssertEqual(snapshot.sevenDay?.usedPercentage, 61)
    }

    func testDecodesWithNullWindows() throws {
        // jq emits nulls when Claude Code reported only one of the windows.
        let json = Data("""
        {"updated_at": 1786000000, "five_hour": null,
         "seven_day": {"used_percentage": 12, "resets_at": 1786500000}}
        """.utf8)
        let snapshot = try JSONDecoder().decode(ClaudeUsageSnapshot.self, from: json)
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertEqual(snapshot.sevenDay?.usedPercentage, 12)
    }
}
