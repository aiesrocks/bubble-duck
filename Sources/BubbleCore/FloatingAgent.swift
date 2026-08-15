// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — floating agent types and speed metric mapping

import Foundation

/// The type of character floating on the water surface.
public enum AgentType: String, Sendable, Equatable, Codable, CaseIterable {
    case rubberDuck = "Rubber Duck"
    case mandarinDuck = "Mandarin Duck"
    case otter = "Otter"
    case turtle = "Turtle"
    case frog = "Frog"
    case hippo = "Hippo"
    case origamiBoat = "Origami Boat"
    case penguin = "Penguin"
}

/// Which system metric drives the floating agent's speed.
public enum SpeedMetric: String, Sendable, Equatable, Codable, CaseIterable {
    case networkIO = "Network I/O"
    case diskIOPS = "Disk IOPS"
    case gpuUtilization = "GPU Utilization"
}

/// A metric that can drive a spawn rate — shared by bubbles and rain, which
/// were both hard-wired before (CPU load and disk IOPS respectively).
///
/// Disk appears twice on purpose: a few large sequential reads and a storm of
/// tiny ones produce very different IOPS for the same throughput, and either
/// can be the one you care about.
public enum MetricSource: String, Sendable, Equatable, Codable, CaseIterable {
    case cpuLoad = "CPU load"
    case claudeFiveHour = "Claude 5-hour usage"
    case claudeWeekly = "Claude weekly usage"
    case gpuUtilization = "GPU utilization"
    case networkIO = "Network I/O"
    case diskIOPS = "Disk IOPS"
    case diskThroughput = "Disk I/O (throughput)"
}

/// Previous name for `MetricSource`, kept so existing call sites and configs
/// keep working.
public typealias BubbleMetric = MetricSource
