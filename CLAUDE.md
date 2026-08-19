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
| Tile readout (one always-on text line, wmbubble's CPU digit slot) | CPU % *(default)*, memory %, Claude 5h usage / countdown / both, Claude weekly % — or off | Single element, never stacked: picking a Claude source replaces the CPU digits. Color, opacity, size, position (top/center/bottom, or `.auto` which flips top↔bottom to stay clear of the floating agent — see `TileReadoutPlacement`), backdrop pill, contrast outline, idle-dim, and "hide Claude sources under band 1" configurable (`TileReadoutConfig`) |
| Bubbles | CPU load *(default)*, or any other `MetricSource` | Spawn probability = the chosen metric, normalized 0…1 (`MetricSource`). CPU uses a rolling 16-sample average; Claude sources fall back to CPU when there's no usable reading |
| Agent speed | Configurable | Network I/O, Disk IOPS, or GPU utilization (user picks in Settings) |
| Rain | Disk IOPS *(default)*, or any other `MetricSource` | Quiet below 10% of the chosen metric, ramping to full — with disk IOPS that's the original 500→5000 range. Toggleable in Settings |
| Sky color | Time of day | 4 anchors: dawn/noon/dusk/night, smooth blending |

## Poke Reactions (treats)

Clicking the Dock icon (or "Poke Agent", or hover when it's enabled) lobs the
agent something to eat. `Treat.swift` in BubbleCore owns the whole thing;
`BubbleRenderer` only draws it.

| Species | Treat | Behavior |
|---|---|---|
| Hippo | Watermelon slice | `.eaten` — arcs into the open mouth, which snaps shut, crumbs scatter |
| Mandarin duck | Food pellet | `.eaten` |
| Otter, penguin | Fish | `.eaten` |
| Turtle | Lettuce leaf | `.eaten` |
| Frog | Insect | `.tongue` — the insect hovers in front, then the tongue fires out and drags it back |
| Rubber duck, origami boat | Rock | `.splash` — neither has a mouth, so it lands in the water beside them and startles them |

Notes that matter when changing this:

- **Flight is timed against the mouth, not the clock.** `treatFlightTime` is
  the species' `mouthProfile.holdStart × duration` (floored at 0.5s), so the
  treat lands while the mouth is at full gape. A hippo's 3.6s gape gets a
  longer lob than a duck's 0.9s snap. Changing a `MouthProfile` moves the
  throw with it.
- **The arc re-solves every frame** against the current mouth position
  (`Treat.arcPosition`), which is why a treat still lands in the mouth of an
  agent that drifted mid-throw. There is deliberately no miss case.
- **`treatAnchor` mirrors renderer geometry.** Each anchor is that species'
  `agentScale × ` its mouth position in agent-local units, with the
  renderer's fixed `-0.1` vertical shift folded in. Move a mouth in
  `BubbleRenderer` and the anchor has to move too.
- **`.splash` drives `DuckState.startle`** — a hop under gravity plus a
  damped tilt spring, both applied in `beginAgent`. The impulse is a `max`,
  not a sum, so repeated poking can't pump the agent off the tile.
- One treat at a time; poking again mid-flight just re-triggers the mouth.
  Suppressed under Reduce Motion and `.lowest` power mode, but a treat
  already airborne when the mode flips still finishes.

The turtle is drawn as a **red-eared slider** — scute grid, head on a neck,
red ear stripe. Those three cues are what separate it from a green blob at
Dock size.

## Paddling

`DuckState.strokePhase` drives limb animation: the turtle's flippers, the
penguin's wings, the otter's paws. It's advanced inside `DuckState.step`, not
in the renderer, so it stops on its own under Reduce Motion and `.lowest`,
where the agent only calls `followWater`.

- `strokeRate` — 0.35 Hz at rest → 2.5 Hz at a pegged speed metric. The
  resting end is slow on purpose: the tile drops to 10fps when idle, which
  still gives a slow stroke ~28 frames per cycle. A fast stroke would step.
- `strokeIntensity` — swing amplitude 0…1, rising with the speed metric and
  falling to zero as `sleepiness` climbs, so a sleeping agent's limbs hang.
- Everything swings about its own joint via `withHinge`. Phase relationships
  are per species: the turtle's front and rear flippers are half a cycle apart
  so it rows; the penguin's two wings mirror each other, because it faces the
  viewer and one-up-one-down reads as falling over; the otter's paws work
  against each other, which reads as fussing rather than swimming.

Cost, measured on an M-series Mac: a full tile frame is ~0.53 ms (sim ~0.015
ms); the flapping adds two `sin()` calls (~5 ns) and two CTM rotations. The
tile costs ~0.5% of one core at 10fps idle and ~3.2% at 60fps. Animation on
something already drawn every frame is free — only raising the frame rate
costs anything.

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
