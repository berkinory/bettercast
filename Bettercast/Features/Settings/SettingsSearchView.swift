import SwiftUI

enum SettingsDestination: Hashable, Sendable {
    case launcherShortcut
    case searchScopes
    case learnedRanking
    case compactMode
    case compactFavorites
    case launchAtLogin
    case showInMenuBar
    case appearance
    case returnToLauncher
    case welcomeGuide
    case clipboardShortcut
    case clipboardRetention
    case clipboardExcludedApps
    case clipboardClearHistory
    case emojiShortcut
    case emojiSkinTone
    case accessibility
    case currencyConversion
    case cryptoConversion
    case exchangeRates
    case shortcutEntry(entryID: String, kind: String)

    var anchorID: String {
        switch self {
        case .launcherShortcut: return "launcher-shortcut"
        case .searchScopes: return "search-scopes"
        case .learnedRanking: return "learned-ranking"
        case .compactMode: return "compact-mode"
        case .compactFavorites: return "compact-favorites"
        case .launchAtLogin: return "launch-at-login"
        case .showInMenuBar: return "show-in-menu-bar"
        case .appearance: return "appearance"
        case .returnToLauncher: return "return-to-launcher"
        case .welcomeGuide: return "welcome-guide"
        case .clipboardShortcut: return "clipboard-shortcut"
        case .clipboardRetention: return "clipboard-retention"
        case .clipboardExcludedApps: return "clipboard-excluded-apps"
        case .clipboardClearHistory: return "clipboard-clear-history"
        case .emojiShortcut: return "emoji-shortcut"
        case .emojiSkinTone: return "emoji-skin-tone"
        case .accessibility: return "accessibility"
        case .currencyConversion: return "currency-conversion"
        case .cryptoConversion: return "crypto-conversion"
        case .exchangeRates: return "exchange-rates"
        case .shortcutEntry(let entryID, _): return "shortcut-entry:\(entryID)"
        }
    }
}

enum SettingsSearchIcon {
    case symbol(String)
    case emoji(String)
}

struct SettingsSearchItem: Identifiable {
    let record: SettingsSearchRecord
    let route: SettingsRoute
    let icon: SettingsSearchIcon
    let tint: Color

    var id: String { record.id }
}

