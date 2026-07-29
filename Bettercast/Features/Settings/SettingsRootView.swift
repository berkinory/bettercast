import AppKit
import SwiftUI

extension Notification.Name {
    /// Navigates an already-open Settings window without rebuilding its SwiftUI tree.
    static let bettercastSelectSettingsRoute = Notification.Name("BettercastSelectSettingsRoute")
}

struct SettingsRoute: Hashable, Sendable {
    let tab: SettingsTab
    var destination: SettingsDestination? = nil

    static let general = SettingsRoute(tab: .general)
    static let about = SettingsRoute(tab: .about)
}

enum SettingsTab: Int, CaseIterable, Identifiable, Sendable {
    case general, launcher, clipboard, emoji, calculator, shortcuts, permissions, about

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .launcher: return "Launcher"
        case .clipboard: return "Clipboard"
        case .emoji: return "Emoji & Symbols"
        case .calculator: return "Calculator"
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
        case .emoji: return "face.smiling"
        case .calculator: return "function"
        case .shortcuts: return "keyboard"
        case .permissions: return "checkmark.shield"
        case .about: return "info.circle"
        }
    }

    var group: SettingsGroup {
        switch self {
        case .general: return .app
        case .launcher, .clipboard, .emoji, .calculator: return .features
        case .shortcuts, .permissions: return .system
        case .about: return .about
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .launcher: return .blue
        case .clipboard: return .orange
        case .emoji: return .yellow
        case .calculator: return .green
        case .shortcuts: return Theme.Colors.brand
        case .permissions: return .green
        case .about: return .pink
        }
    }
}

enum SettingsGroup: String, CaseIterable, Identifiable, Sendable {
    case app, features, system, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: return "Bettercast"
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
    }

    func moveSearchSelection(by offset: Int, ids: [String]) {
        guard !ids.isEmpty else { return }
        let current = selectedSearchResultID.flatMap { ids.firstIndex(of: $0) } ?? 0
        selectedSearchResultID = ids[min(max(current + offset, 0), ids.count - 1)]
    }
}

struct SettingsRootView: View {
    @EnvironmentObject private var appIndex: AppIndex
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
        SettingsSearchCatalog.staticItems + SettingsSearchCatalog.dynamicItems(from: appIndex.apps)
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
        .onReceive(NotificationCenter.default.publisher(for: .bettercastSelectSettingsRoute)) {
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
        .background(
            VisualEffectView(material: .contentBackground, blending: .behindWindow)
                .ignoresSafeArea()
        )
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
        case .emoji: EmojiSettingsView()
        case .calculator: CalculatorSettingsView()
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

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Settings.Layout.groupSpacing) {
                    ForEach(sidebarGroups) { section in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(section.group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, Theme.Spacing.lg)

                            ForEach(section.tabs) { item in
                                sidebarRow(item)
                            }
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
            }
            .overlayScroller()
        }
        .padding(.top, Theme.Settings.Layout.sidebarTopInset)
        .frame(width: Theme.Settings.Size.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(
            ZStack(alignment: .trailing) {
                VisualEffectView(material: .sidebar, blending: .behindWindow)
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isFocused.wrappedValue ? Theme.Colors.brand : .secondary)
            TextField("Search settings", text: $query, onCommit: onActivate)
                .textFieldStyle(.plain)
                .font(.callout)
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
                        .font(.system(size: 12))
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
        .shadow(
            color: isFocused.wrappedValue ? Theme.Colors.brand.opacity(0.14) : .clear,
            radius: 8
        )
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                RoundedRectangle(
                    cornerRadius: Theme.Settings.Radius.iconTile,
                    style: .continuous
                )
                .fill(tint.opacity(isSelected ? 0.22 : 0.12))
                .frame(
                    width: Theme.Settings.Size.sidebarIcon,
                    height: Theme.Settings.Size.sidebarIcon
                )
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tint)
                )

                Text(title)
                    .font(.body.weight(isSelected ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Settings.Size.sidebarRowHeight)
            .background(selectionBackground)
            .overlay(selectionStroke)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsNavigationButtonStyle())
        .settingsFocusRing(cornerRadius: Theme.Settings.Radius.navigation)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        let shape = RoundedRectangle(
            cornerRadius: Theme.Settings.Radius.navigation,
            style: .continuous
        )
        if isSelected {
            shape.fill(Theme.Settings.Colors.navigationSelection)
        } else if hovering {
            shape.fill(Theme.Settings.Colors.navigationHover)
        }
    }

    private var selectionStroke: some View {
        RoundedRectangle(
            cornerRadius: Theme.Settings.Radius.navigation,
            style: .continuous
        )
        .strokeBorder(
            isSelected ? Theme.Settings.Colors.navigationSelectionStroke : .clear,
            lineWidth: 1
        )
    }
}

private struct SettingsNavigationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}
