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

    /// Draws a classic rubber-duck silhouette (facing right) centered at the
    /// current context origin. All coordinates are normalized 0..1 units then
    /// multiplied by `duckSize`, so the shape scales cleanly with the canvas.
    private func drawDuck(context: CGContext, duck: DuckState, theme: ColorTheme, size: Double) {
        let duckSize = size * 0.22
        let dx = duck.x * size
        let dy = (1.0 - duck.y) * size  // flip Y
        let bob = sin(duck.bobAngle) * 2.0

        context.saveGState()
        context.translateBy(x: dx, y: dy + bob)
        // Duck sits slightly above the waterline so its belly grazes the surface
        context.translateBy(x: 0, y: -duckSize * 0.1)

        if duck.isUpsideDown {
            context.scaleBy(x: 1, y: -1)
        }
        context.scaleBy(x: duckSize, y: duckSize)

        // Body silhouette: belly curves down, back slopes up into an upturned
        // tail, then back-top flows forward into the neck.
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 0.55, y: -0.05))                               // chest
        body.addCurve(to: CGPoint(x: -0.45, y: -0.18),                          // belly → back
                      control1: CGPoint(x: 0.55, y: -0.38),
                      control2: CGPoint(x: -0.30, y: -0.40))
        body.addCurve(to: CGPoint(x: -0.58, y: 0.18),                           // up to tail tip
                      control1: CGPoint(x: -0.62, y: -0.15),
                      control2: CGPoint(x: -0.68, y: 0.08))
        body.addCurve(to: CGPoint(x: -0.28, y: 0.12),                           // tail notch forward
                      control1: CGPoint(x: -0.50, y: 0.32),
                      control2: CGPoint(x: -0.40, y: 0.22))
        body.addCurve(to: CGPoint(x: 0.25, y: 0.18),                            // back-top to neck
                      control1: CGPoint(x: -0.05, y: 0.22),
                      control2: CGPoint(x: 0.12, y: 0.28))
        body.addCurve(to: CGPoint(x: 0.55, y: -0.05),                           // neck down to chest
                      control1: CGPoint(x: 0.55, y: 0.12),
                      control2: CGPoint(x: 0.62, y: 0.02))
        body.closeSubpath()

        context.setFillColor(cgColor(theme.duckBody))
        context.addPath(body)
        context.fillPath()

        // Subtle highlight on the back for a 3-D feel (blended body color + white)
        let highlight = blend(theme.duckBody, with: SimColor(r: 1, g: 1, b: 1), t: 0.35)
        context.setFillColor(cgColor(highlight))
        context.fillEllipse(in: CGRect(x: -0.20, y: 0.02, width: 0.30, height: 0.08))

        // Head
        context.setFillColor(cgColor(theme.duckBody))
        context.fillEllipse(in: CGRect(x: 0.18, y: 0.12, width: 0.48, height: 0.48))

        // Bill — two stacked ellipses suggest an open-beak look
        context.setFillColor(cgColor(theme.duckBill))
        context.fillEllipse(in: CGRect(x: 0.55, y: 0.26, width: 0.38, height: 0.16))
        // Bill shadow (darker lower half) for separation
        let billShadow = blend(theme.duckBill, with: SimColor(r: 0, g: 0, b: 0), t: 0.25)
        context.setFillColor(cgColor(billShadow))
        context.fillEllipse(in: CGRect(x: 0.58, y: 0.22, width: 0.32, height: 0.06))

        // Eye
        context.setFillColor(cgColor(theme.duckEye))
        context.fillEllipse(in: CGRect(x: 0.44, y: 0.38, width: 0.08, height: 0.08))

        // Eye glint
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        context.fillEllipse(in: CGRect(x: 0.47, y: 0.42, width: 0.025, height: 0.025))

        context.restoreGState()
    }

    private func blend(_ a: SimColor, with b: SimColor, t: Double) -> SimColor {
        a.lerp(to: b, t: t)
    }

    private func cgColor(_ c: SimColor) -> CGColor {
        CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}
