// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — bridge BubbleCore's pure SimColor to SwiftUI's Color

import AppKit
import SwiftUI
import BubbleCore

extension Color {
    /// Build a SwiftUI Color from a platform-free SimColor.
    init(_ c: SimColor) {
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
}

extension SimColor {
    /// Extract a SimColor from a SwiftUI Color via NSColor's sRGB components.
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        self.init(
            r: Double(ns.redComponent),
            g: Double(ns.greenComponent),
            b: Double(ns.blueComponent),
            a: Double(ns.alphaComponent)
        )
    }
}
