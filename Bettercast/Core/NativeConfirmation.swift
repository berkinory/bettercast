import AppKit

@MainActor
enum NativeConfirmation {
    static func present(
        message: String,
        informativeText: String,
        confirmTitle: String
    ) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText
        alert.alertStyle = .warning
        let confirmButton = alert.addButton(withTitle: confirmTitle)
        confirmButton.hasDestructiveAction = true
        confirmButton.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        alert.window.level = .modalPanel
        return alert.runModal() == .alertFirstButtonReturn
    }
}
