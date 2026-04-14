// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — SwiftUI Canvas-based widget rendering.
//
// Intentionally minimal: widgets refresh every few minutes (at best) so
// there's no animation — we draw a single frozen representation of the
// current system state. The primitives match the main app's visual
// language (water rectangle, agent circle, air above) without sharing code
// with BubbleRenderer (which lives in the AppKit-only executable target).

#if canImport(SwiftUI) && canImport(WidgetKit) && os(macOS)
import SwiftUI
import WidgetKit
import BubbleCore

public struct BubbleDuckEntryView: View {
    public let entry: BubbleDuckEntry

    public init(entry: BubbleDuckEntry) {
        self.entry = entry
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Sky
                skyColor
                // Water rectangle from bottom up, height ∝ memoryUsage
                Rectangle()
                    .fill(waterColor)
                    .frame(width: w, height: max(0, h * entry.snapshot.memoryUsage))
                    .frame(maxHeight: .infinity, alignment: .bottom)

                // Agent — simple yellow blob on the water surface.
                // y offset: sit on the waterline (memoryUsage fraction from bottom).
                let agentSide = min(w, h) * 0.30
                Circle()
                    .fill(Color(red: 0.94, green: 0.82, blue: 0.00))
                    .frame(width: agentSide, height: agentSide)
                    .offset(y: h * (0.5 - entry.snapshot.memoryUsage))

                // Load average in the top-left corner
                VStack {
                    HStack {
                        Text(String(format: "%.2f", entry.snapshot.loadAverage1))
                            .font(.system(size: min(w, h) * 0.12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                    }
                    Spacer()
                }
                .padding(min(w, h) * 0.06)
            }
        }
    }

    /// Water color shifts with the memory-pressure zone (aiesrocks/bubble-duck#22),
    /// so the widget gives visible feedback when the Mac is under load.
    private var waterColor: Color {
        switch entry.snapshot.memoryPressureZone {
        case .healthy:  return Color(red: 0.19, green: 0.25, blue: 0.88)
        case .warning:  return Color(red: 0.72, green: 0.40, blue: 0.45)
        case .critical: return Color(red: 0.88, green: 0.25, blue: 0.19)
        }
    }

    /// Sky color takes a slight tint when swap is high — a softer signal
    /// than the water color, still readable at a glance.
    private var skyColor: Color {
        // Simple blend between calm blue and a dusky mauve
        let calm = SIMD3<Double>(0.12, 0.19, 0.75)
        let tinted = SIMD3<Double>(0.55, 0.25, 0.55)
        let t = min(1, max(0, entry.snapshot.swapUsage))
        let mixed = calm * (1 - t) + tinted * t
        return Color(red: mixed.x, green: mixed.y, blue: mixed.z)
    }
}
#endif
