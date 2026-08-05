import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    var body: some View {
        SettingsPane(
            title: "General",
            subtitle: "Control how Opencast starts and stays available.",
            systemImage: "switch.2",
            tint: Theme.Colors.systemAccent
        ) {
            SettingsSection(
                header: "Startup",
                subtitle: "Keep Opencast ready without adding noise to your desktop.",
                systemImage: "power",
                tint: Theme.Colors.systemAccent
            ) {
                SettingsControlRow(
                    title: "Launch at login",
                    subtitle: "Start automatically after you sign in.",
                    destination: .launchAtLogin
                ) {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                        .settingsToggle()
                }
                SettingsRowDivider()
                SettingsControlRow(
                    title: "Menu bar icon",
                    subtitle: "Global shortcuts continue working when it is hidden.",
                    destination: .showInMenuBar
                ) {
                    Toggle("Show in menu bar", isOn: $showInMenuBar)
                        .settingsToggle()
                }
            }

            if let error = settings.launchAtLoginError {
                SettingsStatusCard(
                    title: "Launch at login is unavailable",
                    message: error,
                    systemImage: "exclamationmark.triangle",
                    tint: Theme.Colors.warning
                )
            }

            AccessibilitySettingsSection()
        }
    }

}
