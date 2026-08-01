import SwiftUI

struct LauncherList: View {
    let results: [AppEntry]
    let selectedID: AppEntry.ID?
    let favoriteCount: Int
    let showSections: Bool
    /// Present only when the list should follow selection or return to its origin.
    let scrollIntent: ListScrollIntent?
    /// Inline calculator answer; occupies flat selection index 0 when present (requires a non-empty query, so it never coexists with the sectioned view).
    var calc: CalcResult?
    var calcSelected = false
    var onActivateCalc: () -> Void = {}
    var onCalcActions: () -> Void = {}
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    @EnvironmentObject private var runningApps: RunningAppsMonitor

    private nonisolated static let calcRowID = "calc-card"

    private enum Row: Identifiable {
        case header(String)
        case calc(CalcResult)
        case app(AppEntry)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .calc: return LauncherList.calcRowID
            case .app(let app): return app.id
            }
        }
    }

    private var rows: [Row] {
        var calcRows: [Row] = []
        if let calc { calcRows = [.header("Calculator"), .calc(calc)] }
        guard showSections else {
            guard !results.isEmpty else { return calcRows }
            return calcRows + [.header("Results")] + results.map(Row.app)
        }
        var rows: [Row] = calcRows
        let favorites = results.prefix(favoriteCount)
        let rest = results.dropFirst(favoriteCount)
        // `rest` is apps-then-panes-then-commands by the AppIndex invariant, so filtering by kind keeps row order identical and the flat selection index valid.
        let apps = rest.filter { $0.kind == .application }
        let panes = rest.filter { $0.kind == .systemSettings }
        let commands = rest.filter { $0.kind == .command }
        for (title, group) in [
            ("Favorites", Array(favorites)), ("Applications", apps),
            ("System Settings", panes), ("Commands", commands),
        ]
        where !group.isEmpty {
            rows.append(.header(title))
            rows.append(contentsOf: group.map(Row.app))
        }
        return rows
    }

    var body: some View {
        let rows = rows
        return Group {
            if results.isEmpty && calc == nil {
                EmptyResults(text: "No apps found")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            LazyVStack(spacing: 0) {
                                ForEach(rows) { row in
                                    switch row {
                                    case .header(let title):
                                        SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                                    case .calc(let result):
                                        CalculatorCard(result: result, selected: calcSelected)
                                            .contentShape(Rectangle())
                                            .onTapGesture(perform: onActivateCalc)
                                            .onRightClick(perform: onCalcActions)
                                            .padding(.bottom, Theme.Spacing.xs)
                                    case .app(let app):
                                        AppRow(
                                            app: app,
                                            selected: app.id == selectedID,
                                            running: runningApps.isRunning(app)
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture { onActivate(app) }
                                        .onRightClick { onActions(app) }
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.top, Theme.Spacing.xs)
                            .padding(.bottom, Theme.Spacing.md)
                        }
                        .hideNativeScrollers()
                        .resetNativeScrollToTop(
                            id: scrollIntent?.kind == .top ? scrollIntent?.id : nil
                        )
                    }
                    .edgeDissolve()
                    .thinScrollbar()
                    .task(id: scrollIntent) {
                        guard let scrollIntent, scrollIntent.kind == .follow else { return }
                        if calcSelected {
                            proxy.scrollTo(Self.calcRowID)
                        } else if let selectedID {
                            proxy.scrollTo(selectedID)
                        }
                    }
                }
            }
        }
    }
}

/// Section label above a group of rows, shared by every palette list so they use one identical header + row layout.
struct SectionHeader: View {
    let title: String
    /// The list's first header hugs the top; every later header gets `sectionSpacing` above it, which reads as bottom padding on the section that just ended.
    var isFirst = false
    var firstTopPadding: CGFloat? = nil
    var body: some View {
        Text(title)
            .font(Theme.Typography.sectionHeader)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(
                .top,
                isFirst ? (firstTopPadding ?? Theme.Spacing.xs) : Theme.Spacing.sectionSpacing
            )
            .padding(.bottom, Theme.Spacing.sectionHeaderBottom)
    }
}

