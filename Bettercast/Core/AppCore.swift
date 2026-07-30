import AppKit
import SwiftUI

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case emoji

    var id: String { rawValue }
    var title: String {
        switch self {
        case .launcher: return "Apps"
        case .clipboard: return "Clipboard History"
        case .emoji: return "Emoji & Symbols"
        }
    }
    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.clipboard"
        case .emoji: return "face.smiling"
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return "Search for apps and commands…"
        case .clipboard: return "Type to filter entries…"
        case .emoji: return "Search emoji and symbols…"
        }
    }
}

/// The app a paste will land in, resolved once per palette show so the footer pill and menu rows can name it without re-reading `NSWorkspace` on every render.
struct PaletteFeedback: Equatable, Identifiable {
    let id = UUID()
    let message: String
}

struct PasteTarget: Equatable {
    let name: String
    /// Bundle path for `IconCache` — nil for a target with no on-disk bundle.
    let iconPath: String?

    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    var pasteTitle: String { "Paste to \(name)" }
}

/// View-model shared between the panel's SwiftUI tree and the coordinator.
@MainActor
final class PaletteViewModel: ObservableObject {
    @Published var mode: PaletteMode = .launcher
    @Published var query: String = ""
    @Published var selection: Int = 0
    /// Changes every time the palette is shown so the search field can re-focus.
    @Published var focusToken = UUID()
    /// Changes only when `prepare` resets the palette, so the lists snap their scroll to the top even when query/mode were already at their defaults (`focusToken` can't serve: it bumps on every reopen, which must preserve a within-timeout scroll).
    @Published var resetToken = UUID()
    @Published var feedback: PaletteFeedback?
    /// Changes when an action reorders the list under the selection (pinning a clip lifts it into the Pinned section), so the list scrolls the highlight back into view.
    @Published var followToken = UUID()
    /// Set by the compact bar's "…" overflow to expand into the full launcher without a query; cleared on every `prepare`.
    @Published var forceExpanded = false
    /// The app a paste would land in, mirrored from `PaletteWindowController.previousApp` on every show. Deliberately *not* cleared by `prepare` — pop-to-root resets the screen, not the paste target.
    @Published var pasteTarget: PasteTarget?
    /// Gates the mouse-hover highlight: true only while the pointer is physically moving (armed on `.mouseMoved`, disarmed on any `.keyDown` in `PalettePanel.sendEvent`). Plain, not `@Published` — read at hover time, never drives a re-render.
    var hoverHighlightArmed = false
    /// True while a footer popover menu (⌘K Actions or the app menu) is open, so `PalettePanel.sendEvent` swallows text-editing keystrokes the field editor would otherwise consume — the query must stay frozen while a menu owns the keyboard (matches Raycast). Plain, not `@Published` — read at event time, mirrored from the view's menu state.
    var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    /// Fired when `menuOpen` flips so `PalettePanel` can hide/show the search field's caret while it keeps first-responder status (no focus swap, so the placeholder never reflows).
    var onMenuOpenChanged: ((Bool) -> Void)?

    func prepare(mode: PaletteMode) {
        self.mode = mode
        query = ""
        selection = 0
        forceExpanded = false
        hoverHighlightArmed = false
        menuOpen = false
        focusToken = UUID()
        resetToken = UUID()
    }

    func postFeedback(_ message: String) {
        feedback = PaletteFeedback(message: message)
    }
}

/// Single owner of every long-lived manager. Wired up once from the app delegate.
@MainActor
final class AppCore: ObservableObject {
    static let shared = AppCore()

    let launcherRanking: LauncherRankingStore
    let appIndex: AppIndex
    let clipboardStore = ClipboardStore()
    let clipboardManager: ClipboardManager
    let hotKeys = HotKeyManager()
    let settings = AppSettings()
    let favorites = FavoritesStore()
    let visibility = VisibilityStore()
    let currencyRates = CurrencyRateStore()
    let emojiIndex = EmojiIndex()
    let frequentEmoji = FrequentEmojiStore()
    let runningApps = RunningAppsMonitor()
    let appUninstaller = AppUninstaller()
    let palette = PaletteViewModel()

    private lazy var windowController = PaletteWindowController(core: self)
    private let auxWindows = AuxWindowController()

    private init() {
        let launcherRanking = LauncherRankingStore()
        self.launcherRanking = launcherRanking
        appIndex = AppIndex(ranking: launcherRanking)
        clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
    }

