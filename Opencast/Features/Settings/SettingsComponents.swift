import AppKit
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
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.title2Bold)
                Text(subtitle)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.xl)

            Group {
                if let emoji {
                    Text(emoji)
                        .font(Theme.Typography.title3)
                } else {
                    Image(systemName: systemImage)
                        .font(Theme.Typography.iconXL)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(tint)
                }
            }
            .frame(width: Theme.Settings.Size.headerIcon, height: Theme.Settings.Size.headerIcon)
        }
    }
}

struct SettingsSection<Content: View>: View {
    var header: String? = nil
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = Theme.Colors.textSecondary
    var destination: SettingsDestination? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let header {
                SettingsSectionLabel(
                    title: header,
                    subtitle: subtitle,
                    systemImage: systemImage,
                    tint: tint
                )
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

struct SettingsSectionLabel: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = Theme.Colors.textSecondary

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.Typography.iconSmall)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tint)
                    .frame(width: Theme.Size.keyCap, height: Theme.Size.keyCap)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }
}

struct SettingsFeatureToggleRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: Theme.Settings.Layout.rowGap) {
            Image(systemName: systemImage)
                .font(Theme.Typography.iconSmall)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(
                    width: Theme.Settings.Size.controlIcon,
                    height: Theme.Settings.Size.controlIcon
                )

            Text(title)
                .font(Theme.Typography.calloutMedium)
                .foregroundStyle(Theme.Colors.textPrimary)

            Spacer(minLength: Theme.Spacing.lg)

            Toggle(title, isOn: $isEnabled)
                .settingsToggle()
        }
        .padding(.horizontal, Theme.Settings.Layout.rowHorizontal)
        .padding(.vertical, Theme.Settings.Layout.rowVertical)
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
                Image(systemName: systemImage)
                    .font(Theme.Typography.iconMedium)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tint)
                    .frame(
                        width: Theme.Settings.Size.controlIcon,
                        height: Theme.Settings.Size.controlIcon
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
            Image(systemName: systemImage)
                .font(Theme.Typography.iconMediumSmall)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(
                    width: Theme.Settings.Size.statusIcon,
                    height: Theme.Settings.Size.statusIcon
                )
                .background(Circle().fill(tint.opacity(0.12)))

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

struct SettingsExcludedApplications: View {
    @Binding var bundleIDs: [String]
    let emptyMessage: String

    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if bundleIDs.isEmpty {
                Text(emptyMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: Theme.Settings.Size.excludedAppChipMinimum),
                            spacing: Theme.Spacing.md
                        )
                    ],
                    spacing: Theme.Spacing.md
                ) {
                    ForEach(bundleIDs, id: \.self) { bundleID in
                        SettingsExcludedAppChip(bundleID: bundleID) {
                            bundleIDs.removeAll { $0 == bundleID }
                        }
                    }
                }
            }

            Button {
                showingPicker = true
            } label: {
                Label("Add Application…", systemImage: "plus")
                    .font(Theme.Typography.captionSemibold)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                SettingsApplicationPicker(excluded: Set(bundleIDs)) { bundleID in
                    bundleIDs.append(bundleID)
                    showingPicker = false
                }
            }
        }
        .padding(Theme.Settings.Layout.rowHorizontal)
    }
}

private struct SettingsExcludedAppChip: View {
    let bundleID: String
    let onRemove: () -> Void

    @EnvironmentObject private var appIndex: AppIndex
    @State private var hovering = false

    var body: some View {
        let app = appIndex.apps.first { $0.bundleID == bundleID }
        HStack(spacing: Theme.Spacing.md) {
            Image(nsImage: app?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
                .resizable()
                .interpolation(.high)
                .frame(
                    width: Theme.Settings.Size.applicationIcon,
                    height: Theme.Settings.Size.applicationIcon
                )
            Text(app?.name ?? bundleID)
                .font(Theme.Typography.captionMedium)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(Theme.Typography.iconSmall)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(
                        width: Theme.Settings.Size.visibilityButton,
                        height: Theme.Settings.Size.visibilityButton
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .settingsFocusRing(cornerRadius: Theme.Settings.Radius.controlIcon)
            .opacity(hovering ? 1 : 0.6)
            .accessibilityLabel("Remove \(app?.name ?? bundleID)")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Settings.Size.excludedAppChipHeight)
        .background(
            RoundedRectangle(
                cornerRadius: Theme.Settings.Radius.controlIcon,
                style: .continuous
            )
            .fill(Theme.Settings.Colors.searchFill)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: Theme.Settings.Radius.controlIcon,
                style: .continuous
            )
            .strokeBorder(Theme.Settings.Colors.searchStroke, lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }
}

private struct SettingsApplicationPicker: View {
    let excluded: Set<String>
    let onSelect: (String) -> Void

    @EnvironmentObject private var appIndex: AppIndex
    @State private var query = ""
    @FocusState private var queryFocused: Bool

    private var candidates: [AppEntry] {
        (query.isEmpty ? appIndex.apps : appIndex.matches(query))
            .filter { $0.kind == .application }
            .filter { $0.bundleID.map { !excluded.contains($0) } ?? false }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Colors.textSecondary)
                TextField("Search applications", text: $query)
                    .textFieldStyle(.plain)
                    .focused($queryFocused)
            }
            .padding(Theme.Spacing.lg)

            Rectangle()
                .fill(Theme.Settings.Colors.rowDivider)
                .frame(height: 1)

            ScrollView {
                LazyVStack(spacing: Theme.Spacing.xxs) {
                    ForEach(candidates) { app in
                        Button {
                            if let bundleID = app.bundleID { onSelect(bundleID) }
                        } label: {
                            HStack(spacing: Theme.Spacing.lg) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(
                                        width: Theme.Settings.Size.applicationIcon,
                                        height: Theme.Settings.Size.applicationIcon
                                    )
                                Text(app.name)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .settingsFocusRing(cornerRadius: Theme.Radius.row)
                    }
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity)
            }
            .overlay {
                if candidates.isEmpty {
                    Text(query.isEmpty ? "No applications available." : "No matching applications.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .overlayScroller(disablesElasticity: true)
        }
        .frame(
            width: Theme.Settings.Size.shortcutPopoverWidth,
            height: Theme.Settings.Size.applicationPickerHeight
        )
        .onAppear { queryFocused = true }
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

    func settingsToggle() -> some View {
        labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .settingsFocusRing(cornerRadius: Theme.Settings.Radius.controlIcon)
    }
}
