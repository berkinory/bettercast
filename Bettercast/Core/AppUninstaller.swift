import AppKit
import Foundation

struct AppUninstallIdentity: Sendable {
    let name: String
    let bundleID: String?
    let appPath: String
}

struct AppUninstallCandidate: Identifiable, Sendable {
    let path: String
    let category: String
    let size: Int64?

    var id: String { path }
}

struct AppUninstallPlan: Sendable {
    let app: AppUninstallIdentity
    let appSize: Int64?
    let userCandidates: [AppUninstallCandidate]
    let systemCandidates: [AppUninstallCandidate]

    var totalCandidates: Int { userCandidates.count + systemCandidates.count }
}

struct AppUninstallResult: Sendable {
    let movedPaths: [String]
    let failedPaths: [String]
    let appFailure: String?
}

@MainActor
final class AppUninstaller {
    static func isEligible(_ app: AppEntry) -> Bool {
        guard app.kind == .application, app.url.pathExtension == "app" else { return false }
        let path = app.url.standardizedFileURL.path
        guard path != Bundle.main.bundleURL.standardizedFileURL.path else { return false }
        return !path.hasPrefix("/System/Applications/") && path != "/System/Applications"
    }

    func plan(for app: AppEntry) async -> AppUninstallPlan {
        let identity = AppUninstallIdentity(name: app.name, bundleID: app.bundleID, appPath: app.url.path)
        return await Task.detached(priority: .userInitiated) {
            AppUninstallPlanner.plan(identity)
        }.value
    }

    func execute(_ plan: AppUninstallPlan) async -> AppUninstallResult {
        await Task.detached(priority: .userInitiated) {
            AppUninstallExecutor.execute(plan)
        }.value
    }
}

private enum AppUninstallPlanner {
    private enum MatchMode {
        case bundleID
        case bundleIDOrName
        case preference
    }

    private struct SearchSpec {
        let root: URL
        let category: String
        let mode: MatchMode
    }

    static func plan(_ identity: AppUninstallIdentity) -> AppUninstallPlan {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let userLibrary = home.appendingPathComponent("Library", isDirectory: true)
        let systemLibrary = URL(fileURLWithPath: "/Library", isDirectory: true)
        let userSpecs = specs(library: userLibrary)
        let systemSpecs = specs(library: systemLibrary)
        let userCandidates = discover(userSpecs, identity: identity)
        let systemCandidates = discover(systemSpecs, identity: identity)
        return AppUninstallPlan(
            app: identity,
            appSize: directorySize(URL(fileURLWithPath: identity.appPath)),
            userCandidates: userCandidates,
            systemCandidates: systemCandidates
        )
    }

    private static func specs(library: URL) -> [SearchSpec] {
        [
            SearchSpec(
                root: library.appendingPathComponent("Application Support"), category: "Application Support",
                mode: .bundleIDOrName),
            SearchSpec(root: library.appendingPathComponent("Caches"), category: "Caches", mode: .bundleIDOrName),
            SearchSpec(root: library.appendingPathComponent("Containers"), category: "Containers", mode: .bundleID),
            SearchSpec(
                root: library.appendingPathComponent("Group Containers"), category: "Group Containers", mode: .bundleID),
            SearchSpec(
                root: library.appendingPathComponent("HTTPStorages"), category: "HTTP Storages", mode: .bundleID),
            SearchSpec(root: library.appendingPathComponent("Logs"), category: "Logs", mode: .bundleIDOrName),
            SearchSpec(
                root: library.appendingPathComponent("Saved Application State"), category: "Saved Application State",
                mode: .bundleID),
            SearchSpec(root: library.appendingPathComponent("WebKit"), category: "WebKit", mode: .bundleID),
            SearchSpec(
                root: library.appendingPathComponent("Application Scripts"), category: "Application Scripts",
                mode: .bundleID),
            SearchSpec(
                root: library.appendingPathComponent("LaunchAgents"), category: "Launch Agents", mode: .bundleID),
            SearchSpec(
                root: library.appendingPathComponent("LaunchDaemons"), category: "Launch Daemons", mode: .bundleID),
            SearchSpec(root: library.appendingPathComponent("Preferences"), category: "Preferences", mode: .preference),
            SearchSpec(
                root: library.appendingPathComponent("Preferences/ByHost"), category: "ByHost Preferences",
                mode: .preference),
        ]
    }

