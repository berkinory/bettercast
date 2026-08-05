import SwiftUI

struct WindowManagementSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings

    var body: some View {
        SettingsPane(
            title: "Window Management",
            subtitle: "Move and resize the frontmost window with launcher actions or shortcuts.",
            systemImage: "macwindow.and.cursorarrow",
            tint: Theme.Colors.launcherAccent
        ) {
            SettingsFeatureToggleRow(
                title: "Window Management",
                systemImage: "rectangle.3.group",
                tint: Theme.Colors.launcherAccent,
                isEnabled: $settings.windowManagementEnabled
            )

            Group {
                SettingsSection(
                    header: "Layout",
                    subtitle: "Match window placement to your macOS preferences.",
                    systemImage: "rectangle.split.3x1",
                    tint: Theme.Colors.launcherAccent
                ) {
                    SettingsControlRow(
                        title: "Respect macOS tile margins",
                        subtitle: "Use the spacing configured in Desktop & Dock."
                    ) {
                        Toggle(
                            "Respect macOS tile margins",
                            isOn: $settings.windowRespectSystemMargins
                        )
                        .settingsToggle()
                    }
                }

                WindowCommandsSettingsSection()
            }
            .opacity(settings.windowManagementEnabled ? 1 : 0.45)
            .disabled(!settings.windowManagementEnabled)
        }
    }
}