    func start() {
        // AppKit's default tooltip delay is ~2–3s; shorten it (in ms) so the compact-bar favorite tooltips appear promptly. Registration domain — never overrides a user default.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
        NSApp.setActivationPolicy(.accessory)
        // Force dark: the Liquid Glass material is tuned for a deep dark surface and renders washed-out in Light mode.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        clipboardStore.maxAge = settings.clipboardRetention.maxAge
        // Defer the initial SQLite read + stale-image prune off the synchronous launch path so the menu bar is interactive immediately; `items` is @Published, so the palette fills in when it lands.
        Task { clipboardStore.load() }
        clipboardManager.start()

        Task { await appIndex.refresh() }
        Task { await emojiIndex.load() }
        if settings.currencyConversionEnabled {
            currencyRates.start(cryptoEnabled: settings.cryptoConversionEnabled)
        }

        hotKeys.onTogglePalette = { [weak self] in self?.togglePalette() }
        hotKeys.onToggleClipboard = { [weak self] in self?.toggleClipboard() }
        hotKeys.onToggleEmoji = { [weak self] in self?.toggleEmoji() }
        hotKeys.start()

        // First launch has no palette hotkey bound and shows nothing but the menu-bar icon; guide the user once. Marker is written at show-time so it stays one-time even if they Cmd-Q mid-flow.
        if !OnboardingState.hasOnboarded {
            OnboardingState.markShown()
            showOnboarding()
        }
    }

    // MARK: - Palette control

    func togglePalette() {
        if windowController.isVisible, palette.mode == .launcher {
            hidePalette()
        } else {
            showPalette(mode: .launcher, restoreAnyMode: true)
        }
    }

    func toggleClipboard() {
        if windowController.isVisible, palette.mode == .clipboard {
            hidePalette()
        } else {
            showPalette(mode: .clipboard)
        }
    }

    func toggleEmoji() {
        if windowController.isVisible, palette.mode == .emoji {
            hidePalette()
        } else {
            showPalette(mode: .emoji)
        }
    }

    /// Shows the palette, honoring Pop to Root Search: a reopen within the timeout restores the pre-close state — any mode for the generic summon (`restoreAnyMode`), else only when the preserved mode already matches the requested one.
    func showPalette(mode: PaletteMode, restoreAnyMode: Bool = false) {
        let preserved = windowController.consumePreservedState()
        if !(preserved && (restoreAnyMode || palette.mode == mode)) {
            palette.prepare(mode: mode)
        }
        windowController.show()
        // Re-scan on open so an app uninstalled since the last scan drops out of the launcher.
        if palette.mode == .launcher { Task { await appIndex.refresh() } }
    }

    func hidePalette(restoreFocus: Bool = true) {
        windowController.hide(restoreFocus: restoreFocus)
    }

    func handlePaletteEscape() {
        if !palette.query.isEmpty {
            palette.query = ""
            palette.selection = 0
            return
        }
        if palette.mode != .launcher {
            palette.prepare(mode: .launcher)
            return
        }
        hidePalette()
    }

