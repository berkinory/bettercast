import AppKit
import Darwin
import Foundation
import Security

struct PreparedUpdate: Sendable {
    let stagingURL: URL
    let appURL: URL
    let version: String
}

enum UpdateInstaller {
    enum Failure: LocalizedError {
        case invalidArchive
        case invalidSignature
        case wrongBundle
        case wrongVersion
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidArchive: "The downloaded update archive is invalid."
            case .invalidSignature: "The downloaded update signature does not match Opencast."
            case .wrongBundle: "The downloaded update is not an Opencast application."
            case .wrongVersion: "The downloaded update has an invalid version."
            case .processFailed(let message): message
            }
        }
    }

    static func prepare(
        archiveURL: URL,
        expectedVersion: String,
        archiveKind: UpdateStore.ArchiveKind,
        currentAppURL: URL,
        currentBundleID: String
    ) throws -> PreparedUpdate {
        let stagingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpencastUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        do {
            switch archiveKind {
            case .zip:
                try run("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, stagingURL.path])
            case .diskImage:
                try extractDiskImage(archiveURL, to: stagingURL)
            }
            let apps = try FileManager.default.contentsOfDirectory(
                at: stagingURL, includingPropertiesForKeys: nil
            ).filter { $0.pathExtension.lowercased() == "app" }
            guard apps.count == 1, let appURL = apps.first else { throw Failure.invalidArchive }
            guard Bundle(url: appURL)?.bundleIdentifier == currentBundleID else {
                throw Failure.wrongBundle
            }
            guard
                Bundle(url: appURL)?.infoDictionary?["CFBundleShortVersionString"] as? String
                    == expectedVersion
            else { throw Failure.wrongVersion }
            try verifySignature(currentAppURL: currentAppURL, updateURL: appURL)
            return PreparedUpdate(stagingURL: stagingURL, appURL: appURL, version: expectedVersion)
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }
    }

    static func discard(_ update: PreparedUpdate) {
        try? FileManager.default.removeItem(at: update.stagingURL)
    }

    static func launchApply(_ update: PreparedUpdate) throws {
        guard let executableURL = Bundle.main.executableURL else { throw Failure.invalidArchive }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--opencast-apply-update", update.stagingURL.path,
            "--opencast-parent-pid", String(getpid()),
            "--opencast-update-version", update.version,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    @MainActor
    static func applyIfRequested() -> Bool {
        guard let stagingPath = argument(after: "--opencast-apply-update"),
            let parentPID = argument(after: "--opencast-parent-pid").flatMap({ pid_t($0) }),
            let expectedVersion = argument(after: "--opencast-update-version")
        else { return false }

        let currentAppURL = Bundle.main.bundleURL
        waitForExit(parentPID)
        do {
            let apps = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: stagingPath), includingPropertiesForKeys: nil
            ).filter { $0.pathExtension.lowercased() == "app" }
            guard apps.count == 1, let updateURL = apps.first else { throw Failure.invalidArchive }
            guard Bundle(url: updateURL)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw Failure.wrongBundle
            }
            guard
                Bundle(url: updateURL)?.infoDictionary?["CFBundleShortVersionString"] as? String
                    == expectedVersion
            else { throw Failure.wrongVersion }
            try verifySignature(currentAppURL: currentAppURL, updateURL: updateURL)
            try replaceApp(at: currentAppURL, with: updateURL)
            NSWorkspace.shared.openApplication(at: currentAppURL, configuration: .init())
        } catch {
            NSWorkspace.shared.openApplication(at: currentAppURL, configuration: .init())
        }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: stagingPath))
        return true
    }

    private static func verifySignature(currentAppURL: URL, updateURL: URL) throws {
        var currentCode: SecStaticCode?
        var updateCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(currentAppURL as CFURL, [], &currentCode) == errSecSuccess,
            SecStaticCodeCreateWithPath(updateURL as CFURL, [], &updateCode) == errSecSuccess,
            let currentCode,
            let updateCode
        else { throw Failure.invalidSignature }

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(currentCode, [], &requirement) == errSecSuccess,
            let requirement,
            SecStaticCodeCheckValidity(updateCode, [], requirement) == errSecSuccess
        else { throw Failure.invalidSignature }
    }

    private static func replaceApp(at destination: URL, with update: URL) throws {
        let backup = destination.deletingLastPathComponent()
            .appendingPathComponent(".Opencast-backup-\(UUID().uuidString).app", isDirectory: true)
        let manager = FileManager.default
        try manager.moveItem(at: destination, to: backup)
        do {
            try manager.moveItem(at: update, to: destination)
            try? manager.removeItem(at: backup)
        } catch {
            try? manager.moveItem(at: backup, to: destination)
            throw error
        }
    }

    private static func extractDiskImage(_ archiveURL: URL, to stagingURL: URL) throws {
        let mountURL = stagingURL.appendingPathComponent("Mount", isDirectory: true)
        try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
        try run(
            "/usr/bin/hdiutil",
            arguments: ["attach", "-nobrowse", "-readonly", "-mountpoint", mountURL.path, archiveURL.path]
        )
        defer { try? run("/usr/bin/hdiutil", arguments: ["detach", mountURL.path]) }
        let apps = try FileManager.default.contentsOfDirectory(
            at: mountURL, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "app" }
        guard apps.count == 1, let app = apps.first else { throw Failure.invalidArchive }
        try FileManager.default.copyItem(
            at: app,
            to: stagingURL.appendingPathComponent(app.lastPathComponent, isDirectory: true)
        )
    }

    private static func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message =
                String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                ?? "The update archive could not be unpacked."
            throw Failure.processFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func waitForExit(_ pid: pid_t) {
        for _ in 0..<300 {
            if kill(pid, 0) != 0 { return }
            usleep(100_000)
        }
    }

    private static func argument(after name: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: name),
            CommandLine.arguments.indices.contains(index + 1)
        else { return nil }
        return CommandLine.arguments[index + 1]
    }
}
