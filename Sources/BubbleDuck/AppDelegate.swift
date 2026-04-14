// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — AppDelegate to manage the dock tile controller lifecycle

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shared store so SwiftUI views can bind to it via @Bindable.
    let configStore = ConfigStore()

    private var dockTileController: DockTileController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = DockTileController(config: configStore.config)
        dockTileController = controller

        // Forward every config change from the UI into the running simulation.
        configStore.setChangeHandler { [weak controller] newConfig in
            controller?.apply(newConfig)
        }

        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dockTileController?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Dock tile keeps animating — keep running even when Settings is closed.
        return false
    }

    /// Clicking the dock icon (when no window is open) opens Settings.
    /// The system auto-activates the app on dock click, so we just need to
    /// surface the Settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openSettings() }
        return true
    }

    /// Right-click dock menu: "Settings…" shortcut into the SwiftUI Settings
    /// scene. The system appends "Quit" automatically.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        item.target = self
        menu.addItem(item)
        return menu
    }

    // MARK: - Private

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    private func openSettings() {
        // macOS 14+: SwiftUI's Settings scene installs a responder for
        // showSettingsWindow:. Going through sendAction lets us open it from
        // AppDelegate without needing the SwiftUI Environment.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
