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
}

/// Which system metric drives the floating agent's speed.
public enum SpeedMetric: String, Sendable, Equatable, Codable, CaseIterable {
    case networkIO = "Network I/O"
    case diskIOPS = "Disk IOPS"
    case gpuUtilization = "GPU Utilization"
}
