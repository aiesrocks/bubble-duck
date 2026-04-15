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
| Water level | Memory usage | `(active + wired + compressor_occupied) / physical_RAM`. Excludes page/file cache (inactive, purgeable, file-backed pages) — only counts non-freeable memory |
| Water color | Memory tightness | `(active + wired + compressed + swap_used) / physical_RAM`. NOT raw swap usage — macOS swap is a lifetime metric that never clears until reboot, making raw swap a poor real-time signal. Tightness > 1.0 means paging is actively happening |
| Bubbles | CPU load | Spawn probability = CPU%. Rolling 16-sample average |
| Agent speed | Configurable | Network I/O, Disk IOPS, or GPU utilization (user picks in Settings) |
| Rain | Disk IOPS | Starts at 500 IOPS, saturates at 5000. Toggleable in Settings |
| Sky color | Time of day | 4 anchors: dawn/noon/dusk/night, smooth blending |

## Important: Memory Metrics on macOS

- `compressor_page_count` = pages **occupied by** the compressor (actual RAM footprint)
- `Pages stored in compressor` (from `vm_stat` CLI) = uncompressed size of compressed data — much larger, do NOT use for "used memory"
- These are different fields in `vm_statistics64`. The app uses `compressor_page_count` which is the physical RAM consumed
