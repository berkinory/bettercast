import Combine
import Foundation

struct InstalledExtension: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let title: String
    let report: ExtensionVerificationReport
    let disabled: Bool
    let url: URL
    let rollbackAvailable: Bool
}

@MainActor
final class ExtensionStoreManager: ObservableObject {
    @Published private(set) var installed: [InstalledExtension] = []
    @Published private(set) var remotePackages: [ExtensionStorePackage] = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var downloadingNames: Set<String> = []
    @Published private(set) var storeNetworkConsentGranted: Bool
    @Published private(set) var lastError: String?

    let directory: URL
    var onChange: (() -> Void)?
    static let catalogURL = URL(
        string: "https://github.com/berkinory/opencast/releases/download/extensions/extensions-catalog.json")!

    private let versionsDirectory: URL
    private let validator = ExtensionPackageValidator()
    private let fileManager = FileManager.default
    private let disabledDefaultsKey: String
    private let storeNetworkConsentKey: String
    private let networkSession: URLSession
    private let decoder: JSONDecoder

    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory()
        self.directory = base
        versionsDirectory = base.appendingPathComponent(".versions", isDirectory: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "com.opencast.app"
        disabledDefaultsKey = "extensions.disabled.\(bundleID)"
        storeNetworkConsentKey = "extensionStoreNetworkConsent." + bundleID
        storeNetworkConsentGranted = UserDefaults.standard.bool(forKey: storeNetworkConsentKey)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        networkSession = URLSession(configuration: configuration)
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date: \(value)"
                )
            }
            return date
        }
    }

    var disabledNames: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: disabledDefaultsKey) ?? [])
    }

    func start() {
        refresh()
    }

    func clearError() {
        lastError = nil
    }

    func setStoreNetworkConsent(_ granted: Bool) {
        storeNetworkConsentGranted = granted
        UserDefaults.standard.set(granted, forKey: storeNetworkConsentKey)
        if !granted { remotePackages = [] }
    }

    func refreshRemoteCatalog() {
        guard storeNetworkConsentGranted else {
            lastError = ExtensionStoreError.consentRequired.localizedDescription
            return
        }
        guard !isLoadingCatalog else { return }
        isLoadingCatalog = true
        lastError = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard storeNetworkConsentGranted else { throw ExtensionStoreError.consentRequired }
                var request = URLRequest(url: Self.catalogURL)
                request.httpMethod = "GET"
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await networkSession.data(for: request)
                guard storeNetworkConsentGranted else { throw ExtensionStoreError.consentRequired }
                guard data.count <= 2 * 1024 * 1024,
                    (response as? HTTPURLResponse)?.statusCode == 200
                else { throw ExtensionStoreError.invalidCatalog }
                let catalog = try decoder.decode(ExtensionStoreCatalog.self, from: data)
                guard catalog.schemaVersion == 1,
                    catalog.packages.allSatisfy(isTrustedCatalogPackage(_:))
                else { throw ExtensionStoreError.invalidCatalog }
                remotePackages = catalog.packages
                isLoadingCatalog = false
            } catch {
                isLoadingCatalog = false
                lastError = error.localizedDescription
            }
        }
    }

    func installRemote(_ package: ExtensionStorePackage) {
        guard storeNetworkConsentGranted else {
            lastError = ExtensionStoreError.consentRequired.localizedDescription
            return
        }
        guard isTrustedCatalogPackage(package) else {
            lastError = ExtensionStoreError.invalidCatalog.localizedDescription
            return
        }
        guard downloadingNames.insert(package.name).inserted else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { downloadingNames.remove(package.name) }
            do {
                let packageURL = try await downloadAndUnpack(package)
                let temporaryRoot = packageURL.deletingLastPathComponent().deletingLastPathComponent()
                defer { try? fileManager.removeItem(at: temporaryRoot) }
                try installValidated(from: packageURL, expected: package)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func refresh() {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let packages = try fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            installed =
                packages
                .filter { $0.pathExtension == "ocx" }
                .compactMap { installedExtension(at: $0) }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        } catch {
            installed = []
            lastError = error.localizedDescription
        }
    }

    func install(from packageURL: URL) {
        do {
            try installValidated(from: packageURL, expected: nil)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disable(_ name: String, disabled: Bool) {
        var names = disabledNames
        if disabled { names.insert(name) } else { names.remove(name) }
        UserDefaults.standard.set(names.sorted(), forKey: disabledDefaultsKey)
        refresh()
        onChange?()
    }

    func remove(_ name: String) {
        guard let current = installed.first(where: { $0.name == name }) else { return }
        do {
            _ = try preserveCurrent(current.url, name: name)
            disable(name, disabled: false)
            refresh()
            onChange?()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func rollback(_ name: String) {
        let historyDirectory = versionsDirectory.appendingPathComponent(name, isDirectory: true)
        do {
            let versions = try fileManager.contentsOfDirectory(
                at: historyDirectory, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            .sorted { lhs, rhs in
                let left =
                    (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                let right =
                    (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                return left > right
            }
            guard let previous = versions.first else { return }
            let destination = directory.appendingPathComponent("\(name).ocx", isDirectory: true)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try preserveCurrent(destination, name: name)
            }
            try fileManager.moveItem(at: previous, to: destination)
            refresh()
            lastError = nil
            onChange?()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func installedExtension(at url: URL) -> InstalledExtension? {
        guard let report = try? validator.validate(packageURL: url),
            let manifestData = try? Data(contentsOf: url.appendingPathComponent("manifest.json")),
            let manifest = try? JSONDecoder().decode(ExtensionManifest.self, from: manifestData)
        else { return nil }
        let historyDirectory = versionsDirectory.appendingPathComponent(manifest.name, isDirectory: true)
        let hasHistory =
            (try? fileManager.contentsOfDirectory(
                at: historyDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ).isEmpty == false) ?? false
        return InstalledExtension(
            id: manifest.name,
            name: manifest.name,
            title: manifest.title,
            report: report,
            disabled: disabledNames.contains(manifest.name),
            url: url,
            rollbackAvailable: hasHistory
        )
    }

    private func installValidated(from packageURL: URL, expected: ExtensionStorePackage?) throws {
        let report = try validator.validate(packageURL: packageURL)
        guard report.isInstallable, let name = report.manifestName else {
            throw ExtensionPackageValidationError.rejected(report.hardVetoes.joined(separator: ", "))
        }
        if let expected {
            guard expected.name == name, expected.bundleHash == report.bundleHash,
                expected.bundleBytes == report.bundleBytes,
                expected.capabilities == capabilities(in: packageURL)
            else { throw ExtensionStoreError.packageMismatch }
        }
        var staging: URL?
        var backup: URL?
        let destination = directory.appendingPathComponent("\(name).ocx", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            staging = directory.appendingPathComponent(".staging-\(UUID().uuidString).ocx", isDirectory: true)
            try fileManager.copyItem(at: packageURL, to: staging!)
            if fileManager.fileExists(atPath: destination.path) {
                backup = try preserveCurrent(destination, name: name)
            }
            try fileManager.moveItem(at: staging!, to: destination)
            refresh()
            lastError = nil
            onChange?()
        } catch {
            if let backup, !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            if let staging, fileManager.fileExists(atPath: staging.path) {
                try? fileManager.removeItem(at: staging)
            }
            throw error
        }
    }

    private func downloadAndUnpack(_ package: ExtensionStorePackage) async throws -> URL {
        guard isTrustedPackageURL(package.packageURL) else { throw ExtensionStoreError.invalidPackageURL }
        guard storeNetworkConsentGranted else { throw ExtensionStoreError.consentRequired }
        let (data, response) = try await networkSession.data(from: package.packageURL)
        guard storeNetworkConsentGranted else { throw ExtensionStoreError.consentRequired }
        guard data.count <= 32 * 1024 * 1024,
            (response as? HTTPURLResponse)?.statusCode == 200
        else { throw ExtensionStoreError.packageTooLarge }
        let root = fileManager.temporaryDirectory.appendingPathComponent("opencast-extension-\(UUID().uuidString)")
        let archive = root.appendingPathComponent("package.zip")
        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
        try data.write(to: archive, options: .atomic)
        let result = try await ExtensionFixedCommand.run(
            path: "/usr/bin/ditto", arguments: ["-x", "-k", archive.path, extracted.path], timeout: 30)
        guard result.status == 0, !result.timedOut else {
            throw ExtensionStoreError.archiveFailed(result.stderr)
        }
        let packages = try fileManager.contentsOfDirectory(
            at: extracted, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "ocx" }
        guard packages.count == 1, let packageURL = packages.first else {
            throw ExtensionStoreError.packageMismatch
        }
        return packageURL
    }

    private func capabilities(in packageURL: URL) -> [String] {
        guard let data = try? Data(contentsOf: packageURL.appendingPathComponent("capabilities.json")),
            let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let values = file["capabilities"] as? [[String: Any]]
        else { return [] }
        return values.compactMap { $0["name"] as? String }.sorted()
    }

    private func isTrustedCatalogPackage(_ package: ExtensionStorePackage) -> Bool {
        package.verified && package.bundleBytes > 0
            && package.bundleBytes <= ExtensionPackageValidator.maximumBundleBytes
            && package.bundleHash.count == 64 && package.bundleHash.allSatisfy(\.isHexDigit)
            && isCompatible(minimumVersion: package.minimumAppVersion)
            && isTrustedPackageURL(package.packageURL)
    }

    private func isTrustedPackageURL(_ url: URL) -> Bool {
        url.scheme == "https" && ["github.com", "objects.githubusercontent.com"].contains(url.host?.lowercased())
    }

    private func isCompatible(minimumVersion: String) -> Bool {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        func components(_ value: String) -> [Int] {
            let values = value.split(separator: ".").prefix(3).map { Int($0) ?? 0 }
            return Array((values + [0, 0, 0]).prefix(3))
        }
        let currentComponents = components(current)
        let minimumComponents = components(minimumVersion)
        for index in 0..<3 where currentComponents[index] != minimumComponents[index] {
            return currentComponents[index] > minimumComponents[index]
        }
        return true
    }

    private func preserveCurrent(_ url: URL, name: String) throws -> URL {
        let historyDirectory = versionsDirectory.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        let report = try validator.validate(packageURL: url)
        let version = report.version ?? String(report.bundleHash.prefix(12))
        let destination = historyDirectory.appendingPathComponent(
            "\(version)-\(UUID().uuidString.prefix(8)).ocx", isDirectory: true)
        try fileManager.moveItem(at: url, to: destination)
        return destination
    }

    private static func defaultDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.opencast.app"
        return applicationSupport.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent(
            "Extensions", isDirectory: true)
    }
}
