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

    /// Push a new configuration into the running simulation.
    func apply(_ config: SimulationConfig) {
        simulation.apply(config)
    }

    /// Set a specific overlay screen.
    func setOverlay(_ screen: OverlayScreen) {
        simulation.overlay.screen = screen
        simulation.overlay.locked = screen != .none
    }

    /// Cycle through overlay screens: none → loadAverage → memoryInfo → none.
    /// wmbubble uses hover/shift; we use dock icon click since macOS dock
    /// doesn't support hover detection.
    func cycleOverlay() {
        if simulation.overlay.locked {
            simulation.overlay.locked = false
            simulation.overlay.screen = .none
        } else {
            switch simulation.overlay.screen {
            case .none:
                simulation.overlay.screen = .loadAverage
                simulation.overlay.locked = true
            case .loadAverage:
                simulation.overlay.screen = .memoryInfo
                simulation.overlay.locked = true
            case .memoryInfo:
                simulation.overlay.screen = .none
                simulation.overlay.locked = false
            }
        }
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

        // Feed overlay data
        simulation.overlay.loadAverage1 = snapshot.loadAverage1
        simulation.overlay.loadAverage5 = snapshot.loadAverage5
        simulation.overlay.loadAverage15 = snapshot.loadAverage15
        simulation.overlay.memoryUsedBytes = snapshot.memoryUsedBytes
        simulation.overlay.memoryTotalBytes = snapshot.memoryTotalBytes
        simulation.overlay.swapUsedBytes = snapshot.swapUsedBytes
        simulation.overlay.swapTotalBytes = snapshot.swapTotalBytes

        // Record history sample (~1/sec like wmbubble)
        simulation.overlay.recordHistory(
            cpuLoad: snapshot.cpuLoad,
            memoryUsage: snapshot.memoryUsage
        )

        // Drive floating agent speed from the configured metric
        let speedFactor: Double
        switch simulation.config.speedMetric {
        case .networkIO:
            // Normalize: 0 bytes/sec = 0, ~10 MB/sec+ = 1.0
            speedFactor = min(1.0, snapshot.networkBytesPerSec / 10_000_000)
        case .diskIOPS:
            // Normalize: 0 IOPS = 0, ~5000+ IOPS = 1.0
            speedFactor = min(1.0, snapshot.diskIOPS / 5000)
        case .gpuUtilization:
            // Already 0.0...1.0
            speedFactor = snapshot.gpuUtilization
        }
        simulation.duck.speedFactor = speedFactor
    }
}
