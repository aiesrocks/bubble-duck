// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — settings UI bound to ConfigStore

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import BubbleCore

struct SettingsView: View {
    @Bindable var store: ConfigStore
    @State private var themeIOError: String? = nil

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
                Picker("Speed driven by", selection: $store.config.speedMetric) {
                    ForEach(SpeedMetric.allCases, id: \.self) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                Toggle("Rain (disk I/O)", isOn: $store.config.rainEnabled)
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
