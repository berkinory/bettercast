import SwiftUI

struct EmojiSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings

    var body: some View {
        SettingsPane(
            title: "Emoji & Symbols",
            subtitle: "Search emoji from anywhere and choose their preferred skin tone.",
            systemImage: "face.smiling",
            tint: Theme.Colors.emojiAccent
        ) {
            SettingsFeatureToggleRow(
                title: "Emoji & symbols",
                systemImage: "face.smiling",
                tint: Theme.Colors.emojiAccent,
                isEnabled: $settings.emojiEnabled
            )

            Group {
                FeatureCommandsSettingsSection(
                    commandIDs: [.searchEmoji],
                    tint: Theme.Colors.emojiAccent
                )

                SettingsSection(
                    header: "Appearance",
                    subtitle: "Choose the skin tone used for supported emoji.",
                    systemImage: "hand.raised",
                    tint: Theme.Colors.emojiAccent
                ) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text("Preferred skin tone")
                                .font(Theme.Typography.calloutMedium)
                            Text("Default keeps each emoji's original appearance.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        SkinToneSelector(selection: $settings.emojiSkinTone)
                    }
                    .padding(Theme.Settings.Layout.rowHorizontal)
                    .settingsDestination(.emojiSkinTone)
                }
            }
            .disabled(!settings.emojiEnabled)
            .opacity(settings.emojiEnabled ? 1 : 0.42)
        }
    }
}

private struct SkinToneSelector: View {
    @Binding var selection: EmojiSkinTone

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(EmojiSkinTone.allCases) { tone in
                Button {
                    selection = tone
                } label: {
                    Text(tone.sample)
                        .font(Theme.Typography.title3)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Settings.Size.skinToneButton)
                        .background(
                            RoundedRectangle(
                                cornerRadius: Theme.Settings.Radius.controlIcon,
                                style: .continuous
                            )
                            .fill(
                                selection == tone
                                    ? Theme.Colors.selection
                                    : Theme.Settings.Colors.searchFill
                            )
                        )
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: Theme.Settings.Radius.controlIcon,
                                style: .continuous
                            )
                            .strokeBorder(
                                selection == tone
                                    ? Theme.Colors.border
                                    : Theme.Settings.Colors.searchStroke,
                                lineWidth: 1
                            )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .settingsFocusRing(cornerRadius: Theme.Settings.Radius.controlIcon)
                .accessibilityLabel("\(tone.title) skin tone")
                .accessibilityAddTraits(selection == tone ? .isSelected : [])
            }
        }
    }
}
