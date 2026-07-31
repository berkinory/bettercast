import AppKit
import SwiftUI

struct ListScrollIntent: Equatable {
    enum Kind: Equatable {
        case follow
        case top
    }

    let id = UUID()
    let kind: Kind
}

struct RootPaletteView: View {
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var vm: PaletteViewModel
    @EnvironmentObject private var appIndex: AppIndex
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var visibility: VisibilityStore
    /// Observed so the inline card re-evaluates the moment a fresh FX snapshot lands, or the user
    /// turns currency conversion on or off.
    @EnvironmentObject private var currencyRates: CurrencyRateStore
    @EnvironmentObject private var emojiIndex: EmojiIndex
    @EnvironmentObject private var frequentEmoji: FrequentEmojiStore
    @EnvironmentObject private var uninstall: UninstallSession
    /// Observed so a skin tone changed in Settings re-renders the grid glyphs immediately.
    @ObservedObject private var settings = AppCore.shared.settings
    @FocusState private var searchFocused: Bool
    @State private var showActions = false
    @State private var showAppMenu = false
    @State private var showSortMenu = false
    /// The selection's running state, sampled once by `openActions` — an app launching or quitting elsewhere must not add or drop the Quit row while the menu is up. `RunningAppsMonitor` is deliberately not observed here: only `LauncherList` needs live running state, and observing it would re-render the whole palette on every workspace launch/terminate.
    @State private var selectionIsRunning = false
    /// Highlighted row of whichever popover menu is open; reset to the first row on open, moved by ↑/↓ and hover, activated by ↵/click.
    @State private var menuSelection = 0
    /// Changes only when a list should follow selection or return to its origin; mouse selection never moves the viewport.
    @State private var listScroll: ListScrollIntent?
    /// The emoji grid's scroll request — the lazy grid needs distinct reset/follow scroll ops.
    @State private var emojiScroll = EmojiScrollIntent(kind: .top)

