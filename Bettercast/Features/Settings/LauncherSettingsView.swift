import SwiftUI

struct LauncherSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @ObservedObject private var launcherRanking = AppCore.shared.launcherRanking
    @State private var confirmingRankingReset = false

    var body: some View {
        SettingsPane(
            title: "Launcher",
            subtitle: "Choose how Bettercast opens and resets.",
            systemImage: "magnifyingglass",
            tint: .blue
        ) {
            SettingsSection(header: "Shortcut") {
                SettingsControlRow(
                    title: "App Launcher",
                    subtitle: "Open Bettercast from anywhere.",
                    systemImage: "keyboard",
                    tint: .blue,
                    destination: .launcherShortcut
                ) {
                    ShortcutRecorder(action: .togglePalette)
                }
            }

            SettingsSection(header: "Appearance") {
                LauncherModeSelector(compactMode: $settings.compactMode)
                    .padding(Theme.Settings.Layout.rowHorizontal)
                    .settingsDestination(.compactMode)

                if settings.compactMode {
                    SettingsRowDivider()
                    SettingsControlRow(
                        title: "Show favorites",
                        subtitle: "Pin up to five apps in the compact bar.",
                        systemImage: "star.fill",
                        tint: .yellow,
                        destination: .compactFavorites
                    ) {
                        Toggle("", isOn: $settings.showFavoritesInCompactMode)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            SettingsSection(header: "Behavior") {
                SettingsControlRow(
                    title: "Return to Launcher",
                    subtitle: "Reset the palette after it closes.",
                    systemImage: "arrow.uturn.backward",
                    tint: .indigo,
                    destination: .returnToLauncher
                ) {
                    Picker("", selection: $settings.popToRootTimeout) {
                        ForEach(PopToRootTimeout.allCases) { timeout in
                            Text(timeout.title).tag(timeout)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRowDivider()
                SettingsControlRow(
                    title: "Learned Ranking",
                    subtitle: "Reset privately learned result ordering.",
                    systemImage: "chart.line.uptrend.xyaxis",
                    tint: .blue,
                    destination: .learnedRanking
                ) {
                    Button("Reset…", role: .destructive) {
                        confirmingRankingReset = true
                    }
                    .controlSize(.small)
                    .disabled(launcherRanking.isEmpty)
                }
            }
        }
        .confirmationDialog(
            "Reset learned launcher ranking?",
            isPresented: $confirmingRankingReset,
            titleVisibility: .visible
        ) {
            Button("Reset Ranking", role: .destructive) {
                launcherRanking.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Bettercast will relearn your preferred results as you use the launcher.")
        }
    }
}

private struct LauncherModeSelector: View {
    @Binding var compactMode: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            LauncherModeTile(
                title: "Standard",
                systemImage: "rectangle.split.1x2",
                isCompact: false,
                isSelected: !compactMode
            ) {
                compactMode = false
            }
            LauncherModeTile(
                title: "Compact",
                systemImage: "rectangle.tophalf.inset.filled",
                isCompact: true,
                isSelected: compactMode
            ) {
                compactMode = true
            }
        }
    }
}

private struct LauncherModeTile: View {
    let title: String
    let systemImage: String
    let isCompact: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.md) {
                preview
                Label(title, systemImage: systemImage)
                    .font(Theme.Typography.captionSemibold)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Settings.Size.modeTileHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: Theme.Settings.Radius.modeTile,
                    style: .continuous
                )
                .fill(
                    isSelected
                        ? Theme.Colors.selection
                        : Theme.Settings.Colors.searchFill
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: Theme.Settings.Radius.modeTile,
                    style: .continuous
                )
                .strokeBorder(
                    isSelected
                        ? Theme.Colors.border
                        : Theme.Settings.Colors.searchStroke,
                    lineWidth: 1
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .settingsFocusRing(cornerRadius: Theme.Settings.Radius.modeTile)
        .accessibilityLabel("\(title) launcher appearance")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var preview: some View {
        RoundedRectangle(
            cornerRadius: Theme.Settings.Radius.modePreview,
            style: .continuous
        )
        .fill(Theme.Colors.previewDimming)
        .frame(
            width: Theme.Settings.Size.modePreviewWidth,
            height: isCompact
                ? Theme.Settings.Size.compactModePreviewHeight
                : Theme.Settings.Size.modePreviewHeight
        )
        .overlay(alignment: .leading) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.Typography.iconMicro)
                if !isCompact {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(index == 0 ? Theme.Colors.previewSelected : Theme.Colors.previewUnselected)
                                .frame(width: 38, height: 3)
                        }
                    }
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Spacing.sm)
        }
    }
}
