import Combine
import CryptoKit
import Foundation
import OSLog

@MainActor
final class UpdateStore: ObservableObject {
    enum ArchiveKind: Equatable, Sendable {
        case zip
        case diskImage
    }

    struct UpdateInfo: Equatable, Sendable {
        let version: String
        let releaseURL: URL
        let downloadURL: URL
        let archiveKind: ArchiveKind
        let sha256: String
        let notes: String
    }

    enum State: Equatable {
        case idle
        case checking
        case downloading
        case preparing
        case upToDate
        case available(UpdateInfo)
        case unavailable(String)
        case failed(String)
    }

    enum HomebrewCheck: Equatable, Sendable {
        case upToDate
        case updateAvailable(current: String, latest: String)
        case unavailable(String)
    }

    private struct GitHubRelease: Decodable, Sendable {
        let tagName: String
        let htmlURL: URL
        let body: String?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
            case assets
        }
    }

    private struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case digest
        }
    }

    private struct HomebrewResponse: Decodable, Sendable {
        let casks: [HomebrewCask]
    }

    private struct HomebrewCask: Decodable, Sendable {
        let installedVersions: [String]
        let currentVersion: String

        enum CodingKeys: String, CodingKey {
            case installedVersions = "installed_versions"
            case currentVersion = "current_version"
        }
    }

    private struct SemanticVersion: Comparable, Sendable {
        private struct Identifier: Comparable, Sendable {
            let value: String
            let number: Int?

            static func < (lhs: Identifier, rhs: Identifier) -> Bool {
                switch (lhs.number, rhs.number) {
                case let (left?, right?): left < right
                case (.some, .none): true
                case (.none, .some): false
                case (.none, .none): lhs.value < rhs.value
                }
            }
        }

        let major: Int
        let minor: Int
        let patch: Int
        private let prerelease: [Identifier]

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
            switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
            case (true, false): return false
            case (false, true): return true
            case (true, true): return false
            case (false, false): return lhs.prerelease.lexicographicallyPrecedes(rhs.prerelease)
            }
        }

        static func parse(_ raw: String) -> SemanticVersion? {
            let value = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
            let withoutBuild = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let parts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let core = parts[0].split(separator: ".", omittingEmptySubsequences: false)
            guard core.count == 3,
                core.allSatisfy({ !$0.isEmpty && ($0 == "0" || !$0.hasPrefix("0")) && Int($0) != nil })
            else { return nil }

            let prerelease: [Identifier]
            if parts.count == 1 {
                prerelease = []
            } else {
                let identifiers = parts[1].split(separator: ".", omittingEmptySubsequences: false)
                guard !identifiers.isEmpty else { return nil }
                let parsed = identifiers.compactMap { value -> Identifier? in
                    let text = String(value)
                    guard text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                        !text.isEmpty,
                        !text.allSatisfy({ $0.isNumber }) || text == "0" || !text.hasPrefix("0")
                    else { return nil }
                    return Identifier(value: text, number: Int(text))
                }
                guard parsed.count == identifiers.count else { return nil }
                prerelease = parsed
            }
            return SemanticVersion(
                major: Int(core[0])!, minor: Int(core[1])!, patch: Int(core[2])!, prerelease: prerelease
            )
        }

        var stringValue: String {
            let core = "\(major).\(minor).\(patch)"
            guard !prerelease.isEmpty else { return core }
            return core + "-" + prerelease.map(\.value).joined(separator: ".")
        }
    }

    private enum Error: LocalizedError {
        case consentRequired
        case invalidResponse
        case missingAsset
        case missingDigest
        case invalidDigest

        var errorDescription: String? {
            switch self {
            case .consentRequired: "Update checks are not enabled."
            case .invalidResponse: "The update service returned an invalid response."
            case .missingAsset: "The latest release has no update archive."
            case .missingDigest: "The latest release has no SHA-256 digest."
            case .invalidDigest: "The downloaded update failed its SHA-256 check."
            }
        }
    }

    private let defaults = UserDefaults.standard
    private let consentKey: String
    private let currentVersion: String
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.opencast.app",
        category: "updates"
    )

    @Published private(set) var state: State = .idle
    @Published private(set) var networkConsentGranted: Bool

    var isHomebrewManaged: Bool {
        DistributionMarker.current == .homebrew
    }

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.opencast.app"
        consentKey = "updates.networkConsent.\(bundleID)"
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        networkConsentGranted = defaults.bool(forKey: consentKey)
    }

    func setNetworkConsent(_ granted: Bool) {
        networkConsentGranted = granted
        defaults.set(granted, forKey: consentKey)
        if !granted { state = .idle }
    }

    func grantNetworkConsent() {
        setNetworkConsent(true)
    }

    func checkHomebrew() async -> HomebrewCheck {
        guard isHomebrewManaged else { return .unavailable("This installation is not managed by Homebrew.") }
        do {
            let response = try await Task.detached(priority: .utility) {
                try Self.runHomebrewOutdated()
            }.value
            guard let cask = response.casks.first else { return .upToDate }
            let current = cask.installedVersions.first ?? "unknown"
            return .updateAvailable(current: current, latest: cask.currentVersion)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func checkNow() async throws -> UpdateInfo? {
        guard networkConsentGranted else { throw Error.consentRequired }
        guard !isHomebrewManaged else {
            state = .unavailable("Updates are managed by Homebrew.")
            return nil
        }
        guard Bundle.main.bundleIdentifier != "com.opencast.app.dev" else {
            state = .unavailable("Updates are not available for the development build.")
            return nil
        }

        state = .checking
        logger.info("Checking for updates from GitHub. Current version: \(self.currentVersion, privacy: .public)")
        do {
            let release = try await Self.fetchLatestRelease()
            guard networkConsentGranted, !isHomebrewManaged else { throw Error.consentRequired }
            guard let version = Self.normalizedVersion(release.tagName),
                Self.isNewer(version, than: currentVersion)
            else {
                state = .upToDate
                return nil
            }
            guard
                let asset = release.assets.first(where: { $0.name == "Opencast-\(version).zip" })
                    ?? release.assets.first(where: { $0.name.hasSuffix(".zip") })
                    ?? release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
                let digest = asset.digest,
                digest.hasPrefix("sha256:")
            else {
                if release.assets.contains(where: { $0.name.hasSuffix(".zip") || $0.name.hasSuffix(".dmg") }) {
                    throw Error.missingDigest
                }
                throw Error.missingAsset
            }

            let info = UpdateInfo(
                version: version,
                releaseURL: release.htmlURL,
                downloadURL: asset.browserDownloadURL,
                archiveKind: asset.name.hasSuffix(".dmg") ? .diskImage : .zip,
                sha256: String(digest.dropFirst("sha256:".count)),
                notes: release.body ?? ""
            )
            state = .available(info)
            logger.info("Update available: \(info.version, privacy: .public)")
            return info
        } catch {
            state = .failed(error.localizedDescription)
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func downloadAndPrepare(_ update: UpdateInfo) async throws -> PreparedUpdate {
        guard networkConsentGranted else { throw Error.consentRequired }
        let homebrewManaged = isHomebrewManaged
        guard !homebrewManaged else { throw Error.consentRequired }
        logger.info(
            "Preparing update \(update.version, privacy: .public) from \(update.downloadURL.absoluteString, privacy: .public)"
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: update.downloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode)
        else { throw Error.invalidResponse }
        logger.info(
            "Update download response: HTTP \(response.statusCode, privacy: .public), bytes: \(data.count, privacy: .public)"
        )
        guard networkConsentGranted, !isHomebrewManaged else { throw Error.consentRequired }

        state = .downloading
        let archiveExtension = update.archiveKind == .zip ? "zip" : "dmg"
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpencastUpdate-\(UUID().uuidString).\(archiveExtension)")
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        let actualDigest = try await Task.detached(priority: .utility) {
            try data.write(to: archiveURL, options: .atomic)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }.value
        guard networkConsentGranted, !isHomebrewManaged else { throw Error.consentRequired }
        guard actualDigest.caseInsensitiveCompare(update.sha256) == .orderedSame else {
            throw Error.invalidDigest
        }
        logger.info("Update archive digest verified for \(update.version, privacy: .public)")
        guard networkConsentGranted, !homebrewManaged else { throw Error.consentRequired }
        state = .preparing

        let currentAppURL = Bundle.main.bundleURL
        let currentBundleID = Bundle.main.bundleIdentifier ?? "com.opencast.app"
        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                try UpdateInstaller.prepare(
                    archiveURL: archiveURL,
                    expectedVersion: update.version,
                    archiveKind: update.archiveKind,
                    currentAppURL: currentAppURL,
                    currentBundleID: currentBundleID
                )
            }.value
            guard networkConsentGranted, !isHomebrewManaged else {
                UpdateInstaller.discard(prepared)
                throw Error.consentRequired
            }
            try? FileManager.default.removeItem(at: archiveURL)
            logger.info("Update archive prepared: \(update.version, privacy: .public)")
            return prepared
        } catch {
            try? FileManager.default.removeItem(at: archiveURL)
            logger.error("Update preparation failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func install(_ update: PreparedUpdate) throws {
        guard networkConsentGranted, !isHomebrewManaged else { throw Error.consentRequired }
        logger.info("Launching updater for \(update.version, privacy: .public)")
        try UpdateInstaller.launchApply(update)
    }

    private nonisolated static func runHomebrewOutdated() throws -> HomebrewResponse {
        let candidates =
            ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) + "/brew" }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw NSError(
                domain: "UpdateStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Homebrew was not found."])
        }

        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["outdated", "--cask", "--json=v2", "opencast"]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"],
            uniquingKeysWith: { _, new in new }
        )
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message =
                String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                ?? "Homebrew could not check for updates."
            throw NSError(domain: "UpdateStore", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(HomebrewResponse.self, from: data)
    }

    private nonisolated static func fetchLatestRelease() async throws -> GitHubRelease {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/berkinory/opencast/releases/latest")!
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Opencast Update Check", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode)
        else { throw Error.invalidResponse }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private nonisolated static func normalizedVersion(_ tag: String) -> String? {
        SemanticVersion.parse(tag)?.stringValue
    }

    private nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidate = SemanticVersion.parse(candidate),
            let current = SemanticVersion.parse(current)
        else { return false }
        return candidate > current
    }
}

enum DistributionMarker {
    case direct
    case homebrew

    static var current: DistributionMarker {
        let url = AppPaths.applicationSupport()
            .appendingPathComponent("distribution", isDirectory: false)
        return (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            == "homebrew"
            ? .homebrew : .direct
    }
}
