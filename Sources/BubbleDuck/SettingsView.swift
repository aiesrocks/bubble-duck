// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — settings UI bound to ConfigStore

import SwiftUI
import BubbleCore

struct SettingsView: View {
    @Bindable var store: ConfigStore

    var body: some View {
        Form {
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
