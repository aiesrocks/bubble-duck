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
        // Widget foundation (aiesrocks/bubble-duck#16). WidgetKit extensions
        // can't be produced by SPM alone — bundling as an .appex is an Xcode
        // project concern — so this target ships the provider / entry / view
        // types as a library. A future Xcode project will embed them into a
        // widget extension bundle. See docs/WIDGET.md for integration steps.
        // All WidgetKit-/SwiftUI-touching files are `#if canImport`-guarded
        // so the target compiles to an empty artifact on Linux.
        .target(
            name: "BubbleWidget",
            dependencies: ["BubbleCore"],
            path: "Sources/BubbleWidget"
        ),
        // Tests for simulation logic — runs on macOS and Linux
        .testTarget(
            name: "BubbleCoreTests",
            dependencies: ["BubbleCore"]
        ),
        // Tests for the widget-foundation types. All test suites are
        // `#if os(macOS)`-guarded so the target compiles to empty on Linux.
        .testTarget(
            name: "BubbleWidgetTests",
            dependencies: ["BubbleWidget", "BubbleCore"]
        ),
    ]
)
