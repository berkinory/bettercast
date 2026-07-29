import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    var body: some View {
        SettingsPane(
            title: "General",
            subtitle: "Startup, menu bar, and setup.",
            systemImage: "gearshape",
            tint: .gray
        ) {
            SettingsSection(header: "App") {
                SettingsControlRow(
                    title: "Launch at login",
                    subtitle: "Start Bettercast automatically when you log in.",
                    systemImage: "power",
                    tint: .green,
                    destination: .launchAtLogin
                ) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsRowDivider()
                SettingsControlRow(
                    title: "Show in menu bar",
                    subtitle: "Shortcuts keep working when the icon is hidden.",
                    systemImage: "menubar.rectangle",
                    tint: .gray,
                    destination: .showInMenuBar
                ) {
                    Toggle("", isOn: $showInMenuBar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsSection(header: "Setup") {
                SettingsControlRow(
                    title: "Welcome Guide",
                    subtitle: "Run shortcut and permission setup again.",
                    systemImage: "sparkles",
                    tint: .yellow,
                    destination: .welcomeGuide
                ) {
                    Button("Open…") { AppCore.shared.showOnboarding() }
                        .controlSize(.small)
                }
            }
        }
    }
}