    private static func discover(_ specs: [SearchSpec], identity: AppUninstallIdentity) -> [AppUninstallCandidate] {
        var candidates: [AppUninstallCandidate] = []
        for spec in specs {
            guard
                let entries = try? FileManager.default.contentsOfDirectory(
                    at: spec.root,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: []
                )
            else { continue }
            for entry in entries where matches(entry, identity: identity, mode: spec.mode) {
                candidates.append(
                    AppUninstallCandidate(
                        path: entry.standardizedFileURL.path,
                        category: spec.category,
                        size: directorySize(entry)
                    )
                )
            }
        }
        return candidates.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    private static func matches(_ url: URL, identity: AppUninstallIdentity, mode: MatchMode) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
        let exactNames = Set(
            [
                normalized(identity.name),
                identity.bundleID.map(normalized) ?? "",
            ].filter { !$0.isEmpty })
        let normalizedName = normalized(name)
        switch mode {
        case .bundleID:
            guard let bundleID = identity.bundleID else { return false }
            let id = normalized(bundleID)
            return normalizedName == id
                || normalizedName == "group." + id
                || normalizedName.hasSuffix("." + id)
        case .bundleIDOrName:
            guard let bundleID = identity.bundleID else { return exactNames.contains(normalizedName) }
            let id = normalized(bundleID)
            return exactNames.contains(normalizedName) || normalizedName.hasPrefix(id + ".")
        case .preference:
            guard let bundleID = identity.bundleID else { return exactNames.contains(normalizedName) }
            let id = normalized(bundleID)
            return normalizedName == id || normalizedName.hasPrefix(id + ".") || exactNames.contains(normalizedName)
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private static func directorySize(_ url: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileAllocatedSizeKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        guard values.isDirectory == true else {
            return values.fileAllocatedSize.map(Int64.init) ?? values.fileSize.map(Int64.init)
        }
        guard
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants]
            )
        else { return nil }
        var total: Int64 = 0
        while let child = enumerator.nextObject() as? URL {
            guard let childValues = try? child.resourceValues(forKeys: keys),
                childValues.isDirectory != true
            else { continue }
            total += Int64(childValues.fileAllocatedSize ?? childValues.fileSize ?? 0)
        }
        return total
    }
}

private enum AppUninstallExecutor {
    static func execute(_ plan: AppUninstallPlan) -> AppUninstallResult {
        guard validateAppPath(plan.app.appPath) else {
            return AppUninstallResult(
                movedPaths: [], failedPaths: [], appFailure: "The application path is no longer valid.")
        }

        unloadUserLaunchAgents(plan.userCandidates, bundleID: plan.app.bundleID)
        var appResultingURL: NSURL?
        do {
            try FileManager.default.trashItem(
                at: URL(fileURLWithPath: plan.app.appPath),
                resultingItemURL: &appResultingURL
            )
        } catch {
            return AppUninstallResult(
                movedPaths: [],
                failedPaths: [],
                appFailure: "Could not move the application to the Trash: \(error.localizedDescription)"
            )
        }

        var movedPaths = [plan.app.appPath]
        var failedPaths: [String] = []
        for candidate in plan.userCandidates {
            guard validateCandidatePath(candidate.path) else {
                failedPaths.append(candidate.path)
                continue
            }
            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(
                    at: URL(fileURLWithPath: candidate.path),
                    resultingItemURL: &resultingURL
                )
                movedPaths.append(candidate.path)
            } catch {
                failedPaths.append(candidate.path)
            }
        }
        return AppUninstallResult(movedPaths: movedPaths, failedPaths: failedPaths, appFailure: nil)
    }

    private static func unloadUserLaunchAgents(_ candidates: [AppUninstallCandidate], bundleID: String?) {
        guard let bundleID, isValidBundleID(bundleID) else { return }
        let uid = String(getuid())
        for candidate in candidates where candidate.category == "Launch Agents" {
            runLaunchctl(["bootout", "gui/\(uid)", candidate.path])
        }
    }

    private static func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let deadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        } catch {}
    }

    private static func validateAppPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.pathExtension == "app", url.path != "/", !url.path.contains("/../") else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func validateCandidatePath(_ path: String) -> Bool {
        let homeLibrary = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .standardizedFileURL.path
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path.hasPrefix(homeLibrary + "/") else { return false }
        guard !url.path.contains("/../"), url.path != homeLibrary else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func isValidBundleID(_ bundleID: String) -> Bool {
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }
}
