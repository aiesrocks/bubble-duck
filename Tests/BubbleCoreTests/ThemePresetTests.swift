// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import BubbleCore

@Suite("Theme Presets")
struct ThemePresetTests {
    @Test("default preset equals the factory ColorTheme")
    func defaultMatchesFactory() {
        #expect(ThemePresets.default.theme == ColorTheme())
    }

    @Test("catalog starts with Default and includes every named preset")
    func catalogOrder() {
        let ids = ThemePresets.all.map(\.id)
        #expect(ids.first == "default")
        #expect(ids.contains("deepSea"))
        #expect(ids.contains("sunsetLagoon"))
        #expect(ids.contains("glacier"))
        #expect(ids.contains("lava"))
        #expect(ids.contains("neonNight"))
        #expect(ids.contains("forestCreek"))
    }

    @Test("non-default presets actually differ from the factory")
    func nonDefaultPresetsDiffer() {
        let defaultTheme = ColorTheme()
        for preset in ThemePresets.all where preset.id != "default" {
            #expect(preset.theme != defaultTheme, "preset \(preset.id) should differ from default")
        }
    }

    @Test("preset ids are unique")
    func idsUnique() {
        let ids = ThemePresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("preset lookup by id round-trips")
    func lookupRoundTrips() {
        for preset in ThemePresets.all {
            #expect(ThemePresets.preset(id: preset.id)?.id == preset.id)
        }
    }

    @Test("presets round-trip through JSON (schema stability)")
    func presetsRoundTripThroughJSON() throws {
        for preset in ThemePresets.all {
            let data = try JSONEncoder().encode(preset.theme)
            let decoded = try JSONDecoder().decode(ColorTheme.self, from: data)
            #expect(decoded == preset.theme, "\(preset.id) failed JSON round-trip")
        }
    }

    @Test("unknown preset id returns nil")
    func unknownIdReturnsNil() {
        #expect(ThemePresets.preset(id: "nope") == nil)
    }
}
