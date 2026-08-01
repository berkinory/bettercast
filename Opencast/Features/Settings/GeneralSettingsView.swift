import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @ObservedObject private var updates = AppCore.shared.updates
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
                    subtitle: "Start Opencast automatically when you log in.",
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

            SettingsSection(header: "Appearance") {
                SettingsControlRow(
                    title: "Interface",
                    subtitle: "Choose the default dark or light appearance.",
                    systemImage: "circle.lefthalf.filled",
                    tint: Theme.Colors.generalAccent,
                    destination: .appearance
                ) {
                    Picker("", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                }
            }

            SettingsSection(header: "Updates") {
                SettingsControlRow(
                    title: "Allow update checks",
                    subtitle: "Contact GitHub only when you check for a newer version.",
                    systemImage: "arrow.down.circle",
                    tint: Theme.Colors.systemAccent
                ) {
                    Toggle("", isOn: updateConsentBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsRowDivider()
                SettingsControlRow(
                    title: "Check for Updates",
                    subtitle: "Look for a newer Opencast release now.",
                    systemImage: "checkmark.circle",
                    tint: Theme.Colors.systemAccent
                ) {
                    Button("Check Now") { AppCore.shared.checkForUpdates() }
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

    private var updateConsentBinding: Binding<Bool> {
        Binding(
            get: { updates.networkConsentGranted },
            set: { granted in
                guard granted else {
                    updates.setNetworkConsent(false)
                    return
                }
                guard
                    NativeConfirmation.show(
                        message: "Allow update checks?",
                        informativeText:
                            "Opencast will contact GitHub only when you check for a newer release. No usage data is sent.",
                        primaryTitle: "Allow",
                        secondaryTitle: "Cancel"
                    ) == .primary
                else { return }
                updates.setNetworkConsent(true)
            }
        )
    }
}
