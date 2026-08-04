import SwiftUI

@MainActor
enum QuicklinkActionsMenu {
    static func content(
        quicklink: Quicklink, core: AppCore, favorites: FavoritesStore,
        onToggleFavorite: @escaping () -> Void,
        onTogglePinned: (() -> Void)? = nil
    ) -> PopoverMenuContent {
        let favoriteItem =
            favorites.isFavorite(quicklink)
            ? PopoverMenuItem(
                title: "Remove from Favorites", systemImage: "star.slash", shortcut: "⌘F",
                action: onToggleFavorite)
            : PopoverMenuItem(
                title: "Add to Favorites", systemImage: "star", shortcut: "⌘F",
                action: onToggleFavorite)
        let pinnedItem =
            quicklink.isPinned
            ? PopoverMenuItem(
                title: "Unpin Quicklink", systemImage: "pin.slash", shortcut: "⌘P"
            ) {
                if let onTogglePinned {
                    onTogglePinned()
                } else {
                    core.togglePinnedQuicklink(quicklink)
                }
            }
            : PopoverMenuItem(
                title: "Pin Quicklink", systemImage: "pin", shortcut: "⌘P"
            ) {
                if let onTogglePinned {
                    onTogglePinned()
                } else {
                    core.togglePinnedQuicklink(quicklink)
                }
            }
        return PopoverMenuContent(
            header: quicklink.name,
            items: [
                PopoverMenuItem(
                    title: "Open Quicklink", systemImage: "arrow.up.right", shortcut: "↵"
                ) {
                    core.openQuicklink(quicklink)
                },
                favoriteItem,
                pinnedItem,
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
