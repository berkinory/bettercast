import SwiftUI
import UniformTypeIdentifiers

struct SearchScopesView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @State private var missingScopes = Set<String>()

    var body: some View {
        SettingsSection(
            header: "Search locations",
            subtitle: "Folders and apps included in launcher search.",
            systemImage: "folder",
            tint: Theme.Colors.launcherAccent,
            destination: .searchScopes
        ) {
            if settings.searchScopes.isEmpty {
                Text("No application locations are being searched.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Settings.Layout.rowHorizontal)
                    .padding(.vertical, Theme.Settings.Layout.rowVertical)
            } else {
                ForEach(Array(settings.searchScopes.enumerated()), id: \.element) { index, scope in
                    SearchScopeRow(
                        scope: scope,
                        isMissing: missingScopes.contains(scope),
                        onRemove: { remove(scope) }
                    )
                    if index < settings.searchScopes.count - 1 {
                        SettingsRowDivider()
                    }
                }
            }

            if !settings.searchScopes.isEmpty {
                SettingsRowDivider()
            }

            HStack(spacing: Theme.Spacing.md) {
                Spacer(minLength: Theme.Spacing.md)

                if settings.searchScopes != SearchScopes.defaults {
                    Button("Reset") {
                        settings.searchScopes = SearchScopes.defaults
                    }
                    .controlSize(.small)
                }

                Button(action: addScopes) {
                    Label("Add Location", systemImage: "plus")
                }
                .controlSize(.small)
            }
            .padding(.horizontal, Theme.Settings.Layout.rowHorizontal)
            .padding(.vertical, Theme.Settings.Layout.rowVertical)
        }
        .onAppear(perform: refreshMissingScopes)
        .onChange(of: settings.searchScopes) { _, _ in refreshMissingScopes() }
    }

    private func remove(_ scope: String) {
        settings.searchScopes.removeAll { $0 == scope }
    }

    private func refreshMissingScopes() {
        let fileManager = FileManager.default
        missingScopes = Set(
            settings.searchScopes.filter {
                !fileManager.fileExists(atPath: SearchScopes.expand($0))
            })
    }

    private func addScopes() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.folder, .applicationBundle]
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders or applications to include in the launcher."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        settings.searchScopes = SearchScopes.normalize(
            settings.searchScopes + panel.urls.map(\.path))
    }
}

private struct SearchScopeRow: View {
    let scope: String
    let isMissing: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: isApplication ? "app" : "folder")
                .font(Theme.Typography.iconSmall)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(
                    isMissing ? Theme.Colors.warning : Theme.Colors.launcherAccent
                )
                .frame(
                    width: Theme.Settings.Size.applicationIcon,
                    height: Theme.Settings.Size.applicationIcon
                )

            Text(scope)
                .font(Theme.Typography.callout)
                .foregroundStyle(isMissing ? Theme.Colors.textTertiary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: Theme.Spacing.md)

            if isMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.warning)
                    .help("This location no longer exists.")
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(Theme.Typography.iconTiny)
                    .foregroundStyle(.tertiary)
                    .frame(
                        width: Theme.Settings.Size.controlIcon,
                        height: Theme.Settings.Size.controlIcon
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .settingsFocusRing(cornerRadius: Theme.Settings.Radius.controlIcon)
            .help("Remove search scope")
            .accessibilityLabel("Remove \(scope)")
        }
        .padding(.horizontal, Theme.Settings.Layout.rowHorizontal)
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var isApplication: Bool {
        (scope as NSString).pathExtension.lowercased() == "app"
    }
}
