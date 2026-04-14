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

    /// Clicking the dock icon cycles through overlay screens:
    /// none → load average → memory info → none.
    /// wmbubble uses hover; we use click since macOS dock has no hover API.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dockTileController?.cycleOverlay()
        return false  // don't open any window on click
    }

    /// Right-click dock menu with overlay toggles and settings.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let loadAvgItem = NSMenuItem(
            title: "Show Load Average",
            action: #selector(showLoadAverage),
            keyEquivalent: ""
        )
        loadAvgItem.target = self
        menu.addItem(loadAvgItem)

        let memInfoItem = NSMenuItem(
            title: "Show Memory Info",
            action: #selector(showMemoryInfo),
            keyEquivalent: ""
        )
        memInfoItem.target = self
        menu.addItem(memInfoItem)

        let hideOverlayItem = NSMenuItem(
            title: "Hide Overlay",
            action: #selector(hideOverlay),
            keyEquivalent: ""
        )
        hideOverlayItem.target = self
        menu.addItem(hideOverlayItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        return menu
    }

    // MARK: - Private

    @objc private func showLoadAverage() {
        dockTileController?.setOverlay(.loadAverage)
    }

    @objc private func showMemoryInfo() {
        dockTileController?.setOverlay(.memoryInfo)
    }

    @objc private func hideOverlay() {
        dockTileController?.setOverlay(.none)
    }

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
