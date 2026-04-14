// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — AppDelegate to manage the dock tile controller lifecycle

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dockTileController: DockTileController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        dockTileController = DockTileController()
        dockTileController?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dockTileController?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running (dock tile keeps animating) even if window is closed
        return false
    }
}
