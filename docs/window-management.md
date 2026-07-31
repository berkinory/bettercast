# Window management

Window management is an optional command category. It is disabled by default so the launcher stays
unchanged until the user enables it in Settings → Window Management.

## Ownership and dispatch

`AppCore` owns the `WindowMover` and is the only dispatch path for palette activation and global
shortcuts. `WindowCommandCatalog` is the source of truth for names, symbols, groups, shortcut IDs,
and launcher entries. `VisibilityStore` controls each command's launcher visibility.

The command palette records the previous application before it hides. A command targets that app when
invoked from the palette, or the current frontmost application when invoked by a global shortcut.
Window management stays disabled at dispatch time even when a previously configured shortcut remains
registered.

## Geometry

`WindowLayout` and `WindowActionMemory` are Foundation + CoreGraphics-only and pure. The standalone
`Tools/window-command-test.swift` harness compiles those files directly and covers tiling, sizing,
restore, cycling, display moves, gaps, and off-screen displays.

`WindowMover` is the AppKit / Accessibility boundary. It reads and writes `AXUIElement` window frames,
uses a one-second messaging timeout, performs at most one correction when an app rejects a requested
minimum size, and never partially applies a placement. Frames are converted through the primary display
anchor between Cocoa and Accessibility coordinates; this remains correct with mixed-size displays.

Restore and repeat-cycling use a bounded LRU keyed by process ID and AX window identity. The mover
observes app termination and drops records for dead processes. A user move breaks the cycle while
preserving the restore frame.

## Margins

When enabled, Opencast reads macOS's `com.apple.WindowManager` preferences at command time:

- `EnableTiledWindowMargins` controls whether a gap is used.
- `TiledWindowSpacing` supplies the gap, with an 8-point fallback when macOS has not persisted it.

The value is clamped to 64 points. Opencast never writes Apple's preferences. The Settings toggle can
disable this integration and use zero gap, so the command behavior remains explicit and reversible.

## Settings and permission

Settings uses the existing Settings pane, cards, feature icons, shortcut recorder, and visibility
controls. No new window or shell is introduced. Accessibility is requested only when a command is
invoked, using the existing permission path.
