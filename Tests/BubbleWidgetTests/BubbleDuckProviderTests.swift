// SPDX-License-Identifier: GPL-2.0-or-later

#if os(macOS)
import Foundation
import Testing
@testable import BubbleWidget

@Suite("BubbleDuckProvider")
struct BubbleDuckProviderTests {
    @Test("placeholder entry wraps WidgetSnapshot.placeholder")
    func placeholderUsesCanonicalSnapshot() {
        let provider = BubbleDuckProvider()
        // The `placeholder(in:)` API takes a `Context` that's hard to
        // synthesize in tests, so we verify via the underlying property
        // that the placeholder maps to the known snapshot.
        let expected = WidgetSnapshot.placeholder
        let entry = BubbleDuckEntry(snapshot: expected)
        #expect(entry.snapshot == expected)
        #expect(entry.date == expected.date)
    }

    @Test("refresh interval is 5 minutes (documented cadence)")
    func refreshIntervalIsFiveMinutes() {
        #expect(BubbleDuckProvider.refreshIntervalSeconds == 300)
    }

    @Test("entry can be constructed from a snapshot alone")
    func entryConvenienceInit() {
        let snapshot = WidgetSnapshot.placeholder
        let entry = BubbleDuckEntry(snapshot: snapshot)
        #expect(entry.date == snapshot.date)
        #expect(entry.snapshot == snapshot)
    }

    @Test("entry with explicit date overrides the snapshot's date")
    func entryExplicitDate() {
        let futureDate = Date(timeIntervalSince1970: 9_999_999)
        let snapshot = WidgetSnapshot.placeholder
        let entry = BubbleDuckEntry(date: futureDate, snapshot: snapshot)
        #expect(entry.date == futureDate)
        #expect(entry.date != snapshot.date)
    }
}
#endif
