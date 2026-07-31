import SwiftUI

struct WindowManagementSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings

    var body: some View {
        SettingsPane(
            title: "Window Management",
            subtitle: "Tile, resize, and move the frontmost window from the launcher or a shortcut.",
            systemImage: "macwindow",
            tint: Theme.Colors.launcherAccent
        ) {
            SettingsSection(header: "Window Management") {
                SettingsControlRow(
                    title: "Enable window management",
                    subtitle: "Uses Accessibility to control the window you were last using.",
                    systemImage: "macwindow",
                    tint: Theme.Colors.launcherAccent
                ) {
                    Toggle("Enable window management", isOn: $settings.windowManagementEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .settingsFocusRing(cornerRadius: Theme.Settings.Radius.controlIcon)
                }
            }

            Group {
                SettingsSection(header: "Options") {
                    SettingsControlRow(
                        title: "Respect macOS tile margins",
                        subtitle: "Use the spacing configured in Desktop & Dock when tiling windows.",
                        systemImage: "square.split.2x1",
                        tint: Theme.Colors.launcherAccent
                    ) {
                        Toggle(
                            "Respect macOS tile margins",
                            isOn: $settings.windowRespectSystemMargins
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .settingsFocusRing(cornerRadius: Theme.Settings.Radius.controlIcon)
                    }
                }

                SettingsSection(header: "Commands") {
                    ForEach(Array(WindowCommandCatalog.grouped().enumerated()), id: \.element.group) {
                        index, section in
                        if index > 0 { SettingsRowDivider() }
                        Text(section.group.title)
                            .font(Theme.Typography.sectionHeader)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.Settings.Layout.rowHorizontal)
                            .padding(.top, Theme.Spacing.lg)
                            .padding(.bottom, Theme.Spacing.xs)
                        ForEach(section.commands) { command in
                            WindowCommandSettingsRow(command: command)
                        }
                    }
                }
            }
            .opacity(settings.windowManagementEnabled ? 1 : 0.45)
            .disabled(!settings.windowManagementEnabled)
        }
    }
}

private struct WindowCommandSettingsRow: View {
    let command: WindowCommand

    @EnvironmentObject private var visibility: VisibilityStore
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Settings.Layout.rowGap) {
            FeatureIcon(
                systemImage: command.sfSymbol,
                tint: Theme.Colors.launcherAccent,
                size: Theme.Settings.Size.controlIcon
            )
            Text(command.name)
                .font(Theme.Typography.calloutMedium)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.md)
            ShortcutRecorder(action: .windowCommand(id: command.id))
                .fixedSize(horizontal: true, vertical: false)
            Toggle("Show in launcher", isOn: visibilityBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .settingsFocusRing(cornerRadius: Theme.Settings.Radius.controlIcon)
                .help("Show in launcher")
                .accessibilityLabel("Show \(command.name) in the launcher")
        }
        .padding(.horizontal, Theme.Settings.Layout.rowHorizontal)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(hovered ? Theme.Colors.rowHover : .clear)
        )
        .onHover { hovered = $0 }
    }

    private var entry: AppEntry {
        AppEntry(
            id: command.entryID,
            name: command.name,
            url: URL(string: "opencast://window-command/" + command.id.rawValue)!,
            bundleID: nil,
            kind: .command
        )
    }

    private var visibilityBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) }
        )
    }
}
