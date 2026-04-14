// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — drives the animated dock tile

import AppKit
import BubbleCore

/// Manages the simulation loop and updates the macOS dock tile with each frame.
@MainActor
final class DockTileController {
    private var simulation: SimulationState
    private let renderer: BubbleRenderer
    private let metrics: SystemMetrics
    private var displayLink: CVDisplayLink?
    private var timer: Timer?

    /// Target frame interval in seconds (~60fps like wmbubble's 15ms delay)
    private let frameInterval: TimeInterval = 1.0 / 60.0
    /// How often to poll system metrics (every ~1 second)
    private let metricsInterval: TimeInterval = 1.0

    init() {
        simulation = SimulationState(canvasSize: 256)
        renderer = BubbleRenderer(size: 256)
        metrics = SystemMetrics()
    }

    func start() {
        // Start simulation timer
        timer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)

        // Start metrics polling on a background queue
        startMetricsPolling()

        // Initial metrics read
        updateMetrics()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        simulation.step()
        let image = renderer.render(state: simulation)
        updateDockTile(with: image)
    }

    private func updateDockTile(with image: NSImage) {
        let dockTile = NSApplication.shared.dockTile
        let imageView = NSImageView(image: image)
        dockTile.contentView = imageView
        dockTile.display()
    }

    private func startMetricsPolling() {
        Timer.scheduledTimer(withTimeInterval: metricsInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }
    }

    private func updateMetrics() {
        let snapshot = metrics.read()
        simulation.cpuLoad = snapshot.cpuLoad
        simulation.memoryUsage = snapshot.memoryUsage
        simulation.swapUsage = snapshot.swapUsage
    }
}
