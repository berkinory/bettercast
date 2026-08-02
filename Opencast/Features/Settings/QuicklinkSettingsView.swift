import SwiftUI

struct QuicklinkSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings

    var body: some View {
        SettingsPane(
            title: "Quicklinks",
            subtitle: "Save and open URLs, files, and folders faster.",
            systemImage: "link",
            tint: Theme.Colors.systemAccent
        ) {
            SettingsSection(header: "Quicklinks") {
                SettingsControlRow(
                    title: "Enable Quicklinks",
                    subtitle: "Show and open saved quicklinks in Opencast.",
                    systemImage: "link",
                    tint: Theme.Colors.systemAccent,
                    destination: .quicklinksEnabled
                ) {
                    Toggle("", isOn: $settings.quicklinksEnabled)
                        .labelsHidden()
                }
            }
        }
    }
}
