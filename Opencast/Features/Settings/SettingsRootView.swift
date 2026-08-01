import AppKit
import SwiftUI

extension Notification.Name {
    /// Navigates an already-open Settings window without rebuilding its SwiftUI tree.
    static let opencastSelectSettingsRoute = Notification.Name("OpencastSelectSettingsRoute")
}

struct SettingsRoute: Hashable, Sendable {
    let tab: SettingsTab
    var destination: SettingsDestination? = nil

    static let general = SettingsRoute(tab: .general)
    static let about = SettingsRoute(tab: .about)
}

enum SettingsTab: Int, CaseIterable, Identifiable, Sendable {
    case general, launcher, clipboard, snippets, emoji, calculator, windowManagement, shortcuts, permissions, about

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .launcher: return "Launcher"
        case .clipboard: return "Clipboard"
        case .snippets: return "Snippets"
        case .emoji: return "Emoji & Symbols"
        case .calculator: return "Calculator"
        case .windowManagement: return "Window Management"
        case .shortcuts: return "Shortcuts"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.clipboard"
        case .snippets: return "text.quote"
        case .emoji: return "face.smiling"
        case .calculator: return "function"
        case .windowManagement: return "macwindow"
        case .shortcuts: return "keyboard"
        case .permissions: return "lock.shield.fill"
        case .about: return "info.circle.fill"
        }
    }

    var emoji: String? {
        self == .emoji ? "😀" : nil
    }

    var group: SettingsGroup {
        switch self {
        case .general: return .app
        case .launcher, .clipboard, .snippets, .emoji, .calculator, .windowManagement: return .features
        case .shortcuts, .permissions: return .system
        case .about: return .about
        }
    }

    var tint: Color {
        switch self {
        case .general: return Theme.Colors.generalAccent
        case .launcher: return Theme.Colors.launcherAccent
        case .clipboard: return Theme.Colors.clipboardAccent
        case .snippets: return Theme.Colors.systemAccent
        case .emoji: return Theme.Colors.emojiAccent
        case .calculator: return Theme.Colors.calculatorAccent
        case .windowManagement: return Theme.Colors.launcherAccent
        case .shortcuts, .permissions: return Theme.Colors.systemAccent
        case .about: return Theme.Colors.brand
        }
    }
}

enum SettingsGroup: String, CaseIterable, Identifiable, Sendable {
    case app, features, system, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: return "Opencast"
        case .features: return "Features"
        case .system: return "System"
        case .about: return "About"
        }
    }

    var tabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0.group == self }
    }
}

@MainActor
private final class SettingsNavigationModel: ObservableObject {
    @Published var route: SettingsRoute
    @Published var searchQuery = ""
    @Published var selectedSearchResultID: String?
    @Published var searchScrollToken = UUID()

    init(route: SettingsRoute) {
        self.route = route
    }

    func navigate(to route: SettingsRoute) {
        searchQuery = ""
        selectedSearchResultID = nil
        self.route = route
    }

    func select(_ tab: SettingsTab) {
        navigate(to: SettingsRoute(tab: tab))
    }

    func reconcileSearchSelection(with ids: [String]) {
        selectedSearchResultID = ids.first
        searchScrollToken = UUID()
    }

    func moveSearchSelection(by offset: Int, ids: [String]) {
        guard !ids.isEmpty else { return }
        let current = selectedSearchResultID.flatMap { ids.firstIndex(of: $0) } ?? 0
        selectedSearchResultID = ids[min(max(current + offset, 0), ids.count - 1)]
        searchScrollToken = UUID()
    }
}

struct SettingsRootView: View {
    @StateObject private var navigation: SettingsNavigationModel
    @FocusState private var searchFocused: Bool

    private struct SidebarGroup: Identifiable {
        let group: SettingsGroup
        let tabs: [SettingsTab]
        var id: String { group.id }
    }

    init(initialRoute: SettingsRoute = .general) {
        _navigation = StateObject(wrappedValue: SettingsNavigationModel(route: initialRoute))
    }

    private var sidebarGroups: [SidebarGroup] {
        SettingsGroup.allCases.map { SidebarGroup(group: $0, tabs: $0.tabs) }
    }

