import AppKit
import UniformTypeIdentifiers

/// User-facing entry points for the native backup and import flows.
@MainActor
enum BackupActions {
    // MARK: - Bettercast native (self-contained: own file panels + alerts)

    static func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Bettercast-Settings-\(dateStamp()).json"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackup.gather().encoded().write(to: url, options: .atomic)
        } catch {
            present(title: "Export Failed", message: error.localizedDescription, style: .warning)
        }
    }

    static func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let backup = try SettingsBackup(json: try Data(contentsOf: url))
            present(
                title: "Settings Imported", message: summaryText(backup.apply()),
                style: .informational
            )
        } catch {
            present(title: "Import Failed", message: error.localizedDescription, style: .warning)
        }
    }

    // MARK: - Helpers

    static func summaryText(_ s: SettingsBackup.ApplySummary) -> String {
        var parts: [String] = []
        if s.settingsFields > 0 { parts.append("\(s.settingsFields) settings") }
        if s.hotkeys > 0 { parts.append("\(s.hotkeys) shortcuts") }
        if s.favorites > 0 { parts.append("\(s.favorites) favorites") }
        if s.hiddenItems > 0 { parts.append("\(s.hiddenItems) hidden items") }
        return parts.isEmpty
            ? "Nothing to import from this file." : "Applied " + parts.joined(separator: ", ") + "."
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func present(title: String, message: String, style: NSAlert.Style) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.runModal()
    }
}
