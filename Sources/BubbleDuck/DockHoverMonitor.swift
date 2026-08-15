// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — detects the cursor entering our Dock tile

import AppKit
import ApplicationServices

/// Watches for the mouse entering BubbleDuck's Dock tile and reports the
/// crossing, so the agent can react to being hovered.
///
/// macOS gives a Dock tile no hover events of its own — the Dock is a
/// separate process and `NSApplication.dockTile` has no tracking API. The
/// only reliable way to know where our tile sits on screen is to read the
/// Dock's own accessibility tree, which needs the user to grant Accessibility
/// permission. That is why this is opt-in and off by default: it is a real
/// privacy trade for a cosmetic reaction, and the user should make it
/// knowingly.
///
/// Everything degrades quietly. No permission, no Dock element, or a tile
/// that can't be found means `isEnabled` stays false and nothing polls.
@MainActor
final class DockHoverMonitor {
    /// Called when the cursor crosses into the tile (not continuously while
    /// it sits there).
    var onEnter: (() -> Void)?

    private(set) var isRunning = false
    private(set) var lastError: String?

    /// Tile rect in Cocoa screen coordinates, or nil until resolved.
    private var tileRect: CGRect?
    private var pollTimer: Timer?
    private var rectResolvedAt: Date?
    private var cursorWasInside = false

    /// Cursor position is sampled rather than event-driven: a global mouse
    /// monitor wakes on every movement anywhere on screen, which is far more
    /// work than checking one point a few times a second.
    private let pollInterval: TimeInterval = 0.15

    /// The Dock rearranges as apps launch and quit, so the tile rect is
    /// re-resolved periodically rather than cached forever.
    private let rectTTL: TimeInterval = 20

    /// True when the process already holds Accessibility permission.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Ask for Accessibility permission, showing the system prompt that
    /// deep-links to System Settings. Returns the current state; granting is
    /// asynchronous and out of our hands, so callers should re-check later.
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func start() {
        guard !isRunning else { return }
        guard DockHoverMonitor.hasAccessibilityPermission else {
            lastError = "Accessibility permission not granted"
            return
        }
        isRunning = true
        lastError = nil
        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        isRunning = false
        cursorWasInside = false
        tileRect = nil
        rectResolvedAt = nil
    }

    // MARK: - Polling

    private func poll() {
        let now = Date()
        if tileRect == nil || (rectResolvedAt.map { now.timeIntervalSince($0) > rectTTL } ?? true) {
            tileRect = resolveTileRect()
            rectResolvedAt = now
        }
        guard let rect = tileRect else { return }

        let inside = rect.contains(NSEvent.mouseLocation)
        if inside && !cursorWasInside { onEnter?() }
        cursorWasInside = inside
    }

    // MARK: - Finding our tile in the Dock

    /// Walks the Dock's accessibility tree for the tile whose title matches
    /// this app, and converts its rect into Cocoa screen coordinates.
    private func resolveTileRect() -> CGRect? {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            lastError = "Dock not running"
            return nil
        }

        let appName = ProcessInfo.processInfo.processName
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)

        guard let list = firstChildList(of: dockElement) else {
            lastError = "Could not read the Dock's item list"
            return nil
        }

        for item in children(of: list) {
            guard let title = stringAttribute(item, kAXTitleAttribute), title == appName else { continue }
            guard let position = pointAttribute(item, kAXPositionAttribute),
                  let size = sizeAttribute(item, kAXSizeAttribute) else { continue }
            lastError = nil
            return cocoaRect(axOrigin: position, size: size)
        }

        lastError = "Tile for \"\(appName)\" not found in the Dock"
        return nil
    }

    private func firstChildList(of element: AXUIElement) -> AXUIElement? {
        children(of: element).first { child in
            stringAttribute(child, kAXRoleAttribute) == kAXListRole as String
        }
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    /// Accessibility reports a top-left origin measured from the primary
    /// display's top edge; `NSEvent.mouseLocation` is bottom-left from the
    /// primary display's bottom. Flip through the primary screen's height.
    private func cocoaRect(axOrigin: CGPoint, size: CGSize) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: axOrigin.x,
                      y: primaryHeight - axOrigin.y - size.height,
                      width: size.width,
                      height: size.height)
    }
}
