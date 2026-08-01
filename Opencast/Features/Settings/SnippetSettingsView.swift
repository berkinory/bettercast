import AppKit
import SwiftUI

struct SnippetSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @State private var showingAppPicker = false

    var body: some View {
        SettingsPane(
            title: "Snippets",
            subtitle: "Save and paste text you use often.",
            systemImage: "text.quote",
            tint: Theme.Colors.systemAccent
        ) {
            SettingsSection(header: "Expansion") {
                SettingsControlRow(
                    title: "Enable Snippet Expansion",
                    subtitle: "Automatically expand keywords while you type.",
                    systemImage: "text.quote",
                    tint: Theme.Colors.systemAccent,
                    destination: .snippetExpansion
                ) {
                    Toggle("", isOn: $settings.snippetExpansionEnabled)
                        .labelsHidden()
                }
            }

            SettingsSection(header: "Disabled Applications", destination: .snippetDisabledApps) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if settings.snippetDisabledApps.isEmpty {
                        Text("Snippets expand in every application.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(
                                    .adaptive(minimum: Theme.Settings.Size.excludedAppChipMinimum),
                                    spacing: Theme.Spacing.md
                                )
                            ],
                            spacing: Theme.Spacing.md
                        ) {
                            ForEach(settings.snippetDisabledApps, id: \.self) { bundleID in
                                SnippetExcludedAppChip(bundleID: bundleID) {
                                    settings.snippetDisabledApps.removeAll { $0 == bundleID }
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
                        SnippetAppPickerPopover(excluded: Set(settings.snippetDisabledApps)) { bundleID in
                            settings.snippetDisabledApps.append(bundleID)
                            showingAppPicker = false
                        }
                    }
                }
                .padding(Theme.Settings.Layout.rowHorizontal)
            }
        }
    }
}

private struct SnippetExcludedAppChip: View {
    let bundleID: String
    let onRemove: () -> Void

    @EnvironmentObject private var appIndex: AppIndex
    @State private var hovering = false

    var body: some View {
        let app = appIndex.apps.first { $0.bundleID == bundleID }
        HStack(spacing: Theme.Spacing.md) {
            Image(nsImage: app?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
            Text(app?.name ?? bundleID)
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
            .accessibilityLabel("Remove \(app?.name ?? bundleID)")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Settings.Size.excludedAppChipHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Settings.Radius.controlIcon, style: .continuous)
                .fill(Theme.Settings.Colors.searchFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Settings.Radius.controlIcon, style: .continuous)
                .strokeBorder(Theme.Settings.Colors.searchStroke, lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }
}

private struct SnippetAppPickerPopover: View {
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
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
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
                            if let bundleID = app.bundleID { onSelect(bundleID) }
                        } label: {
                            HStack(spacing: Theme.Spacing.lg) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 22, height: 22)
                                Text(app.name).lineLimit(1)
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
