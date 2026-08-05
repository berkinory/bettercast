import Combine
import SwiftUI

struct AccessibilitySettingsSection: View {
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsSection(
            header: "Accessibility",
            subtitle: "Required to control windows and restore focus before pasting.",
            systemImage: "accessibility",
            tint: accessibilityTrusted ? Theme.Colors.success : Theme.Colors.warning,
            destination: .accessibility
        ) {
            SettingsControlRow(
                title: accessibilityTrusted ? "Access granted" : "Access required",
                subtitle: accessibilityTrusted
                    ? "Opencast can control the frontmost window."
                    : "Grant access before using window commands."
            ) {
                Button(accessibilityTrusted ? "Manage…" : "Open Settings…") {
                    Permissions.openAccessibilitySettings()
                }
                .controlSize(.small)
            }
        }
        .onAppear { accessibilityTrusted = Permissions.isAccessibilityTrusted() }
        .onReceive(refreshTimer) { _ in
            let trusted = Permissions.isAccessibilityTrusted()
            if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        }
    }
}