    private var isQueryEmpty: Bool { vm.query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Slim compact bar vs. full window — the single source of truth lives on `AppCore` so the window controller and this view can never disagree.
    private var isCollapsed: Bool { core.paletteIsCollapsed }

    /// Favorite slots shown in the compact bar: up to 5 launchable apps, or the first 4 plus an overflow "…" that expands the window. Evaluated only in the compact render and on the rare ⌘N keypress.
    private var compactFavoriteSlots: [CompactFavoriteSlot] {
        let favs = favorites.ordered(appIndex.matches("").filter(visibility.isVisible)).favorites
        if favs.count <= 5 { return favs.map(CompactFavoriteSlot.app) }
        return favs.prefix(4).map(CompactFavoriteSlot.app) + [.more]
    }

    /// Ordered launcher results (the single source of truth for list, selection and activation): empty query pins favorites to the top, otherwise plain ranked matches.
    private var appResults: [AppEntry] {
        // Visibility filtering stays downstream of `matches` so its one-deep memo cache is never keyed on hidden state; hidden favorites drop out here too.
        let base = appIndex.matches(vm.query).filter(visibility.isVisible)
        guard isQueryEmpty, !favorites.keys.isEmpty else { return base }
        let split = favorites.ordered(base)
        return split.favorites + split.rest
    }
    private var clipResults: [ClipboardItem] { store.search(vm.query) }
    private var uninstallResults: [LeftoverItem] { uninstall.filtered(vm.query) }
    private var emojiSections: [EmojiGridSection] {
        EmojiGrid.sections(query: vm.query, index: emojiIndex, frequent: frequentEmoji)
    }
    /// Flat grid order across sections — what `vm.selection` indexes in emoji mode.
    private var emojiResults: [EmojiEntry] { emojiSections.flatMap(\.entries) }

    /// Inline calculator answer for the current launcher query; when present it occupies flat selection index 0 so rows shift by `calcCount`.
    private var calcResult: CalcResult? {
        vm.mode == .launcher
            ? CalcMemo.evaluate(
                vm.query,
                currency: settings.currencyConversionEnabled
                    ? currencyRates.source(cryptoEnabled: settings.cryptoConversionEnabled)
                    : .off
            )
            : nil
    }
    private var calcCount: Int { calcResult == nil ? 0 : 1 }

    private var resultCount: Int {
        switch vm.mode {
        case .launcher: return appResults.count + calcCount
        case .clipboard: return clipResults.count
        case .emoji: return emojiResults.count
        case .uninstall: return uninstall.phase == .selecting ? uninstallResults.count : 0
        }
    }
    /// Selection clamped into the current results — the single source of truth for highlight, preview and activation so the list and preview can never disagree.
    private var selection: Int { resultCount == 0 ? 0 : min(max(vm.selection, 0), resultCount - 1) }

    private var menuOpen: Bool { showActions || showAppMenu || showSortMenu }

    // MARK: - Popover menu content
    //
    // These resolve the current selection for whichever menu is open. They are evaluated only inside the
    // menu overlays (menu visible) or on a keypress (rare), so re-running the unmemoized `appResults`
    // filter here is fine — the same idiom the other rare event handlers use.

    /// The inline calc card sits at flat index 0 when present; only value payloads have a Copy action.
    private var calcActionableResult: CalcResult? {
        guard calcCount > 0, selection == 0, let calc = calcResult, calc.isActionable else {
            return nil
        }
        return calc
    }
    private var selectedAppEntry: AppEntry? {
        let index = selection - calcCount
        return appResults.indices.contains(index) ? appResults[index] : nil
    }
    private var selectedClipItem: ClipboardItem? {
        clipResults.indices.contains(selection) ? clipResults[selection] : nil
    }
    private var selectedEmojiEntry: EmojiEntry? {
        emojiResults.indices.contains(selection) ? emojiResults[selection] : nil
    }

    /// The bottom-right Actions menu content for the current mode's selection, or nil when the selection has no actions.
    private var actionsContent: PopoverMenuContent? {
        switch vm.mode {
        case .launcher:
            if let calc = calcActionableResult {
                return CalcActionsMenu.content(result: calc, core: core)
            }
            if let app = selectedAppEntry {
                return AppActionsMenu.content(
                    app: app, searchQuery: vm.query, core: core, favorites: favorites,
                    running: selectionIsRunning,
                    onResetRanking: {
                        core.resetRanking(for: app)
                        // Reset can move the item; keep the highlight on the item whose action ran.
                        if let index = appResults.firstIndex(of: app) {
                            vm.selection = index + calcCount
                        }
                    },
                    onToggleFavorite: { toggleFavorite(app) })
            }
            return nil
        case .clipboard:
            if let clip = selectedClipItem {
                return ClipboardActionsMenu.content(
                    item: clip, core: core, target: vm.pasteTarget,
                    onFeedback: showFeedback(_:))
            }
            return nil
        case .emoji:
            if let emoji = selectedEmojiEntry {
                return EmojiActionsMenu.content(
                    entry: emoji, core: core, target: vm.pasteTarget)
            }
            return nil
        case .uninstall:
            guard uninstall.phase == .selecting, !uninstallResults.isEmpty else { return nil }
            return UninstallActionsMenu.content(
                session: uninstall, visible: uninstallResults, selection: selection, core: core)
        }
    }

    private var sortMenuContent: PopoverMenuContent {
        UninstallActionsMenu.sortContent(session: uninstall) { sort in
            core.setUninstallSort(sort)
            listScroll = ListScrollIntent(kind: .top)
        }
    }

    /// The bottom-left app menu content (About / Settings).
    private var appMenuContent: PopoverMenuContent {
        PopoverMenuContent(items: [
            PopoverMenuItem(title: "About Bettercast", systemImage: "info.circle") {
                core.showAbout()
            },
            PopoverMenuItem(title: "Settings", systemImage: "gearshape", shortcut: "⌘,") {
                core.showSettings()
            },
        ])
    }

    /// Whichever menu is open (Actions takes precedence; the two are kept mutually exclusive) — the source for keyboard navigation and activation.
    private var menuContent: PopoverMenuContent? {
        if showActions { return actionsContent }
        if showAppMenu { return appMenuContent }
        if showSortMenu { return sortMenuContent }
        return nil
    }

    var body: some View {
        // Filter once per render for the active mode only, so the matcher/search doesn't run several times per render (rare event handlers use the computed properties above).
        let apps = vm.mode == .launcher ? appResults : []
        let clips = vm.mode == .clipboard ? clipResults : []
        let emojiSections = vm.mode == .emoji ? emojiSections : []
        let emojis = emojiSections.flatMap(\.entries)
        let uninstallItems = vm.mode == .uninstall ? uninstallResults : []
        // Newest stored clip + the reorder token: the pair changes only when the store mutates, never when a query filters the list.
        let clipFollow = ClipFollowKey(id: store.items.first?.id, token: vm.followToken)
        // Every count/selection below derives from this one calc/offset pair — the flat selection index must always match the visible row order, calc card included.
        let calc = calcResult
        let offset = calc == nil ? 0 : 1
        // Only the active mode is non-empty.
        let count = apps.count + offset + clips.count + emojis.count + uninstallItems.count
        let sel = count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
        let calcSelected = calc != nil && sel == 0
        // An error card is selectable but has no action: it must not drive the Copy Answer pill, ⌘K menu, or Enter.
        let calcActionable = calcSelected && calc?.isActionable == true
        let showSections = vm.mode == .launcher && isQueryEmpty
        let favoriteCount =
            showSections ? apps.prefix(while: { favorites.isFavorite($0) }).count : 0
        let selectedApp = apps.indices.contains(sel - offset) ? apps[sel - offset] : nil
        // Derive the footer label from the already-resolved selection so `bottomBar` doesn't re-run `appResults` (its filter/sort aren't memoized). The primary/Actions group is hidden when there's nothing to act on: no results in any mode, or an error calc card (selectable but action-less).
        let pillLabel = actionPillLabel(selectedApp: selectedApp, calcActionable: calcActionable)
        let showActionGroup = showsActionGroup(count: count, calcBlocked: calcSelected && !calcActionable)

        // The `header` (and its single search field) is always attached in the same position via safeAreaInset so its focus survives the compact↔expanded swap — only the results below it toggle. Collapsed shows the bar alone; expanded floats header + action bar over the list with edge-dissolve (see docs/ui.md).
        return Group {
            if isCollapsed {
                Color.clear
            } else {
                content(
                    apps: apps, clips: clips, emojiSections: emojiSections,
                    uninstallItems: uninstallItems, calc: calc,
                    selection: sel, favoriteCount: favoriteCount, showSections: showSections
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isCollapsed {
                bottomBar(pillLabel: pillLabel, showActionGroup: showActionGroup)
            }
        }
        // Menus are in-window overlays anchored to a bottom corner, so they stay clipped inside the panel — never a system popover spilling outside the window.
        .overlay { menuDismissCatcher }
        .overlay(alignment: .bottomLeading) { appMenuOverlay }
        .overlay(alignment: .topTrailing) { sortMenuOverlay }
        .overlay(alignment: .bottomTrailing) { actionsMenuOverlay }
        // The window's own frame (driven by `PaletteWindowController`) is the size source of truth; filling it keeps the glass background and corner clip matched to the current compact/expanded window height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.panelSurface)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        // Every show bumps focusToken — refocus search and drop any menu left open from last time (e.g. dismissed by clicking away with a context menu up).
        .onChange(of: vm.focusToken) {
            searchFocused = true
            vm.feedback = nil
            showActions = false
            showAppMenu = false
            showSortMenu = false
        }
        .onChange(of: vm.query) {
            vm.selection = 0
            listScroll = ListScrollIntent(kind: .top)
            emojiScroll = EmojiScrollIntent(kind: .top)
        }
        .onChange(of: vm.mode) {
            vm.selection = 0
            vm.feedback = nil
            showActions = false
            showSortMenu = false
            listScroll = ListScrollIntent(kind: .top)
            emojiScroll = EmojiScrollIntent(kind: .top)
        }
        // Pop-to-root can leave query and mode unchanged, so explicitly restore the content origin.
        .onChange(of: vm.resetToken) {
            listScroll = ListScrollIntent(kind: .top)
            emojiScroll = EmojiScrollIntent(kind: .top)
        }
        // Opening either menu highlights its first row and closes the other, so exactly one menu is ever open and always has a highlight.
        .onChange(of: menuOpen) { vm.menuOpen = menuOpen }
        // Follow a row the store moved: a fresh capture (or promote-on-paste) lands at the head of its section, and pinning lifts a row into the Pinned section. With a query typed the highlight stays put; `AppCore` has already placed it for pin/paste.
        .onChange(of: clipFollow) { old, new in
            // A nil `old.id` is the first load landing, not a row that moved.
            guard vm.mode == .clipboard, old.id != nil else { return }
            if isQueryEmpty, old.id != new.id, let id = new.id,
                let index = clips.firstIndex(where: { $0.id == id })
            {
                vm.selection = index
            }
            listScroll = ListScrollIntent(kind: .follow)
        }
        .onAppear { searchFocused = true }
        .task(id: vm.feedback?.id) {
            guard vm.feedback != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(Self.feedbackAnimation) { vm.feedback = nil }
        }
        // Resize first, then reassert the top after compact mode adopts the full frame.
        .onChange(of: core.paletteIsCollapsed) { oldCollapsed, collapsed in
            core.syncPaletteSize()
            guard oldCollapsed, !collapsed else { return }
            Task { @MainActor in
                await Task.yield()
                guard !core.paletteIsCollapsed else { return }
                listScroll = ListScrollIntent(kind: .top)
            }
        }
        // ⌘1–⌘5 launch the compact bar's favorite slots (or expand, for the "…" overflow slot).
        .onKeyPress(keys: ["1", "2", "3", "4", "5"], phases: .down) { press in
            guard isCollapsed, settings.showFavoritesInCompactMode,
                press.modifiers.contains(.command),
                let digit = press.key.character.wholeNumberValue
            else { return .ignored }
            let slots = compactFavoriteSlots
            let index = digit - 1
            guard slots.indices.contains(index) else { return .ignored }
            switch slots[index] {
            case .app(let app): core.launch(app)
            case .more: core.expandFromCompact()
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if isCollapsed {
                // The compact bar has no visible selection; Down reveals the list at its first row
                // while the shared search field stays mounted and focused.
                vm.selection = 0
                core.expandFromCompact()
                return .handled
            }
            if menuOpen {
                moveMenu(1)
                return .handled
            }
            if vm.mode == .emoji { moveEmojiRow(1) } else { move(1) }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if isCollapsed { return .ignored }
            if menuOpen {
                moveMenu(-1)
                return .handled
            }
            if vm.mode == .emoji { moveEmojiRow(-1) } else { move(-1) }
            return .handled
        }
        // Horizontal arrows step the emoji grid; everywhere else they stay with the field editor's caret. An open menu swallows them so the list behind never moves.
        .onKeyPress(.leftArrow) {
            if menuOpen { return .handled }
            let isEmojiMode = vm.mode == .emoji
            guard isEmojiMode else { return .ignored }
            move(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if menuOpen { return .handled }
            let isEmojiMode = vm.mode == .emoji
            guard isEmojiMode else { return .ignored }
            move(1)
            return .handled
        }
        // With a menu open, plain ↵ activates its highlighted row. A modified ↵ always runs the selection's own action regardless of menu state: ⌘↵ the secondary copy action (each menu advertises it), ⌥↵ paste-in-place; plain ↵ (no menu) falls through to the field's onSubmit.
        .onKeyPress(keys: [.return], phases: .down) { press in
            let command = press.modifiers.contains(.command)
            let option = press.modifiers.contains(.option)
            if menuOpen, !command, !option {
                activateMenuItem(menuSelection)
                return .handled
            }
            guard command || option else { return .ignored }
            switch vm.mode {
            case .emoji:
                guard emojiResults.indices.contains(selection) else { return .ignored }
                let emoji = emojiResults[selection]
                if command {
                    core.copyEmoji(emoji)
                } else {
                    core.pasteEmojiKeepingWindowOpen(emoji)
                }
            case .clipboard:
                guard command else { return .ignored }
                guard clipResults.indices.contains(selection) else { return .ignored }
                core.copyToClipboard(clipResults[selection])
            case .launcher:
                guard command, let app = selectedAppEntry,
                    app.kind == .application || app.kind == .systemSettings
                else {
                    return .ignored
                }
                core.showInFinder(app)
            case .uninstall:
                guard command, uninstallResults.indices.contains(selection) else { return .ignored }
                core.showLeftoverInFinder(uninstallResults[selection])
            }
            return .handled
        }
        // ⌘F toggles the selected app's favorite state while its Actions menu is open.
        .onKeyPress(keys: ["f"], phases: .down) { press in
            guard showActions, vm.mode == .launcher else { return .ignored }
            guard press.modifiers.contains(.command),
                press.modifiers.intersection([.shift, .option, .control]).isEmpty
            else { return .ignored }
            guard let app = selectedAppEntry else { return .ignored }
            toggleFavorite(app)
            closeMenus()
            return .handled
        }
        .onKeyPress(keys: ["c"], phases: .down) { press in
            guard showActions,
                vm.mode == .launcher,
                press.modifiers.contains([.command, .shift]),
                press.modifiers.intersection([.option, .control]).isEmpty,
                let app = selectedAppEntry,
                app.kind == .application
            else { return .ignored }
            core.copyPath(app)
            closeMenus()
            return .handled
        }
        .onKeyPress(.escape) {
            if menuOpen {
                closeMenus()
                return .handled
            }
            if vm.mode == .uninstall {
                core.exitUninstall()
                return .handled
            }
            core.handlePaletteEscape()
            return .handled
        }
        .onKeyPress(.tab) {
            if menuOpen || vm.mode == .uninstall { return .handled }
            toggleMode()
            return .handled
        }
        .onKeyPress(keys: [","], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            core.showSettings()
            return .handled
        }
        // ⌘K toggles the actions panel for the current selection.
        .onKeyPress(keys: ["k"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            // The Actions menu has no anchor in the compact bar (no bottom bar); swallow ⌘K there.
            guard !isCollapsed else { return .handled }
            guard resultCount > 0 else { return .handled }
            // An error calc card is the selection but has no actions — don't open an empty panel.
            if calcCount > 0, selection == 0, calcResult?.isActionable != true { return .handled }
            toggleActions()
            return .handled
        }
        // Bare backspace (back out of a sub-screen when the search is empty) is intercepted by PalettePanel.sendEvent — the field editor consumes it before onKeyPress could fire.
        .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
            if menuOpen { return .handled }
            if press.modifiers.contains(.control), !isCollapsed, vm.mode == .launcher,
                let app = selectedAppEntry,
                AppLeftovers.canUninstall(url: app.url, bundleID: app.bundleID)
            {
                core.beginUninstall(app)
                return .handled
            }
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.modifiers.contains(.shift), vm.mode == .uninstall,
                uninstall.phase == .selecting
            {
                core.confirmUninstall(permanently: true)
                return .handled
            }
            switch vm.mode {
            case .clipboard:
                deleteSelectedClip()
            case .launcher, .emoji, .uninstall:
                return .ignored
            }
            return .handled
        }
        // ⌘P pins/unpins the selected clip — mirrors the Actions menu row, and works while that menu is open like the other advertised chords.
        .onKeyPress(keys: ["p"], phases: .down) { press in
            guard press.modifiers.contains(.command), vm.mode == .clipboard,
                clipResults.indices.contains(selection)
            else { return .ignored }
            core.togglePinnedClip(clipResults[selection])
            return .handled
        }
    }

    @ViewBuilder
    private var menuDismissCatcher: some View {
        if menuOpen {
            Theme.Colors.invisibleOverlay
                .contentShape(Rectangle())
                .onTapGesture(perform: closeMenus)
        }
    }

    @ViewBuilder
    private var appMenuOverlay: some View {
        if showAppMenu {
            let content = appMenuContent
            PopoverMenu(
                header: content.header, items: content.items, selection: $menuSelection,
                onActivate: activateMenuItem
            )
            .padding(Self.menuInset)
            .transition(Self.menuTransition(.bottomLeading))
        }
    }

    @ViewBuilder
    private var sortMenuOverlay: some View {
        if showSortMenu, vm.mode == .uninstall {
            let content = sortMenuContent
            PopoverMenu(
                header: content.header, items: content.items, selection: $menuSelection,
                onActivate: activateMenuItem
            )
            .padding(Self.menuInset)
            .padding(.top, Theme.Size.headerHeight + Theme.Size.headerPadding)
            .transition(Self.menuTransition(.topTrailing))
        }
    }

    @ViewBuilder
    private var actionsMenuOverlay: some View {
        if showActions, let content = actionsContent {
            PopoverMenu(
                header: content.header, items: content.items, selection: $menuSelection,
                onActivate: activateMenuItem
            )
            .padding(Self.menuInset)
            .transition(Self.menuTransition(.bottomTrailing))
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            // Sub-screens use a back chevron instead of a mode glyph.
            if vm.mode != .launcher {
                Button(action: exitToLauncher) {
                    Image(systemName: "chevron.left")
                        .font(Theme.Typography.headerIcon)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: Theme.Size.headerIconSlot)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.arrow.set() }
                }
            } else {
                Image(systemName: vm.mode.systemImage)
                    .font(Theme.Typography.headerIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: Theme.Size.headerIconSlot)
            }
            searchField
            headerTrailing
        }
        // Align the search icon with the list rows and section headers below (list inset + row inset).
        .padding(.horizontal, Theme.Spacing.md * 2)
        // Fixed row height + top padding, identical in both states, so typing (which flips compact→expanded) can't move the search bar. Compact centers the row in symmetric slack; expanded floats the same row over the list.
        .frame(height: Theme.Size.headerHeight)
        .padding(.top, Theme.Size.headerPadding)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var headerTrailing: some View {
        if vm.mode == .uninstall, uninstall.phase == .selecting, !uninstall.items.isEmpty {
            UninstallSortButton(sort: uninstall.sort, action: toggleSortMenu)
        }
        if isCollapsed, settings.showFavoritesInCompactMode {
            let slots = compactFavoriteSlots
            if !slots.isEmpty {
                CompactFavoritesRow(
                    slots: slots,
                    onLaunch: { core.launch($0) },
                    onOverflow: { core.expandFromCompact() }
                )
            }
        }
    }

    /// The one search field, kept in a single tree position (the `header`) so its focus survives the compact↔expanded swap.
    private var searchField: some View {
        TextField(
            "", text: $vm.query,
            prompt: Text(vm.mode.placeholder).foregroundStyle(Theme.Colors.searchPlaceholder)
        )
        .textFieldStyle(.plain)
        .font(Theme.Typography.searchField)
        .tint(.white)
        .focused($searchFocused)
        .onSubmit(activateSelection)
    }

    @ViewBuilder
    private func content(
        apps: [AppEntry], clips: [ClipboardItem],
        emojiSections: [EmojiGridSection], uninstallItems: [LeftoverItem], calc: CalcResult?,
        selection: Int, favoriteCount: Int, showSections: Bool
    ) -> some View {
        switch vm.mode {
        case .launcher:
            let offset = calc == nil ? 0 : 1
            let calcSelected = calc != nil && selection == 0
            let appIndex = selection - offset
            let selectedID = apps.indices.contains(appIndex) ? apps[appIndex].id : nil
            LauncherList(
                results: apps,
                selectedID: calcSelected ? nil : selectedID,
                favoriteCount: favoriteCount,
                showSections: showSections,
                scrollIntent: listScroll,
                calc: calc,
                calcSelected: calcSelected,
                onActivateCalc: {
                    vm.selection = 0
                    activateSelection()
                },
                onCalcActions: {
                    guard let calc, case .value = calc.payload else { return }
                    vm.selection = 0
                    openActions()
                },
                onActivate: { core.launch($0, searchQuery: vm.query) },
                onActions: { app in
                    if let index = apps.firstIndex(of: app) { vm.selection = index + offset }
                    openActions()
                }
            )
        case .clipboard:
            // Empty history: center one message across the whole panel rather than wedging it into the narrow list column beside a blank preview.
            if clips.isEmpty {
                EmptyResults(text: "Clipboard history is empty")
            } else {
                let selected = clips.indices.contains(selection) ? clips[selection] : nil
                HStack(spacing: 0) {
                    ClipboardList(
                        results: clips,
                        selectedID: selected?.id,
                        scrollIntent: listScroll,
                        onSelect: { item in vm.selection = clips.firstIndex(of: item) ?? 0 },
                        onActivate: activateSelection,
                        onActions: { item in
                            if let index = clips.firstIndex(of: item) { vm.selection = index }
                            openActions()
                        }
                    )
                    .frame(width: Theme.Size.clipboardListWidth)
                    Rectangle()
                        .fill(Theme.Colors.separator)
                        .frame(width: 1)
                    ClipboardPreview(item: selected)
                }
            }
        case .emoji:
            if !emojiIndex.isLoaded {
                EmptyResults(text: "Loading emoji…")
            } else if emojiSections.isEmpty {
                EmptyResults(text: "No emoji found")
            } else {
                EmojiGridView(
                    sections: emojiSections,
                    selection: selection,
                    tone: settings.emojiSkinTone,
                    scroll: emojiScroll,
                    onSelect: { vm.selection = $0 },
                    onActivate: activateSelection,
                    onActions: { flat in
                        vm.selection = flat
                        openActions()
                    }
                )
            }
        case .uninstall:
            switch uninstall.phase {
            case .removing(let permanently):
                UninstallProgressView(
                    name: uninstall.target?.name ?? "Application", permanently: permanently)
            case .done(let outcome):
                UninstallSummaryView(
                    name: uninstall.target?.name ?? "Application", outcome: outcome)
            case .selecting:
                if uninstall.items.isEmpty {
                    EmptyResults(
                        text: uninstall.isScanning ? "Looking for files to remove…" : "Nothing found to remove")
                } else if uninstallItems.isEmpty {
                    EmptyResults(text: "No files match")
                } else {
                    VStack(spacing: 0) {
                        UninstallStatusLine(
                            checkedCount: uninstall.checkedItems.count,
                            totalCount: uninstall.items.count,
                            checkedSize: uninstall.checkedSize
                        )
                        UninstallList(
                            items: uninstallItems,
                            selection: selection,
                            isChecked: uninstall.isChecked,
                            appIcon: uninstall.target.flatMap { IconCache.cached(forFile: $0.url.path) },
                            scroll: listScroll ?? ListScrollIntent(kind: .top),
                            onSelect: { vm.selection = $0 },
                            onToggle: { uninstall.toggle(uninstallItems[$0]) },
                            onActions: { index in
                                vm.selection = index
                                openActions()
                            }
                        )
                    }
                }
            }
        }
    }

    private func bottomBar(pillLabel: String, showActionGroup: Bool) -> some View {
        // No bar — just floating glass controls over the list; the edge dissolve ghosts rows passing beneath, so the buttons read clearly without a hard-edged strip.
        HStack(spacing: 0) {
            if vm.mode == .uninstall, let target = uninstall.target {
                UninstallContextPill(
                    name: target.name,
                    icon: IconCache.cached(forFile: target.url.path)
                )
            } else {
                footerMenuButton
            }
            Spacer()
            if showActionGroup {
                actionGroup(
                    pillLabel: pillLabel,
                    destructive: vm.mode == .uninstall && uninstall.phase == .selecting,
                    showActionsToggle: vm.mode != .uninstall || uninstall.phase == .selecting
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
        .animation(Self.feedbackAnimation, value: vm.feedback?.id)
    }

    @ViewBuilder
    private var footerMenuButton: some View {
        if let feedback = vm.feedback {
            PaletteFeedbackButton(message: feedback.message)
        } else if vm.mode == .launcher {
            MenuCircleButton(action: toggleAppMenu)
        } else {
            PaletteModeMenuButton(mode: vm.mode, action: toggleAppMenu)
        }
    }

    /// The footer control group: primary action and the Actions toggle sharing one glass capsule.
    private func actionGroup(
        pillLabel: String, destructive: Bool = false, showActionsToggle: Bool = true
    ) -> some View {
        HStack(spacing: 2) {
            PaletteBarButton(action: activateSelection) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(pillLabel)
                        .font(Theme.Typography.bar)
                        .foregroundStyle(destructive ? Color.red : Theme.Colors.textPrimary)
                    KeyCapChip(text: "↵", style: .outline)
                }
            }
            if showActionsToggle {
                PaletteBarButton(action: toggleActions) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Actions")
                            .font(Theme.Typography.bar)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        HStack(spacing: Theme.Spacing.xxs) {
                            KeyCapChip(text: "⌘", style: .outline)
                            KeyCapChip(text: "K", style: .outline)
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.xs)
        .frosted(in: Capsule())
    }

    /// Pill label for the current selection, derived from the selection already resolved in `body` so it never re-runs the (unmemoized) `appResults` filter/sort.
    private func actionPillLabel(selectedApp: AppEntry?, calcActionable: Bool) -> String {
        switch vm.mode {
        case .clipboard, .emoji:
            return vm.pasteTarget?.pasteTitle ?? "Paste"
        case .launcher:
            if calcActionable { return "Copy Answer" }
            switch selectedApp?.kind {
            case .systemSettings: return "Open System Setting"
            case .command:
                return selectedApp.flatMap { SystemCommandCatalog.command(forEntryID: $0.id) } == nil
                    ? "Open Command" : "Run Command"
            default: return "Open Application"
            }
        case .uninstall:
            switch uninstall.phase {
            case .selecting: return uninstall.checkedItems.isEmpty ? "Nothing Checked" : "Uninstall Application"
            case .removing: return "Removing…"
            case .done: return "Back to Search"
            }
        }
    }

    private func showsActionGroup(count: Int, calcBlocked: Bool) -> Bool {
        if vm.mode == .uninstall {
            switch uninstall.phase {
            case .selecting: return count > 0
            case .removing: return false
            case .done: return true
            }
        }
        return count > 0 && !calcBlocked
    }

    private func toggleFavorite(_ app: AppEntry) {
        let added = !favorites.isFavorite(app)
        favorites.toggle(app)
        showFeedback(added ? "Added to favorites" : "Removed from favorites")
    }

    private func showFeedback(_ message: String) {
        withAnimation(Self.feedbackAnimation) {
            vm.postFeedback(message)
        }
    }

    /// The single path that opens the Actions menu: samples the state its rows depend on, then shows it. Callers set `vm.selection` first, so the sample matches the row the menu is for.
    private func openActions() {
        // Only the launcher's menu carries a Quit row, so the other modes skip the (unmemoized) `appResults` walk entirely.
        if vm.mode == .launcher, let app = selectedAppEntry {
            selectionIsRunning = core.runningApps.isRunning(app)
        } else {
            selectionIsRunning = false
        }
        guard actionsContent != nil else { return }
        withAnimation(Self.menuAnimation) {
            showAppMenu = false
            showSortMenu = false
            menuSelection = 0
            showActions = true
        }
    }

    private func toggleActions() {
        if showActions {
            withAnimation(Self.menuAnimation) { showActions = false }
        } else {
            openActions()
        }
    }

    private func toggleAppMenu() {
        withAnimation(Self.menuAnimation) {
            let opening = !showAppMenu
            showActions = false
            showSortMenu = false
            menuSelection = 0
            showAppMenu = opening
        }
    }

    private func toggleSortMenu() {
        withAnimation(Self.menuAnimation) {
            let opening = !showSortMenu
            showActions = false
            showAppMenu = false
            menuSelection = 0
            showSortMenu = opening
        }
    }

    private func closeMenus() {
        withAnimation(Self.menuAnimation) {
            showActions = false
            showAppMenu = false
            showSortMenu = false
        }
    }

    /// Inset of the menu panels from the window's bottom corners, kept just inside the rounded corner so the menu's own corner isn't clipped.
    private static let menuInset: CGFloat = 8
    private static let menuAnimation: Animation = .easeOut(duration: 0.14)
    private static let feedbackAnimation: Animation = .easeOut(duration: 0.14)

    private static func menuTransition(_ anchor: UnitPoint) -> AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: anchor))
    }

    private func deleteSelectedClip() {
        guard clipResults.indices.contains(selection) else { return }
        core.deleteClipboardEntry(clipResults[selection])
        showFeedback("Deleted entry")
    }

    // MARK: - Actions

    private func move(_ delta: Int) {
        guard resultCount > 0 else { return }
        let nextSelection = min(max(selection + delta, 0), resultCount - 1)
        vm.selection = nextSelection
        let kind: ListScrollIntent.Kind = delta < 0 && nextSelection == 0 ? .top : .follow
        listScroll = ListScrollIntent(kind: kind)
        emojiScroll = EmojiScrollIntent(kind: .follow)
    }

    /// Move the open menu's highlight, clamped at the ends (no wrap — consistent with `move`).
    private func moveMenu(_ delta: Int) {
        guard let count = menuContent?.items.count, count > 0 else { return }
        menuSelection = min(max(menuSelection + delta, 0), count - 1)
    }

    /// The single activation path for a menu row, shared by a click and Return: run the row's action, then close.
    private func activateMenuItem(_ index: Int) {
        guard let items = menuContent?.items, items.indices.contains(index) else { return }
        items[index].action()
        closeMenus()
    }

    /// Vertical grid move: one visual row within a section, spilling into the neighbor while keeping the column.
    private func moveEmojiRow(_ delta: Int) {
        let geometry = EmojiGridGeometry(
            counts: emojiSections.map(\.entries.count), columns: EmojiGrid.columns)
        guard resultCount > 0 else { return }
        vm.selection = delta > 0 ? geometry.down(from: selection) : geometry.up(from: selection)
        emojiScroll = EmojiScrollIntent(kind: .follow)
    }

    /// Tab flips between the launcher and clipboard.
    private func toggleMode() {
        vm.mode = vm.mode == .launcher ? .clipboard : .launcher
    }

    /// Back out to a fresh root search — `prepare` is the same reset used when the palette is shown (clears query/selection, bumps focusToken to refocus the field).
    private func exitToLauncher() {
        if vm.mode == .uninstall {
            core.exitUninstall()
            return
        }
        vm.prepare(mode: .launcher)
    }

    private func activateSelection() {
        // Nothing is visibly selected in the collapsed compact bar; launch only via ⌘1–⌘5 or by typing.
        guard !isCollapsed else { return }
        switch vm.mode {
        case .launcher:
            if let calcResult, selection == 0 {
                // Error cards no-op — copyCalculatorResult only acts on value payloads.
                core.copyCalculatorResult(calcResult)
                return
            }
            let index = selection - calcCount
            guard appResults.indices.contains(index) else { return }
            core.launch(appResults[index], searchQuery: vm.query)
        case .clipboard:
            guard clipResults.indices.contains(selection) else { return }
            core.paste(clipResults[selection])
        case .emoji:
            guard emojiResults.indices.contains(selection) else { return }
            core.pasteEmoji(emojiResults[selection])
        case .uninstall:
            switch uninstall.phase {
            case .selecting: core.confirmUninstall()
            case .removing: break
            case .done: core.finishUninstall()
            }
        }
    }
}

struct PaletteFeedbackButton: View {
    let message: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Theme.Colors.feedbackAccent.opacity(0.34),
                                Theme.Colors.feedbackAccent.opacity(0.12),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: Theme.Size.feedbackHalo / 2
                        )
                    )
                Circle()
                    .fill(Theme.Colors.feedbackAccent)
                    .frame(width: Theme.Spacing.sm, height: Theme.Spacing.sm)
            }
            .frame(width: Theme.Size.feedbackHalo, height: Theme.Size.feedbackHalo)
            Text(message)
                .font(Theme.Typography.bar)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.leading, Theme.Spacing.xl)
        .padding(.trailing, Theme.Spacing.xxl)
        .frame(height: Theme.Size.menuButton)
        .background {
            Capsule()
                .fill(Theme.Colors.feedbackShade)
                .overlay {
                    Capsule().fill(Theme.Colors.feedbackFill)
                }
                .overlay {
                    Capsule().strokeBorder(Theme.Colors.feedbackStroke, lineWidth: 1)
                }
        }
        .allowsHitTesting(false)
    }
}

