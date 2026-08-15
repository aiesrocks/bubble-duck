// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — reads Claude Code usage handed over by the status-line wrapper

import Foundation
import os
import BubbleCore

/// Diagnostics for "why is the tile showing that?". Read with:
/// `log show --predicate 'subsystem == "com.bubbleduck.app"' --last 10m`
private let usageLog = Logger(subsystem: "com.bubbleduck.app", category: "usage")

/// Polls the small JSON file that `scripts/bubbleduck-statusline.sh` writes
/// from Claude Code's status-line payload.
///
/// Nothing here talks to Anthropic: Claude Code owns the OAuth token and the
/// usage fetch, and passes `rate_limits` to whatever status-line command the
/// user configured. We read the leftovers. That means the numbers are only as
/// fresh as the last *interactive* Claude Code render — hence the staleness
/// handling in `SimulationState.usableClaudeUsage(now:)`.
final class ClaudeUsageReader {
    /// Latest successfully parsed reading, or nil if the file is missing,
    /// malformed, or has never contained a `rate_limits` block.
    private(set) var snapshot: ClaudeUsageSnapshot?

    /// Reason the last read produced nothing, for the Settings panel.
    private(set) var lastError: String?

    /// When `refresh` last actually hit the disk.
    private(set) var lastReadAt: Date?

    /// How often to look for a new window while the held one has rolled over.
    static let rolloverPollSeconds: TimeInterval = 5

    private var expandedPath: String = ""
    private var lastModified: Date?

    /// Re-read the file if `interval` seconds have passed since the last read.
    /// Returns the new snapshot when the file changed, nil otherwise — the
    /// caller uses a non-nil return to record a history sample.
    @discardableResult
    func refresh(path: String, interval: TimeInterval, now: Date = Date()) -> ClaudeUsageSnapshot? {
        // While the window we're holding has already rolled over, the tile is
        // showing "--:--" and 0% — check far more often so the new window
        // lands as soon as Claude Code writes it. This isn't extra parsing:
        // the mtime guard below still skips an unchanged file, so it's one
        // `stat` every few seconds until the gap closes.
        let rolledOver = snapshot?.fiveHour?.hasRolledOver(now: now) ?? false
        let effectiveInterval = rolledOver
            ? min(interval, ClaudeUsageReader.rolloverPollSeconds)
            : interval
        if let last = lastReadAt, now.timeIntervalSince(last) < effectiveInterval { return nil }
        lastReadAt = now

        let expanded = (path as NSString).expandingTildeInPath
        if expanded != expandedPath {
            // Path changed in Settings — drop cached state so the new file is
            // read immediately rather than skipped as "unmodified".
            expandedPath = expanded
            lastModified = nil
            snapshot = nil
        }

        let url = URL(fileURLWithPath: expanded)
        guard FileManager.default.fileExists(atPath: expanded) else {
            lastError = "No usage file at \(expanded)"
            snapshot = nil
            return nil
        }

        // Skip parsing when the file hasn't been rewritten since last read.
        let modified = (try? FileManager.default.attributesOfItem(atPath: expanded)[.modificationDate]) as? Date
        if let modified, let lastModified, modified <= lastModified {
            lastError = nil
            return nil
        }
        lastModified = modified

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(ClaudeUsageSnapshot.self, from: data)
            guard decoded.fiveHour != nil || decoded.sevenDay != nil else {
                lastError = "Usage file has no rate_limits yet"
                snapshot = nil
                return nil
            }
            lastError = nil
            snapshot = decoded
            // One line per actual parse (at most once a minute) so a wrong
            // tile can be diagnosed from `log show --predicate
            // 'process == "BubbleDuck"'` without guessing.
            if let five = decoded.fiveHour {
                // Explicitly public — the unified log redacts interpolated
                // values by default, which makes the line useless here.
                let summary = String(
                    format: "5h %.0f%% resets in %.0f min%@, written %.0fs ago",
                    five.usedPercentage, five.timeUntilReset(now: now) / 60,
                    five.hasRolledOver(now: now) ? " (ROLLED OVER)" : "",
                    decoded.age(now: now)
                )
                usageLog.info("usage read — \(summary, privacy: .public)")
            }
            return decoded
        } catch {
            lastError = "Unreadable usage file: \(error.localizedDescription)"
            snapshot = nil
            return nil
        }
    }

    /// Force the next `refresh` to hit the disk regardless of the interval.
    func invalidate() {
        lastReadAt = nil
        lastModified = nil
    }
}
