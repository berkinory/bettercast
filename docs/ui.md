# UI & Design System

The design system for Bettercast's UI, written so an agent restyling or extending it stays consistent
with what's already there. This documents **Bettercast as built** — every rule here maps to code in
`Bettercast/`. `Core/Theme.swift` is the single design-token source.

Read this before touching any view body, `Theme` value, or the panel chrome.

---

## The look, in one paragraph

Bettercast is a **Raycast-style dark command palette**: a borderless floating panel whose surface is
just the OS behind-window blur under a 40% black scrim — there is no gray chrome. Everything on that
surface is white at a fixed alpha ramp. The header and bottom bar **float over the list as fully
transparent overlays**; there are no hard-edged bars, strips, or dividers. Rows don't clip under the
bars, they **dissolve**: a scroll-driven gradient mask ghosts them as they pass beneath. Floating controls (the action pill, the menu circle, popover menus) use **Liquid Glass on macOS 26+**
and a solid dark fallback on older supported systems. The whole app is locked to dark mode because the
glass material is tuned for a deep dark surface.

Five load-bearing ideas, in priority order:

1. **Surface = 40% black over behind-window blur.** No solid backgrounds. Depth comes from the desktop showing through.
2. **White-alpha ramp, never grays.** Text and surfaces are `Color.white.opacity(…)` at fixed stops.
3. **Floating bars, not chrome.** Header/footer are transparent overlays; the list fills the whole panel.
4. **Edges dissolve, they don't clip.** Scroll-driven mask, no separators between list and bars.
5. **Glass only on floating controls.** The main surface is never glass; pills/menus/circles are.

---

## Non-negotiable invariants

These are the things that quietly break the look if changed. Preserve them unless the task is explicitly to change them.

- **Forced dark.** `AppCore.start()` sets `NSApp.appearance = .darkAqua`. All colors are literal white/black alphas, not adaptive `Color`s. Don't introduce semantic/adaptive colors or a light variant.
- **No grays, no opaque fills on the surface.** Reach for `Theme.Colors.*` (white-alpha) instead of `.gray`, `NSColor.windowBackground`, etc.
- **No hard dividers between the list and the bars.** The header and bottom bar are `safeAreaInset` overlays with no background; separation comes from `edgeDissolve()`, nothing else. (One deliberate exception: the vertical hairline between the clipboard list and its preview pane.)
- **The panel corner is clipped once, at the root.** `RootPaletteView.body` ends with `.background(black 40%) → .background(VisualEffectView()) → .clipShape(RoundedRectangle(26, .continuous))`. Keep that order; the scrim goes _over_ the vibrancy, and the clip is last.
- **Don't use the native scroll edge effect.** Inside a transparent panel it renders a hard-bounded rectangle. Use `edgeDissolve()`.
- **Test over a light desktop.** Transparency and corner masking bugs only show over bright wallpaper. Dark wallpaper hides them.

---

## Tokens — `Bettercast/Core/Theme.swift`

`Theme` is the single source of truth. **Never hardcode a spacing/radius/size/color that has a token.**
Add a token rather than a magic number when introducing a new value.

### Spacing (`Theme.Spacing`)

`xxs 2` · `xs 4` · `sm 6` · `md 8` · `lg 10` · `xl 12` · `xxl 20`

`xxs` is the tight gap between adjacent keycap chips (used everywhere keycaps sit side by side).

Row content insets are `md`; list horizontal inset is `md`; the search icon aligns with rows via `md * 2`.

