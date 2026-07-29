import SwiftUI

struct HyperKeySettingsSection: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @ObservedObject private var hyperTap = AppCore.shared.hyperKeyTap

    private var hyperGlyphs: [String] {
        settings.hyperKeyIncludesShift ? ["⌃", "⌥", "⇧", "⌘"] : ["⌃", "⌥", "⌘"]
    }

    var body: some View {
        SettingsSection(header: "Hyper Key") {
            HyperKeyComposer(
                key: $settings.hyperKey,
                modifierGlyphs: hyperGlyphs,
                status: hyperTap.status
            )
            .padding(Theme.Settings.Layout.rowHorizontal)
            .settingsDestination(.hyperKey)
            .onChange(of: settings.hyperKey) { _, newKey in
                settings.hyperKeyQuickPress = .none
                if newKey != .none { Permissions.ensureAccessibility() }
            }

            if hyperTap.status == .needsAccessibility {
                SettingsRowDivider()
                SettingsControlRow(
                    title: "Accessibility access needed",
                    subtitle: "Required to remap a physical key.",
                    systemImage: "hand.raised.fill",
                    tint: .orange
                ) {
                    Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                        .controlSize(.small)
                }
            }

            if settings.hyperKey.hasOriginalFunction {
                SettingsRowDivider()
                SettingsControlRow(
                    title: "Quick Press",
                    subtitle: "Action for a short press without another key.",
                    systemImage: "hand.tap",
                    tint: .teal,
                    destination: .hyperQuickPress
                ) {
                    Picker("", selection: $settings.hyperKeyQuickPress) {
                        Text("Does Nothing").tag(HyperKeyQuickPress.none)
                        if let original = settings.hyperKey.quickPressOriginalTitle {
                            Text(original).tag(HyperKeyQuickPress.originalKey)
                        }
                        Text("Trigger Escape").tag(HyperKeyQuickPress.escape)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsRowDivider()
            SettingsControlRow(
                title: "Include Shift",
                subtitle: "Add ⇧ to the modifier chord.",
                systemImage: "shift",
                tint: .indigo,
                destination: .hyperIncludeShift
            ) {
                Toggle("", isOn: $settings.hyperKeyIncludesShift)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            SettingsRowDivider()
            SettingsControlRow(
                title: "Show chord as ✦",
                subtitle: "Use one glyph in shortcut labels.",
                systemImage: "keyboard",
                tint: .gray,
                destination: .hyperReplaceGlyph
            ) {
                Toggle("", isOn: $settings.hyperKeyReplacesGlyph)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }
}

private struct HyperKeyComposer: View {
    @Binding var key: HyperKeyPhysicalKey
    let modifierGlyphs: [String]
    let status: HyperKeyTap.Status

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Physical key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Physical key", selection: $key) {
                        ForEach(HyperKeyPhysicalKey.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Modifier chord")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(modifierGlyphs, id: \.self) { glyph in
                            Text(glyph)
                                .font(.callout.weight(.medium))
                                .frame(
                                    width: Theme.Settings.Size.hyperKeyCap,
                                    height: Theme.Settings.Size.hyperKeyCap
                                )
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: Theme.Radius.recorderKeyCap,
                                        style: .continuous
                                    )
                                    .fill(Theme.Settings.Colors.searchFill)
                                )
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: Theme.Radius.recorderKeyCap,
                                        style: .continuous
                                    )
                                    .strokeBorder(
                                        Theme.Settings.Colors.searchStroke,
                                        lineWidth: 1
                                    )
                                )
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            if key != .none {
                Label(statusText, systemImage: statusImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var statusText: String {
        switch status {
        case .off: return "Select a key to enable Hyper Key"
        case .active: return "Hyper Key is active"
        case .needsAccessibility: return "Waiting for Accessibility access"
        }
    }

    private var statusImage: String {
        switch status {
        case .off: return "circle"
        case .active: return "checkmark.circle.fill"
        case .needsAccessibility: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .off: return .secondary
        case .active: return .green
        case .needsAccessibility: return .orange
        }
    }
}
