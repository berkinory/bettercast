import AppKit
import SwiftUI

/// UserDefaults keys shared between `@AppStorage` call sites so the App and the Settings UI bind to the same key.
enum SettingsKey {
    /// Menu-bar icon visibility — read by `MenuBarExtra(isInserted:)` and the Settings toggle.
    static let showInMenuBar = "showInMenuBar"
}

/// Delay before a closed palette resets to the root launcher; raw value is seconds in UserDefaults, so an unset key (0) reads as `.immediately`, the default.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var nsAppearance: NSAppearance {
        NSAppearance(named: self == .dark ? .darkAqua : .aqua)!
    }
}

enum PopToRootTimeout: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case afterFive = 5
    case afterFifteen = 15
    case afterThirty = 30
    case afterSixty = 60
    case afterNinety = 90

    var id: Int { rawValue }

    var title: String {
        self == .immediately ? "Immediately" : "After \(rawValue) seconds"
    }

    var interval: TimeInterval { TimeInterval(rawValue) }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard
    private enum Key {
        static let clipboardRetention = "clipboardRetentionDays"
        static let clipboardDisabledApps = "clipboardDisabledApps"
        static let emojiSkinTone = "emojiSkinTone"
        static let popToRootTimeout = "popToRootTimeout"
        static let compactMode = "compactMode"
        static let showFavoritesInCompactMode = "showFavoritesInCompactMode"
        static let currencyConversionEnabled = "currencyConversionEnabled"
        static let cryptoConversionEnabled = "cryptoConversionEnabled"
        static let searchScopes = "launcherSearchScopes"
        static let appearance = "appearance"
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    @Published var searchScopes: [String] {
        didSet { defaults.set(searchScopes, forKey: Key.searchScopes) }
    }

    @Published var clipboardRetention: ClipboardRetention {
        didSet { defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention) }
    }

    /// Bundle IDs whose clipboard changes are never recorded. Ordered so the Settings list is stable.
    @Published var clipboardDisabledApps: [String] {
        didSet { defaults.set(clipboardDisabledApps, forKey: Key.clipboardDisabledApps) }
    }

    @Published var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    /// Preferred skin tone applied to modifier-capable emoji at render and copy time.
    @Published var emojiSkinTone: EmojiSkinTone {
        didSet { defaults.set(emojiSkinTone.rawValue, forKey: Key.emojiSkinTone) }
    }

    /// How long a closed palette keeps its state before popping back to the root launcher.
    @Published var popToRootTimeout: PopToRootTimeout {
        didSet { defaults.set(popToRootTimeout.rawValue, forKey: Key.popToRootTimeout) }
    }

    /// Summon the launcher as a slim search bar that expands into the full list on typing.
    @Published var compactMode: Bool {
        didSet { defaults.set(compactMode, forKey: Key.compactMode) }
    }

    /// Pin favorite app icons to the right of the compact search bar (⌘1–⌘5 to launch).
    @Published var showFavoritesInCompactMode: Bool {
        didSet { defaults.set(showFavoritesInCompactMode, forKey: Key.showFavoritesInCompactMode) }
    }

    @Published var currencyConversionEnabled: Bool {
        didSet { defaults.set(currencyConversionEnabled, forKey: Key.currencyConversionEnabled) }
    }

    @Published var cryptoConversionEnabled: Bool {
        didSet { defaults.set(cryptoConversionEnabled, forKey: Key.cryptoConversionEnabled) }
    }

    init() {
        // integer(forKey:) returns 0 when unset, which no case matches — falls through to 3 Months.
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: Key.clipboardRetention))
            ?? .threeMonths
        // Password managers are excluded out of the box; the defaults apply only until the user first edits the list.
        clipboardDisabledApps =
            defaults.stringArray(forKey: Key.clipboardDisabledApps)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        launchAtLogin = LaunchAtLogin.isEnabled
        emojiSkinTone =
            defaults.string(forKey: Key.emojiSkinTone).flatMap(EmojiSkinTone.init) ?? .none
        popToRootTimeout =
            PopToRootTimeout(rawValue: defaults.integer(forKey: Key.popToRootTimeout))
            ?? .immediately
        compactMode = defaults.bool(forKey: Key.compactMode)
        // Defaults to true, so absence must be distinguished from a stored `false`.
        showFavoritesInCompactMode =
            defaults.object(forKey: Key.showFavoritesInCompactMode) == nil
            || defaults.bool(forKey: Key.showFavoritesInCompactMode)
        currencyConversionEnabled =
            defaults.object(forKey: Key.currencyConversionEnabled) == nil
            || defaults.bool(forKey: Key.currencyConversionEnabled)
        cryptoConversionEnabled = defaults.bool(forKey: Key.cryptoConversionEnabled)
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init) ?? .dark
        searchScopes = SearchScopes.normalize(
            defaults.stringArray(forKey: Key.searchScopes) ?? SearchScopes.defaults)
    }
}
