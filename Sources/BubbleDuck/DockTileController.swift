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
    private var accessibilityObserver: NSObjectProtocol?
    private var lowPowerObserver: NSObjectProtocol?

    /// Active GIF recording, if any. Set by `startRecording`, cleared when
    /// the recorder reports completion (or when explicitly cancelled).
    private var gifRecorder: GIFRecorder?

    /// Reduced-motion frame interval (2fps) — honors the accessibility
    /// preference (aiesrocks/bubble-duck#15). At 2fps the water level still
    /// tracks RAM smoothly enough without being motion-sickness inducing.
    private let reducedMotionFrameInterval: TimeInterval = 0.5
    /// How often to poll system metrics (every ~1 second)
    private let metricsInterval: TimeInterval = 1.0

    /// Currently installed frame interval, tracked to avoid unnecessary
    /// timer reinstalls when the adaptive rate hasn't changed much.
    private var currentFrameInterval: TimeInterval = 1.0 / 60.0

    /// Smoothed activity level 0...1 used to drive adaptive frame rate in
    /// Auto mode. Computed from CPU load, rain intensity, and bubble fill.
    private var activityLevel: Double = 0.0

    /// Resolved power mode after considering system Low Power Mode.
    private var effectivePowerMode: PowerMode = .auto

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
        resolveEffectivePowerMode()
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
        // Pick up current Reduce Motion setting before scheduling the first
        // frame, and subscribe for live changes.
        simulation.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        resolveEffectivePowerMode()
        installFrameTimer()
        observeAccessibilityChanges()
        observeLowPowerMode()

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
        if let observer = accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            accessibilityObserver = nil
        }
        if let observer = lowPowerObserver {
            NotificationCenter.default.removeObserver(observer)
            lowPowerObserver = nil
        }
    }

    // MARK: - Frame rate

    /// Compute the desired frame interval based on the effective power mode
    /// and current activity level.
    private func desiredFrameInterval() -> TimeInterval {
        if simulation.reduceMotion { return reducedMotionFrameInterval }
        switch effectivePowerMode {
        case .smoothest:
            return 1.0 / 60.0
        case .auto:
            // Adaptive: 10fps at idle → 60fps at full activity.
            let fps = 10.0 + activityLevel * 50.0
            return 1.0 / fps
        case .low:
            return 1.0 / 15.0
        case .lowest:
            return 1.0 / 4.0
        }
    }

    /// Install (or reinstall) the frame timer. Called when the desired rate
    /// changes significantly (power mode switch, activity level shift,
    /// accessibility toggle).
    private func installFrameTimer() {
        frameTimer?.invalidate()
        let interval = desiredFrameInterval()
        currentFrameInterval = interval
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    /// Reinstall the frame timer only if the desired interval diverged from
    /// the currently installed one by more than 20%. Avoids churning the
    /// RunLoop on every metrics tick.
    private func updateFrameRateIfNeeded() {
        let desired = desiredFrameInterval()
        let ratio = desired / currentFrameInterval
        if ratio < 0.8 || ratio > 1.2 {
            installFrameTimer()
        }
    }

    // MARK: - Power mode

    /// Resolve the effective power mode from the user's config and the
    /// system's Low Power Mode state, then push it into the simulation and
    /// adjust the frame timer.
    private func resolveEffectivePowerMode() {
        let configured = simulation.config.powerMode
        let systemLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if systemLowPower {
            effectivePowerMode = .lowest
        } else {
            effectivePowerMode = configured
        }
        simulation.effectivePowerMode = effectivePowerMode
        updateFrameRateIfNeeded()
    }

    private func observeLowPowerMode() {
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resolveEffectivePowerMode()
            }
        }
    }

    // MARK: - Accessibility

    private func observeAccessibilityChanges() {
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.accessibilityOptionsChanged()
            }
        }
    }

    private func accessibilityOptionsChanged() {
        let newValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard newValue != simulation.reduceMotion else { return }
        simulation.reduceMotion = newValue
        // Reinstall the timer so the frame rate matches the new mode.
        installFrameTimer()
    }

    // MARK: - Tick

    private func tick() {
        simulation.step()
        let image = renderer.render(state: simulation)
        imageView.image = image
        NSApplication.shared.dockTile.display()

        // Feed the GIF recorder, if active. The recorder samples one frame
        // out of every N sim ticks (see GIFRecorder.sampleEvery), so this
        // is cheap on the non-sample frames and writes a single CGImage
        // through ImageIO on the sample frames.
        if let recorder = gifRecorder, recorder.tick(image: image) {
            gifRecorder = nil
        }
    }

    // MARK: - GIF recording

    /// True if a GIF recording is currently in progress.
    var isRecording: Bool { gifRecorder != nil }

    /// Start a fresh GIF recording for `duration` seconds. Completes by
    /// calling `onComplete` with the saved URL (reveals in Finder by default
    /// at the AppDelegate layer). No-op if a recording is already active.
    /// Returns `true` if recording started.
    @discardableResult
    func startRecording(duration: TimeInterval,
                        onComplete: @escaping (URL) -> Void) -> Bool {
        guard gifRecorder == nil else { return false }
        do {
            let recorder = try GIFRecorder(duration: duration)
            recorder.onComplete = onComplete
            gifRecorder = recorder
            return true
        } catch {
            NSLog("BubbleDuck: failed to start GIF recording: \(error)")
            return false
        }
    }

    /// Stop the active recording early, flushing whatever's been captured.
    func cancelRecording() {
        gifRecorder?.cancel()
        gifRecorder = nil
    }

    // MARK: - Metrics

    private func updateMetrics() {
        let snapshot = metrics.read()
        simulation.cpuLoad = snapshot.cpuLoad
        simulation.memoryUsage = snapshot.memoryUsage
        // Water color is driven by memory tightness (real-time pressure)
        // rather than raw swap usage, which is a lifetime metric on macOS
        // that never clears until reboot. Tightness = (active + wired +
        // compressed + swapUsed) / totalPhysical; values > 1.0 mean paging.
        // We clamp to 0...1 for the color lerp.
        simulation.swapUsage = min(1.0, snapshot.memoryTightness)
        // Day/night sky (#3) — pulled from the local clock once per tick.
        simulation.timeOfDay = TimeOfDay.fraction(from: Date())
        // Battery tint (#17) — nil for desktop Macs, forwarded to the renderer.
        simulation.batteryFraction = snapshot.batteryFraction

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

        // Rain intensity (aiesrocks/bubble-duck#10) — driven by disk IOPS,
        // independent of the agent speed metric. Quiet below 500 IOPS so
        // idle systems don't spontaneously rain; saturates at ~5000 IOPS.
        let rainFloor: Double = 500
        let rainCeiling: Double = 5000
        let excess = max(0, snapshot.diskIOPS - rainFloor)
        simulation.rainIntensity = simulation.config.rainEnabled
            ? min(1.0, excess / (rainCeiling - rainFloor))
            : 0

        // Update activity level for adaptive frame rate (Auto mode).
        // Smoothed so fps doesn't oscillate on every metrics tick.
        let bubbleRatio = Double(simulation.bubbleSystem.bubbles.count)
            / Double(max(1, simulation.config.maxBubbles))
        let rawActivity = max(snapshot.cpuLoad, simulation.rainIntensity, bubbleRatio)
        activityLevel += (rawActivity - activityLevel) * 0.3

        // Re-evaluate power mode (system Low Power may have changed) and
        // adjust the frame timer if the adaptive rate shifted.
        resolveEffectivePowerMode()
    }
}
