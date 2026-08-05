import SwiftUI

private enum LauncherItemCategory: String, CaseIterable, Identifiable {
    case applications
    case systemSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applications: return "Applications"
        case .systemSettings: return "System Settings"
        }
    }

    var kind: AppEntry.Kind {
        switch self {
        case .applications: return .application
        case .systemSettings: return .systemSettings
        }
    }
}

struct LauncherItemsSettingsSection: View {
    @EnvironmentObject private var appIndex: AppIndex
    @State private var category: LauncherItemCategory = .applications

    private var entries: [AppEntry] {
        appIndex.apps.filter { $0.kind == category.kind }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SettingsSectionLabel(
                title: "Launcher items",
                subtitle: "Choose what appears and assign optional shortcuts.",
                systemImage: "square.grid.2x2",
                tint: Theme.Colors.launcherAccent
            )

            Picker("Category", selection: $category) {
                ForEach(LauncherItemCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            SettingsEntryList(
                kind: category.kind,
                entries: entries
            )
            .id(category.rawValue)
        }
    }
}

struct CommandsSettingsView: View {
    @EnvironmentObject private var appIndex: AppIndex

    private let featureCommandIDs = Set([
        CommandID.clipboardHistory.rawValue,
        CommandID.searchSnippets.rawValue,
        CommandID.createSnippet.rawValue,
        CommandID.searchQuicklinks.rawValue,
        CommandID.createQuicklink.rawValue,
        CommandID.searchEmoji.rawValue,
    ])

    private var entries: [AppEntry] {
        appIndex.apps.filter {
            $0.kind == .command
                && !featureCommandIDs.contains($0.id)
                && WindowCommandCatalog.command(forEntryID: $0.id) == nil
        }
    }

    var body: some View {
        SettingsPane(
            title: "Commands",
            subtitle: "Control launcher commands and assign shortcuts where useful.",
            systemImage: "terminal",
            tint: Theme.Colors.systemAccent
        ) {
            SettingsEntryList(
                kind: .command,
                entries: entries
            )
        }
    }
}

struct FeatureCommandsSettingsSection: View {
    let commandIDs: [CommandID]
    var tint: Color = Theme.Colors.systemAccent

    private var entries: [AppEntry] {
        commandIDs.compactMap { id in CommandRegistry.all.first { $0.id == id.rawValue } }
    }

    var body: some View {
        SettingsSection(
            header: "Commands",
            subtitle: "Assign shortcuts or hide individual launcher actions.",
            systemImage: "command",
            tint: tint
        ) {
            SettingsEntryRows(entries: entries)
        }
    }
}

struct WindowCommandsSettingsSection: View {
    private var entries: [AppEntry] {
        WindowCommandCatalog.all.map { command in
            AppEntry(
                id: command.entryID,
                name: command.name,
                url: URL(string: "opencast://window-command/" + command.id.rawValue)!,
                bundleID: nil,
                kind: .command
            )
        }
    }

    var body: some View {
        SettingsSection(
            header: "Window commands",
            subtitle: "Assign shortcuts or hide individual window actions.",
            systemImage: "macwindow.on.rectangle",
            tint: Theme.Colors.launcherAccent
        ) {
            SettingsEntryRows(entries: entries)
        }
    }
}

private struct SettingsEntryList: View {
    let kind: AppEntry.Kind
    let entries: [AppEntry]

    @EnvironmentObject private var visibility: VisibilityStore

    var body: some View {
        let kindVisible = visibility.isKindVisible(kind)
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text(kindControlTitle)
                    .font(Theme.Typography.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Toggle(kindControlTitle, isOn: kindBinding)
                    .settingsToggle()
            }
            .padding(.horizontal, Theme.Spacing.xs)

            SettingsSection {
                if entries.isEmpty {
                    Text("Nothing here yet.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xl)
                } else {
                    SettingsEntryRows(entries: entries)
                }
            }
            .opacity(kindVisible ? 1 : 0.45)
        }
    }

    private var kindControlTitle: String {
        switch kind {
        case .application: return "Show applications in launcher"
        case .systemSettings: return "Show System Settings in launcher"
        case .command: return "Show commands in launcher"
        }
    }

    private var kindBinding: Binding<Bool> {
        Binding(
            get: { visibility.isKindVisible(kind) },
            set: { visibility.setKindVisible($0, for: kind) }
        )
    }
}

private struct SettingsEntryRows: View {
    let entries: [AppEntry]

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(entries) { entry in
                SettingsEntryRow(entry: entry)
                if entry.id != entries.last?.id { SettingsRowDivider() }
            }
        }
    }
}

private struct SettingsEntryRow: View {
    let entry: AppEntry

    @EnvironmentObject private var visibility: VisibilityStore
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            AppIconView(app: entry)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            Text(entry.name)
                .font(Theme.Typography.calloutMedium)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.md)
            if let action = entry.hotKeyAction {
                ShortcutRecorder(action: action)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: Theme.Settings.Size.shortcutColumn, alignment: .leading)
            }
            VisibilityToggle(label: entry.name, isVisible: itemBinding)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(hovered ? Theme.Colors.rowHover : .clear)
        )
        .onHover { hovered = $0 }
        .settingsDestination(.shortcutEntry(entryID: entry.id, kind: entry.kind.rawValue))
    }

    private var itemBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) }
        )
    }
}

private struct VisibilityToggle: View {
    let label: String
    @Binding var isVisible: Bool

    var body: some View {
        Toggle("Show \(label)", isOn: $isVisible)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Theme.Colors.textSecondary)
            .frame(width: Theme.Settings.Size.visibilityButton)
            .help(isVisible ? "Hide from launcher" : "Show in launcher")
    }
}
