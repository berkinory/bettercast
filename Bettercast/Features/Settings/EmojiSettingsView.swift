import SwiftUI

struct EmojiSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings

    var body: some View {
        SettingsPane(
            title: "Emoji & Symbols",
            subtitle: "Search and paste emoji from anywhere.",
            systemImage: "face.smiling",
            tint: .yellow
        ) {
            SettingsSection(header: "Shortcut") {
                SettingsControlRow(
                    title: "Emoji & Symbols",
                    subtitle: "Open the emoji and symbols palette.",
                    systemImage: "keyboard",
                    tint: .yellow,
                    destination: .emojiShortcut
                ) {
                    ShortcutRecorder(action: .toggleEmoji)
                }
            }

            SettingsSection(header: "Skin Tone") {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "hand.wave")
                            .font(Theme.Typography.iconMedium)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(
                                width: Theme.Settings.Size.controlIcon,
                                height: Theme.Settings.Size.controlIcon
                            )

                        VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                            Text("Preferred tone")
                                .font(Theme.Typography.calloutMedium)
                            Text("Used for supported emoji in results and pasted text.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SkinToneSelector(selection: $settings.emojiSkinTone)
                }
                .padding(Theme.Settings.Layout.rowHorizontal)
                .settingsDestination(.emojiSkinTone)
            }
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
