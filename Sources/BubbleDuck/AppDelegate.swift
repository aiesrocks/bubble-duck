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
        // Keep running (dock tile keeps animating) even if window is closed
        return false
    }
}
