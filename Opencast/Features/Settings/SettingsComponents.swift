import SwiftUI

private struct SettingsDestinationKey: EnvironmentKey {
    static let defaultValue: SettingsDestination? = nil
}

extension EnvironmentValues {
    var settingsDestination: SettingsDestination? {
        get { self[SettingsDestinationKey.self] }
        set { self[SettingsDestinationKey.self] = newValue }
    }
}

struct SettingsPane<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var emoji: String? = nil
    let tint: Color
    @ViewBuilder var content: Content

    @Environment(\.settingsDestination) private var destination

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Settings.Layout.sectionSpacing) {
                    SettingsFeatureHeader(
                        title: title,
                        subtitle: subtitle,
                        systemImage: systemImage,
                        emoji: emoji,
                        tint: tint
                    )
                    content
                }
                .padding(Theme.Settings.Layout.paneInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlayScroller(disablesElasticity: true)
            }
            .task(id: destination?.anchorID) {
                guard let destination else { return }
                await Task.yield()
                proxy.scrollTo(destination.anchorID, anchor: .center)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

struct SettingsFeatureHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var emoji: String? = nil
    let tint: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.xl) {
            Group {
                if let emoji {
                    FeatureIcon(emoji: emoji, tint: tint, size: Theme.Settings.Size.controlIcon)
                } else {
                    FeatureIcon(
                        systemImage: systemImage,
                        tint: tint,
                        size: Theme.Settings.Size.controlIcon
                    )
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(title)
                    .font(Theme.Typography.title3Semibold)
                Text(subtitle)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

struct SettingsSection<Content: View>: View {
    var header: String? = nil
    var destination: SettingsDestination? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let header {
                Text(header)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.leading, Theme.Spacing.xs)
            }
            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(
                        cornerRadius: Theme.Settings.Radius.surface,
                        style: .continuous
                    )
                    .fill(Theme.Settings.Colors.surfaceFill)
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: Theme.Settings.Radius.surface,
                        style: .continuous
                    )
                    .strokeBorder(Theme.Settings.Colors.surfaceStroke, lineWidth: 1)
                )
        }
        .settingsDestination(destination)
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Settings.Colors.rowDivider)
            .frame(height: 1)
            .padding(
                .leading,
                Theme.Settings.Layout.rowHorizontal + Theme.Settings.Size.controlIcon
                    + Theme.Settings.Layout.rowGap
            )
    }
}

struct SettingsControlRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = Theme.Colors.textSecondary
    var statusDot: Color? = nil
    var destination: SettingsDestination? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Settings.Layout.rowGap) {
            if let systemImage {
                FeatureIcon(
                    systemImage: systemImage,
                    tint: tint,
                    size: Theme.Settings.Size.controlIcon
                )
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(title)
                        .font(Theme.Typography.calloutMedium)
                    if let statusDot {
                        Circle()
                            .fill(statusDot)
                            .frame(width: Theme.Size.statusDot, height: Theme.Size.statusDot)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Theme.Spacing.md)
            trailing
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, Theme.Settings.Layout.rowHorizontal)
        .padding(.vertical, Theme.Settings.Layout.rowVertical)
        .settingsDestination(destination)
    }
}

struct SettingsStatusCard<Trailing: View>: View {
    let title: String
    var message: String? = nil
    var systemImage: String = "info.circle"
    var tint: Color = Theme.Colors.textSecondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.xl) {
            FeatureIcon(
                systemImage: systemImage,
                tint: tint,
                size: Theme.Settings.Size.statusIcon
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(title)
                    .font(Theme.Typography.calloutSemibold)
                if let message {
                    Text(message)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Theme.Spacing.md)
            trailing
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(Theme.Settings.Layout.rowHorizontal)
        .background(
            RoundedRectangle(
                cornerRadius: Theme.Settings.Radius.surface,
                style: .continuous
            )
            .fill(Theme.Settings.Colors.surfaceFill)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: Theme.Settings.Radius.surface,
                style: .continuous
            )
            .strokeBorder(Theme.Settings.Colors.surfaceStroke, lineWidth: 1)
        )
    }
}

extension SettingsStatusCard where Trailing == EmptyView {
    init(
        title: String,
        message: String? = nil,
        systemImage: String = "info.circle",
        tint: Color = .secondary
    ) {
        self.init(title: title, message: message, systemImage: systemImage, tint: tint) {
            EmptyView()
        }
    }
}

private struct SettingsDestinationModifier: ViewModifier {
    let destination: SettingsDestination?

    @Environment(\.settingsDestination) private var target
    @State private var highlighted = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if let destination {
            let shape = RoundedRectangle(
                cornerRadius: Theme.Settings.Radius.rowHighlight,
                style: .continuous
            )
            content
                .id(destination.anchorID)
                .background(shape.fill(Theme.Colors.selection.opacity(highlighted ? 1 : 0)))
                .overlay(
                    shape.strokeBorder(
                        Theme.Colors.border.opacity(highlighted ? 1 : 0),
                        lineWidth: 1
                    )
                )
                .onAppear { highlightIfNeeded(target) }
                .onChange(of: target) { _, newTarget in highlightIfNeeded(newTarget) }
        } else {
            content
        }
    }

    private func highlightIfNeeded(_ target: SettingsDestination?) {
        guard let destination, destination == target else { return }
        highlighted = true
        withAnimation(.easeOut(duration: Theme.Settings.Motion.highlightFade).delay(0.04)) {
            highlighted = false
        }
    }
}

private struct SettingsFocusRingModifier: ViewModifier {
    let cornerRadius: CGFloat
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        focused ? Theme.Settings.Colors.searchFocus : .clear,
                        lineWidth: focused ? 2 : 0
                    )
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func settingsDestination(_ destination: SettingsDestination?) -> some View {
        modifier(SettingsDestinationModifier(destination: destination))
    }

    func settingsFocusRing(cornerRadius: CGFloat) -> some View {
        modifier(SettingsFocusRingModifier(cornerRadius: cornerRadius))
    }
}
