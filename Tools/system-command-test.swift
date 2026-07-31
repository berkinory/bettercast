import Foundation

@main
private struct SystemCommandTests {
    static func main() {
        let commands = SystemCommandCatalog.all
        precondition(commands.count == 21)
        precondition(Set(commands.map(\.entryID)).count == commands.count)
        precondition(
            SystemCommandCatalog.command(forEntryID: "command:quit-all-apps")?.id
                == .quitAllApps)
        precondition(
            SystemCommandCatalog.command(forEntryID: "system-command:show-desktop")?.id
                == .showDesktop)
        precondition(
            SystemCommandCatalog.command(forEntryID: "system-command:toggle-hidden-files")?.id
                == .toggleHiddenFiles)
        precondition(
            SystemCommandCatalog.command(forEntryID: "system-command:eject-all-disks")?.id
                == .ejectAllDisks)
        precondition(
            SystemCommandCatalog.command(forEntryID: "system-command:eject-all-disks")?.confirmation
                == .required)
        precondition(
            SystemCommandCatalog.command(forEntryID: "system-command:quit-all-apps") == nil)
        precondition(
            SystemCommandCatalog.command(forEntryID: "command:quit-all-apps")?.confirmation
                == .required)
        print("system command tests passed")
    }
}