    /// True when the palette should render as the slim compact bar: compact mode on, launcher root, empty query, and not force-expanded via the "…" overflow.
    var paletteIsCollapsed: Bool {
        settings.compactMode
            && !palette.forceExpanded
            && palette.mode == .launcher
            && palette.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The compact bar's "…" overflow: expand into the full favorites-pinned launcher without typing.
    func expandFromCompact() {
        palette.forceExpanded = true
    }

    /// Resize the panel to match the current collapsed state; called by the view when `paletteIsCollapsed` flips while open.
    func syncPaletteSize() {
        windowController.applyCollapsed(paletteIsCollapsed)
    }

    /// Dock-icon / reopen: focus an open aux window (About/Settings/Onboarding), else summon the launcher. Decoupled from the individual show paths so activation always works.
    func handleReopen() {
        if auxWindows.focusExisting() { return }
        showPalette(mode: .launcher, restoreAnyMode: true)
    }

    /// Settings runs in its own window (the SwiftUI `Settings` scene is unreliable for accessory apps). A fresh window mounts directly on its route; an already-open one navigates in place.
    func showSettings(route: SettingsRoute = .general) {
        let isNew = auxWindows.show(
            id: "settings", title: "Settings", size: Theme.Settings.Size.window,
            seamlessTitleBar: true, transparentBackground: true
        ) {
            SettingsRootView(initialRoute: route)
                .environmentObject(self.appIndex)
                .environmentObject(self.visibility)
        }
        if !isNew {
            NotificationCenter.default.post(name: .bettercastSelectSettingsRoute, object: route)
        }
    }

    func showAbout() {
        showSettings(route: .about)
    }

    /// The first-run wizard: palette shortcut and Accessibility. Also re-runnable from Settings.
    func showOnboarding() {
        auxWindows.show(
            id: "onboarding", title: "Welcome to Bettercast",
            size: OnboardingView.windowSize, seamlessTitleBar: true
        ) {
            OnboardingView()
        }
    }

    /// Final onboarding step: close the wizard and drop straight into the launcher.
    func finishOnboarding() {
        auxWindows.close(id: "onboarding")
        showPalette(mode: .launcher)
    }

    // MARK: - Actions invoked from the palette UI

    func launch(_ app: AppEntry, searchQuery: String? = nil) {
        // Every palette launch teaches weak global usage; typed launches additionally teach the submitted query and each of its prefixes.
        launcherRanking.record(itemKey: app.preferenceKey, query: searchQuery ?? "")
        // Commands dispatch before the palette hides: mode-switching commands keep it open.
        if app.kind == .command {
            runCommand(app)
            return
        }
        hidePalette(restoreFocus: false)
        switch app.kind {
        case .application:
            AppLauncher.launch(app.url)
        case .systemSettings:
            guard let bundleID = app.bundleID else { return }
            AppLauncher.openSettingsPane(bundleID: bundleID)
        case .command:
            break  // handled above
        }
    }

    func resetRanking(for app: AppEntry) {
        launcherRanking.reset(itemKey: app.preferenceKey)
    }

    /// Quits the app behind an entry; a no-op (palette stays put) when it isn't running.
    func uninstall(_ app: AppEntry) {
        guard AppUninstaller.isEligible(app) else { return }
        Task { [weak self] in
            guard let self else { return }
            let plan = await appUninstaller.plan(for: app)
            guard confirmUninstall(plan) else { return }

            if runningApps.isRunning(app) {
                _ = AppLauncher.quit(bundleID: app.bundleID ?? "")
                for _ in 0..<20 {
                    try? await Task.sleep(for: .milliseconds(100))
                    if !runningApps.isRunning(app) { break }
                }
                guard !runningApps.isRunning(app) else {
                    showUninstallFailure("\(app.name) is still running. Nothing was removed.")
                    return
                }
            }

            let result = await appUninstaller.execute(plan)
            guard result.appFailure == nil else {
                showUninstallFailure(result.appFailure ?? "Could not uninstall \(app.name).")
                return
            }
            if favorites.isFavorite(app) { favorites.toggle(app) }
            launcherRanking.reset(itemKey: app.preferenceKey)
            visibility.setItemVisible(true, for: app)
            if let action = app.hotKeyAction { hotKeys.setShortcut(nil, for: action) }
            palette.postFeedback("Moved \(app.name) to Trash")
            Task { await appIndex.refresh() }
            if !result.failedPaths.isEmpty {
                let count = result.failedPaths.count
                showUninstallFailure(
                    "The application was moved to the Trash, but \(count) related \(count == 1 ? "item" : "items") could not be moved."
                )
            }
        }
    }

    private func confirmUninstall(_ plan: AppUninstallPlan) -> Bool {
        let userCount = plan.userCandidates.count
        let systemCount = plan.systemCandidates.count
        var details =
            "This will move the application and its related user data to the Trash. You can restore them before emptying it."
        if userCount == 0 {
            details += "\n\nNo related user files were found."
        } else {
            let itemLabel = userCount == 1 ? "related item" : "related items"
            let categories = Set(plan.userCandidates.map(\.category)).sorted().joined(separator: ", ")
            details += "\n\nFound \(userCount) \(itemLabel): \(categories)."
        }
        if systemCount > 0 {
            let itemLabel = systemCount == 1 ? "item" : "items"
            details +=
                "\n\n\(systemCount) system \(itemLabel) will stay untouched because administrator access is required."
        }
        let totalBytes = ([plan.appSize] + plan.userCandidates.map(\.size)).compactMap { $0 }.reduce(0, +)
        if totalBytes > 0 {
            details += "\n\nTotal size: \(uninstallSizeText(totalBytes))"
        }
        return windowController.presentConfirmation(
            message: "Move \(plan.app.name) to Trash?",
            informativeText: details,
            confirmTitle: "Move to Trash"
        )
    }

    private func uninstallSizeText(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes < 10 {
            return String(format: "%.1f MB", megabytes)
        }
        return String(format: "%.0f MB", megabytes)
    }

    private func showUninstallFailure(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Uninstall Incomplete"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Quits the app behind an entry; a no-op (palette stays put) when it isn't running.
    func quit(_ app: AppEntry) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        // Unlike `launch`, nothing here takes focus on its own — hand it back to where the user was, unless that's the app now on its way out.
        let quittingPreviousApp = windowController.previousApp?.bundleIdentifier == bundleID
        guard AppLauncher.quit(bundleID: bundleID) else { return }
        hidePalette(restoreFocus: !quittingPreviousApp)
    }

    /// Quit All: the one action whose blast radius reaches outside Bettercast, so it confirms first. The target list is resolved once and both counted and terminated, so the set the user approves is the set that quits.
    private func quitAllApps() {
        let targets = AppLauncher.quitAllTargets()
        guard !targets.isEmpty, confirmQuitAll(count: targets.count) else { return }
        for app in targets { app.terminate() }
    }

    private func confirmQuitAll(count: Int) -> Bool {
        return windowController.presentConfirmation(
            message: count == 1 ? "Quit 1 application?" : "Quit \(count) applications?",
            informativeText: "Applications with unsaved changes will ask you to save.",
            confirmTitle: "Quit All"
        )
    }

    private func runCommand(_ entry: AppEntry) {
        switch CommandRegistry.command(for: entry) {
        case .clipboardHistory:
            showPalette(mode: .clipboard)
        case .searchEmoji:
            showPalette(mode: .emoji)
        case .settings:
            hidePalette(restoreFocus: false)
            showSettings()
        case .quitAllApps:
            quitAllApps()
        case .quit:
            NSApp.terminate(nil)
        case nil:
            break
        }
    }

    /// Enter on the inline calculator card: copy the answer and dismiss.
    func copyCalculatorResult(_ result: CalcResult) {
        guard case .value(_, let copyText) = result.payload else { return }
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(copyText)
    }

    func showInFinder(_ app: AppEntry) {
        hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(app.url)
    }

    func copyPath(_ app: AppEntry) {
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(app.url.path)
    }

    func paste(_ item: ClipboardItem) {
        let previous = windowController.previousApp
        hidePalette(restoreFocus: false)
        // A successful write promotes the item to the head of its section; follow it so any preserved (pop-to-root) or open clipboard state highlights the row that moved.
        if Paster.paste(item, store: clipboardStore, previousApp: previous) {
            selectClip(item)
        }
    }

    func pasteKeepingWindowOpen(_ item: ClipboardItem) {
        if windowController.pasteKeepingWindowOpen(item, store: clipboardStore) {
            selectClip(item)
        }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        hidePalette(restoreFocus: false)
        if Paster.copy(item, store: clipboardStore) {
            selectClip(item)
        }
    }

    func revealClipboardImage(_ item: ClipboardItem) {
        guard let url = clipboardStore.imageURL(for: item) else { return }
        hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(url)
    }

    /// Pin or unpin a clipboard entry: the row jumps into (or out of) the Pinned section at the top, so the selection and the scroll follow it.
    func togglePinnedClip(_ item: ClipboardItem) {
        clipboardStore.togglePinned(item)
        selectClip(item)
        palette.followToken = UUID()
    }

    func deleteClipboardEntry(_ item: ClipboardItem) {
        clipboardStore.remove(item)
    }

    func confirmAndDeleteAllClipboardEntries(onConfirmed: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            windowController.confirmDeleteAllClipboardEntries { [weak self] in
                self?.clipboardStore.clearAll()
                onConfirmed()
            }
        }
    }

    /// Put the selection on `item`'s row in the list as currently filtered — pinned rows hold the top, so a row that moved isn't always index 0.
    private func selectClip(_ item: ClipboardItem) {
        palette.selection = clipboardStore.rowIndex(of: item, in: palette.query) ?? 0
    }

    // MARK: - Emoji actions (frequency is tallied on the base glyph; the configured tone is applied at copy time)

    func pasteEmoji(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        let previous = windowController.previousApp
        hidePalette(restoreFocus: false)
        Paster.pasteString(entry.display(tone: settings.emojiSkinTone), previousApp: previous)
    }

    func copyEmoji(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        hidePalette(restoreFocus: false)
        Paster.copyString(entry.display(tone: settings.emojiSkinTone))
    }

    func pasteEmojiKeepingWindowOpen(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        windowController.pasteStringKeepingWindowOpen(entry.display(tone: settings.emojiSkinTone))
    }
}
