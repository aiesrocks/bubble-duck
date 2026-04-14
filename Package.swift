// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-2.0-or-later

import PackageDescription

let package = Package(
    name: "BubbleDuck",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Core simulation logic — pure Swift, cross-platform, testable on Linux
        .target(
            name: "BubbleCore",
            path: "Sources/BubbleCore"
        ),
        // macOS app — AppKit/SwiftUI dock tile app
        .executableTarget(
            name: "BubbleDuck",
            dependencies: ["BubbleCore"],
            path: "Sources/BubbleDuck"
        ),
        // Tests for simulation logic — runs on macOS and Linux
        .testTarget(
            name: "BubbleCoreTests",
            dependencies: ["BubbleCore"]
        ),
    ]
)