    private var isSearching: Bool {
        !navigation.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchItems: [SettingsSearchItem] {
        SettingsSearchCatalog.staticItems
    }

    private var searchResults: [SettingsSearchItem] {
        let items = searchItems
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return SettingsSearchIndex.search(
            navigation.searchQuery,
            in: items.map(\.record)
        ).compactMap { itemsByID[$0.record.id] }
    }

    private var searchResultIDs: [String] { searchResults.map(\.id) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.panelSurface.ignoresSafeArea())
        .background(VisualEffectView().ignoresSafeArea())
        .tint(Theme.Colors.textSecondary)
        .onReceive(NotificationCenter.default.publisher(for: .opencastSelectSettingsRoute)) {
            note in
            guard let route = note.object as? SettingsRoute else { return }
            navigation.navigate(to: route)
        }
        .onChange(of: searchResultIDs, initial: true) { _, ids in
            navigation.reconcileSearchSelection(with: ids)
        }
        .onKeyPress(keys: ["f"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            searchFocused = true
            return .handled
        }
    }

    private var content: some View {
        ZStack {
            if isSearching {
                SettingsSearchView(
                    query: navigation.searchQuery,
                    items: searchResults,
                    selectedID: navigation.selectedSearchResultID,
                    scrollToken: navigation.searchScrollToken,
                    onSelect: { navigation.selectedSearchResultID = $0 },
                    onActivate: activateSearchResult
                )
            } else {
                pane(for: navigation.route.tab)
                    .environment(\.settingsDestination, navigation.route.destination)
                    .id(navigation.route.tab)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activateSearchResult(_ item: SettingsSearchItem) {
        searchFocused = false
        navigation.navigate(to: item.route)
    }

    private func activateSelectedSearchResult() {
        let selected = navigation.selectedSearchResultID.flatMap { id in
            searchResults.first { $0.id == id }
        }
        guard let item = selected ?? searchResults.first else { return }
        activateSearchResult(item)
    }

    @ViewBuilder
    private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettingsView()
        case .launcher: LauncherSettingsView()
        case .clipboard: ClipboardSettingsView()
        case .snippets: SnippetSettingsView()
        case .emoji: EmojiSettingsView()
        case .calculator: CalculatorSettingsView()
        case .windowManagement: WindowManagementSettingsView()
        case .shortcuts: ShortcutsSettingsView()
        case .permissions: PermissionsSettingsView()
        case .about: AboutView()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSearchField(
                query: $navigation.searchQuery,
                isFocused: $searchFocused,
                onMove: {
                    navigation.moveSearchSelection(by: $0, ids: searchResultIDs)
                },
                onActivate: activateSelectedSearchResult,
                onCancel: { navigation.searchQuery = "" }
            )
            .padding(.horizontal, Theme.Settings.Layout.sidebarInset)

            VStack(alignment: .leading, spacing: Theme.Settings.Layout.groupSpacing) {
                ForEach(sidebarGroups) { section in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(section.group.title)
                            .font(Theme.Typography.caption2Medium)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, Theme.Spacing.lg)

                        ForEach(section.tabs) { item in
                            sidebarRow(item)
                                .padding(.horizontal, Theme.Settings.Layout.sidebarInset)
                        }
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.xxl)

            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Settings.Layout.sidebarTopInset)
        .frame(width: Theme.Settings.Size.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(
            ZStack(alignment: .trailing) {
                Theme.Settings.Colors.sidebarDimming
                Rectangle()
                    .fill(Theme.Settings.Colors.sidebarSeparator)
                    .frame(width: 1)
            }
            .ignoresSafeArea()
        )
    }

    private func sidebarRow(_ item: SettingsTab) -> some View {
        SidebarRow(
            title: item.title,
            systemImage: item.systemImage,
            emoji: item.emoji,
            tint: item.tint,
            isSelected: navigation.route.tab == item
        ) {
            searchFocused = false
            navigation.select(item)
        }
    }
}

private struct SidebarSearchField: View {
    @Binding var query: String
    var isFocused: FocusState<Bool>.Binding
    let onMove: (Int) -> Void
    let onActivate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: Theme.Settings.Radius.search,
            style: .continuous
        )

        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.iconMedium)
                .foregroundStyle(isFocused.wrappedValue ? .primary : .secondary)
            TextField("Search settings", text: $query, onCommit: onActivate)
                .textFieldStyle(.plain)
                .font(Theme.Typography.callout)
                .focused(isFocused)
                .onCommand(#selector(NSResponder.moveDown(_:))) { onMove(1) }
                .onCommand(#selector(NSResponder.moveUp(_:))) { onMove(-1) }
                .onCommand(#selector(NSResponder.cancelOperation(_:))) {
                    if query.isEmpty {
                        isFocused.wrappedValue = false
                    } else {
                        onCancel()
                    }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.Typography.iconSmall)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .settingsFocusRing(cornerRadius: Theme.Settings.Radius.controlIcon)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: Theme.Settings.Size.searchHeight)
        .background(shape.fill(Theme.Settings.Colors.searchFill))
        .overlay(
            shape.strokeBorder(
                isFocused.wrappedValue
                    ? Theme.Settings.Colors.searchFocus : Theme.Settings.Colors.searchStroke,
                lineWidth: 1
            )
        )
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let emoji: String?
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.lg) {
                if let emoji {
                    FeatureIcon(
                        emoji: emoji,
                        tint: isSelected ? tint : tint.opacity(0.72),
                        size: Theme.Size.rowIcon
                    )
                } else {
                    FeatureIcon(
                        systemImage: systemImage,
                        tint: isSelected ? tint : tint.opacity(0.72),
                        size: Theme.Size.rowIcon
                    )
                }

                Text(title)
                    .font(Theme.Typography.callout.weight(isSelected ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: Theme.Settings.Size.sidebarRowHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: Theme.Settings.Radius.navigation,
                    style: .continuous
                )
                .fill(rowFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .opacity(focused ? 1 : 0.96)
        .onHover { hovering = $0 }
    }

    private var rowFill: Color {
        if isSelected { return Theme.Settings.Colors.navigationSelection }
        if hovering || focused { return Theme.Settings.Colors.navigationHover }
        return .clear
    }
}
