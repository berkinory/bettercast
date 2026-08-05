import SwiftUI

struct QuicklinkSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings

    var body: some View {
        SettingsPane(
            title: "Quicklinks",
            subtitle: "Open saved URLs, files, and folders from the launcher.",
            systemImage: "link",
            tint: Theme.Colors.launcherAccent
        ) {
            SettingsFeatureToggleRow(
                title: "Quicklinks",
                systemImage: "link",
                tint: Theme.Colors.launcherAccent,
                isEnabled: $settings.quicklinksEnabled
            )

            FeatureCommandsSettingsSection(
                commandIDs: [.searchQuicklinks, .createQuicklink],
                tint: Theme.Colors.launcherAccent
            )
            .disabled(!settings.quicklinksEnabled)
            .opacity(settings.quicklinksEnabled ? 1 : 0.42)
        }
    }
}
