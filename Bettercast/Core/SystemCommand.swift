import Foundation

struct SystemCommand: Identifiable, Hashable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case lockScreen = "lock-screen"
        case sleep
        case sleepDisplays = "sleep-displays"
        case toggleMute = "toggle-mute"
        case volumeUp = "volume-up"
        case volumeDown = "volume-down"
        case openTrash = "open-trash"
        case hideOtherApps = "hide-all-apps-except-frontmost"
        case unhideAllApps = "unhide-all-hidden-apps"
        case quitAllApps = "quit-all-apps"
    }

    enum Confirmation: Sendable, Equatable {
        case none
        case required
    }

    let id: ID
    let name: String
    let sfSymbol: String
    let confirmation: Confirmation

    var entryID: String {
        id == .quitAllApps ? "command:quit-all-apps" : "system-command:" + id.rawValue
    }
}

enum SystemCommandCatalog {
    static let all: [SystemCommand] = SystemCommand.ID.allCases.map { id in
        SystemCommand(
            id: id,
            name: name(for: id),
            sfSymbol: symbol(for: id),
            confirmation: confirmation(for: id)
        )
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private static let byEntryID = Dictionary(uniqueKeysWithValues: all.map { ($0.entryID, $0) })

    static func command(forEntryID entryID: String) -> SystemCommand? {
        byEntryID[entryID]
    }

    private static func name(for id: SystemCommand.ID) -> String {
        switch id {
        case .lockScreen: return "Lock Screen"
        case .sleep: return "Sleep"
        case .sleepDisplays: return "Sleep Displays"
        case .toggleMute: return "Toggle Mute"
        case .volumeUp: return "Turn Volume Up"
        case .volumeDown: return "Turn Volume Down"
        case .openTrash: return "Open Trash"
        case .hideOtherApps: return "Hide All Apps Except Frontmost"
        case .unhideAllApps: return "Unhide All Hidden Apps"
        case .quitAllApps: return "Quit All Applications"
        }
    }

    private static func symbol(for id: SystemCommand.ID) -> String {
        switch id {
        case .lockScreen: return "lock"
        case .sleep: return "moon.zzz"
        case .sleepDisplays: return "display"
        case .toggleMute: return "speaker.slash"
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        case .openTrash: return "trash"
        case .hideOtherApps: return "eye.slash.circle"
        case .unhideAllApps: return "eye.circle"
        case .quitAllApps: return "xmark.circle"
        }
    }

    private static func confirmation(for id: SystemCommand.ID) -> SystemCommand.Confirmation {
        id == .quitAllApps ? .required : .none
    }
}