@MainActor
enum SettingsSearchCatalog {
    static let staticItems: [SettingsSearchItem] = [
        pane(.general, detail: "Startup, menu bar, and setup."),
        pane(.launcher, detail: "Launcher shortcut, appearance, and behavior."),
        pane(.clipboard, detail: "History retention and excluded applications."),
        pane(.emoji, detail: "Emoji shortcut and preferred skin tone."),
        pane(.calculator, detail: "Inline calculations and currency conversion."),
        pane(.shortcuts, detail: "Application visibility and shortcuts."),
        pane(.permissions, detail: "Access Bettercast needs to work with other apps."),
        pane(.about, detail: "Version, support, and project links."),
        item(
            .launcherShortcut, tab: .launcher, title: "App Launcher Shortcut",
            detail: "Open the fuzzy app launcher.", section: "Shortcut",
            keywords: ["hotkey", "keyboard", "open", "summon"], image: "magnifyingglass",
            tint: .blue
        ),
        item(
            .searchScopes, tab: .launcher, title: "Search Scopes",
            detail: "Choose folders and applications included in the launcher.", section: "Search",
            keywords: ["apps", "folders", "directories", "index", "locations"],
            image: "folder.badge.gearshape", tint: .blue
        ),
        item(
            .learnedRanking, tab: .launcher, title: "Learned Ranking",
            detail: "Reset privately learned search result ordering.", section: "Behavior",
            keywords: ["personalized", "results", "reset", "relearn"],
            image: "chart.line.uptrend.xyaxis", tint: .blue
        ),
        item(
            .compactMode, tab: .launcher, title: "Compact Mode",
            detail: "Open Bettercast as a slim search bar.", section: "Appearance",
            keywords: ["launcher", "small", "collapsed", "search bar"], image: "macwindow",
            tint: .blue
        ),
        item(
            .compactFavorites, tab: .launcher, title: "Favorites in Compact Mode",
            detail: "Show favorite app icons in the compact launcher.", section: "Appearance",
            keywords: ["pinned", "apps", "command 1", "launcher"], image: "star",
            tint: .yellow
        ),
        item(
            .launchAtLogin, tab: .general, title: "Launch at Login",
            detail: "Start Bettercast when you log in.", section: "General",
            keywords: ["startup", "boot", "automatic", "login item"], image: "power",
            tint: .green
        ),
        item(
            .showInMenuBar, tab: .general, title: "Show in Menu Bar",
            detail: "Keep the Bettercast icon visible in the menu bar.", section: "General",
            keywords: ["status item", "hide icon", "menubar"],
            image: "menubar.arrow.up.rectangle", tint: .gray
        ),
        item(
            .appearance, tab: .general, title: "Appearance",
            detail: "Choose the dark or light interface.", section: "General",
            keywords: ["theme", "dark mode", "light mode", "colors", "interface"],
            image: "circle.lefthalf.filled", tint: .gray
        ),
        item(
            .returnToLauncher, tab: .launcher, title: "Return to Launcher",
            detail: "Choose when a closed palette resets to the root search.", section: "Behavior",
            keywords: ["pop to root", "timeout", "reset", "close"],
            image: "arrow.uturn.backward", tint: .indigo
        ),
        item(
            .welcomeGuide, tab: .general, title: "Welcome Guide",
            detail: "Run first-launch setup again.", section: "General",
            keywords: ["onboarding", "setup", "permissions", "tutorial"], image: "sparkles",
            tint: .yellow
        ),
        item(
            .clipboardShortcut, tab: .clipboard, title: "Clipboard History Shortcut",
            detail: "Open the clipboard history browser.", section: "Shortcut",
            keywords: ["hotkey", "keyboard", "paste"], image: "doc.on.clipboard",
            tint: .orange
        ),
        item(
            .clipboardRetention, tab: .clipboard, title: "Keep Clipboard History For",
            detail: "Choose when old clipboard entries are deleted.", section: "History",
            keywords: ["retention", "delete", "days", "months", "forever"],
            image: "clock.arrow.circlepath", tint: .orange
        ),
        item(
            .clipboardExcludedApps, tab: .clipboard, title: "Excluded Applications",
            detail: "Choose apps Bettercast never records from.", section: "Privacy",
            keywords: ["disabled apps", "ignore", "password manager", "private"],
            image: "hand.raised", tint: .orange
        ),
        item(
            .clipboardClearHistory, tab: .clipboard, title: "Clear Clipboard History",
            detail: "Permanently remove saved clips and images.", section: "History",
            keywords: ["delete all", "erase", "reset"], image: "trash", tint: .red
        ),
        item(
            .emojiShortcut, tab: .emoji, title: "Emoji & Symbols Shortcut",
            detail: "Open the emoji and symbols palette.", section: "Shortcut",
            keywords: ["hotkey", "keyboard", "picker"], image: "face.smiling", tint: .yellow,
            emoji: "😀"
        ),
        item(
            .emojiSkinTone, tab: .emoji, title: "Emoji Skin Tone",
            detail: "Choose the preferred tone for supported emoji.", section: "Appearance",
            keywords: ["hand", "modifier", "color", "paste"], image: "hand.wave",
            tint: .orange, emoji: "👋"
        ),
        item(
            .accessibility, tab: .permissions, title: "Accessibility Permission",
            detail: "Allow Bettercast to paste into the previous app.", section: "Permissions",
            keywords: ["privacy", "security", "grant access", "system settings", "paste"],
            image: "accessibility", tint: .blue
        ),
        item(
            .currencyConversion, tab: .calculator, title: "Currency Conversion",
            detail: "Convert currencies inline with daily exchange rates.", section: "Currency",
            keywords: ["money", "foreign exchange", "frankfurter", "network", "yen", "usd"],
            image: "dollarsign.arrow.circlepath", tint: .green
        ),
        item(
            .cryptoConversion, tab: .calculator, title: "Crypto Conversion",
            detail: "Optionally download crypto rates from CoinGecko.", section: "Currency",
            keywords: ["bitcoin", "btc", "ethereum", "crypto", "coingecko", "network"],
            image: "bitcoinsign.circle", tint: .orange
        ),
    ]