/// Change key for the clipboard list's follow-the-moved-row handler: the newest stored clip (a capture or promote puts a different row there) plus the token an action bumps when it reorders the list (pin/unpin). Deliberately read from the store, not the filtered results, so typing a query never reads as a row that moved.
private struct ClipFollowKey: Equatable {
    let id: ClipboardItem.ID?
    let token: UUID
}

/// The active sub-screen label in the footer; it opens the same app menu as the root footer button.
private struct PaletteModeMenuButton: View {
    let mode: PaletteMode
    let action: () -> Void
    @State private var hovered = false

    private var iconTint: Color {
        switch mode {
        case .launcher: return Theme.Colors.launcherAccent
        case .clipboard: return Theme.Colors.clipboardAccent
        case .emoji: return Theme.Colors.emojiAccent
        case .uninstall: return Theme.Colors.textSecondary
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                FeatureIcon(
                    systemImage: mode.systemImage,
                    tint: iconTint,
                    size: Theme.Size.rowIcon
                )
                Text(mode.title)
                    .font(Theme.Typography.calloutMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Size.menuButton)
            .contentShape(Capsule())
            .background(
                Capsule().fill(hovered ? Theme.Colors.rowHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hovered = hovering
            if hovering { NSCursor.arrow.set() }
        }
        .frosted(in: Capsule())
    }
}

/// The footer's glass menu circle; hover lives here so a mouse sweep never re-renders the palette body.
private struct MenuCircleButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Capsule().frame(width: 14, height: 1.5)
                Capsule().frame(width: 8, height: 1.5)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(width: Theme.Size.menuButton, height: Theme.Size.menuButton)
            .background(Circle().fill(hovered ? Theme.Colors.rowHover : Color.clear))
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Circle())
    }
}

