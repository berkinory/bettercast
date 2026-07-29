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
                        RoundedRectangle(
                            cornerRadius: Theme.Settings.Radius.controlIcon,
                            style: .continuous
                        )
                        .fill(Color.orange.opacity(0.12))
                        .frame(
                            width: Theme.Settings.Size.controlIcon,
                            height: Theme.Settings.Size.controlIcon
                        )
                        .overlay(
                            Image(systemName: "hand.wave")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.orange)
                        )

                        VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                            Text("Preferred tone")
                                .font(.callout.weight(.medium))
                            Text("Used for supported emoji in results and pasted text.")
                                .font(.caption)
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
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Settings.Size.skinToneButton)
                        .background(
                            RoundedRectangle(
                                cornerRadius: Theme.Settings.Radius.controlIcon,
                                style: .continuous
                            )
                            .fill(
                                selection == tone
                                    ? Color.orange.opacity(0.18)
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
                                    ? Color.orange.opacity(0.65)
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
