# BubbleDuck

A macOS Dock tile system monitor inspired by [wmbubble](https://github.com/rnjacobs/wmbubble).
License: GPL-2.0-or-later (matching wmbubble).

## Architecture

Two-layer design for CLI/Web portability:

- **BubbleCore** (`Sources/BubbleCore/`) — Pure Swift, cross-platform simulation logic. Testable on Linux.
  - `WaterSimulation.swift` — Water columns with ripple physics; baseline pinned to memory usage
  - `Bubble.swift` — Bubble creation/physics tied to CPU load
  - `SimulationState.swift` — Combined state: water, bubbles, duck, overlays, rain, ripples
  - `ColorTheme.swift` — Sky color (time-of-day), water color (memory tightness)
  - `FloatingAgent.swift` — Agent types (rubber duck, penguin, otter, etc.)
  - `OverlayState.swift` — Load average / memory info overlay state + history
  - `SimulationConfig.swift` — All user-configurable knobs (persisted via JSON)
  - `MemoryPressure.swift` — Tightness calculation and pressure zones
  - `Raindrop.swift`, `RippleRing.swift`, `BlinkState.swift` — Visual effects

- **BubbleDuck** (`Sources/BubbleDuck/`) — macOS-only AppKit/SwiftUI app layer.
  - `SystemMetrics.swift` — CPU/memory/swap/network/disk/GPU via Mach/IOKit APIs
  - `BubbleRenderer.swift` — Core Graphics rendering to NSImage (all agents)
  - `DockTileController.swift` — Animation loop updating the Dock tile
  - `BubbleDuckApp.swift` / `AppDelegate.swift` — App entry point
  - `SettingsView.swift` — SwiftUI settings panel (hosted in AppKit NSWindow)
  - `ConfigStore.swift` — Observable config store backed by UserDefaults
  - `GIFRecorder.swift` — Record dock tile animation to GIF

- **BubbleWidget** (`Sources/BubbleWidget/`) — WidgetKit extension foundation (planned).

## Build & Test

```bash
swift build                    # Build (macOS only for BubbleDuck target)
swift test                     # Run BubbleCore tests (works on Linux too)
./scripts/build-app.sh         # Build .app bundle
./scripts/package-release.sh   # Build release + zip for distribution
open .build/BubbleDuck.app     # Launch
```

## Design Decisions

- Canvas size: 256x256 (scaled up from wmbubble's 58x58 for Retina)
- Dock tile: Uses NSApplication.shared.dockTile with animated NSImageView
- Physics ported from wmbubble C code with same default parameters
- Settings window uses AppKit NSWindow + NSHostingView (SwiftUI Settings scene was unreliable)
- Metrics: Mach host_statistics (CPU), vm_statistics64 (memory), sysctl (swap/network), IOKit (disk/GPU)

## Metric Mappings

| Visual | Metric | Notes |
|---|---|---|
| Water level | Memory usage *(default)* or Claude 5-hour usage | Memory: `(active + wired + compressor_occupied) / physical_RAM`. Excludes page/file cache (inactive, purgeable, file-backed pages) — only counts non-freeable memory. Source is user-selectable in Settings |
| Water color | Memory tightness *(default)* or Claude weekly usage | Memory: `(active + wired + compressed + swap_used) / physical_RAM`. NOT raw swap usage — macOS swap is a lifetime metric that never clears until reboot, making raw swap a poor real-time signal. Tightness > 1.0 means paging is actively happening. Claude weekly: five discrete bands at configurable edges (default 25/50/75/90%) |
| Tile readout (one always-on text line, wmbubble's CPU digit slot) | CPU % *(default)*, memory %, Claude 5h usage / countdown / both, Claude weekly % — or off | Single element, never stacked: picking a Claude source replaces the CPU digits. Color, opacity, size, position, backdrop pill, contrast outline, idle-dim, and "hide Claude sources under band 1" configurable (`TileReadoutConfig`) |
| Bubbles | CPU load *(default)*, or any other `MetricSource` | Spawn probability = the chosen metric, normalized 0…1 (`MetricSource`). CPU uses a rolling 16-sample average; Claude sources fall back to CPU when there's no usable reading |
| Agent speed | Configurable | Network I/O, Disk IOPS, or GPU utilization (user picks in Settings) |
| Rain | Disk IOPS *(default)*, or any other `MetricSource` | Quiet below 10% of the chosen metric, ramping to full — with disk IOPS that's the original 500→5000 range. Toggleable in Settings |
| Sky color | Time of day | 4 anchors: dawn/noon/dusk/night, smooth blending |

## Claude Usage Integration

BubbleDuck can drive the water level/color from Claude Code subscription limits.

**Where the data comes from:** Claude Code passes `rate_limits` (`five_hour` /
`seven_day`, each with `used_percentage` + `resets_at`) to its status-line
command on stdin. `scripts/bubbleduck-statusline.sh` wraps the user's real
status-line command, tees that block to `~/.claude/bubbleduck-usage.json`, and
passes stdin through untouched. The app polls that file (never more often than
once a minute — `ClaudeUsageConfig.minimumRefreshSeconds`).

**No credentials are involved.** Claude Code owns the OAuth token and the
`/api/oauth/usage` fetch. Do not add code that reads `~/.claude/.credentials.json`
or the Keychain — that path was investigated and rejected (token is stale on
disk, refresh sits behind bot protection, rotation risks logging the user out).

**Known limits, which the UI must not paper over:**
- Only *interactive* Claude Code sessions emit `rate_limits`; headless `claude -p`
  never does. With no session running, percentages freeze.
- `resets_at` is absolute, so countdowns stay correct while percentages go stale.
  Past `resets_at`, `ClaudeUsageWindow.percentage` returns 0 — the window rolled over.
- Stale readings dim the countdown and (by default) fall back to system metrics.
- There is no historical usage series from Anthropic. `OverlayState.claudeFiveHourHistory`
  is BubbleDuck's own recording, one sample per refresh, reset on relaunch.

## Important: Memory Metrics on macOS

- `compressor_page_count` = pages **occupied by** the compressor (actual RAM footprint)
- `Pages stored in compressor` (from `vm_stat` CLI) = uncompressed size of compressed data — much larger, do NOT use for "used memory"
- These are different fields in `vm_statistics64`. The app uses `compressor_page_count` which is the physical RAM consumed
