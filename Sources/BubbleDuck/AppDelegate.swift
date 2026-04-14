// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — AppDelegate to manage the dock tile controller lifecycle

import AppKit
import SwiftUI
import BubbleCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let configStore = ConfigStore()

    private var dockTileController: DockTileController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = DockTileController(config: configStore.config)
        dockTileController = controller

        configStore.setChangeHandler { [weak controller] newConfig in
            controller?.apply(newConfig)
        }

        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dockTileController?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Clicking the dock icon cycles overlays.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dockTileController?.cycleOverlay()
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let loadAvgItem = NSMenuItem(title: "Show Load Average",
                                      action: #selector(showLoadAverage), keyEquivalent: "")
        loadAvgItem.target = self
        menu.addItem(loadAvgItem)

        let memInfoItem = NSMenuItem(title: "Show Memory Info",
                                      action: #selector(showMemoryInfo), keyEquivalent: "")
        memInfoItem.target = self
        menu.addItem(memInfoItem)

        let hideItem = NSMenuItem(title: "Hide Overlay",
                                   action: #selector(hideOverlay), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings\u{2026}",
                                       action: #selector(openSettingsFromMenu), keyEquivalent: ",")
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
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(store: configStore)
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 620)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BubbleDuck Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
