# BubbleDuck

A macOS Dock tile system monitor inspired by [wmbubble](https://github.com/rnjacobs/wmbubble).
License: GPL-2.0-or-later (matching wmbubble).

## Architecture

Two-layer design for CLI/Web portability:

- **BubbleCore** (`Sources/BubbleCore/`) — Pure Swift, cross-platform simulation logic. Testable on Linux.
  - `WaterSimulation.swift` — Spring-model water columns (from wmbubble's `do_water_sim`)
  - `Bubble.swift` — Bubble creation/physics tied to CPU load
  - `SimulationState.swift` — Combined state + duck
  - `ColorTheme.swift` — Color interpolation by swap usage

- **BubbleDuck** (`Sources/BubbleDuck/`) — macOS-only AppKit/SwiftUI app layer.
  - `SystemMetrics.swift` — CPU/memory/swap via Mach APIs
  - `BubbleRenderer.swift` — Core Graphics rendering to NSImage
  - `DockTileController.swift` — Animation loop updating the Dock tile
  - `BubbleDuckApp.swift` / `AppDelegate.swift` — App entry point

## Build & Test

```bash
swift build          # Build (macOS only for BubbleDuck target)
swift test           # Run BubbleCore tests (works on Linux too)
swift run BubbleDuck # Launch the dock tile app
```

## Design Decisions

- Canvas size: 256x256 (scaled up from wmbubble's 58x58 for Retina)
- Dock tile: Uses NSApplication.shared.dockTile with animated NSImageView
- Physics ported from wmbubble C code with same default parameters
- Metrics: Mach host_statistics (CPU), vm_statistics64 (memory), sysctl vm.swapusage (swap)
