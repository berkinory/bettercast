import AppKit
import SwiftUI

struct AboutView: View {
    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

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
        VStack(spacing: 0) {
            ScrollView {
                // A tighter block rhythm than `SettingsPane`'s `xxl` so hero, links and support all land above the fold of the fixed-height Settings window.
                VStack(spacing: Theme.Spacing.xl) {
                    hero
                    links
                    support
                }
                // Ignore the transparent-titlebar safe area and use one fixed `xxl` inset every side, matching `SettingsPane`.
                .padding(Theme.Spacing.xxl)
                .frame(maxWidth: .infinity)
                .overlayScroller(disablesElasticity: true)
            }
            // Outside the scroll view so the copyright stays pinned to the pane's bottom edge, the way a real About window reads.
            footer
                .padding(.bottom, Theme.Spacing.xxl)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var hero: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Image(nsImage: Self.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: Theme.Settings.Size.aboutIcon,
                    height: Theme.Settings.Size.aboutIcon
                )
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

            VStack(spacing: Theme.Spacing.sm) {
                Text(Bundle.main.appDisplayName)
                    .font(Theme.Typography.titleBold)
                Text(Self.version)
                    .font(Theme.Typography.captionMonospacedDigit)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs / 2)
                    .background(
                        Capsule().fill(Theme.Colors.cardFill)
                    )
                    .overlay(
                        Capsule().strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            }

            Text("A focused, native launcher for macOS.")
                .font(Theme.Typography.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var links: some View {
        SettingsSection(header: "Project & Community") {
            // Rows paint a full-bleed hover fill, so the stack is clipped to the card's corner — otherwise the first/last row's highlight squares off the rounded ends.
            VStack(spacing: 0) {
                ForEach(AboutLink.all) { link in
                    if link.id != AboutLink.all.first?.id { SettingsRowDivider() }
                    AboutLinkRow(link: link)
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Theme.Settings.Radius.surface,
                    style: .continuous
                )
            )
        }
    }

    // No section header: the callout's own title is the header.
    private var support: some View {
        SettingsStatusCard(
            title: "Built in the open",
            message: "Bettercast builds on Tinycast by Abue Ammar and is released under AGPL-3.0.",
            systemImage: "chevron.left.forwardslash.chevron.right",
            tint: Theme.Colors.textSecondary
        )
    }

    private var footer: some View {
        Text("Tinycast © 2026 Abue Ammar · AGPL-3.0")
            .font(Theme.Typography.caption2)
            .foregroundStyle(.tertiary)
    }
}

/// One external destination in the About "Links" card.
private struct AboutLink: Identifiable {
    enum Glyph {
        case symbol(String)
        /// A brand mark from `Assets.xcassets` (template SVG) — SF Symbols ships no GitHub/Discord/X logo.
        case brand(String)
    }

    let id: String
    let glyph: Glyph
    let title: String
    let detail: String
    let url: URL

    static let all: [AboutLink] = [
        AboutLink(
            id: "github", glyph: .brand("BrandGitHub"), title: "Tinycast Source",
            detail: "Original open-source project",
            url: URL(string: "https://github.com/abue-ammar/tinycast")!),
        AboutLink(
            id: "discord", glyph: .brand("BrandDiscord"), title: "Discord",
            detail: "Join the community",
            url: URL(string: "https://discord.gg/v2Eeb4QQy3")!),
        AboutLink(
            id: "x", glyph: .brand("BrandX"), title: "X", detail: "@abue_ammar",
            url: URL(string: "https://x.com/abue_ammar")!),
        AboutLink(
            id: "email", glyph: .symbol("envelope"), title: "Email",
            detail: "iabueammar@gmail.com", url: URL(string: "mailto:iabueammar@gmail.com")!),
    ]
}

/// A tappable row inside the About "Links" card: glyph, title, the destination in plain text, and the external-link arrow.
private struct AboutLinkRow: View {
    let link: AboutLink

    @State private var hovered = false

    var body: some View {
        Link(destination: link.url) {
            HStack(spacing: Theme.Spacing.lg) {
                glyph
                    .frame(width: Theme.Settings.Size.controlIcon)
                    .foregroundStyle(.secondary)
                Text(link.title)
                    .font(Theme.Typography.body)
                Spacer(minLength: Theme.Spacing.xl)
                Text(link.detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(Theme.Typography.captionSemibold)
                    .foregroundStyle(hovered ? .secondary : .tertiary)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
            .background(hovered ? Theme.Colors.rowHover : .clear)
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
