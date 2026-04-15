// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — WidgetKit TimelineEntry shell around a WidgetSnapshot.

#if canImport(WidgetKit)
import Foundation
import WidgetKit

/// The TimelineEntry the widget system reads to render a single frame.
/// Wraps a `WidgetSnapshot` so the pure data type stays reusable.
public struct BubbleDuckEntry: TimelineEntry {
    public let date: Date
    public let snapshot: WidgetSnapshot

    public init(date: Date, snapshot: WidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }

    public init(snapshot: WidgetSnapshot) {
        self.init(date: snapshot.date, snapshot: snapshot)
    }
}
#endif
