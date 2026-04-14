// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — A macOS Dock system monitor inspired by wmbubble

import SwiftUI

@main
struct BubbleDuckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — the dock tile is the primary UI.
        // Settings window is managed directly by AppDelegate via NSWindow
        // to avoid SwiftUI Settings scene reliability issues.
        Settings {
            EmptyView()
        }
    }
}
