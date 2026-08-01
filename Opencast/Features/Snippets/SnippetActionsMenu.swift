import SwiftUI

@MainActor
enum SnippetActionsMenu {
    static func content(snippet: Snippet, core: AppCore) -> PopoverMenuContent {
        PopoverMenuContent(
            header: snippet.name,
            items: [
                PopoverMenuItem(
                    title: core.palette.pasteTarget?.pasteTitle ?? "Paste",
                    systemImage: "doc.on.clipboard",
                    shortcut: "↵"
                ) {
                    core.pasteSnippet(snippet)
                },
                PopoverMenuItem(title: "Copy to Clipboard", systemImage: "doc.on.doc", shortcut: "⌘↵") {
                    core.copySnippet(snippet)
                },
                PopoverMenuItem(title: "Edit Snippet", systemImage: "pencil") {
                    core.editSnippet(snippet)
                },
                PopoverMenuItem(
                    title: "Delete Snippet", systemImage: "trash", isDestructive: true
                ) {
                    core.deleteSnippet(snippet)
                },
            ]
        )
    }
}
