import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @ObservedObject private var updates = AppCore.shared.updates
    @ObservedObject private var extensionScheduler = AppCore.shared.extensionScheduler
    @ObservedObject private var extensionStore = AppCore.shared.extensionStore
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true
    @State private var showingExtensionStore = false

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

            SettingsSection(header: "Extensions") {
                SettingsControlRow(
                    title: "Import Extension",
                    subtitle: "Install a prebuilt .ocx package. Packages are validated before activation.",
                    systemImage: "shippingbox",
                    tint: Theme.Colors.systemAccent
                ) {
                    Button("Choose…") { AppCore.shared.importExtension() }
                        .controlSize(.small)
                }
                SettingsRowDivider()
                SettingsControlRow(
                    title: "Extension Store",
                    subtitle: "Browse verified .ocx packages from the static GitHub Releases catalog.",
                    systemImage: "shippingbox.fill",
                    tint: Theme.Colors.systemAccent
                ) {
                    Button("Browse…") { showingExtensionStore = true }
                        .controlSize(.small)
                }
                ForEach(extensionStore.installed) { installed in
                    SettingsRowDivider()
                    SettingsControlRow(
                        title: installed.title,
                        subtitle:
                            "\(installed.report.channel.title) · \(installed.report.score)/100 · \(ByteCountFormatter.string(fromByteCount: Int64(installed.report.bundleBytes), countStyle: .file))",
                        systemImage: installed.disabled ? "pause.circle" : "checkmark.seal",
                        tint: installed.disabled ? .orange : .green
                    ) {
                        Menu("Manage") {
                            Button(installed.disabled ? "Enable" : "Disable") {
                                extensionStore.disable(installed.name, disabled: !installed.disabled)
                            }
                            if installed.rollbackAvailable {
                                Button("Rollback") { extensionStore.rollback(installed.name) }
                            }
                            Button("Remove", role: .destructive) { extensionStore.remove(installed.name) }
                        }
                        .controlSize(.small)
                    }
                }
                if let error = extensionStore.lastError {
                    SettingsRowDivider()
                    SettingsControlRow(
                        title: "Extension error",
                        subtitle: error,
                        systemImage: "exclamationmark.triangle",
                        tint: .orange
                    ) {
                        Button("Dismiss") { extensionStore.clearError() }
                            .controlSize(.small)
                    }
                }
                SettingsRowDivider()
                SettingsControlRow(
                    title: "Allow background refresh",
                    subtitle:
                        "Run interval and menu-bar extensions only when enabled. Background work is disabled by default.",
                    systemImage: "arrow.clockwise",
                    tint: Theme.Colors.systemAccent
                ) {
                    Toggle("", isOn: $extensionScheduler.backgroundEnabled)
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
        .sheet(isPresented: $showingExtensionStore) {
            ExtensionStoreView()
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