Section-header rhythm has two dedicated tokens: `sectionHeaderBottom` (header → first row) and
`sectionSpacing` (gap above every header **except the list's first**, which reads as the previous
section's closing padding). See "Section headers" below.

### Radius (`Theme.Radius`)

`panel 26` · `row 10` · `card 10` · `menuPanel 16` · `menu 6` · `menuRow 10` · `thumbnail 6` · `keyCap 6` · `recorderKeyCap 4`

`menu` is the shared small-control corner (sidebar tiles, About link pills); `menuRow` is the slightly rounder hover highlight behind popover-menu rows.

Always `RoundedRectangle(cornerRadius:, style: .continuous)` — continuous corners everywhere, never `.circular`.

### Size (`Theme.Size`)

`panelWidth 750` · `panelHeight 475` · `headerHeight 44` · `bottomBarHeight 52` · `rowIcon 24` ·
`keyCap 18` · `recorderKeyCap 16` · `menuButton 36` · `clipboardListWidth 290` · `menuWidth 276` · `menuIcon 20`

Settings metrics live in the nested `Theme.Settings` namespace so changing its compact fixed-window UI cannot drift the palette: window `760×560`, sidebar `200`, header icon `38`, row icon `28`, and control height `32`.

`keyCap` sizes the palette's keycap chips; `recorderKeyCap` (both size and radius) is the intentionally-smaller Settings shortcut-recorder chip.

### Typography (`Theme.Typography`)

System fonts only — **no fixed point sizes in views** (honors Dynamic Type). `searchField` is the one
explicit size (20pt regular). Use `rowTitle` (`.body`), `sectionHeader` (`.subheadline.medium`),
`rowTrailing`/`bar`/`menuRow`/`keyCap` etc. as named.

### Colors (`Theme.Colors`) — the white-alpha ramp

| Token            | Value          | Use                                              |
| ---------------- | -------------- | ------------------------------------------------ |
| `panelDimming`   | black **0.40** | the panel scrim over vibrancy                    |
| `selection`      | white 0.10     | selected row fill (keyboard/active selection)    |
| `rowHover`       | white 0.05     | mouse-hover fill (always fainter than selection) |
| `menuHover`      | white 0.10     | popover-menu row hover                           |
| `separator`      | white 0.10     | the clipboard list↔preview hairline              |
| `controlSurface` | white 0.10     | filled keycaps, glyph tiles                      |
| `border`         | white 0.20     | outlined keycap borders                          |
| `textSecondary`  | white 0.60     | secondary labels                                 |
| `textTertiary`   | white 0.40     | placeholders, trailing kind labels               |
| `cardFill`       | white 0.05     | settings/calc card fill                          |
| `cardStroke`     | white 0.10     | settings/calc card border + inset dividers       |
| `glassFrost`     | white 0.01     | whitish tint layered into the floating glass     |

Beyond these, `.secondary`/`.tertiary` foreground styles are fine for SF Symbols (they resolve against
the forced-dark environment). **Selection always beats hover** when a row is both.

---

## Panel structure — `Core/PalettePanel.swift`, `Features/RootPaletteView.swift`

- **`PalettePanel`** is a borderless `NSPanel`: `isOpaque = false`, `backgroundColor = .clear`, `.floating` level, `hasShadow`, `animationBehavior = .none`. It hosts SwiftUI via `NSHostingView`. `PaletteWindowController` centers it slightly above screen center (`+8%`) and dismisses it on `windowDidResignKey`.
- **The results layer fills the whole panel.** The header and bottom bar attach via `.safeAreaInset(edge: .top/.bottom)` as transparent overlays that float _over_ the list. The list underlaps them and dissolves at the edges.
- **Header** (`headerHeight 44`): a back-chevron _or_ mode glyph, then the plain `TextField` (no border/background). Sub-screens (Clipboard, Calculator History) show the back chevron; the launcher shows a magnifying glass. The search icon aligns horizontally with row content.
- **Compact keyboard entry:** pressing `↓` in the collapsed launcher expands the results and selects the first row without replacing or defocusing the shared search field.
- **Bottom bar** (`bottomBarHeight 52`): a menu circle on the left, the action group on the right — both floating glass, no bar background. The action group is one glass `Capsule` holding the primary-action pill (label + `↵`) and the Actions toggle (`⌘K`).

---

## The edge dissolve — `Core/EdgeDissolve.swift`

The signature effect. A scroll-driven `LinearGradient` mask on each list so rows soften as they approach
a floating bar, ghost beneath it, and vanish only at the window edge. Attach with `.edgeDissolve()` on
the `ScrollView`, **before `.thinScrollbar()`** (so the scrollbar overlay stays unmasked).

- Fade bands: top = `headerHeight + headerPadding + 32`, bottom = `bottomBarHeight + 28` — each overshoots its bar into the visible list, so the ramp finishes ~32/28px _past_ the bar rather than cliffing at its edge.
- Alpha floors mid-scroll (not to 0): **top 0.15, bottom 0.25**, eased by how much content is hidden past the edge (`1 − (1 − floor)·clamp(dist/band, 0, 1)`).
- Only masks when the list is scrollable; the edge stop stays transparent so rubber-band bounces still dissolve. A list that fits gets no mask.
- The mask spans the scroll view's **full** frame (`.ignoresSafeArea()`) — otherwise the bars' safe-area insets shift the gradient onto at-rest rows.

---

## Rows, selection, hover — `Launcher/LauncherView.swift`, `Clipboard/ClipboardView.swift`

All lists share one row grammar so launcher and clipboard look identical:

- `HStack(spacing: lg)`: leading 24pt icon/thumbnail, title (`.body`, `lineLimit(1)`), optional trailing keycaps/kind label, `Spacer`. Insets: `.horizontal md`, `.vertical sm`.
- Background is a `RoundedRectangle(row, .continuous)` filled by `fill`: **selection → hover → clear**, in that precedence. This `fill` computed property is copy-identical across `AppRow`, `ClipboardRow`, `CalculatorCard` — keep them in sync.
- **Hover state lives on the row**, not the list, so a mouse sweep repaints only the rows entering/leaving (a list-level hover rebuilds every row per move — don't do that).
- **Scroll follows selection only on keyboard nav/reset**, driven by a `scrollToken` UUID — mouse selection targets a visible row and never yanks scroll.
- **Keycaps** use `KeyCapChip`: `.outline` (white-0.20 border) for hotkey hints on rows, `.filled` (white-0.10 fill) for footer shortcuts.

### Section headers

All four palette lists (App Launcher, Clipboard, Emoji, Calculator History) render category labels
through one shared **`SectionHeader`** (`.subheadline.medium`, secondary — `Features/Launcher/LauncherView.swift`).
The launcher shows a single "Results" header over search matches, and per-kind sections
(Favorites / Applications / System Settings / Commands) for the empty query; clipboard/history use
date buckets (Today / Yesterday / …), and the clipboard adds a "Pinned" section above them holding
every pinned entry (filtered searches included).

Spacing lives in `Theme.Spacing`: `sectionHeaderBottom` (header → first row) and `sectionSpacing`
(gap above every header **except the list's first**, which reads as the previous section's closing
padding). Each list passes `isFirst: row.id == <rows>.first?.id` so only the very first row skips the
leading gap. Headers are non-selectable display rows, so selection (keyed by id) is unaffected.

---

## Liquid Glass — `Theme.frosted(in:)`, `Features/PopoverMenu.swift`

Glass is **only** for floating controls, never the main surface.

- `View.frosted(in:)` uses `glassEffect(.regular.interactive().tint(glassFrost), in:)` + `.tint(.clear)` on macOS 26+, and a solid dark surface with a border below it. Used on the action-group capsule, menu circle, and popover menus; tune the frost amount via the `glassFrost` token, not per call site.
- **Menus are in-window overlays, not system popovers.** `.contextMenu`/`NSMenu` stall clicks for seconds inside a `LazyVStack` and spill outside the panel. Use `PopoverMenu` anchored to a bottom corner via `.overlay`, inset `menuInset` (8pt) so its own corner isn't clipped by the panel's.
- **`PopoverMenu`** uses the same `frosted` surface with **no hand-tuned shadow** — Tahoe glass carries its own elevation, while the older-system fallback uses the shared dark surface and border.
- `PopoverMenuRow`: leading glyph, label, trailing shortcut glyph, `menuHover` fill on hover, `menuRow 10` corner. Menus animate in with `.opacity + .scale(0.96)` from the anchored corner, `easeOut 0.14`.
- The glyph is a `PopoverMenuIcon`: `.symbol` (SF Symbol, `hierarchical`, secondary — or **red** when `isDestructive`) or `.file` (a real app icon via `IconCache`, used by the paste rows to show the paste target). `PopoverMenuItem` keeps a `systemImage:` convenience init, so symbol rows read exactly as before.
- **Both glyph kinds share one square `menuIcon` (20) slot**, which is what makes symbol and app-icon rows read as the same size and pins a single row height. 20 is deliberately larger than the artwork looks: an `IconCache` icon paints only ~85% of its canvas (13pt visible at a 16pt slot), while a `.body` SF Symbol renders 17–18pt tall — at 20 the icon lands on 17pt and the two match. Measure before changing it.
- Menu rows are the one place that uses `sm` for the icon→label gap instead of the row-standard `lg`, because that slot's built-in slack already contributes 2–3pt of apparent space.

---

## Scrollbars — `Core/ThinScrollbar.swift`

Custom thin overlay scrollbar (the native one flashes and reserves a gutter inside a transparent panel).
`.hideNativeScrollers()` on the scroll _content_ forces the backing `NSScrollView` to a hidden `.overlay`
style; `.thinScrollbar()` on the scroll view draws a hairline thumb (`Color.primary` alpha 0.30 rest →
0.42 hover → 0.5 drag) that fattens on hover, with a faint rail revealed only while hovering/dragging.

Routing: the palette lists (App Launcher, Clipboard history, Emoji, Calculator history) use
`.thinScrollbar()` + `.hideNativeScrollers()`; the Clipboard preview (right pane) and every Settings
pane use the native `.overlayScroller()`. Don't reintroduce native scrollers on the palette lists.

---

## Settings — `Features/Settings/SettingsComponents.swift`

Settings runs in a fixed `760×560` `NSWindow` (the SwiftUI `Settings` scene is unreliable for accessory apps) and uses the palette's own surface language: behind-window blur under the same 40% black scrim, the same white-alpha ramp, and the same row/keycap grammar. Its navigation is specific rather than catch-all: General; Launcher, Clipboard, Emoji & Symbols, Calculator; Shortcuts, Permissions; About. Networked currency conversion lives under Calculator.

- **Sidebar** is compact and neutral: bare hierarchical symbols, 34pt rows inset 8pt from both edges, one `selection` fill, and no colored icon tiles, selection stroke, or scroll container. Other Settings scrollers disable AppKit elasticity.
- **`SettingsPane`** owns scrolling, destination jumps, fixed insets, and a compact `SettingsFeatureHeader`: a bare secondary symbol beside a `.title3.semibold` title and one-line subtitle.
- **`SettingsSection`** groups related controls on the palette's `cardFill`/`cardStroke` surface with the shared 10pt card radius. `SettingsRowDivider` aligns below the row title, past the icon slot.
- **`SettingsControlRow`** uses a bare 28pt symbol slot, medium callout title, optional two-line caption, and intrinsic-width trailing control. Feature tint arguments never color generic chrome; color is reserved for real success, warning, and destructive states.
- **`SettingsStatusCard`** keeps a neutral card surface and uses semantic color only on its status glyph.
- Feature controls do not have to collapse into rows: Launcher uses visual Standard/Compact tiles, Clipboard uses app chips, Emoji uses direct tone swatches, and per-item shortcuts use an aligned table with eye buttons instead of a wall of switches. Their selection surfaces stay neutral.
- `ShortcutRecorder` follows the Raycast-style two-layer model: its fixed monochrome trigger always shows a neutral border around `Record Hotkey` or one combined glyph value, and a bound shortcut shows its clear `×` whenever it is idle, without changing the footprint; capture hides the clear segment and releases its reserved content space. Recording opens an instant anchored capture popover above the field with modifier preview and a target footer whose icon matches the target row. Conflict feedback resolves on the next key press; success enters quickly, then fades into the neutral editing state. Feedback color animates independently while foreground content always changes immediately. Space or Return starts capture, Escape closes it, and Delete clears the binding.
- Settings search indexes panes and actual setting targets only. It deliberately excludes every application, command, and System Settings item listed inside Shortcuts; those belong to the Shortcuts pane's local search.
- Custom Settings controls use the shared neutral `settingsFocusRing` modifier so they remain visible and operable in the full keyboard-access loop.
- Settings navigation, hover, search mode, and destination scrolling update immediately. The only deliberate animation is the short destination highlight fade; do not add springs or slow pane transitions.

The calculator's inline `CalculatorCard` reuses this card language (`cardFill` + `cardStroke`) rather than the row language, since it's a highlighted answer, not a list item. A value answer is a **two-column** layout: a source column (input echo) and a target column (result), separated by a centered `arrow.right` glyph (no divider line). Each column optionally carries a word-name **badge pill** beneath its value (`keyCap` font, `controlSurface` fill, `keyCap` radius) — the unit long names for a conversion (`Meters`→`Feet`), or the moment labels for a date/time calc (`12:18 AM`→`9:00 AM`, `Friday, 24 July`→`Friday, 9 April, 2027`). Plain arithmetic leaves both badges nil, so the card stays a clean value → value line.

---

## Rules for agents working on the UI

- **Restyle from screenshots, not extracted CSS.** Pixel-matching Raycast from its bundle led to wrong results before; compare rendered screenshots over a light desktop instead. There's no screen-recording from the shell here — verify AppKit rendering with a `swiftc` harness that prints layer state, and let the user do visual sign-off.
- **Don't add behavior that wasn't requested.** A restyle changes appearance, not interaction — keep selection/scroll/dismiss/focus flows exactly as they are unless the task is about them.
- **New tokens go in `Theme`**, referenced everywhere. No magic numbers in views.
- **Keep the shared grammar shared.** If you change row insets, the `fill` precedence, section-header style, or keycap style, change it for _all_ lists — divergence is the bug, not the feature.
- **Build & verify** with the real toolchain (see [`development.md`](development.md)); a design change that doesn't compile under Swift 6 mode isn't done.
