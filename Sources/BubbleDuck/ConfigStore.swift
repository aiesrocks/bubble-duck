// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — UserDefaults-backed store for SimulationConfig

import Foundation
import Observation
import BubbleCore

/// Observable, persistable wrapper around `SimulationConfig`.
///
/// Mutations to `config` (including nested mutations like
/// `store.config.maxBubbles = 42`) are automatically persisted to
/// UserDefaults and forwarded to a registered change handler so the
/// running simulation can react.
@MainActor
@Observable
final class ConfigStore {
    /// Current configuration. Mutating this (including its fields) persists
    /// and fires the change handler.
    var config: SimulationConfig {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private let storageKey: String

    // Not observed — it's plumbing, not state the UI should track.
    @ObservationIgnored
    private var changeHandler: ((SimulationConfig) -> Void)?

    init(defaults: UserDefaults = .standard, storageKey: String = "BubbleDuckConfig.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let cfg = try? JSONDecoder().decode(SimulationConfig.self, from: data) {
            self.config = cfg
        } else {
            self.config = .default
        }
    }

    /// Reset to factory defaults (clears persisted value too).
    func reset() {
        config = .default
    }

    /// Register a handler that fires whenever the config changes.
    /// Fires once immediately with the current value so callers can
    /// synchronize their initial state.
    func setChangeHandler(_ handler: @escaping (SimulationConfig) -> Void) {
        changeHandler = handler
        handler(config)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: storageKey)
        }
        changeHandler?(config)
    }
}
