# App launcher & fuzzy match

`AppIndex.scan()` runs off-main, enumerates the standard `/Applications` dirs, and dedups by bundle ID
(first dir wins).

`FuzzyMatch` classifies matches as exact → prefix → word-start → substring → subsequence, with
consecutive / word-boundary detail scoring inside each class. `LauncherRankingStore` learns an
adaptive query affinity: one choice nudges results within the same class, while three recent choices
may promote a word-start or substring match by exactly one class. Exact matches remain absolute,
prefixes never become exact, and weak subsequences never receive a class promotion. This lets a
repeated `ch` → Google Chrome choice overtake the default prefix match Chess without allowing an
unrelated frequent app to surface. Matching strips invisible Unicode format scalars first, since app
metadata can contain bidi/zero-width markers before the visible name.

Selecting a launcher result records every prefix of the submitted query, so choosing WhatsApp for
`wha` also teaches `w`, `wh`, and `wha`. Every palette launch also records weak item-wide usage,
including empty-query favorites; it is only a final tie-break and can never change a fuzzy match
class. Direct hotkeys remain excluded because toggling an app outside Root Search provides no query
intent. Query affinity has a 30-day half-life, global usage a 60-day half-life, and repeated visits
approach a ceiling with diminishing returns, so stale habits yield quickly instead of becoming permanent. Learned
data stays on device in `launcher-ranking.json`; a ranked result offers a per-item reset in its
Actions menu, and users can clear all learned ranking in General Settings.

Rankings are memoized one query deep and keyed by the ranking store's revision, so a launch or reset
invalidates the cached order. `rank` resolves the query and global affinity tables once per pass — one
fold and one clock read per table, not per candidate.

> **Invariant:** `Tools/fuzz-test.swift` contains a **copy** of `FuzzyMatch` from
> `Bettercast/Core/AppIndex.swift`. If you change the scoring in one, mirror it in the other or the test
> is meaningless.

The ranking harness covers prefix learning, frequency/recency scoring, persistence, and both reset
paths; see the command in `development.md`.

Icons go through a count-capped `NSCache` (`IconCache`).

## Uninstall Application

Application actions include a guarded uninstall flow. Bettercast identifies the app bundle by its path and bundle ID, checks common per-user remnants in Application Support, Caches, Containers, Group Containers, preferences, saved state, logs, WebKit, HTTP storage, and user launch agents, then shows the exact paths before confirmation. The app and confirmed user files are moved to the Trash, not permanently deleted. Running apps are asked to quit first. System-owned remnants are reported but left untouched when administrator authorization would be required.

Matching is conservative: Bettercast uses exact bundle-ID/name matches and does not recursively sweep arbitrary home-directory data. This avoids the dangerous false positives that generic name-based cleanup can cause.

## Reveal in Finder

Application and System Settings results expose **Show in Finder** in their ⌘K Actions menu and on
**⌘↵**. Synthetic command results do not have a filesystem location, so the shortcut is unavailable
for them.

## Quitting apps

`RunningAppsMonitor` (live from `NSWorkspace` launch/terminate notifications) drives both the row's
running dot and the availability of the quit actions:

- **Quit Application** — the last row of an app's ⌘K Actions menu, shown only while that app is
  running. `AppLauncher.quit(bundleID:)` terminates every instance of the bundle and reports whether
  anything was running; the palette only dismisses when something was, and it restores focus unless
  the app it just quit *was* `previousApp`.
- **Quit All Applications** — a System Command. `AppLauncher.quitAllTargets()` is the policy (every
  `.regular` app except Finder — `terminate()` only relaunches it — and Bettercast, excluded by PID
  because About/Settings temporarily flips it to `.regular`). `AppCore.quitAllApps()` resolves that
  list **once**, confirms it with an `NSAlert`, then terminates exactly what was confirmed. The palette
  hides before the alert — it is a floating panel and would sit above it.

## System Commands

The launcher also exposes Lock Screen, Sleep, Sleep Displays, volume controls, Open Trash, Hide All
Apps Except Frontmost, and Unhide All Hidden Apps. Keyboard-event commands require Accessibility
permission; failures explain the missing permission and link to its System Settings pane.

Both quits are graceful `NSRunningApplication.terminate()`, so an app with unsaved work still puts up
its own save sheet.

The ⌘K menu samples `isRunning` **once, when it opens** (`RootPaletteView.openActions()`), so an app
launching or quitting elsewhere can't add or drop the Quit row while the menu is up — the same freeze
the rest of the menu already has ([palette.md](palette.md)). Only `LauncherList` observes
`RunningAppsMonitor` live, for the running dot.
