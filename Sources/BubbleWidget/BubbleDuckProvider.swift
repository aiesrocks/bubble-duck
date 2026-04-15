// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — TimelineProvider that feeds the widget with current metrics.

#if canImport(WidgetKit) && os(macOS)
import Foundation
import WidgetKit

public struct BubbleDuckProvider: TimelineProvider {
    public init() {}

    /// Returned while the widget is still loading its first real entry.
    /// Should render a reasonable placeholder.
    public func placeholder(in context: Context) -> BubbleDuckEntry {
        BubbleDuckEntry(snapshot: .placeholder)
    }

    /// Returned for widget gallery previews and the "add widget" sheet.
    /// No animation — single frozen frame.
    public func getSnapshot(in context: Context, completion: @escaping (BubbleDuckEntry) -> Void) {
        let snapshot = context.isPreview
            ? WidgetSnapshot.placeholder
            : WidgetMetrics().read()
        completion(BubbleDuckEntry(snapshot: snapshot))
    }

    /// Hands the system a single entry + a refresh policy. Widgets on macOS
    /// are limited in how often they refresh, so one entry every five
    /// minutes is a reasonable baseline.
    public func getTimeline(in context: Context, completion: @escaping (Timeline<BubbleDuckEntry>) -> Void) {
        let now = Date()
        let entry = BubbleDuckEntry(date: now, snapshot: WidgetMetrics().read())
        let nextRefresh = now.addingTimeInterval(BubbleDuckProvider.refreshIntervalSeconds)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    /// How frequently the widget asks for a new timeline. The OS may throttle
    /// actual refreshes; this is our requested cadence.
    public static let refreshIntervalSeconds: TimeInterval = 5 * 60
}
#endif
