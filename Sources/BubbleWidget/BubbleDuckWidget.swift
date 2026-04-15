// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — Widget declaration, ready to drop into a WidgetKit extension target.
//
// ─── Integration (aiesrocks/bubble-duck#16) ─────────────────────────────
//
// SPM alone can't produce a runnable widget extension on macOS — that
// requires an Xcode project with a Widget Extension target (built as a
// `.appex` bundle and embedded inside the main BubbleDuck app bundle).
// This library ships the provider, entry, view, widget, and bundle types
// so the extension target can be a thin wrapper.
//
// Recommended Xcode integration:
//
//   1. Open (or generate) an Xcode project for BubbleDuck.
//   2. Add a new target → macOS → Widget Extension → "BubbleDuckWidgetExt".
//   3. Delete the Xcode-generated widget code files from that target.
//   4. Add this Swift package (or its `BubbleWidget` product) as a
//      dependency of the widget extension target.
//   5. Replace the extension's `@main` entry point with:
//
//         import WidgetKit
//         import BubbleWidget
//
//         @main
//         struct Main: WidgetBundle {
//             var body: some Widget {
//                 BubbleDuckWidget()
//             }
//         }
//
//      (or use `BubbleDuckWidgetBundle` directly).
//
//   6. Ensure the widget extension's Info.plist has:
//        NSExtensionPointIdentifier = com.apple.widgetkit-extension
//      This is the default for a Widget Extension target.
//
//   7. Embed the extension into the parent app (General → Frameworks,
//      Libraries, and Embedded Content → add the .appex with "Embed &
//      Sign" set).
//
// The widget refreshes every 5 minutes by default
// (see `BubbleDuckProvider.refreshIntervalSeconds`). The system may
// throttle further depending on budget.
// ────────────────────────────────────────────────────────────────────────

#if canImport(SwiftUI) && canImport(WidgetKit) && os(macOS)
import SwiftUI
import WidgetKit

public struct BubbleDuckWidget: Widget {
    public static let kind: String = "BubbleDuckWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: BubbleDuckProvider()) { entry in
            BubbleDuckEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .configurationDisplayName("BubbleDuck")
        .description("Your Mac's memory, swap, and load at a glance — with a duck.")
    }
}

/// Convenience bundle — wire this up from the extension target's @main entry.
public struct BubbleDuckWidgetBundle: WidgetBundle {
    public init() {}
    public var body: some Widget {
        BubbleDuckWidget()
    }
}
#endif
