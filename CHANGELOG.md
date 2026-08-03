# Changelog

## [0.1.0]

### Added

### Fixed

### Improved

### Removed

## [0.1.1]

### Added

- Snippet support with search, create, edit, and optional keyword expansion.
- Self-update flow for direct installations.

## [0.1.2]

### Added

- Quicklinks support.
- Reusable inline argument inputs for extension commands.

### Improved

- Hotkeys now support double-tapping command, option, or control modifiers.
- Launcher search now finds renamed applications by previous names retained in macOS metadata.
- Added duplicate actions for snippets and quicklinks.
- Added paste-target application icons to snippet actions.

### Fixed

- Creating a snippet or quicklink now returns to the previous palette screen with success feedback.

## [0.1.3]

### Added

- Caffeinate, Decaffeinate, and timed Caffeinate For launcher commands.

### Improved

- Quicklinks can now be added to and removed from launcher favorites.
- Palette-level command shortcuts now handle Settings, close, and return-to-root actions reliably.
- Refined the palette surface, footer controls, action keycaps, row spacing, and dark-only styling.
- Settings navigation now scrolls independently from the selected pane.

### Fixed

- Prevented Actions menus from showing the underlying palette rows on older macOS versions.
- Removed the leftover top spacing after removing the Settings sidebar search field.

### Removed

- Removed the light appearance option. Opencast now uses the dark appearance only.
- Removed the Settings-wide search field and search results view.

## [0.1.4]

### Fixed

- Fixed the self-update flow so downloads complete reliably and the install confirmation appears as expected.