extension View {
    /// Faint mouse-hover highlight for a palette row, lit only while the pointer is physically moving (`hoverHighlightArmed`) so it never fires on open or when rows slide under a still pointer during keyboard nav. Independent of the keyboard selection, so both coexist.
    func armedHover(_ hovered: Binding<Bool>) -> some View {
        onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active: hovered.wrappedValue = AppCore.shared.palette.hoverHighlightArmed
            case .ended: hovered.wrappedValue = false
            }
        }
    }
}

struct EmptyResults: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(Theme.Typography.largeTitle)
                .symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A slot in the compact bar's favorites strip: a launchable app, or the "…" overflow that expands the window.
enum CompactFavoriteSlot {
    case app(AppEntry)
    case more

    // Stable identity so a slot keeps its icon tied to its app, not its position, when favorites reorder.
    var id: String {
        switch self {
        case .app(let app): return app.id
        case .more: return "__bettercast.more__"
        }
    }
}

/// The compact bar's favorites strip — up to 5 icon buttons, ⌘1–⌘5 mirrored in each tooltip.
private struct CompactFavoritesRow: View {
    let slots: [CompactFavoriteSlot]
    let onLaunch: (AppEntry) -> Void
    let onOverflow: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                switch slot {
                case .app(let app):
                    CompactFavoriteButton(
                        title: app.name, shortcutIndex: index + 1, action: { onLaunch(app) }
                    ) {
                        AppIconView(app: app)
                            .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                    }
                case .more:
                    CompactFavoriteButton(
                        title: "Show all", shortcutIndex: index + 1, action: onOverflow
                    ) {
                        Image(systemName: "ellipsis")
                            .font(Theme.Typography.iconTiny)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.Colors.controlSurface)
                                    .padding(Theme.Spacing.xxs)
                            )
                    }
                }
            }
        }
    }
}

