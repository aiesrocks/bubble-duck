// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — overlay state and history tracking, ported from wmbubble

import Foundation

/// Which overlay screen is currently displayed.
public enum OverlayScreen: Sendable, Equatable {
    case none
    case loadAverage   // wmbubble: hover without shift
    case memoryInfo    // wmbubble: hover with shift
}

/// Rolling history buffer for graph overlays.
/// wmbubble uses 55 samples (BOX_SIZE - 3); we use 55 scaled to our canvas.
public struct HistoryBuffer: Sendable {
    public let capacity: Int
    public private(set) var samples: [Double]

    public init(capacity: Int = 55) {
        self.capacity = capacity
        self.samples = []
    }

    public mutating func push(_ value: Double) {
        samples.append(value)
        if samples.count > capacity {
            samples.removeFirst()
        }
    }

    /// The maximum value in the buffer, used for auto-scaling.
    public var maxValue: Double {
        samples.max() ?? 0
    }
}

/// Tracks overlay visibility, history data, and load averages.
public struct OverlayState: Sendable {
    public var screen: OverlayScreen = .none
    public var locked: Bool = false  // wmbubble: right-click locks overlay

    /// Alpha for the overlay (0.0 = fully transparent, 1.0 = fully opaque).
    /// Animated smoothly on show/hide.
    public var overlayAlpha: Double = 0.0

    /// Alpha for the CPU gauge (always partially visible).
    /// wmbubble: 0.26 when idle, 0.69 on hover.
    public var gaugeAlpha: Double = 0.26

    /// Load averages: 1, 5, 15 minutes
    public var loadAverage1: Double = 0.0
    public var loadAverage5: Double = 0.0
    public var loadAverage15: Double = 0.0

    /// Memory info (absolute values for display)
    public var memoryUsedBytes: UInt64 = 0
    public var memoryTotalBytes: UInt64 = 0
    public var swapUsedBytes: UInt64 = 0
    public var swapTotalBytes: UInt64 = 0

    /// Rolling history for graphs
    public var cpuHistory: HistoryBuffer = HistoryBuffer()
    public var loadHistory: HistoryBuffer = HistoryBuffer()
    public var memoryHistory: HistoryBuffer = HistoryBuffer()

    /// Current CPU percentage (0...100) for the gauge
    public var cpuPercent: Int = 0

    public init() {}

    /// Animate alpha values toward their targets.
    public mutating func stepAlpha() {
        let showOverlay = screen != .none
        let targetOverlay: Double = showOverlay ? 0.84 : 0.0  // wmbubble: 216/256
        let targetGauge: Double = showOverlay ? 0.69 : 0.26   // wmbubble: brighter on hover

        // Smooth fade (~0.3s at 60fps)
        let fadeSpeed = 0.06
        overlayAlpha += (targetOverlay - overlayAlpha) * fadeSpeed
        gaugeAlpha += (targetGauge - gaugeAlpha) * fadeSpeed

        // Snap when close enough
        if abs(overlayAlpha - targetOverlay) < 0.01 { overlayAlpha = targetOverlay }
        if abs(gaugeAlpha - targetGauge) < 0.01 { gaugeAlpha = targetGauge }
    }

    /// Record a history sample (called ~once per second like wmbubble).
    public mutating func recordHistory(cpuLoad: Double, memoryUsage: Double) {
        cpuHistory.push(cpuLoad * 100.0)          // CPU % for the bar graph
        loadHistory.push(loadAverage1)
        memoryHistory.push(memoryUsage * 100.0)
        cpuPercent = Int(cpuLoad * 100)
    }
}
