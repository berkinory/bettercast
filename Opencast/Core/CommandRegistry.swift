import Foundation

/// App-internal launcher actions surfaced as a "Commands" category; each is a synthetic `AppEntry` (kind `.command`, no bundle ID) so existing `AppEntry` plumbing applies, with dispatch in `AppCore.runCommand`.
enum CommandID: String, CaseIterable, Sendable {
    case clipboardHistory = "command:clipboard-history"
    case searchSnippets = "command:search-snippets"
    case createSnippet = "command:create-snippet"
    case searchQuicklinks = "command:search-quicklinks"
    case createQuicklink = "command:create-quicklink"
    case searchEmoji = "command:search-emoji"
    case settings = "command:settings"
    case checkForUpdates = "command:check-for-updates"
    case quit = "command:quit"

    var name: String {
        switch self {
        case .clipboardHistory: return "Clipboard History"
        case .searchSnippets: return "Search Snippets"
        case .createSnippet: return "Create Snippet"
        case .searchQuicklinks: return "Search Quicklinks"
        case .createQuicklink: return "Create Quicklink"
        case .searchEmoji: return "Search Emoji & Symbols"
        case .settings: return "Settings"
        case .checkForUpdates: return "Check for Updates"
        case .quit: return "Quit Opencast"
        }
    }

    var sfSymbol: String {
        switch self {
        case .clipboardHistory: return "doc.on.clipboard"
        case .searchSnippets, .createSnippet: return "text.quote"
        case .searchQuicklinks, .createQuicklink: return "link"
        case .searchEmoji: return "face.smiling"
        case .settings: return "gearshape"
        case .checkForUpdates: return "arrow.down.circle"
        case .quit: return "power"
        }
    }
}

enum CommandRegistry {
    /// Sorted by name to keep the AppIndex sort invariant; the URL is a placeholder since commands are never launched from disk.
    nonisolated static let all: [AppEntry] =
        CommandID.allCases
        .map { id in
            AppEntry(
                id: id.rawValue, name: id.name,
                url: URL(
                    string: "opencast://" + id.rawValue.replacingOccurrences(of: ":", with: "/"))!,
                bundleID: nil, kind: .command)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    static func command(for entry: AppEntry) -> CommandID? {
        CommandID(rawValue: entry.id)
    }
}
