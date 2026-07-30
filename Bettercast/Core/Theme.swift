import SwiftUI

/// Central design tokens for the palette UI (dark design system per `docs/ui.md`; the app forces `.darkAqua`, so colors are literal white/black alphas).
enum Theme {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 20
        /// Calculator answer card's roomier vertical breathing room.
        static let xxxl: CGFloat = 28
        /// Gap under a category header before its first row; shared by every palette list's `SectionHeader` (launcher, clipboard, emoji, calculator history).
        static let sectionHeaderBottom: CGFloat = 4
        /// Space above a category header (every header except the list's first), which reads as bottom padding closing the previous section — shared by every palette list.
        static let sectionSpacing: CGFloat = 12
    }

    enum Radius {
        static let panel: CGFloat = 26
        static let row: CGFloat = 10
        static let menu: CGFloat = 6
        /// Hover highlight behind a popover menu row.
        static let menuRow: CGFloat = 10
        static let menuPanel: CGFloat = 16
        static let thumbnail: CGFloat = 6
        static let card: CGFloat = 10
        static let keyCap: CGFloat = 6
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 4
    }

    enum Size {
        static let panelWidth: CGFloat = 750
        static let panelHeight: CGFloat = 475
        /// Fraction of the active screen's visible height between the top of the visible area and the palette's top edge; the window grows downward from this edge (Spotlight-style upper placement).
        static let paletteTopMarginFraction: CGFloat = 0.18
        static let headerHeight: CGFloat = 44
        /// Fixed slot for the header leading glyph (search / back chevron / mode icon) so the search field starts at the same x in every mode — glyphs have different intrinsic widths (chevron 14, magnifyingglass 22). Sized to the magnifyingglass so the launcher spacing is unchanged.
        static let headerIconSlot: CGFloat = 22
        /// Vertical breathing room above the search row — constant across compact/expanded so the bar never shifts when typing flips the state; also the compact bar's symmetric top/bottom slack.
        static let headerPadding: CGFloat = 10
        /// Collapsed compact bar: the search row centered in symmetric `headerPadding` slack.
        static let compactHeight: CGFloat = headerHeight + headerPadding * 2
        static let bottomBarHeight: CGFloat = 52
        static let rowIcon: CGFloat = 24
        static let keyCap: CGFloat = 18
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 16
        static let menuButton: CGFloat = 36
        static let feedbackHalo: CGFloat = 18
        /// Minimum height for each value column so badges sit near the card's lower edge.
        static let calcCardColumnHeight: CGFloat = 88
        static let clipboardListWidth: CGFloat = 290
        static let emojiCell: CGFloat = 56
        static let menuWidth: CGFloat = 276
        /// Square slot for a popover-menu row's leading glyph. 20 (not the 16 the artwork suggests) because an `IconCache` app icon only paints ~85% of its canvas: at 20 its visible artwork is 17pt, matching the 17–18pt a `.body` SF Symbol renders at, so symbol and app-icon rows read the same size.
        static let menuIcon: CGFloat = 20
        static let statusDot: CGFloat = 6
    }

    /// System text styles (not hardcoded sizes) so the UI honors Dynamic Type.
    enum Typography {
        static let searchField = Font.system(size: 20, weight: .regular)
        static let headerIcon = Font.system(size: 18, weight: .medium)
        static let rowTitle = Font.body
        static let rowTrailing = Font.callout
        static let sectionHeader = Font.subheadline.weight(.medium)
        /// The big value line on the calculator answer card (both source and target sides).
        static let calcResult = Font.largeTitle
        static let calcBadge = Font.subheadline.weight(.semibold)
        static let calcArrow = Font.callout.weight(.semibold)
        static let keyCap = Font.caption
        static let bar = Font.callout.weight(.medium)
        static let menuRow = Font.body
        static let menuShortcut = Font.callout
        static let menuIcon = Font.body
    }

    enum Settings {
        enum Size {
            static let window = CGSize(width: 760, height: 560)
            static let sidebarWidth: CGFloat = 190
            static let sidebarIcon: CGFloat = 18
            static let sidebarRowHeight: CGFloat = 34
            static let searchHeight: CGFloat = 32
            static let controlHeight: CGFloat = 32
            static let headerIcon: CGFloat = 38
            static let controlIcon: CGFloat = 28
            static let statusIcon: CGFloat = 34
            static let modeTileHeight: CGFloat = 92
            static let modePreviewWidth: CGFloat = 74
            static let modePreviewHeight: CGFloat = 42
            static let compactModePreviewHeight: CGFloat = 18
            static let excludedAppChipMinimum: CGFloat = 150
            static let excludedAppChipHeight: CGFloat = 36
            static let skinToneButton: CGFloat = 40
            static let shortcutColumn: CGFloat = 132
            static let visibilityButton: CGFloat = 36
            static let shortcutRecorderHeight: CGFloat = 28
            static let shortcutRecorderWidth: CGFloat = 102
            static let shortcutRecorderClearWidth: CGFloat = 26
            static let shortcutPopoverWidth: CGFloat = 280
            static let shortcutPopoverBodyHeight: CGFloat = 113
            static let shortcutPopoverFooterHeight: CGFloat = 36
            static let shortcutPopoverKeycap: CGFloat = 28
            static let aboutIcon: CGFloat = 88
        }

        enum Radius {
            static let navigation: CGFloat = Theme.Radius.row
            static let search: CGFloat = Theme.Radius.row
            static let iconTile: CGFloat = 7
            static let headerIcon: CGFloat = 10
            static let controlIcon: CGFloat = 8
            static let surface: CGFloat = Theme.Radius.card
            static let rowHighlight: CGFloat = 11
            static let modeTile: CGFloat = 12
            static let modePreview: CGFloat = 8
        }

        enum Layout {
            static let paneInset: CGFloat = 20
            static let sectionSpacing: CGFloat = 18
            static let sidebarInset: CGFloat = 8
            static let sidebarTopInset: CGFloat = 20
            static let groupSpacing: CGFloat = 18
            static let rowHorizontal: CGFloat = 12
            static let rowVertical: CGFloat = 9
            static let rowGap: CGFloat = 10
        }

        enum Colors {
            static let navigationSelection = Theme.Colors.selection
            static let navigationHover = Theme.Colors.rowHover
            static let searchFill = Theme.Colors.cardFill
            static let searchStroke = Theme.Colors.cardStroke
            static let searchFocus = Theme.Colors.border
            static let captureConflict = Color(red: 1.0, green: 0.36, blue: 0.46)
            static let captureConflictFill = captureConflict.opacity(0.08)
            static let captureSuccessFill = Color.green.opacity(0.07)
            static let sidebarSeparator = Theme.Colors.separator
            static let sidebarDimming = Color.black.opacity(0.14)
            static let surfaceFill = Theme.Colors.cardFill
            static let surfaceStroke = Theme.Colors.cardStroke
            static let rowDivider = Theme.Colors.separator
        }

        enum Motion {
            static let highlightFade = 0.10
        }
    }

    enum Colors {
        /// Black opacity of the panel's surface tint over the behind-window material.
        static let panelDimming: CGFloat = 0.4
        /// Selection fill: a soft neutral translucent layer shared by launcher and clipboard so both lists look identical.
        static let selection = Color.white.opacity(0.10)
        /// Mouse hover — a fainter layer that follows the cursor, visually distinct from selection.
        static let rowHover = Color.white.opacity(0.05)
        static let menuHover = Color.white.opacity(0.10)
        static let separator = Color.white.opacity(0.10)
        /// Small control surfaces: kbd chips, glyph tiles.
        static let controlSurface = Color.white.opacity(0.10)
        /// Control borders: outlined kbd chips.
        static let border = Color.white.opacity(0.20)
        static let textSecondary = Color.white.opacity(0.60)
        static let textTertiary = Color.white.opacity(0.40)
        /// Settings grouped "card": a faint raised surface whose hairline border doubles as the inset row divider.
        static let cardFill = Color.white.opacity(0.05)
        static let cardStroke = Color.white.opacity(0.10)
        /// Whitish tint layered into the Liquid Glass floating controls (action group + menu circle) so the glass reads frosted rather than clear.
        static let glassFrost = Color.white.opacity(0.05)
        static let feedbackFill = Color.green.opacity(0.18)
        static let feedbackShade = Color.black.opacity(0.40)
        static let feedbackStroke = Color.white.opacity(0.20)
        static let feedbackAccent = Color(red: 0.24, green: 0.82, blue: 0.52)
        /// The violet of the app mark. The one non-white hue in the system, used only to tint the About support callout.
        static let brand = Color(red: 0.525, green: 0.231, blue: 1.0)
    }
}

