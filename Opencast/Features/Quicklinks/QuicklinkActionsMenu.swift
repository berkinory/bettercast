import SwiftUI

@MainActor
enum QuicklinkActionsMenu {
    static func content(quicklink: Quicklink, core: AppCore) -> PopoverMenuContent {
        PopoverMenuContent(
            header: quicklink.name,
            items: [
                PopoverMenuItem(
                    title: "Open Quicklink", systemImage: "arrow.up.right", shortcut: "↵"
                ) {
                    core.openQuicklink(quicklink)
                },
                PopoverMenuItem(title: "Copy Link", systemImage: "doc.on.doc", shortcut: "⌘↵") {
                    core.copyQuicklink(quicklink)
                },
                PopoverMenuItem(title: "Duplicate Quicklink", systemImage: "plus.square.on.square") {
                    core.duplicateQuicklink(quicklink)
                },
                PopoverMenuItem(title: "Edit Quicklink", systemImage: "pencil") {
                    core.editQuicklink(quicklink)
                },
                PopoverMenuItem(
                    title: "Delete Quicklink", systemImage: "trash", isDestructive: true
                ) {
                    core.deleteQuicklink(quicklink)
                },
            ]
        )
    }
}
