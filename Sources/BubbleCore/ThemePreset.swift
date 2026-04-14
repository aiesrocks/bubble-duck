// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — curated preset themes (aiesrocks/bubble-duck#11).

import Foundation

/// A named, curated `ColorTheme` that users can select from the
/// Settings picker. Presets are immutable — selecting one copies its
/// theme into the live config, which the user can continue to tweak.
public struct ThemePreset: Sendable, Equatable {
    public let id: String
    public let name: String
    public let theme: ColorTheme

    public init(id: String, name: String, theme: ColorTheme) {
        self.id = id
        self.name = name
        self.theme = theme
    }
}

public enum ThemePresets {
    // MARK: - Preset catalog

    /// Factory defaults — matches the built-in `ColorTheme()`.
    public static let `default` = ThemePreset(
        id: "default",
        name: "Default",
        theme: ColorTheme()
    )

    /// Dark blues + teals with deep-ocean abyss vibes.
    public static let deepSea = ThemePreset(
        id: "deepSea",
        name: "Deep Sea",
        theme: ColorTheme(
            skyDawn:  SimColor(hex: 0x0D3B4A),
            skyNoon:  SimColor(hex: 0x134C6A),
            skyDusk:  SimColor(hex: 0x0B2E47),
            skyNight: SimColor(hex: 0x020B1A),
            liquidNoSwap:  SimColor(hex: 0x0E3542),
            liquidMaxSwap: SimColor(hex: 0x8A2A55),
            duckBody: SimColor(hex: 0xE8E08A),
            duckBill: SimColor(hex: 0xB88E30),
            duckEye:  SimColor(hex: 0x0A0A0A),
            bubbleColor: SimColor(r: 0.70, g: 0.90, b: 0.95, a: 0.55)
        )
    )

    /// Warm oranges + purples — golden-hour lagoon.
    public static let sunsetLagoon = ThemePreset(
        id: "sunsetLagoon",
        name: "Sunset Lagoon",
        theme: ColorTheme(
            skyDawn:  SimColor(hex: 0xE87A8B),
            skyNoon:  SimColor(hex: 0xE39D4A),
            skyDusk:  SimColor(hex: 0x7A2E6D),
            skyNight: SimColor(hex: 0x2C0A3D),
            liquidNoSwap:  SimColor(hex: 0x2F8080),
            liquidMaxSwap: SimColor(hex: 0xB23058),
            duckBody: SimColor(hex: 0xF0B95D),
            duckBill: SimColor(hex: 0xD36E1A),
            duckEye:  SimColor(hex: 0x2B1A08),
            bubbleColor: SimColor(r: 1.00, g: 0.95, b: 0.80, a: 0.6)
        )
    )

    /// Icy whites + pale blues — glacier meltwater.
    public static let glacier = ThemePreset(
        id: "glacier",
        name: "Glacier",
        theme: ColorTheme(
            skyDawn:  SimColor(hex: 0xE6DFF0),
            skyNoon:  SimColor(hex: 0xB8D4E3),
            skyDusk:  SimColor(hex: 0xC6B8D9),
            skyNight: SimColor(hex: 0x2E4567),
            liquidNoSwap:  SimColor(hex: 0x94C0D0),
            liquidMaxSwap: SimColor(hex: 0xBF6A7A),
            duckBody: SimColor(hex: 0xF7E8A1),
            duckBill: SimColor(hex: 0xE1A454),
            duckEye:  SimColor(hex: 0x2B2A30),
            bubbleColor: SimColor(r: 1.0, g: 1.0, b: 1.0, a: 0.7)
        )
    )

    /// Volcanic reds + blacks — melt-your-eyes intensity.
    public static let lava = ThemePreset(
        id: "lava",
        name: "Lava",
        theme: ColorTheme(
            skyDawn:  SimColor(hex: 0x3A0A0A),
            skyNoon:  SimColor(hex: 0xB22E14),
            skyDusk:  SimColor(hex: 0x5C1005),
            skyNight: SimColor(hex: 0x120404),
            liquidNoSwap:  SimColor(hex: 0xC94A10),
            liquidMaxSwap: SimColor(hex: 0xF0D02C),
            duckBody: SimColor(hex: 0x1F1612),
            duckBill: SimColor(hex: 0xE64A16),
            duckEye:  SimColor(hex: 0xF8C72C),
            bubbleColor: SimColor(r: 1.0, g: 0.55, b: 0.12, a: 0.6)
        )
    )

    /// Neon cyan + magenta against inky night — synth-wave energy.
    public static let neonNight = ThemePreset(
        id: "neonNight",
        name: "Neon Night",
        theme: ColorTheme(
            skyDawn:  SimColor(hex: 0xE84FB5),
            skyNoon:  SimColor(hex: 0x1FD4E8),
            skyDusk:  SimColor(hex: 0x9F2ED0),
            skyNight: SimColor(hex: 0x0A0224),
            liquidNoSwap:  SimColor(hex: 0x0C4FAA),
            liquidMaxSwap: SimColor(hex: 0xE93B9B),
            duckBody: SimColor(hex: 0xF0F020),
            duckBill: SimColor(hex: 0x32F0E0),
            duckEye:  SimColor(hex: 0xE93B9B),
            bubbleColor: SimColor(r: 0.30, g: 1.0, b: 1.0, a: 0.6)
        )
    )

    /// Mossy greens + earthy browns — shaded creek bed.
    public static let forestCreek = ThemePreset(
        id: "forestCreek",
        name: "Forest Creek",
        theme: ColorTheme(
            skyDawn:  SimColor(hex: 0xB5C25A),
            skyNoon:  SimColor(hex: 0x4D7A32),
            skyDusk:  SimColor(hex: 0x70552A),
            skyNight: SimColor(hex: 0x141D0E),
            liquidNoSwap:  SimColor(hex: 0x2E5030),
            liquidMaxSwap: SimColor(hex: 0x8B3A1A),
            duckBody: SimColor(hex: 0xCBB860),
            duckBill: SimColor(hex: 0x8A6A2E),
            duckEye:  SimColor(hex: 0x20180A),
            bubbleColor: SimColor(r: 0.80, g: 0.95, b: 0.75, a: 0.55)
        )
    )

    /// Every built-in preset in display order. The first is always
    /// `.default` so the picker shows "Default" at the top.
    public static let all: [ThemePreset] = [
        .default, .deepSea, .sunsetLagoon, .glacier, .lava, .neonNight, .forestCreek
    ]

    /// Look up a preset by id — used when persisting the current selection.
    public static func preset(id: String) -> ThemePreset? {
        all.first { $0.id == id }
    }
}
