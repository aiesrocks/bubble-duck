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
        XCTAssertEqual(ClaudeUsageFormat.countdown(0), "—")
        XCTAssertEqual(ClaudeUsageFormat.countdown(-10), "—")
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
        XCTAssertEqual(s.tileReadout(now: now)?.text, "—")
    }

    func testReadoutWeeklyUsage() {
        var s = state { $0.tileReadout.source = .claudeWeeklyUsage }
        s.claudeUsage = snapshot(sevenDay: window(percent: 61, resetsInSeconds: 86_400))
        XCTAssertEqual(s.tileReadout(now: now)?.text, "61%")
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
        XCTAssertGreaterThanOrEqual(duck.y, DuckState.minimumY)
    }

    func testFollowWaterAlsoRespectsTheFloor() {
        var duck = DuckState()
        duck.followWater(waterLevels: Array(repeating: 0.0, count: 64))
        XCTAssertEqual(duck.y, DuckState.minimumY)
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
