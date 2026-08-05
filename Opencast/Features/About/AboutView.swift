import AppKit
import SwiftUI

struct AboutView: View {
    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "Version \(short)"
    }

    @ObservedObject private var updates = AppCore.shared.updates

    // Loaded once and cached: reading the .icns is disk I/O, and body can re-run often. Read the
    // bundled file directly since NSApp.applicationIconImage returns the generic placeholder until
    // LaunchServices registers the app, which it hasn't when run from build/.
    @MainActor private static let appIcon: NSImage = {
        if let name = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
            let url = Bundle.main.url(forResource: name, withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApp.applicationIconImage
    }()

    var body: some View {
        VStack(spacing: Theme.Settings.Layout.sectionSpacing) {
            hero
            links
            updatesBar
        }
        .padding(Theme.Settings.Layout.paneInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .ignoresSafeArea(edges: .top)
    }

    private var hero: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.brand.opacity(0.16))
                    .frame(
                        width: Theme.Settings.Size.aboutGlow,
                        height: Theme.Settings.Size.aboutGlow
                    )
                    .blur(radius: Theme.Spacing.xl)

                Image(nsImage: Self.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: Theme.Settings.Size.aboutIcon,
                        height: Theme.Settings.Size.aboutIcon
                    )
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            }
            .frame(height: Theme.Settings.Size.aboutGlow)

            VStack(spacing: Theme.Spacing.xs) {
                Text(Bundle.main.appDisplayName)
                    .font(Theme.Typography.titleBold)
                Text(Self.version)
                    .font(Theme.Typography.captionMonospacedDigit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var links: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(AboutLink.all) { link in
                AboutLinkTile(link: link)
            }
        }
    }

    private var updatesBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(Theme.Typography.iconMedium)
                    .foregroundStyle(Theme.Colors.launcherAccent)
                    .frame(
                        width: Theme.Settings.Size.statusIcon,
                        height: Theme.Settings.Size.statusIcon
                    )
                    .background(
                        Circle().fill(Theme.Colors.launcherAccent.opacity(0.10))
                    )

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Updates")
                        .font(Theme.Typography.calloutMedium)
                    Text(updateSubtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: Theme.Spacing.md)

                if updates.supportsSparkle {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Allow")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Toggle("Allow update checks", isOn: updateConsentBinding)
                            .settingsToggle()
                    }
                }

                Button("Check Now") { AppCore.shared.checkForUpdates() }
                    .controlSize(.small)
                    .disabled(!updates.isHomebrewManaged && !updates.supportsSparkle)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)

            if updates.supportsSparkle {
                Rectangle()
                    .fill(Theme.Settings.Colors.rowDivider)
                    .frame(height: 1)
                    .padding(.horizontal, Theme.Spacing.xl)

                HStack(spacing: Theme.Spacing.xl) {
                    updatePreference(
                        title: "Check automatically",
                        subtitle: "Look for signed updates once a day.",
                        isOn: automaticChecksBinding
                    )
                    updatePreference(
                        title: "Update automatically",
                        subtitle: "Download and install in the background.",
                        isOn: automaticDownloadsBinding
                    )
                    .disabled(!updates.automaticallyChecksForUpdates)
                    .opacity(updates.automaticallyChecksForUpdates ? 1 : 0.45)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
            }
        }
        .background(aboutSurface)
    }

    private var updateSubtitle: String {
        if updates.isHomebrewManaged {
            return "Managed by Homebrew. Checks never install anything."
        }
        if updates.supportsSparkle {
            return "Signed updates delivered securely by Sparkle."
        }
        return "Unavailable in development builds."
    }

    private func updatePreference(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.captionMedium)
                Text(subtitle)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.sm)
            Toggle(title, isOn: isOn)
                .settingsToggle()
        }
        .frame(maxWidth: .infinity)
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
                    AppCore.shared.presentDialog(
                        message: "Allow update checks?",
                        informativeText:
                            "Sparkle will use GitHub to check for signed Opencast updates. Automatic checks run once a day when enabled. Only the app version and normal connection information leave your Mac; no usage data or system profile is sent.",
                        primaryTitle: "Allow",
                        secondaryTitle: "Cancel"
                    ) == .primary
                else { return }
                updates.grantNetworkConsent()
            }
        )
    }

    private var automaticChecksBinding: Binding<Bool> {
        Binding(
            get: { updates.automaticallyChecksForUpdates },
            set: { updates.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var automaticDownloadsBinding: Binding<Bool> {
        Binding(
            get: { updates.automaticallyDownloadsUpdates },
            set: { updates.setAutomaticallyDownloadsUpdates($0) }
        )
    }

    private var aboutSurface: some View {
        RoundedRectangle(
            cornerRadius: Theme.Settings.Radius.surface,
            style: .continuous
        )
        .fill(Theme.Settings.Colors.surfaceFill)
        .overlay(
            RoundedRectangle(
                cornerRadius: Theme.Settings.Radius.surface,
                style: .continuous
            )
            .strokeBorder(Theme.Settings.Colors.surfaceStroke, lineWidth: 1)
        )
    }
}

/// One external destination in the About "Links" card.
private struct AboutLink: Identifiable {
    enum Glyph {
        case symbol(String)
        /// A brand mark from `Assets.xcassets` (template SVG) — SF Symbols ships no GitHub/X logo.
        case brand(String)
    }

    let id: String
    let glyph: Glyph
    let title: String
    let detail: String
    let url: URL

    static let all: [AboutLink] = [
        AboutLink(
            id: "github", glyph: .brand("BrandGitHub"), title: "GitHub",
            detail: "berkinory/opencast",
            url: URL(string: "https://github.com/berkinory/opencast")!),
        AboutLink(
            id: "x", glyph: .brand("BrandX"), title: "X", detail: "@berkinory",
            url: URL(string: "https://x.com/berkinory")!),
        AboutLink(
            id: "email", glyph: .symbol("envelope"), title: "Email",
            detail: "berk@mirac.dev", url: URL(string: "mailto:berk@mirac.dev")!),
    ]
}

private struct AboutLinkTile: View {
    let link: AboutLink

    @State private var hovered = false

    var body: some View {
        Link(destination: link.url) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    glyph
                        .frame(
                            width: Theme.Settings.Size.statusIcon,
                            height: Theme.Settings.Size.statusIcon
                        )
                        .foregroundStyle(hovered ? Theme.Colors.textPrimary : .secondary)
                        .background(
                            RoundedRectangle(
                                cornerRadius: Theme.Settings.Radius.controlIcon,
                                style: .continuous
                            )
                            .fill(Theme.Colors.controlSurface.opacity(0.64))
                        )

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(Theme.Typography.captionSemibold)
                        .foregroundStyle(hovered ? .secondary : .tertiary)
                }

                Text(link.title)
                    .font(Theme.Typography.calloutMedium)

                Text(link.detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: Theme.Settings.Size.aboutLinkTile)
            .background(
                RoundedRectangle(
                    cornerRadius: Theme.Settings.Radius.surface,
                    style: .continuous
                )
                .fill(hovered ? Theme.Colors.rowHover : Theme.Settings.Colors.surfaceFill)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: Theme.Settings.Radius.surface,
                    style: .continuous
                )
                .strokeBorder(
                    hovered ? Theme.Colors.border : Theme.Settings.Colors.surfaceStroke,
                    lineWidth: 1
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .settingsFocusRing(cornerRadius: Theme.Settings.Radius.surface)
        .onHover { hovered = $0 }
        .accessibilityHint("Opens in another app")
    }

    @ViewBuilder
    private var glyph: some View {
        switch link.glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(Theme.Typography.iconMedium)
        case .brand(let name):
            // Brand marks paint edge to edge, so they sit a point under the SF Symbol box to read the same weight.
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
        }
    }
}

/// Hosts auxiliary SwiftUI windows (About, Settings), torn down on close so their SwiftUI trees deallocate instead of lingering, and rebuilt instantly on reopen from live state.
@MainActor
final class AuxWindowController: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]

    /// Returns `true` when a new window was created, `false` when an existing one was re-raised.
    @discardableResult
    func show<Content: View>(
        id: String, title: String, size: CGSize, seamlessTitleBar: Bool = false,
        transparentBackground: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> Bool {
        let window: NSWindow
        let isNew: Bool
        if let existing = windows[id] {
            window = existing
            isNew = false
        } else {
            isNew = true
            var style: NSWindow.StyleMask = [.titled, .closable]
            if seamlessTitleBar { style.insert(.fullSizeContentView) }
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: style,
                backing: .buffered,
                defer: false
            )
            window.title = title
            // Let the content run edge-to-edge under a transparent titlebar so the window reads as one continuous surface — the modern inspector look.
            if seamlessTitleBar {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.isMovableByWindowBackground = true
            }
            if transparentBackground {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarSeparatorStyle = .none
            }
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: content())
            // Let the window keep its requested size instead of resizing to the SwiftUI fitting size (an unconstrained fill would otherwise blow the window up); the content fills the fixed frame.
            hosting.sizingOptions = []
            window.contentView = hosting
            window.delegate = self
            window.center()
            windows[id] = window
        }
        // Promote to a regular app so the window gets a Dock icon and normal layering; demoted back to accessory when the last aux window closes.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // A plain `NSWindow` only becomes key while the app is active, but `NSApp.activate` from the menu bar is async, so the synchronous `makeKeyAndOrderFront` above can land first; re-asserting key on the next runloop makes the window truly key up front.
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
        }
        return isNew
    }

    /// Re-focus an open aux window on reopen (Dock-icon click); returns false when none is open. `windows` only holds live windows (`windowWillClose` prunes them).
    @discardableResult
    func focusExisting() -> Bool {
        guard let window = windows.values.first(where: { $0.isVisible }) ?? windows.values.first
        else { return false }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// Close a window programmatically; `windowWillClose` handles the dict/teardown so the SwiftUI tree deallocates.
    func close(id: String) {
        windows[id]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let id = windows.first(where: { $0.value === window })?.key
        else { return }
        windows.removeValue(forKey: id)
        if windows.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}
