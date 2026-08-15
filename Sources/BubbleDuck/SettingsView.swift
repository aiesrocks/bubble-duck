// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — settings UI bound to ConfigStore

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import BubbleCore

struct SettingsView: View {
    @Bindable var store: ConfigStore

    /// Live view of what the running simulation believes about Claude usage.
    /// Supplied by the AppDelegate so Settings reports the *app's* state
    /// rather than re-reading the file and possibly disagreeing with the tile.
    var usageStatus: () -> (snapshot: ClaudeUsageSnapshot?, error: String?) = { (nil, nil) }

    /// Whether the hover monitor is actually running, and why not if it isn't.
    var hoverStatus: () -> (running: Bool, error: String?) = { (false, nil) }

    @State private var themeIOError: String? = nil
    @State private var statusLines: [String] = []

    var body: some View {
        Form {
            Section("Power") {
                Picker("Mode", selection: $store.config.powerMode) {
                    ForEach(PowerMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                switch store.config.powerMode {
                case .smoothest:
                    Text("Full render at 60 fps. Maximum energy use.")
                        .font(.caption).foregroundStyle(.secondary)
                case .auto:
                    Text("Adaptive 10–60 fps based on activity. Drops to Lowest when macOS Low Power Mode is on.")
                        .font(.caption).foregroundStyle(.secondary)
                case .low:
                    Text("15 fps. No rain, fewer bubbles and ripples.")
                        .font(.caption).foregroundStyle(.secondary)
                case .lowest:
                    Text("4 fps. Minimal bubbles, no rain/ripples/bob.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Physics") {
                Stepper(value: $store.config.maxBubbles, in: 1...500) {
                    LabeledReadout(label: "Max bubbles", value: "\(store.config.maxBubbles)")
                }
                LabeledSlider(label: "Gravity", value: $store.config.gravity,
                              range: 0.0001...0.01, format: "%.4f")
                LabeledSlider(label: "Ripple strength", value: $store.config.rippleStrength,
                              range: 0...0.05, format: "%.4f")
                LabeledSlider(label: "Volatility", value: $store.config.volatility,
                              range: 0...3, format: "%.2f")
                LabeledSlider(label: "Viscosity", value: $store.config.viscosity,
                              range: 0.5...1, format: "%.2f")
                LabeledSlider(label: "Speed limit", value: $store.config.speedLimit,
                              range: 0.1...5, format: "%.2f")
            }

            Section("Floating Agent") {
                Toggle("Show agent", isOn: $store.config.duckEnabled)
                Picker("Character", selection: $store.config.agentType) {
                    ForEach(AgentType.allCases, id: \.self) { agent in
                        Text(agent.rawValue).tag(agent)
                    }
                }
                LabeledSlider(label: "Size", value: $store.config.agentSizeScale,
                              range: SimulationConfig.agentSizeRange, format: "%.2f×")
                Picker("Speed driven by", selection: $store.config.speedMetric) {
                    ForEach(SpeedMetric.allCases, id: \.self) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                Toggle("Rain (disk I/O)", isOn: $store.config.rainEnabled)

                Toggle("React to mouse hover", isOn: Binding(
                    get: { store.config.hoverReactionEnabled },
                    set: { wantsHover in
                        // Ask for permission at the moment the user opts in,
                        // so the system prompt has obvious context.
                        if wantsHover && !DockHoverMonitor.hasAccessibilityPermission {
                            DockHoverMonitor.requestAccessibilityPermission()
                        }
                        store.config.hoverReactionEnabled = wantsHover
                    }
                ))
                if store.config.hoverReactionEnabled {
                    Text(hoverStatusText)
                        .font(.caption)
                        .foregroundStyle(DockHoverMonitor.hasAccessibilityPermission
                                         ? Color.secondary : Color.red)
                } else {
                    Text("The agent reacts when the cursor enters the Dock tile. "
                         + "macOS gives Dock tiles no hover events, so this needs "
                         + "Accessibility permission to find the tile.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Claude usage") {
                Picker("Water level", selection: $store.config.claudeUsage.waterLevelSource) {
                    ForEach(WaterLevelSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                Picker("Water color", selection: $store.config.claudeUsage.waterColorSource) {
                    ForEach(WaterColorSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }

                LabeledSlider(label: "Refresh interval (s)",
                              value: $store.config.claudeUsage.refreshSeconds,
                              range: ClaudeUsageConfig.minimumRefreshSeconds...900,
                              format: "%.0f")
                LabeledSlider(label: "Treat as stale after (min)",
                              value: $store.config.claudeUsage.staleAfterMinutes,
                              range: 5...120, format: "%.0f")
                Toggle("Fall back to system metrics when stale",
                       isOn: $store.config.claudeUsage.fallbackWhenStale)

                Text("Claude Code only reports usage from interactive sessions. "
                     + "Install scripts/bubbleduck-statusline.sh as your status line to feed this.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Claude usage status") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(statusLines, id: \.self) { line in
                        Text(line)
                            .font(.caption).monospaced()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Weekly usage bands") {
                ForEach(0..<4) { i in
                    LabeledSlider(
                        label: "Band \(i + 1) edge (%)",
                        value: thresholdBinding(i),
                        range: 1...100, format: "%.0f"
                    )
                }
                SimColorRow(label: "Under band 1",  color: bandBinding(0))
                SimColorRow(label: "Under band 2",  color: bandBinding(1))
                SimColorRow(label: "Under band 3",  color: bandBinding(2))
                SimColorRow(label: "Under band 4",  color: bandBinding(3))
                SimColorRow(label: "At or over band 4", color: bandBinding(4))
                Text("Applies when water color is driven by Claude weekly usage. "
                     + "Band colors come from the theme and are replaced when you pick a "
                     + "different preset; the edges above are yours and stay put.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Tile readout") {
                Picker("Show", selection: $store.config.tileReadout.source) {
                    ForEach(TileReadoutSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                Picker("Position", selection: $store.config.tileReadout.position) {
                    ForEach(TileReadoutPosition.allCases, id: \.self) { position in
                        Text(position.rawValue).tag(position)
                    }
                }
                Picker("Text color", selection: $store.config.tileReadout.colorMode) {
                    ForEach(TileReadoutColorMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                switch store.config.tileReadout.colorMode {
                case .custom:
                    SimColorRow(label: "Color", color: $store.config.tileReadout.color)
                case .autoInverse:
                    LabeledSlider(label: "Inverse strength",
                                  value: $store.config.tileReadout.autoInverseStrength,
                                  range: 0.3...1.0, format: "%.2f")
                    Text("Follows whatever the text sits on — sky, water, or both — "
                         + "keeping the hue and flipping the lightness.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledSlider(label: "Opacity", value: $store.config.tileReadout.opacity,
                              range: 0...1, format: "%.2f")
                LabeledSlider(label: "Text size", value: $store.config.tileReadout.fontScale,
                              range: 0.04...0.40, format: "%.2f")
                Toggle("Dark backdrop behind text", isOn: $store.config.tileReadout.backdrop)
                Toggle("Outline text for contrast", isOn: $store.config.tileReadout.outline)
                Toggle("Dim while no overlay is showing",
                       isOn: $store.config.tileReadout.dimWhenIdle)
                Toggle("Hide while Claude usage is under band 1",
                       isOn: $store.config.tileReadout.hideClaudeWhenLow)
                Text("One line of text on the tile — the slot wmbubble used for CPU digits. "
                     + "Hiding under band 1 uses the first weekly band edge "
                     + "(\(Int(store.config.claudeUsage.weeklyThresholds.sorted().first ?? 25))%) "
                     + "and applies only to the Claude sources.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Theme") {
                Picker("Preset", selection: Binding(
                    get: { "custom" },  // we don't persist preset id; always shows Custom unless user picks one
                    set: { newId in
                        if let preset = ThemePresets.preset(id: newId) {
                            store.config.theme = preset.theme
                        }
                    }
                )) {
                    Text("Custom / (current)").tag("custom")
                    ForEach(ThemePresets.all, id: \.id) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }

                HStack {
                    Button("Export Theme…") { exportTheme() }
                    Button("Import Theme…") { importTheme() }
                }
                if let err = themeIOError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Sky (time of day)") {
                SimColorRow(label: "Dawn",  color: $store.config.theme.skyDawn)
                SimColorRow(label: "Noon",  color: $store.config.theme.skyNoon)
                SimColorRow(label: "Dusk",  color: $store.config.theme.skyDusk)
                SimColorRow(label: "Night", color: $store.config.theme.skyNight)
            }

            Section("Water (swap pressure)") {
                SimColorRow(label: "Water (no swap)",  color: $store.config.theme.liquidNoSwap)
                SimColorRow(label: "Water (max swap)", color: $store.config.theme.liquidMaxSwap)
            }

            Section("Agent & bubbles") {
                SimColorRow(label: "Duck body", color: $store.config.theme.duckBody)
                SimColorRow(label: "Duck bill", color: $store.config.theme.duckBill)
                SimColorRow(label: "Duck eye",  color: $store.config.theme.duckEye)
                SimColorRow(label: "Bubble", color: $store.config.theme.bubbleColor,
                            supportsOpacity: true)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults", role: .destructive) {
                        store.reset()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 520, idealHeight: 620)
        .task {
            // Poll the controller's view of the world while Settings is open.
            while !Task.isCancelled {
                statusLines = Self.describe(usageStatus())
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    // MARK: - Claude usage status

    /// Turns the reader's state into a few plain lines: what was read, how
    /// long ago, and when each window resets. Deliberately shows the raw
    /// reported figure alongside the rollover-corrected one, because
    /// "reported 100% but the window already rolled over" is exactly the
    /// state that makes the tile look wrong.
    private static func describe(_ status: (snapshot: ClaudeUsageSnapshot?,
                                            error: String?)) -> [String] {
        if let error = status.error { return [error] }
        guard let snapshot = status.snapshot else {
            return ["No reading yet — is the status-line wrapper installed?"]
        }

        let now = Date()
        let stamp = DateFormatter()
        stamp.dateFormat = "HH:mm"

        var lines = [String(format: "read %.0fs ago", snapshot.age(now: now))]
        func line(_ label: String, _ window: ClaudeUsageWindow?) {
            guard let window else {
                lines.append("\(label) — not reported")
                return
            }
            let rolled = window.hasRolledOver(now: now)
            lines.append(String(
                format: "%@ %.0f%% · resets %@ · %@",
                label, window.usedPercentage, stamp.string(from: window.resetsAt),
                rolled ? "ROLLED OVER (showing 0%)"
                       : ClaudeUsageFormat.countdown(window.timeUntilReset(now: now))
            ))
        }
        line("5h", snapshot.fiveHour)
        line("7d", snapshot.sevenDay)
        return lines
    }

    // MARK: - Hover status

    private var hoverStatusText: String {
        guard DockHoverMonitor.hasAccessibilityPermission else {
            return "Waiting for Accessibility permission — grant BubbleDuck in "
                + "System Settings → Privacy & Security → Accessibility, then toggle this off and on."
        }
        let status = hoverStatus()
        if let error = status.error { return error }
        return status.running
            ? "Watching the Dock tile."
            : "Not watching — reopen Settings after granting permission."
    }

    // MARK: - Claude usage bindings

    /// Binding onto one weekly threshold, kept sorted so the bands stay in
    /// order however the sliders are dragged.
    private func thresholdBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                let values = store.config.claudeUsage.weeklyThresholds
                return index < values.count ? values[index] : Double((index + 1) * 25)
            },
            set: { newValue in
                var values = store.config.claudeUsage.weeklyThresholds
                while values.count < 4 { values.append(Double((values.count + 1) * 25)) }
                values[index] = newValue
                store.config.claudeUsage.weeklyThresholds = values.sorted()
            }
        )
    }

    private func bandBinding(_ index: Int) -> Binding<SimColor> {
        Binding(
            get: {
                let bands = store.config.theme.claudeWeeklyBands
                return index < bands.count
                    ? bands[index]
                    : ColorTheme.defaultClaudeWeeklyBands[index]
            },
            set: { newValue in
                var bands = store.config.theme.claudeWeeklyBands
                while bands.count < 5 {
                    bands.append(ColorTheme.defaultClaudeWeeklyBands[bands.count])
                }
                bands[index] = newValue
                store.config.theme.claudeWeeklyBands = bands
            }
        )
    }

    // MARK: - Theme import / export (aiesrocks/bubble-duck#11)

    private func exportTheme() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "BubbleDuckTheme.json"
        panel.canCreateDirectories = true
        panel.title = "Export BubbleDuck Theme"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(store.config.theme)
                try data.write(to: url)
                themeIOError = nil
            } catch {
                themeIOError = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import BubbleDuck Theme"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let theme = try JSONDecoder().decode(ColorTheme.self, from: data)
                store.config.theme = theme
                themeIOError = nil
            } catch {
                themeIOError = "Import failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Subviews

private struct LabeledReadout: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: format, value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}

private struct SimColorRow: View {
    let label: String
    @Binding var color: SimColor
    var supportsOpacity: Bool = false

    var body: some View {
        ColorPicker(
            label,
            selection: Binding(
                get: { Color(color) },
                set: { color = SimColor($0) }
            ),
            supportsOpacity: supportsOpacity
        )
    }
}
