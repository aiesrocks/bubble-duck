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

    /// Single reusable image view installed as the dock tile's content view.
    /// Recreating an NSImageView every frame was wasteful and could flicker;
    /// we just mutate its `.image` and call `dockTile.display()`.
    private let imageView = NSImageView()

    private var frameTimer: Timer?
    private var metricsTimer: Timer?

    /// Target frame interval in seconds (~60fps like wmbubble's 15ms delay)
    private let frameInterval: TimeInterval = 1.0 / 60.0
    /// How often to poll system metrics (every ~1 second)
    private let metricsInterval: TimeInterval = 1.0

    init(config: SimulationConfig = .default) {
        simulation = SimulationState(canvasSize: 256, config: config)
        renderer = BubbleRenderer(size: 256)
        metrics = SystemMetrics()

        imageView.imageScaling = .scaleProportionallyUpOrDown
        NSApplication.shared.dockTile.contentView = imageView
    }

    /// Push a new configuration into the running simulation. Takes effect on
    /// the next frame — bubbles, water levels, and duck position are preserved.
    func apply(_ config: SimulationConfig) {
        simulation.apply(config)
    }

    func start() {
        frameTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(frameTimer!, forMode: .common)

        metricsTimer = Timer.scheduledTimer(withTimeInterval: metricsInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }

        // Initial metrics read so the first frame isn't all zeros
        updateMetrics()
    }

    func stop() {
        frameTimer?.invalidate()
        frameTimer = nil
        metricsTimer?.invalidate()
        metricsTimer = nil
    }

    private func tick() {
        simulation.step()
        imageView.image = renderer.render(state: simulation)
        NSApplication.shared.dockTile.display()
    }

    private func updateMetrics() {
        let snapshot = metrics.read()
        simulation.cpuLoad = snapshot.cpuLoad
        simulation.memoryUsage = snapshot.memoryUsage
        simulation.swapUsage = snapshot.swapUsage
    }
}
