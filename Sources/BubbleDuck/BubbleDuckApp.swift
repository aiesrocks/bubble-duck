// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — A macOS Dock system monitor inspired by wmbubble

import SwiftUI

@main
struct BubbleDuckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Minimal window — the real UI is the dock tile
        Window("BubbleDuck", id: "main") {
            ContentView()
        }
        .defaultSize(width: 300, height: 300)
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "drop.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("BubbleDuck")
                .font(.title)
            Text("System monitor running in your Dock")
                .foregroundStyle(.secondary)
            Text("CPU → bubbles · Memory → water level · Swap → color")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
    }
}
