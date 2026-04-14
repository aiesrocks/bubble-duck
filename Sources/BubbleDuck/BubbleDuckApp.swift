// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — A macOS Dock system monitor inspired by wmbubble

import SwiftUI

@main
struct BubbleDuckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Standard macOS Settings scene — opened via Cmd-, or by clicking
        // the dock icon (wired up in AppDelegate). The dock tile itself is
        // the app's primary UI, so there's no main Window scene.
        Settings {
            SettingsView(store: appDelegate.configStore)
        }
    }
}