/// A single compact favorite icon with a custom tooltip and its position-based shortcut.
private struct CompactFavoriteButton<Content: View>: View {
    let title: String
    let shortcutIndex: Int
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            content
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hovered = hovering
            if hovering { NSCursor.arrow.set() }
        }
        .background {
            CompactFavoriteTooltipPresenter(
                isPresented: hovered, title: title, shortcutIndex: shortcutIndex
            )
        }
    }
}

private struct CompactFavoriteTooltip: View {
    let title: String
    let shortcutIndex: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.xl) {
            Text(title)
                .font(Theme.Typography.headlineSemibold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            HStack(spacing: Theme.Spacing.xxs) {
                KeyCapChip(text: "⌘")
                KeyCapChip(text: "\(shortcutIndex)")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
                .fill(Theme.Colors.tooltipSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
                        .strokeBorder(Theme.Colors.border, lineWidth: 1)
                }
        }
        .fixedSize()
    }
}

private struct CompactFavoriteTooltipPresenter: NSViewRepresentable {
    let isPresented: Bool
    let title: String
    let shortcutIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(title: title, shortcutIndex: shortcutIndex)
    }

    func makeNSView(context: Context) -> NSView {
        TooltipAnchorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isPresented = isPresented
        context.coordinator.title = title
        context.coordinator.shortcutIndex = shortcutIndex
        if isPresented {
            DispatchQueue.main.async { context.coordinator.present(from: nsView) }
        } else {
            context.coordinator.dismiss()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    @MainActor final class Coordinator: NSObject {
        var isPresented = false
        var title: String
        var shortcutIndex: Int
        private let panel: NSPanel
        private let host: NSHostingView<CompactFavoriteTooltip>

        init(title: String, shortcutIndex: Int) {
            self.title = title
            self.shortcutIndex = shortcutIndex
            host = NSHostingView(
                rootView: CompactFavoriteTooltip(title: title, shortcutIndex: shortcutIndex))
            panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            super.init()
            panel.contentView = host
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
        }

        func present(from anchor: NSView) {
            guard isPresented, anchor.window != nil else { return }
            host.rootView = CompactFavoriteTooltip(title: title, shortcutIndex: shortcutIndex)
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            guard size.width > 0, size.height > 0,
                let screen = anchor.window?.screen ?? NSScreen.main
            else { return }
            let anchorRect = anchor.window!.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let visible = screen.visibleFrame
            let gap = Theme.Spacing.sm
            var origin = NSPoint(
                x: anchorRect.midX - size.width / 2,
                y: anchorRect.maxY + gap
            )
            if origin.y + size.height > visible.maxY {
                origin.y = anchorRect.minY - size.height - gap
            }
            origin.x = min(max(origin.x, visible.minX + gap), visible.maxX - size.width - gap)
            panel.setFrame(NSRect(origin: origin, size: size), display: false)
            panel.orderFrontRegardless()
        }

        func dismiss() {
            panel.orderOut(nil)
        }
    }

    private final class TooltipAnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