private struct AppRow: View {
    let app: AppEntry
    let selected: Bool
    let running: Bool
    /// Observed so a hotkey set/cleared in Settings re-renders the row's keycaps immediately.
    @EnvironmentObject private var hotKeys: HotKeyManager
    @State private var hovered = false

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// Keycaps for this entry's hotkey, or `nil` if none is bound.
    private var shortcutCaps: [String]? {
        guard let action = app.hotKeyAction,
            let binding = hotKeys.binding(for: action)
        else { return nil }
        return binding.keycaps
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            AppIconView(app: app)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                .overlay(alignment: .bottom) {
                    if running {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 3, height: 3)
                            .offset(y: 3)
                    }
                }
            Text(app.name)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            if let caps = shortcutCaps {
                HStack(spacing: Theme.Spacing.xxs) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
            Spacer()
            Text(app.kindLabel)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}

/// Row icon that decodes off the main thread (mirrors `ImageThumbnail`), so surfacing new apps while typing never rasterizes on-main during render. Warm icons seed synchronously so there's no placeholder flash on re-open.
struct AppIconView: View {
    let app: AppEntry
    @State private var image: NSImage?

    init(app: AppEntry) {
        self.app = app
        _image = State(initialValue: app.isSymbolIcon ? nil : IconCache.cached(forFile: app.url.path))
    }

    private var iconTint: Color {
        switch CommandRegistry.command(for: app) {
        case .searchEmoji: return Theme.Colors.emojiAccent
        case .clipboardHistory: return Theme.Colors.clipboardAccent
        case .searchSnippets, .createSnippet: return Theme.Colors.systemAccent
        case .settings: return Theme.Colors.systemAccent
        case .checkForUpdates: return Theme.Colors.systemAccent
        case .quit: return Theme.Colors.textSecondary
        case nil: return Theme.Colors.textPrimary
        }
    }

    var body: some View {
        Group {
            if CommandRegistry.command(for: app) == .searchEmoji {
                FeatureIcon(
                    emoji: "😀",
                    tint: Theme.Colors.emojiAccent,
                    size: Theme.Size.rowIcon
                )
            } else if app.isSymbolIcon {
                FeatureIcon(
                    systemImage: app.symbolIconName,
                    tint: iconTint,
                    size: Theme.Size.rowIcon
                )
            } else if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.imagePlaceholder)
            }
        }
        .task(id: app.id) {
            guard !app.isSymbolIcon, image == nil else { return }
            image = await IconCache.loadAsync(forFile: app.url.path)
        }
    }
}

/// Actions menu content for a launcher app, shown bottom-right on right-click or from the Actions pill.
@MainActor
enum AppActionsMenu {
    static func content(
        app: AppEntry, searchQuery: String, core: AppCore, favorites: FavoritesStore,
        running: Bool, onResetRanking: @escaping () -> Void, onToggleFavorite: @escaping () -> Void
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: openTitle(app), systemImage: "list.bullet.rectangle", shortcut: "↵"
            ) { core.launch(app, searchQuery: searchQuery) }
        ]
        if favorites.isFavorite(app) {
            items.append(
                PopoverMenuItem(
                    title: "Remove from Favorites", systemImage: "star.slash", shortcut: "⌘F"
                ) {
                    onToggleFavorite()
                })
        } else {
            items.append(
                PopoverMenuItem(title: "Add to Favorites", systemImage: "star", shortcut: "⌘F") {
                    onToggleFavorite()
                })
        }
        if core.launcherRanking.hasRanking(for: app.preferenceKey) {
            items.append(
                PopoverMenuItem(title: "Reset Ranking", systemImage: "arrow.counterclockwise") {
                    onResetRanking()
                })
        }
        if app.kind == .application {
            items.append(
                PopoverMenuItem(title: "Copy Path", systemImage: "doc.on.doc", shortcut: "⌘⇧C") {
                    core.copyPath(app)
                })
        }
        if app.kind == .application || app.kind == .systemSettings {
            items.append(
                PopoverMenuItem(title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵") {
                    core.showInFinder(app)
                })
        }
        if app.kind == .application,
            app.url.standardizedFileURL.path != Bundle.main.bundleURL.standardizedFileURL.path,
            AppLeftovers.canUninstall(url: app.url, bundleID: app.bundleID)
        {
            items.append(
                PopoverMenuItem(
                    title: "Uninstall Application", systemImage: "trash", shortcut: "⌃⌫", isDestructive: true
                ) {
                    core.beginUninstall(app)
                })
        }
        if running, app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: "Quit Application", systemImage: "power", isDestructive: true
                ) {
                    core.quit(app)
                })
        }
        return PopoverMenuContent(header: app.name, items: items)
    }

    private static func openTitle(_ app: AppEntry) -> String {
        switch app.kind {
        case .application: return "Open Application"
        case .systemSettings: return "Open System Setting"
        case .command:
            return SystemCommandCatalog.command(forEntryID: app.id) == nil
                ? "Open Command" : "Run Command"
        }
    }
}
