import SwiftUI

struct ShortcutsSettingsView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case items
        case hyper

        var id: String { rawValue }
        var title: String { self == .items ? "Apps & Commands" : "Hyper Key" }
    }

    @EnvironmentObject private var appIndex: AppIndex
    @Environment(\.settingsDestination) private var destination
    @State private var mode: Mode = .items
    @State private var tab: AppEntry.Kind = .application
    @State private var query = ""
    @FocusState private var itemSearchFocused: Bool

    private var entries: [AppEntry] {
        let matched = query.isEmpty ? appIndex.apps : appIndex.matches(query)
        return matched.filter { $0.kind == tab }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Settings.Layout.sectionSpacing) {
            SettingsFeatureHeader(
                title: "Shortcuts",
                subtitle: "Configure Hyper Key and launcher items.",
                systemImage: "keyboard",
                tint: Theme.Colors.brand
            )

            Picker("Shortcut type", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .items:
                itemSettings
            case .hyper:
                hyperKeySettings
            }
        }
        .padding(Theme.Settings.Layout.paneInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .top)
        .task(id: destination?.anchorID) { applyDestination() }
    }

    private var itemSettings: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Picker("Category", selection: $tab) {
                Text("Applications").tag(AppEntry.Kind.application)
                Text("System Settings").tag(AppEntry.Kind.systemSettings)
                Text("Commands").tag(AppEntry.Kind.command)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            searchField

            ShortcutTable(kind: tab, entries: entries, query: query)
                .id(tab.rawValue)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var hyperKeySettings: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HyperKeySettingsSection()
            }
            .overlayScroller()
            .task(id: destination?.anchorID) {
                guard let destination, isHyperDestination(destination) else { return }
                await Task.yield()
                proxy.scrollTo(destination.anchorID, anchor: .center)
            }
        }
    }

    private var searchPrompt: String {
        switch tab {
        case .application: return "Search applications"
        case .systemSettings: return "Search System Settings"
        case .command: return "Search commands"
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(searchPrompt, text: $query)
                .textFieldStyle(.plain)
                .focused($itemSearchFocused)
                .onExitCommand {
                    if query.isEmpty {
                        itemSearchFocused = false
                    } else {
                        query = ""
                    }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .settingsFocusRing(cornerRadius: Theme.Settings.Radius.controlIcon)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.callout)
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: Theme.Settings.Size.searchHeight)
        .background(
            RoundedRectangle(
                cornerRadius: Theme.Settings.Radius.search,
                style: .continuous
            )
            .fill(Theme.Settings.Colors.searchFill)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: Theme.Settings.Radius.search,
                style: .continuous
            )
            .strokeBorder(
                itemSearchFocused
                    ? Theme.Settings.Colors.searchFocus : Theme.Settings.Colors.searchStroke,
                lineWidth: 1
            )
        )
    }

    private func applyDestination() {
        guard let destination else { return }
        if isHyperDestination(destination) {
            mode = .hyper
            return
        }
        guard case .shortcutEntry(_, let kind) = destination else { return }
        mode = .items
        query = ""
        if let targetKind = AppEntry.Kind(rawValue: kind) { tab = targetKind }
    }

    private func isHyperDestination(_ destination: SettingsDestination) -> Bool {
        switch destination {
        case .hyperKey, .hyperQuickPress, .hyperIncludeShift, .hyperReplaceGlyph: return true
        default: return false
        }
    }
}

private struct ShortcutTable: View {
    let kind: AppEntry.Kind
    let entries: [AppEntry]
    let query: String

    @EnvironmentObject private var visibility: VisibilityStore
    @Environment(\.settingsDestination) private var destination

    var body: some View {
        let kindVisible = visibility.isKindVisible(kind)
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Label("Show category", systemImage: kindVisible ? "eye" : "eye.slash")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: kindBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Show \(kindTitle) in the launcher")
            }
            .padding(.horizontal, Theme.Spacing.xs)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.xxs) {
                        shortcutTableHeader
                        ForEach(entries) { entry in
                            ShortcutTableRow(entry: entry)
                        }
                    }
                    .padding(Theme.Spacing.sm)
                }
                .overlayScroller()
                .task(id: destination?.anchorID) {
                    guard case .shortcutEntry(let entryID, _)? = destination else { return }
                    await Task.yield()
                    proxy.scrollTo(
                        SettingsDestination.shortcutEntry(
                            entryID: entryID,
                            kind: kind.rawValue
                        ).anchorID,
                        anchor: .center
                    )
                }
            }
            .background(
                RoundedRectangle(
                    cornerRadius: Theme.Settings.Radius.surface,
                    style: .continuous
                )
                .fill(Theme.Settings.Colors.surfaceFill)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: Theme.Settings.Radius.surface,
                    style: .continuous
                )
                .strokeBorder(Theme.Settings.Colors.surfaceStroke, lineWidth: 1)
            )
            .overlay {
                if entries.isEmpty {
                    Text(query.isEmpty ? "Nothing here yet." : "No matches for “\(query)”.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(kindVisible ? 1 : 0.45)
        }
    }

    private var shortcutTableHeader: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Text("Name")
            Spacer(minLength: 0)
            Text("Shortcut")
                .frame(width: Theme.Settings.Size.shortcutColumn, alignment: .leading)
            Image(systemName: "eye")
                .frame(width: Theme.Settings.Size.visibilityButton)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var kindTitle: String {
        switch kind {
        case .application: return "applications"
        case .systemSettings: return "System Settings"
        case .command: return "commands"
        }
    }

    private var kindBinding: Binding<Bool> {
        Binding(
            get: { visibility.isKindVisible(kind) },
            set: { visibility.setKindVisible($0, for: kind) }
        )
    }
}

private struct ShortcutTableRow: View {
    let entry: AppEntry

    @EnvironmentObject private var visibility: VisibilityStore
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(nsImage: entry.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
            Text(entry.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.md)

            Group {
                if let action = entry.hotKeyAction {
                    ShortcutRecorder(action: action)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: Theme.Settings.Size.shortcutColumn, alignment: .leading)

            VisibilityButton(label: entry.name, isVisible: itemBinding)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(hovered ? Theme.Colors.rowHover : .clear)
        )
        .onHover { hovered = $0 }
        .settingsDestination(
            .shortcutEntry(entryID: entry.id, kind: entry.kind.rawValue)
        )
    }

    private var itemBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) }
        )
    }
}

private struct VisibilityButton: View {
    let label: String
    @Binding var isVisible: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            isVisible.toggle()
        } label: {
            Image(systemName: isVisible ? "eye" : "eye.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isVisible ? Color.secondary : Color.orange)
                .frame(
                    width: Theme.Settings.Size.visibilityButton,
                    height: Theme.Settings.Size.visibilityButton
                )
                .background(
                    RoundedRectangle(
                        cornerRadius: Theme.Settings.Radius.controlIcon,
                        style: .continuous
                    )
                    .fill(hovering ? Theme.Colors.rowHover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .settingsFocusRing(cornerRadius: Theme.Settings.Radius.controlIcon)
        .onHover { hovering = $0 }
        .help(isVisible ? "Hide from launcher" : "Show in launcher")
        .accessibilityLabel(
            isVisible ? "Hide \(label) from the launcher" : "Show \(label) in the launcher"
        )
        .accessibilityValue(isVisible ? "Visible" : "Hidden")
    }
}
