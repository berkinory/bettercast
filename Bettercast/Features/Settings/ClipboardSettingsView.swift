import AppKit
import SwiftUI

struct ClipboardSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @State private var confirmingClear = false
    @State private var showingAppPicker = false

    var body: some View {
        SettingsPane(
            title: "Clipboard",
            subtitle: "Control retention and which apps are recorded.",
            systemImage: "doc.on.clipboard",
            tint: .orange
        ) {
            SettingsSection(header: "Shortcut") {
                SettingsControlRow(
                    title: "Clipboard History",
                    subtitle: "Open saved text and images from anywhere.",
                    systemImage: "keyboard",
                    tint: .orange,
                    destination: .clipboardShortcut
                ) {
                    ShortcutRecorder(action: .toggleClipboard)
                }
            }

            SettingsSection(header: "History") {
                SettingsControlRow(
                    title: "Keep history for",
                    subtitle: "Older entries are deleted automatically.",
                    systemImage: "clock.arrow.circlepath",
                    tint: .orange,
                    destination: .clipboardRetention
                ) {
                    Picker("", selection: $settings.clipboardRetention) {
                        ForEach(ClipboardRetention.allCases) { retention in
                            Text(retention.title).tag(retention)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: settings.clipboardRetention) {
                        let store = AppCore.shared.clipboardStore
                        store.maxAge = settings.clipboardRetention.maxAge
                        store.enforceLimits()
                    }
                }
            }

            SettingsSection(
                header: "Excluded Applications",
                destination: .clipboardExcludedApps
            ) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if settings.clipboardDisabledApps.isEmpty {
                        Text("Clipboard changes from every app are recorded.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(
                                    .adaptive(
                                        minimum: Theme.Settings.Size.excludedAppChipMinimum
                                    ),
                                    spacing: Theme.Spacing.md
                                )
                            ],
                            spacing: Theme.Spacing.md
                        ) {
                            ForEach(settings.clipboardDisabledApps, id: \.self) { bundleID in
                                ExcludedAppChip(bundleID: bundleID) {
                                    settings.clipboardDisabledApps.removeAll { $0 == bundleID }
                                }
                            }
                        }
                    }

                    Button {
                        showingAppPicker = true
                    } label: {
                        Label("Add Application…", systemImage: "plus")
                            .font(Theme.Typography.captionSemibold)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showingAppPicker, arrowEdge: .bottom) {
                        AppPickerPopover(excluded: Set(settings.clipboardDisabledApps)) { bundleID in
                            settings.clipboardDisabledApps.append(bundleID)
                            showingAppPicker = false
                        }
                    }
                }
                .padding(Theme.Settings.Layout.rowHorizontal)
            }

            SettingsStatusCard(
                title: "Clear clipboard history",
                message: "Permanently remove every saved clip and image.",
                systemImage: "trash",
                tint: .red
            ) {
                Button("Clear…", role: .destructive) { confirmingClear = true }
                    .controlSize(.small)
            }
            .settingsDestination(.clipboardClearHistory)
        }
        .confirmationDialog(
            "Clear clipboard history?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                AppCore.shared.clipboardStore.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}

private struct ExcludedAppChip: View {
    let bundleID: String
    let onRemove: () -> Void

    @EnvironmentObject private var appIndex: AppIndex
    @State private var hovering = false

    var body: some View {
        let (name, icon) = resolve()
        HStack(spacing: Theme.Spacing.md) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
            Text(name)
                .font(Theme.Typography.captionMedium)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(Theme.Typography.iconSmall)
                    .foregroundStyle(.tertiary)
                    .frame(
                        width: Theme.Settings.Size.visibilityButton,
                        height: Theme.Settings.Size.visibilityButton
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .settingsFocusRing(cornerRadius: Theme.Settings.Radius.controlIcon)
            .opacity(hovering ? 1 : 0.55)
            .help("Remove \(name)")
            .accessibilityLabel("Remove \(name)")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Settings.Size.excludedAppChipHeight)
        .background(
            RoundedRectangle(
                cornerRadius: Theme.Settings.Radius.controlIcon,
                style: .continuous
            )
            .fill(Theme.Settings.Colors.searchFill)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: Theme.Settings.Radius.controlIcon,
                style: .continuous
            )
            .strokeBorder(Theme.Settings.Colors.searchStroke, lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }

    private func resolve() -> (String, NSImage) {
        if let app = appIndex.apps.first(where: { $0.bundleID == bundleID }) {
            return (app.name, app.icon)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return (
                url.deletingPathExtension().lastPathComponent,
                IconCache.icon(forFile: url.path)
            )
        }
        return (bundleID, NSWorkspace.shared.icon(for: .applicationBundle))
    }
}

private struct AppPickerPopover: View {
    let excluded: Set<String>
    let onSelect: (String) -> Void

    @EnvironmentObject private var appIndex: AppIndex
    @State private var query = ""
    @FocusState private var queryFocused: Bool

    private var candidates: [AppEntry] {
        (query.isEmpty ? appIndex.apps : appIndex.matches(query))
            .filter { $0.kind == .application }
            .filter { $0.bundleID.map { !excluded.contains($0) } ?? false }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search applications", text: $query)
                    .textFieldStyle(.plain)
                    .focused($queryFocused)
            }
            .padding(Theme.Spacing.lg)

            Rectangle()
                .fill(Theme.Settings.Colors.rowDivider)
                .frame(height: 1)

            ScrollView {
                LazyVStack(spacing: Theme.Spacing.xxs) {
                    ForEach(candidates) { app in
                        Button {
                            if let id = app.bundleID { onSelect(id) }
                        } label: {
                            HStack(spacing: Theme.Spacing.lg) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 22, height: 22)
                                Text(app.name)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .settingsFocusRing(cornerRadius: Theme.Radius.row)
                    }
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity)
            }
            .overlay {
                if candidates.isEmpty {
                    Text(query.isEmpty ? "No applications available." : "No matching applications.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .overlayScroller(disablesElasticity: true)
        }
        .frame(width: 280, height: 320)
        .onAppear { queryFocused = true }
    }
}