    private static func pane(_ tab: SettingsTab, detail: String) -> SettingsSearchItem {
        SettingsSearchItem(
            record: SettingsSearchRecord(
                id: "pane:\(tab.rawValue)",
                title: tab.title,
                detail: detail,
                breadcrumb: "Settings",
                keywords: []
            ),
            route: SettingsRoute(tab: tab),
            icon: tab.emoji.map(SettingsSearchIcon.emoji) ?? .symbol(tab.systemImage),
            tint: tab.tint
        )
    }

    private static func item(
        _ destination: SettingsDestination,
        tab: SettingsTab,
        title: String,
        detail: String,
        section: String,
        keywords: [String],
        image: String,
        tint: Color,
        emoji: String? = nil,
        recordID: String? = nil,
        routeDestination: SettingsDestination? = nil
    ) -> SettingsSearchItem {
        SettingsSearchItem(
            record: SettingsSearchRecord(
                id: recordID ?? destination.anchorID,
                title: title,
                detail: detail,
                breadcrumb: "\(tab.title) › \(section)",
                keywords: keywords
            ),
            route: SettingsRoute(tab: tab, destination: routeDestination ?? destination),
            icon: emoji.map(SettingsSearchIcon.emoji) ?? .symbol(image),
            tint: tint
        )
    }
}

struct SettingsSearchView: View {
    let query: String
    let items: [SettingsSearchItem]
    let selectedID: String?
    let scrollToken: UUID
    let onSelect: (String) -> Void
    let onActivate: (SettingsSearchItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Settings.Layout.sectionSpacing) {
            SettingsFeatureHeader(
                title: "Search",
                subtitle: summary,
                systemImage: "magnifyingglass",
                tint: Theme.Colors.brand
            )

            if items.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.xs) {
                            ForEach(items) { item in
                                SettingsSearchResultRow(
                                    item: item,
                                    isSelected: selectedID == item.id
                                ) {
                                    onActivate(item)
                                }
                                .id(item.id)
                                .onHover { hovering in
                                    if hovering { onSelect(item.id) }
                                }
                            }
                        }
                        .padding(.trailing, Theme.Spacing.md)
                    }
                    .overlayScroller(disablesElasticity: true)
                    .onChange(of: scrollToken) {
                        guard let selectedID else { return }
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
        .padding(Theme.Settings.Layout.paneInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .top)
    }

    private var summary: String {
        let count = items.count
        return count == 1 ? "1 result for “\(query)”" : "\(count) results for “\(query)”"
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.emptyStateIcon)
            Text("No matches for “\(query)”")
                .font(Theme.Typography.headline)
            Text("Try a feature, setting, shortcut, or permission.")
                .font(Theme.Typography.callout)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SettingsSearchResultRow: View {
    let item: SettingsSearchItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.lg) {
                icon
                    .frame(
                        width: Theme.Settings.Size.searchResultIcon,
                        height: Theme.Settings.Size.searchResultIcon
                    )
                VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                    Text(item.record.title)
                        .font(Theme.Typography.bodyMedium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(item.record.breadcrumb)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text("·")
                        Text(item.record.detail)
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: Theme.Spacing.md)
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.captionSemibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(isSelected ? Theme.Settings.Colors.navigationSelection : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsSearchButtonStyle())
        .settingsFocusRing(cornerRadius: Theme.Radius.row)
    }

    @ViewBuilder
    private var icon: some View {
        switch item.icon {
        case .symbol(let name):
            FeatureIcon(
                systemImage: name,
                tint: item.tint,
                size: Theme.Settings.Size.searchResultIcon
            )
        case .emoji(let value):
            FeatureIcon(
                emoji: value,
                tint: item.tint,
                size: Theme.Settings.Size.searchResultIcon
            )
        }
    }
}

private struct SettingsSearchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}
