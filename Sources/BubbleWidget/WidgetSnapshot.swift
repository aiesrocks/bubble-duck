// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — widget-side snapshot of system state
// Pure data; no platform framework imports here so it's testable without
// WidgetKit / SwiftUI.

import Foundation
import BubbleCore

/// A dated snapshot of system metrics the widget's view renders from.
/// Shaped as a value type with fixed fields so tests can construct
/// instances and assert exact equality.
public struct WidgetSnapshot: Sendable, Equatable {
    /// When this snapshot was captured. TimelineEntry uses this to schedule
    /// widget redraws.
    public let date: Date
    public let cpuLoad: Double          // 0...1
    public let memoryUsage: Double      // 0...1
    public let swapUsage: Double        // 0...1
    public let loadAverage1: Double     // raw load avg
    public let memoryTightness: Double  // aiesrocks/bubble-duck#22
    public let memoryPressureZone: MemoryPressure.Zone

    public init(
        date: Date,
        cpuLoad: Double,
        memoryUsage: Double,
        swapUsage: Double,
        loadAverage1: Double,
        memoryTightness: Double,
        memoryPressureZone: MemoryPressure.Zone
    ) {
        self.date = date
        self.cpuLoad = cpuLoad
        self.memoryUsage = memoryUsage
        self.swapUsage = swapUsage
        self.loadAverage1 = loadAverage1
        self.memoryTightness = memoryTightness
        self.memoryPressureZone = memoryPressureZone
    }

    /// Fixed-date placeholder for previews and timeline placeholders.
    /// Equality is deterministic across instances (same date).
    public static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            date: Date(timeIntervalSince1970: 0),
            cpuLoad: 0.30,
            memoryUsage: 0.55,
            swapUsage: 0.10,
            loadAverage1: 1.20,
            memoryTightness: 0.45,
            memoryPressureZone: .healthy
        )
    }
}
