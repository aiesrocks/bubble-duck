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

    // wmbubble overlay colors
    private let digitColor = CGColor(red: 0.19, green: 0.55, blue: 0.94, alpha: 1)     // #308cf0
    private let warningColor = CGColor(red: 0.94, green: 0.2, blue: 0.2, alpha: 1)     // red >90%
    private let graphField = CGColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 1)   // #202020
    private let graphGrid = CGColor(red: 0.024, green: 0.165, blue: 0, alpha: 1)        // #062A00
    private let graphBar = CGColor(red: 0, green: 0.49, blue: 0.44, alpha: 1)           // #007D71
    private let graphMax = CGColor(red: 0.125, green: 0.71, blue: 0.68, alpha: 1)       // #20B6AE
    private let graphMarker = CGColor(red: 0.44, green: 0.89, blue: 0.44, alpha: 1)     // #71E371
    private let gaugeDigitColor = CGColor(red: 0.125, green: 0.69, blue: 0.67, alpha: 1) // #20B0AC

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
            let waterY = waterLevel * s

            // Water (below water level)
            context.setFillColor(cgColor(liquidColor))
            context.fill(CGRect(x: x, y: 0, width: colWidth + 1, height: waterY))

            // Air (above water)
            context.setFillColor(cgColor(airColor))
            context.fill(CGRect(x: x, y: waterY, width: colWidth + 1, height: s - waterY))
        }

        // Draw bubbles
        for bubble in state.bubbleSystem.bubbles {
            let bx = bubble.x * s
            let by = bubble.y * s
            let br = bubble.size * s

            context.setFillColor(cgColor(theme.bubbleColor))
            context.fillEllipse(in: CGRect(
                x: bx - br, y: by - br,
                width: br * 2, height: br * 2
            ))
        }

        // Draw floating agent
        if state.duck.enabled {
            drawAgent(context: context, duck: state.duck, agentType: state.config.agentType,
                      theme: theme, size: s)
            // Sleepy "Z" sprite drifts above the agent once sleepiness > 0.5
            // (aiesrocks/bubble-duck#5). Drawn after the agent so it floats
            // on top of the silhouette.
            drawSleepZ(duck: state.duck, size: s)
        }

        // CPU gauge (always visible, like wmbubble)
        drawCPUGauge(context: context, overlay: state.overlay, size: s)

        // Overlay screens (load average or memory info)
        if state.overlay.overlayAlpha > 0.01 {
            drawOverlay(context: context, overlay: state.overlay, size: s)
        }

        nsImage.unlockFocus()
        return nsImage
    }

    // MARK: - CPU Gauge

    /// Draws "XX%" at bottom-center, like wmbubble's draw_cpugauge().
    /// Always visible with alpha controlled by overlay.gaugeAlpha.
    private func drawCPUGauge(context: CGContext, overlay: OverlayState, size: Double) {
        let alpha = overlay.gaugeAlpha
        guard alpha > 0.01 else { return }

        context.saveGState()
        context.setAlpha(alpha)

        let text = String(format: "%d%%", overlay.cpuPercent)
        let fontSize = size * 0.14
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor(cgColor: gaugeDigitColor) ?? .cyan
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()
        let x = (size - textSize.width) / 2
        let y = size * 0.03  // near bottom (CG y=0 is bottom)

        attrStr.draw(at: NSPoint(x: x, y: y))

        context.restoreGState()
    }

    // MARK: - Overlay Screens

    /// Draw overlay directly on top of the water/bubbles (semi-transparent).
    /// No opaque background box — just text and graph composited over the scene.
    private func drawOverlay(context: CGContext, overlay: OverlayState, size: Double) {
        context.saveGState()
        context.setAlpha(overlay.overlayAlpha)

        switch overlay.screen {
        case .loadAverage:
            drawLoadAverageScreen(context: context, overlay: overlay, size: size)
        case .memoryInfo:
            drawMemoryInfoScreen(context: context, overlay: overlay, size: size)
        case .none:
            break
        }

        context.restoreGState()
    }

    /// Load average screen matching wmbubble layout:
    /// - Top: "1" "5" "15" labels with values below
    /// - Bottom: CPU utilization bar graph
    private func drawLoadAverageScreen(context: CGContext, overlay: OverlayState, size: Double) {
        let labelFontSize = size * 0.07
        let valueFontSize = size * 0.09

        // --- Top section: load average labels and values ---
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: labelFontSize, weight: .medium),
            .foregroundColor: NSColor(cgColor: digitColor) ?? .cyan
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: valueFontSize, weight: .bold),
            .foregroundColor: NSColor(cgColor: digitColor) ?? .cyan
        ]

        let labels = ["1", "5", "15"]
        let values = [overlay.loadAverage1, overlay.loadAverage5, overlay.loadAverage15]
        let colWidth = size / 3.0

        for (i, label) in labels.enumerated() {
            // Label at top
            let labelStr = NSAttributedString(string: label, attributes: labelAttrs)
            let labelW = labelStr.size().width
            let lx = colWidth * Double(i) + (colWidth - labelW) / 2
            labelStr.draw(at: NSPoint(x: lx, y: size - labelFontSize - 4))

            // Value below label
            let valueText = String(format: "%.2f", values[i])
            let valueStr = NSAttributedString(string: valueText, attributes: valueAttrs)
            let valueW = valueStr.size().width
            let vx = colWidth * Double(i) + (colWidth - valueW) / 2
            valueStr.draw(at: NSPoint(x: vx, y: size - labelFontSize - valueFontSize - 8))
        }

        // --- Bottom section: CPU utilization bar graph ---
        let graphHeight = size * 0.42
        let graphRect = CGRect(x: size * 0.04, y: size * 0.04,
                                width: size * 0.92, height: graphHeight)

        // Semi-transparent dark background for graph area only
        context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 0.7))
        context.fill(graphRect)

        drawBarGraph(context: context, history: overlay.cpuHistory, in: graphRect,
                     isLoadAvg: false)

        // Thin separator line above graph
        context.setStrokeColor(digitColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: graphRect.minX, y: graphRect.maxY))
        context.addLine(to: CGPoint(x: graphRect.maxX, y: graphRect.maxY))
        context.strokePath()
    }

    /// Memory info screen: used mem/swap at top + memory bar graph at bottom.
    private func drawMemoryInfoScreen(context: CGContext, overlay: OverlayState, size: Double) {
        let fontSize = size * 0.07

        let memUsedMB = Double(overlay.memoryUsedBytes) / 1_048_576
        let memTotalMB = Double(overlay.memoryTotalBytes) / 1_048_576
        let memPercent = overlay.memoryTotalBytes > 0
            ? Int(Double(overlay.memoryUsedBytes) * 100 / Double(overlay.memoryTotalBytes))
            : 0
        let swapUsedMB = Double(overlay.swapUsedBytes) / 1_048_576
        let swapTotalMB = Double(overlay.swapTotalBytes) / 1_048_576
        let swapPercent = overlay.swapTotalBytes > 0
            ? Int(Double(overlay.swapUsedBytes) * 100 / Double(overlay.swapTotalBytes))
            : 0

        // Memory line at top
        let memColor = memPercent > 90 ? warningColor : digitColor
        let memAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor(cgColor: memColor) ?? .cyan
        ]
        let memText = String(format: "m %.0f/%.0fM %d%%", memUsedMB, memTotalMB, memPercent)
        NSAttributedString(string: memText, attributes: memAttrs)
            .draw(at: NSPoint(x: size * 0.06, y: size - fontSize - 6))

        // Swap line below
        let swpColor = swapPercent > 90 ? warningColor : digitColor
        let swpAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor(cgColor: swpColor) ?? .cyan
        ]
        let swpText = String(format: "s %.0f/%.0fM %d%%", swapUsedMB, swapTotalMB, swapPercent)
        NSAttributedString(string: swpText, attributes: swpAttrs)
            .draw(at: NSPoint(x: size * 0.06, y: size - fontSize * 2 - 12))

        // Memory bar graph at bottom
        let graphHeight = size * 0.42
        let graphRect = CGRect(x: size * 0.04, y: size * 0.04,
                                width: size * 0.92, height: graphHeight)

        context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 0.7))
        context.fill(graphRect)

        drawBarGraph(context: context, history: overlay.memoryHistory, in: graphRect,
                     isLoadAvg: false)

        context.setStrokeColor(digitColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: graphRect.minX, y: graphRect.maxY))
        context.addLine(to: CGPoint(x: graphRect.maxX, y: graphRect.maxY))
        context.strokePath()
    }

    /// Draw a bar graph matching wmbubble's draw_history():
    /// auto-scaling, two-tone bars, grid lines, integer markers.
    private func drawBarGraph(context: CGContext, history: HistoryBuffer,
                               in rect: CGRect, isLoadAvg: Bool) {
        let samples = history.samples
        guard !samples.isEmpty else { return }

        // Grid background
        context.setFillColor(graphField)
        context.fill(rect)

        // Grid lines at 25%, 50%, 75%
        context.setStrokeColor(graphGrid)
        context.setLineWidth(0.5)
        for fraction in [0.25, 0.5, 0.75] {
            let y = rect.minY + rect.height * fraction
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.strokePath()
        }
        // Vertical grid every 8 bars
        let barWidth = rect.width / Double(history.capacity)
        for i in stride(from: 0, to: history.capacity, by: 8) {
            let x = rect.minX + Double(i) * barWidth
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.strokePath()
        }

        // Auto-scale: wmbubble scales by 100 (1.0 for load avg, 100% for mem)
        var scale: Double = isLoadAvg ? 1.0 : 100.0
        let maxVal = history.maxValue
        while maxVal > scale { scale += isLoadAvg ? 1.0 : 100.0 }

        // Draw bars
        let startIndex = max(0, samples.count - history.capacity)
        for (i, sample) in samples[startIndex...].enumerated() {
            let barHeight = (sample / scale) * rect.height
            let x = rect.minX + Double(i) * barWidth
            let capHeight = min(barHeight, 4.0)

            // Bar body
            context.setFillColor(graphBar)
            context.fill(CGRect(x: x, y: rect.minY,
                                 width: barWidth - 0.5, height: barHeight - capHeight))
            // Bar cap (brighter top 2-4 pixels, like wmbubble's graph_max)
            if barHeight > 1 {
                context.setFillColor(graphMax)
                context.fill(CGRect(x: x, y: rect.minY + barHeight - capHeight,
                                     width: barWidth - 0.5, height: capHeight))
            }
        }

        // Integer markers for load average (horizontal lines at 1.0, 2.0, etc.)
        if isLoadAvg && scale > 1.0 {
            context.setStrokeColor(graphMarker)
            context.setLineWidth(1)
            for i in 1...Int(scale) {
                let y = rect.minY + rect.height * (Double(i) / scale)
                context.move(to: CGPoint(x: rect.minX, y: y))
                context.addLine(to: CGPoint(x: rect.maxX, y: y))
                context.strokePath()
            }
        }
    }

    // MARK: - Floating Agents

    private func drawAgent(context: CGContext, duck: DuckState, agentType: AgentType,
                           theme: ColorTheme, size: Double) {
        switch agentType {
        case .rubberDuck:
            drawRubberDuck(context: context, duck: duck, theme: theme, size: size)
        case .mandarinDuck:
            drawMandarinDuck(context: context, duck: duck, size: size)
        case .otter:
            drawOtter(context: context, duck: duck, size: size)
        case .turtle:
            drawTurtle(context: context, duck: duck, size: size)
        case .frog:
            drawFrog(context: context, duck: duck, size: size)
        case .hippo:
            drawHippo(context: context, duck: duck, size: size)
        case .origamiBoat:
            drawOrigamiBoat(context: context, duck: duck, size: size)
        }
    }

    /// Positions the agent on the water surface and returns the scale factor.
    private func beginAgent(context: CGContext, duck: DuckState, size: Double,
                            agentScale: Double = 0.22) -> Double {
        let agentSize = size * agentScale
        let dx = duck.x * size
        let dy = duck.y * size
        let bob = sin(duck.bobAngle) * 2.0

        context.saveGState()
        context.translateBy(x: dx, y: dy + bob)
        context.translateBy(x: 0, y: -agentSize * 0.1)

        if duck.isUpsideDown {
            context.scaleBy(x: 1, y: -1)
        }
        context.scaleBy(x: agentSize, y: agentSize)
        return agentSize
    }

    // MARK: Blink rendering helpers

    /// Draws an eye-shaped ellipse that squashes vertically when the agent
    /// blinks. `openness` is BlinkState.openness (0 = closed, 1 = open);
    /// the eye never mathematically vanishes — a thin line remains so the
    /// squash reads naturally. Horizontal center is preserved via the x/y
    /// origin convention already used by each agent's draw code.
    private func fillEye(_ context: CGContext,
                         x: Double, y: Double, width: Double, height: Double,
                         openness: Double) {
        let o = max(0.05, openness)
        let h = height * o
        let centerY = y + height / 2
        context.fillEllipse(in: CGRect(x: x, y: centerY - h / 2, width: width, height: h))
    }

    /// Like fillEye, but the highlight is hidden once the eye is mostly
    /// closed so no stray sparkle hovers mid-blink.
    private func fillEyeGlint(_ context: CGContext,
                              x: Double, y: Double, width: Double, height: Double,
                              openness: Double) {
        guard openness > 0.4 else { return }
        let h = height * openness
        let centerY = y + height / 2
        context.fillEllipse(in: CGRect(x: x, y: centerY - h / 2, width: width, height: h))
    }

    /// Draws a floating "Z" above the agent once `sleepiness > 0.5`
    /// (aiesrocks/bubble-duck#5). Alpha eases up smoothly between 0.5 and
    /// 1.0 sleepiness so the Z fades in rather than pops. Uses AppKit text
    /// rendering since it's cheap and easy to style.
    private func drawSleepZ(duck: DuckState, size: Double) {
        guard duck.sleepiness > 0.5 else { return }
        let alpha = DuckState.smoothstep(from: 0.5, to: 1.0, value: duck.sleepiness) * 0.85
        let dx = duck.x * size
        let dy = duck.y * size
        let bob = sin(duck.bobAngle) * 2.0
        // Position the Z just above the agent's head, matching the sign
        // convention the body path uses (positive local y = "away from water").
        let zY = dy + bob + size * 0.18

        let font = NSFont.systemFont(ofSize: size * 0.09, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 0.15, alpha: alpha)
        ]
        let str = NSAttributedString(string: "Z", attributes: attrs)
        // `dx` is the agent's horizontal center; nudge left so the Z reads as centered.
        str.draw(at: NSPoint(x: dx - size * 0.04, y: zY))
    }

    private func drawRubberDuck(context: CGContext, duck: DuckState, theme: ColorTheme, size: Double) {
        _ = beginAgent(context: context, duck: duck, size: size)

        // Body silhouette
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 0.55, y: -0.05))
        body.addCurve(to: CGPoint(x: -0.45, y: -0.18),
                      control1: CGPoint(x: 0.55, y: -0.38),
                      control2: CGPoint(x: -0.30, y: -0.40))
        body.addCurve(to: CGPoint(x: -0.58, y: 0.18),
                      control1: CGPoint(x: -0.62, y: -0.15),
                      control2: CGPoint(x: -0.68, y: 0.08))
        body.addCurve(to: CGPoint(x: -0.28, y: 0.12),
                      control1: CGPoint(x: -0.50, y: 0.32),
                      control2: CGPoint(x: -0.40, y: 0.22))
        body.addCurve(to: CGPoint(x: 0.25, y: 0.18),
                      control1: CGPoint(x: -0.05, y: 0.22),
                      control2: CGPoint(x: 0.12, y: 0.28))
        body.addCurve(to: CGPoint(x: 0.55, y: -0.05),
                      control1: CGPoint(x: 0.55, y: 0.12),
                      control2: CGPoint(x: 0.62, y: 0.02))
        body.closeSubpath()

        context.setFillColor(cgColor(theme.duckBody))
        context.addPath(body)
        context.fillPath()

        // Highlight
        let highlight = blend(theme.duckBody, with: SimColor(r: 1, g: 1, b: 1), t: 0.35)
        context.setFillColor(cgColor(highlight))
        context.fillEllipse(in: CGRect(x: -0.20, y: 0.02, width: 0.30, height: 0.08))

        // Head
        context.setFillColor(cgColor(theme.duckBody))
        context.fillEllipse(in: CGRect(x: 0.18, y: 0.12, width: 0.48, height: 0.48))

        // Bill
        context.setFillColor(cgColor(theme.duckBill))
        context.fillEllipse(in: CGRect(x: 0.55, y: 0.26, width: 0.38, height: 0.16))
        let billShadow = blend(theme.duckBill, with: SimColor(r: 0, g: 0, b: 0), t: 0.25)
        context.setFillColor(cgColor(billShadow))
        context.fillEllipse(in: CGRect(x: 0.58, y: 0.22, width: 0.32, height: 0.06))

        // Eye
        let o = duck.effectiveEyelidOpenness
        context.setFillColor(cgColor(theme.duckEye))
        fillEye(context, x: 0.44, y: 0.38, width: 0.08, height: 0.08, openness: o)

        // Eye glint
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        fillEyeGlint(context, x: 0.47, y: 0.42, width: 0.025, height: 0.025, openness: o)

        context.restoreGState()
    }

    // MARK: - Mandarin Duck (colorful, elegant)

    private func drawMandarinDuck(context: CGContext, duck: DuckState, size: Double) {
        _ = beginAgent(context: context, duck: duck, size: size)

        // Body — brown/chestnut
        let bodyColor = CGColor(red: 0.55, green: 0.27, blue: 0.07, alpha: 1)
        context.setFillColor(bodyColor)
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 0.5, y: -0.05))
        body.addCurve(to: CGPoint(x: -0.45, y: -0.15),
                      control1: CGPoint(x: 0.5, y: -0.35), control2: CGPoint(x: -0.3, y: -0.38))
        body.addCurve(to: CGPoint(x: -0.5, y: 0.15),
                      control1: CGPoint(x: -0.55, y: -0.1), control2: CGPoint(x: -0.6, y: 0.05))
        body.addCurve(to: CGPoint(x: 0.25, y: 0.15),
                      control1: CGPoint(x: -0.1, y: 0.2), control2: CGPoint(x: 0.1, y: 0.25))
        body.addCurve(to: CGPoint(x: 0.5, y: -0.05),
                      control1: CGPoint(x: 0.5, y: 0.1), control2: CGPoint(x: 0.55, y: 0.0))
        body.closeSubpath()
        context.addPath(body)
        context.fillPath()

        // Orange "sail" feather on back
        context.setFillColor(CGColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1))
        let sail = CGMutablePath()
        sail.move(to: CGPoint(x: -0.1, y: 0.1))
        sail.addCurve(to: CGPoint(x: -0.25, y: 0.35),
                      control1: CGPoint(x: -0.2, y: 0.25), control2: CGPoint(x: -0.25, y: 0.3))
        sail.addCurve(to: CGPoint(x: 0.05, y: 0.12),
                      control1: CGPoint(x: -0.15, y: 0.3), control2: CGPoint(x: 0.0, y: 0.2))
        sail.closeSubpath()
        context.addPath(sail)
        context.fillPath()

        // Head — green/purple iridescent
        context.setFillColor(CGColor(red: 0.1, green: 0.45, blue: 0.2, alpha: 1))
        context.fillEllipse(in: CGRect(x: 0.2, y: 0.1, width: 0.42, height: 0.42))

        // Orange crest
        context.setFillColor(CGColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1))
        context.fillEllipse(in: CGRect(x: 0.25, y: 0.38, width: 0.35, height: 0.15))

        // White eye stripe
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        context.fillEllipse(in: CGRect(x: 0.35, y: 0.3, width: 0.18, height: 0.06))

        // Red bill
        context.setFillColor(CGColor(red: 0.9, green: 0.15, blue: 0.1, alpha: 1))
        context.fillEllipse(in: CGRect(x: 0.52, y: 0.2, width: 0.3, height: 0.12))

        // Eye
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        fillEye(context, x: 0.42, y: 0.32, width: 0.07, height: 0.07,
                openness: duck.effectiveEyelidOpenness)

        context.restoreGState()
    }

    // MARK: - Otter (chubby, cute, floating on back)

    private func drawOtter(context: CGContext, duck: DuckState, size: Double) {
        _ = beginAgent(context: context, duck: duck, size: size, agentScale: 0.30)

        // Chubby body — round and plump
        let furColor = CGColor(red: 0.4, green: 0.25, blue: 0.12, alpha: 1)
        context.setFillColor(furColor)
        context.fillEllipse(in: CGRect(x: -0.42, y: -0.2, width: 0.9, height: 0.42))

        // Big round lighter belly (floating on back, chubby!)
        context.setFillColor(CGColor(red: 0.72, green: 0.58, blue: 0.42, alpha: 1))
        context.fillEllipse(in: CGRect(x: -0.3, y: -0.12, width: 0.65, height: 0.28))

        // Round chubby head
        context.setFillColor(furColor)
        context.fillEllipse(in: CGRect(x: 0.22, y: -0.08, width: 0.35, height: 0.35))

        // Big lighter face — round cheeks
        context.setFillColor(CGColor(red: 0.75, green: 0.6, blue: 0.45, alpha: 1))
        context.fillEllipse(in: CGRect(x: 0.3, y: -0.02, width: 0.24, height: 0.22))

        // Cute round nose
        context.setFillColor(CGColor(red: 0.15, green: 0.1, blue: 0.05, alpha: 1))
        context.fillEllipse(in: CGRect(x: 0.48, y: 0.1, width: 0.07, height: 0.06))

        // Round ears
        context.setFillColor(furColor)
        context.fillEllipse(in: CGRect(x: 0.28, y: 0.2, width: 0.1, height: 0.1))
        context.fillEllipse(in: CGRect(x: 0.44, y: 0.2, width: 0.1, height: 0.1))

        // Small happy eyes
        let oOtter = duck.effectiveEyelidOpenness
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        fillEye(context, x: 0.35, y: 0.12, width: 0.06, height: 0.06, openness: oOtter)
        fillEye(context, x: 0.45, y: 0.12, width: 0.06, height: 0.06, openness: oOtter)

        // Eye glints
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
        fillEyeGlint(context, x: 0.37, y: 0.14, width: 0.02, height: 0.02, openness: oOtter)
        fillEyeGlint(context, x: 0.47, y: 0.14, width: 0.02, height: 0.02, openness: oOtter)

        // Little paws resting on belly
        context.setFillColor(furColor)
        context.fillEllipse(in: CGRect(x: 0.0, y: 0.06, width: 0.1, height: 0.08))
        context.fillEllipse(in: CGRect(x: 0.12, y: 0.06, width: 0.1, height: 0.08))

        // Chubby tail
        context.fillEllipse(in: CGRect(x: -0.5, y: -0.1, width: 0.18, height: 0.14))

        context.restoreGState()
    }

    // MARK: - Turtle (slow, steady)

    private func drawTurtle(context: CGContext, duck: DuckState, size: Double) {
        _ = beginAgent(context: context, duck: duck, size: size, agentScale: 0.28)

        // Shell — big dome shape
        let shellColor = CGColor(red: 0.3, green: 0.45, blue: 0.2, alpha: 1)
        context.setFillColor(shellColor)
        context.fillEllipse(in: CGRect(x: -0.4, y: -0.12, width: 0.8, height: 0.5))

        // Shell rim — darker edge
        context.setFillColor(CGColor(red: 0.22, green: 0.35, blue: 0.14, alpha: 1))
        context.setLineWidth(0.02)
        context.strokeEllipse(in: CGRect(x: -0.4, y: -0.12, width: 0.8, height: 0.5))

        // Shell pattern — darker hexagonal segments
        context.setFillColor(CGColor(red: 0.2, green: 0.35, blue: 0.12, alpha: 1))
        context.fillEllipse(in: CGRect(x: -0.18, y: 0.02, width: 0.22, height: 0.22))
        context.fillEllipse(in: CGRect(x: 0.05, y: 0.0, width: 0.2, height: 0.2))
        context.fillEllipse(in: CGRect(x: -0.08, y: -0.06, width: 0.18, height: 0.14))

        // Head — poking out right
        let skinColor = CGColor(red: 0.4, green: 0.55, blue: 0.3, alpha: 1)
        context.setFillColor(skinColor)
        context.fillEllipse(in: CGRect(x: 0.3, y: 0.0, width: 0.28, height: 0.24))

        // Eye
        let oTurtle = duck.effectiveEyelidOpenness
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        fillEye(context, x: 0.46, y: 0.13, width: 0.06, height: 0.06, openness: oTurtle)

        // Eye glint
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.7))
        fillEyeGlint(context, x: 0.48, y: 0.15, width: 0.02, height: 0.02, openness: oTurtle)

        // Front flippers — bigger, paddle-shaped
        context.setFillColor(skinColor)
        context.fillEllipse(in: CGRect(x: 0.15, y: -0.22, width: 0.2, height: 0.14))
        context.fillEllipse(in: CGRect(x: -0.2, y: -0.22, width: 0.2, height: 0.14))

        // Back flippers
        context.fillEllipse(in: CGRect(x: -0.38, y: -0.15, width: 0.14, height: 0.1))

        context.restoreGState()
    }

    // MARK: - Frog (sits on water, bursty)

    private func drawFrog(context: CGContext, duck: DuckState, size: Double) {
        _ = beginAgent(context: context, duck: duck, size: size, agentScale: 0.34)

        // Big round body — bright lime/yellow-green to distinguish from turtle
        let frogGreen = CGColor(red: 0.45, green: 0.85, blue: 0.1, alpha: 1)
        context.setFillColor(frogGreen)
        context.fillEllipse(in: CGRect(x: -0.35, y: -0.18, width: 0.7, height: 0.42))

        // Lighter yellow-green belly
        context.setFillColor(CGColor(red: 0.7, green: 0.95, blue: 0.3, alpha: 1))
        context.fillEllipse(in: CGRect(x: -0.22, y: -0.12, width: 0.5, height: 0.24))

        // Wide head
        context.setFillColor(frogGreen)
        context.fillEllipse(in: CGRect(x: 0.02, y: -0.02, width: 0.48, height: 0.35))

        // Big bulging eyes (on top of head) — bright lime
        let oFrog = duck.effectiveEyelidOpenness
        context.setFillColor(CGColor(red: 0.55, green: 0.9, blue: 0.15, alpha: 1))
        fillEye(context, x: 0.1, y: 0.24, width: 0.18, height: 0.18, openness: oFrog)
        fillEye(context, x: 0.3, y: 0.24, width: 0.18, height: 0.18, openness: oFrog)

        // Pupils
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        fillEye(context, x: 0.15, y: 0.29, width: 0.08, height: 0.08, openness: oFrog)
        fillEye(context, x: 0.35, y: 0.29, width: 0.08, height: 0.08, openness: oFrog)

        // Eye glints
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.7))
        fillEyeGlint(context, x: 0.18, y: 0.33, width: 0.03, height: 0.03, openness: oFrog)
        fillEyeGlint(context, x: 0.38, y: 0.33, width: 0.03, height: 0.03, openness: oFrog)

        // Wide smile
        context.setStrokeColor(CGColor(red: 0.2, green: 0.5, blue: 0.0, alpha: 1))
        context.setLineWidth(0.025)
        context.move(to: CGPoint(x: 0.42, y: 0.12))
        context.addCurve(to: CGPoint(x: 0.08, y: 0.12),
                         control1: CGPoint(x: 0.35, y: 0.04), control2: CGPoint(x: 0.15, y: 0.04))
        context.strokePath()

        // Back legs (folded, bigger)
        context.setFillColor(frogGreen)
        context.fillEllipse(in: CGRect(x: -0.42, y: -0.1, width: 0.2, height: 0.26))

        // Front legs
        context.fillEllipse(in: CGRect(x: 0.2, y: -0.2, width: 0.12, height: 0.14))

        context.restoreGState()
    }

    // MARK: - Hippo (big, mostly submerged)

    private func drawHippo(context: CGContext, duck: DuckState, size: Double) {
        _ = beginAgent(context: context, duck: duck, size: size, agentScale: 0.42)

        // Only the top of the head and eyes poke above water — hippo style
        let hippoGray = CGColor(red: 0.45, green: 0.4, blue: 0.42, alpha: 1)

        // Wide head dome
        context.setFillColor(hippoGray)
        context.fillEllipse(in: CGRect(x: -0.45, y: -0.12, width: 0.9, height: 0.3))

        // Big snout bump (front) — the most prominent feature
        context.setFillColor(CGColor(red: 0.52, green: 0.47, blue: 0.49, alpha: 1))
        context.fillEllipse(in: CGRect(x: 0.15, y: -0.08, width: 0.4, height: 0.26))

        // Nostrils — bigger
        context.setFillColor(CGColor(red: 0.25, green: 0.2, blue: 0.22, alpha: 1))
        context.fillEllipse(in: CGRect(x: 0.33, y: 0.08, width: 0.08, height: 0.05))
        context.fillEllipse(in: CGRect(x: 0.42, y: 0.08, width: 0.08, height: 0.05))

        // Ears — small bumps on top
        context.setFillColor(hippoGray)
        context.fillEllipse(in: CGRect(x: -0.2, y: 0.12, width: 0.12, height: 0.12))
        context.fillEllipse(in: CGRect(x: 0.05, y: 0.12, width: 0.12, height: 0.12))

        // Inner ear
        context.setFillColor(CGColor(red: 0.55, green: 0.45, blue: 0.48, alpha: 1))
        context.fillEllipse(in: CGRect(x: -0.17, y: 0.14, width: 0.06, height: 0.06))
        context.fillEllipse(in: CGRect(x: 0.08, y: 0.14, width: 0.06, height: 0.06))

        // Eyes — big, sitting on top of head
        let oHippo = duck.effectiveEyelidOpenness
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        fillEye(context, x: -0.12, y: 0.08, width: 0.14, height: 0.14, openness: oHippo)
        fillEye(context, x: 0.02, y: 0.08, width: 0.14, height: 0.14, openness: oHippo)

        // Pupils
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        fillEye(context, x: -0.07, y: 0.12, width: 0.07, height: 0.07, openness: oHippo)
        fillEye(context, x: 0.06, y: 0.12, width: 0.07, height: 0.07, openness: oHippo)

        // Eye glints
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.6))
        fillEyeGlint(context, x: -0.04, y: 0.15, width: 0.025, height: 0.025, openness: oHippo)
        fillEyeGlint(context, x: 0.09, y: 0.15, width: 0.025, height: 0.025, openness: oHippo)

        context.restoreGState()
    }

    // MARK: - Origami Boat (folded paper sailboat)

    private func drawOrigamiBoat(context: CGContext, duck: DuckState, size: Double) {
        _ = beginAgent(context: context, duck: duck, size: size, agentScale: 0.26)

        // Crisp paper palette: cream base, soft shadow for folded sides, dark
        // crease for outlines. Keeps the boat readable on any water color.
        let paperBase = CGColor(red: 0.97, green: 0.95, blue: 0.90, alpha: 1)
        let paperShadow = CGColor(red: 0.80, green: 0.77, blue: 0.70, alpha: 1)
        let edge = CGColor(red: 0.32, green: 0.30, blue: 0.27, alpha: 1)

        // Hull — trapezoid: flat bottom, flared sides, wide deck.
        let hull = CGMutablePath()
        hull.move(to: CGPoint(x: -0.55, y: 0.00))
        hull.addLine(to: CGPoint(x: 0.55, y: 0.00))
        hull.addLine(to: CGPoint(x: 0.38, y: -0.26))
        hull.addLine(to: CGPoint(x: -0.38, y: -0.26))
        hull.closeSubpath()

        context.setFillColor(paperBase)
        context.addPath(hull)
        context.fillPath()

        // Shaded right half suggests a central paper fold.
        let hullShadow = CGMutablePath()
        hullShadow.move(to: CGPoint(x: 0.00, y: 0.00))
        hullShadow.addLine(to: CGPoint(x: 0.55, y: 0.00))
        hullShadow.addLine(to: CGPoint(x: 0.38, y: -0.26))
        hullShadow.addLine(to: CGPoint(x: 0.00, y: -0.26))
        hullShadow.closeSubpath()

        context.setFillColor(paperShadow)
        context.addPath(hullShadow)
        context.fillPath()

        // Hull outline + center fold line.
        context.setStrokeColor(edge)
        context.setLineWidth(0.020)
        context.addPath(hull)
        context.strokePath()

        context.setLineWidth(0.015)
        context.move(to: CGPoint(x: 0.00, y: 0.00))
        context.addLine(to: CGPoint(x: 0.00, y: -0.26))
        context.strokePath()

        // Sail — tall triangle rising from deck, slightly forward-leaning.
        let sail = CGMutablePath()
        sail.move(to: CGPoint(x: -0.05, y: 0.02))
        sail.addLine(to: CGPoint(x: 0.30, y: 0.02))
        sail.addLine(to: CGPoint(x: 0.12, y: 0.58))
        sail.closeSubpath()

        context.setFillColor(paperBase)
        context.addPath(sail)
        context.fillPath()

        // Mirror the hull's fold shading on the sail's back half.
        let sailShadow = CGMutablePath()
        sailShadow.move(to: CGPoint(x: 0.12, y: 0.58))
        sailShadow.addLine(to: CGPoint(x: 0.30, y: 0.02))
        sailShadow.addLine(to: CGPoint(x: 0.12, y: 0.02))
        sailShadow.closeSubpath()

        context.setFillColor(paperShadow)
        context.addPath(sailShadow)
        context.fillPath()

        // Sail outline + central crease.
        context.setStrokeColor(edge)
        context.setLineWidth(0.020)
        context.addPath(sail)
        context.strokePath()

        context.setLineWidth(0.015)
        context.move(to: CGPoint(x: 0.12, y: 0.58))
        context.addLine(to: CGPoint(x: 0.12, y: 0.02))
        context.strokePath()

        context.restoreGState()
    }

    // MARK: - Helpers

    private func blend(_ a: SimColor, with b: SimColor, t: Double) -> SimColor {
        a.lerp(to: b, t: t)
    }

    private func cgColor(_ c: SimColor) -> CGColor {
        CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}
