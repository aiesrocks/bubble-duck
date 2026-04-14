// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — renders the simulation state to a CGImage for the dock tile

import AppKit
import BubbleCore

/// Renders a SimulationState into a CGImage, matching wmbubble's draw_watertank()
/// and bubblebuf_colorspace() pipeline but at 256x256 resolution.
/// The color theme is read from `state.config.theme` so live config changes
/// take effect without having to rebuild the renderer.
struct BubbleRenderer {
    let size: Int

    init(size: Int = 256) {
        self.size = size
    }

    func render(state: SimulationState) -> NSImage {
        let nsImage = NSImage(size: NSSize(width: size, height: size))
        nsImage.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            nsImage.unlockFocus()
            return nsImage
        }

        let theme = state.config.theme
        let airColor = theme.airColor(swapUsage: state.swapUsage)
        let liquidColor = theme.liquidColor(swapUsage: state.swapUsage)
        let s = Double(size)

        // Draw water tank column by column
        let columnCount = state.water.columnCount
        let colWidth = s / Double(columnCount)

        for col in 0..<columnCount {
            let x = Double(col) * colWidth
            let waterLevel = state.water.levels[col]
            let waterY = (1.0 - waterLevel) * s  // flip Y: 0=top in CG

            // Air (above water)
            context.setFillColor(cgColor(airColor))
            context.fill(CGRect(x: x, y: waterY, width: colWidth + 1, height: s - waterY))

            // Water (below water level)
            context.setFillColor(cgColor(liquidColor))
            context.fill(CGRect(x: x, y: 0, width: colWidth + 1, height: waterY))
        }

        // Draw bubbles
        for bubble in state.bubbleSystem.bubbles {
            let bx = bubble.x * s
            // Bubbles are underwater, flip Y
            let by = (1.0 - bubble.y) * s
            let br = bubble.size * s

            context.setFillColor(cgColor(theme.bubbleColor))
            context.fillEllipse(in: CGRect(
                x: bx - br, y: by - br,
                width: br * 2, height: br * 2
            ))
        }

        // Draw duck
        if state.duck.enabled {
            drawDuck(context: context, duck: state.duck, theme: theme, size: s)
        }

        nsImage.unlockFocus()
        return nsImage
    }

    private func drawDuck(context: CGContext, duck: DuckState, theme: ColorTheme, size: Double) {
        let duckSize = size * 0.12
        let dx = duck.x * size
        let dy = (1.0 - duck.y) * size  // flip Y
        let bob = sin(duck.bobAngle) * 2.0

        context.saveGState()
        context.translateBy(x: dx, y: dy + bob)

        if duck.isUpsideDown {
            context.scaleBy(x: 1, y: -1)
        }

        // Body (oval)
        context.setFillColor(cgColor(theme.duckBody))
        context.fillEllipse(in: CGRect(
            x: -duckSize * 0.6, y: -duckSize * 0.4,
            width: duckSize * 1.2, height: duckSize * 0.8
        ))

        // Head (circle)
        context.fillEllipse(in: CGRect(
            x: duckSize * 0.3, y: -duckSize * 0.1,
            width: duckSize * 0.5, height: duckSize * 0.5
        ))

        // Bill
        context.setFillColor(cgColor(theme.duckBill))
        context.fillEllipse(in: CGRect(
            x: duckSize * 0.65, y: duckSize * 0.05,
            width: duckSize * 0.35, height: duckSize * 0.2
        ))

        // Eye
        context.setFillColor(cgColor(theme.duckEye))
        context.fillEllipse(in: CGRect(
            x: duckSize * 0.5, y: duckSize * 0.15,
            width: duckSize * 0.1, height: duckSize * 0.1
        ))

        context.restoreGState()
    }

    private func cgColor(_ c: SimColor) -> CGColor {
        CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}
