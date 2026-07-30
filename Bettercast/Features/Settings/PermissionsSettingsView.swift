import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPane(
            title: "Permissions",
            subtitle: "System access Bettercast needs to work across apps.",
            systemImage: "checkmark.shield",
            tint: .green
        ) {
            SettingsStatusCard(
                title: accessibilityTrusted ? "Accessibility is ready" : "Accessibility access needed",
                message: accessibilityTrusted
                    ? "Bettercast can restore focus and paste into the app you were using."
                    : "Grant access so clipboard and emoji results can be pasted into other apps.",
                systemImage: accessibilityTrusted
                    ? "checkmark.shield.fill" : "hand.raised.fill",
                tint: accessibilityTrusted ? .green : .orange
            ) {
                Button(accessibilityTrusted ? "Manage…" : "Open Settings…") {
                    Permissions.openAccessibilitySettings()
                }
                .controlSize(.small)
            }
            .settingsDestination(.accessibility)

            SettingsSection(header: "Access") {
                SettingsControlRow(
                    title: "Paste into the previous app",
                    subtitle: "Bettercast records no keystrokes and requests no network access.",
                    systemImage: "arrow.right.doc.on.clipboard",
                    tint: .blue
                ) {
                    Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(accessibilityTrusted ? Theme.Colors.success : Theme.Colors.textSecondary)
                }
            }
        }
        .onAppear { accessibilityTrusted = Permissions.isAccessibilityTrusted() }
        .onReceive(refreshTimer) { _ in
            let trusted = Permissions.isAccessibilityTrusted()
            if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        }
    }
}