/// A single keycap chip: `.outline` for hotkey hints on rows, `.filled` for footer shortcuts.
struct KeyCapChip: View {
    enum Style {
        case outline
        case filled
    }

    let text: String
    var style: Style = .filled

    /// "↵" is absent from SF Pro and falls back to Lucida Grande UI, which seats it 1.1pt higher in the line box than the SF caps — visibly top-heavy in a chip. Nudging via `offset` is render-only, so the chip keeps the same footprint as every other cap.
    private static let returnGlyphDrop: CGFloat = 1.1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
        Text(text)
            .font(Theme.Typography.keyCap)
            .foregroundStyle(Theme.Colors.textSecondary)
            .offset(y: text == "↵" ? Self.returnGlyphDrop : 0)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(minWidth: Theme.Size.keyCap, minHeight: Theme.Size.keyCap)
            .background {
                switch style {
                case .filled: shape.fill(Theme.Colors.controlSurface)
                case .outline: shape.strokeBorder(Theme.Colors.border, lineWidth: 1)
                }
            }
    }
}

extension View {
    /// A floating Liquid Glass control surface on Tahoe, with a solid dark fallback on older supported systems.
    @ViewBuilder
    func frosted<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.interactive().tint(Theme.Colors.glassFrost), in: shape)
                .tint(.clear)
        } else {
            background(shape.fill(Theme.Colors.controlSurface))
                .overlay(shape.stroke(Theme.Colors.border, lineWidth: 1))
                .tint(.clear)
        }
    }
}
