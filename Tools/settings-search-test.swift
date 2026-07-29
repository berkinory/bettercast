import Foundation

private let records = [
    SettingsSearchRecord(
        id: "login",
        title: "Launch at Login",
        detail: "Start Bettercast when you log in.",
        breadcrumb: "General",
        keywords: ["startup", "boot", "login item"]
    ),
    SettingsSearchRecord(
        id: "clipboard-retention",
        title: "Keep Clipboard History For",
        detail: "Choose when old clipboard entries are deleted.",
        breadcrumb: "Clipboard › History",
        keywords: ["retention", "days", "months", "forever"]
    ),
    SettingsSearchRecord(
        id: "activity-monitor",
        title: "Activity Monitor",
        detail: "Configure visibility and shortcut.",
        breadcrumb: "Applications",
        keywords: ["com.apple.ActivityMonitor"]
    ),
    SettingsSearchRecord(
        id: "accessibility",
        title: "Accessibility Permission",
        detail: "Allow Bettercast to paste into the previous app.",
        breadcrumb: "Permissions",
        keywords: ["privacy", "security", "grant access"]
    ),
]

private func ids(_ query: String) -> [String] {
    SettingsSearchIndex.search(query, in: records).map(\.record.id)
}

private func expect(_ query: String, first expected: String) {
    let result = ids(query)
    guard result.first == expected else {
        fatalError("\(query.debugDescription): expected \(expected), got \(result)")
    }
}

@main
private struct SettingsSearchTest {
    static func main() {
        expect("launch", first: "login")
        expect("startup", first: "login")
        expect("retention", first: "clipboard-retention")
        expect("clipboard months", first: "clipboard-retention")
        expect("activity", first: "activity-monitor")
        expect("activty monitor", first: "activity-monitor")
        expect("privacy", first: "accessibility")

        precondition(ids("currency").isEmpty)
        precondition(SettingsSearchIndex.search("", in: records).isEmpty)
        precondition(SettingsSearchIndex.search("login", in: records, limit: 1).count == 1)

        print("settings search tests passed")
    }
}
