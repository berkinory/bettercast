import Foundation

struct ExtensionBrewPackage: Codable, Equatable, Identifiable, Sendable {
    let name: String
    let version: String?
    let installed: Bool
    let outdated: Bool
    let kind: String

    var id: String { kind + ":" + name }
}

struct ExtensionBrewPackageDetail: Codable, Equatable, Sendable {
    let name: String
    let kind: String
    let summary: String?
    let version: String?
    let homepage: String?
    let installedVersions: [String]
}

actor ExtensionBrewProvider {
    private static let executableCandidates = [
        "/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/usr/bin/brew",
    ]
    private struct CacheEntry {
        let value: [ExtensionBrewPackage]
        let expiresAt: Date
        let staleAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let cacheLifetime: TimeInterval = 30
    private let staleLifetime: TimeInterval = 300

    func search(query: String, limit: Int = 100) async throws -> [ExtensionBrewPackage] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128, !trimmed.contains("\0") else { return [] }
        let cacheKey = "search:" + trimmed.lowercased()
        if let cached = cachedValue(for: cacheKey) { return Array(cached.prefix(limit)) }
        let result = try await run(["search", "--formula", "--cask", trimmed], timeout: 15)
        guard result.status == 0 else {
            if let stale = staleValue(for: cacheKey) { return Array(stale.prefix(limit)) }
            throw ExtensionProviderError.commandFailed(
                path: executablePath, status: result.status, stderr: result.stderr)
        }
        let packages = parseNames(result.stdout, limit: 500)
        store(packages, for: cacheKey)
        return Array(packages.prefix(limit))
    }

    func installed(limit: Int = 500) async throws -> [ExtensionBrewPackage] {
        let cacheKey = "installed"
        if let cached = cachedValue(for: cacheKey) { return Array(cached.prefix(limit)) }
        let formula = try await run(["list", "--formula", "--versions"], timeout: 15)
        let casks = try await run(["list", "--cask", "--versions"], timeout: 15)
        guard formula.status == 0, casks.status == 0 else {
            if let stale = staleValue(for: cacheKey) { return Array(stale.prefix(limit)) }
            throw ExtensionProviderError.commandFailed(
                path: executablePath, status: formula.status, stderr: formula.stderr)
        }
        let packages =
            parseInstalled(formula.stdout, kind: "formula") + parseInstalled(casks.stdout, kind: "cask")
        store(packages, for: cacheKey)
        return Array(packages.prefix(limit))
    }

    func outdated(limit: Int = 500) async throws -> [ExtensionBrewPackage] {
        let cacheKey = "outdated"
        if let cached = cachedValue(for: cacheKey) { return Array(cached.prefix(limit)) }
        let result = try await run(["outdated", "--formula", "--cask"], timeout: 15)
        guard result.status == 0 else {
            if let stale = staleValue(for: cacheKey) { return Array(stale.prefix(limit)) }
            throw ExtensionProviderError.commandFailed(
                path: executablePath, status: result.status, stderr: result.stderr)
        }
        let packages = parseNames(result.stdout, limit: 500).map {
            ExtensionBrewPackage(
                name: $0.name, version: $0.version, installed: true, outdated: true, kind: $0.kind)
        }
        store(packages, for: cacheKey)
        return Array(packages.prefix(limit))
    }

    func detail(name: String, kind: String) async throws -> ExtensionBrewPackageDetail {
        let validName = try validatedName(name)
        let flag = try validatedKind(kind)
        let result = try await run(["info", "--json=v2", flag, validName], timeout: 15)
        guard result.status == 0 else {
            throw ExtensionProviderError.commandFailed(
                path: executablePath, status: result.status, stderr: result.stderr)
        }
        return try parseDetail(result.stdout, name: validName, kind: kind)
    }

    func mutate(
        operation: String, name: String?, kind: String?, serviceAction: String?
    ) async throws -> ExtensionCommandResult {
        let arguments: [String]
        switch operation {
        case "install", "upgrade":
            guard let name, let kind else {
                throw ExtensionProviderError.operationFailed("A package and kind are required.")
            }
            arguments = [operation, try validatedKind(kind), try validatedName(name)]
        case "cleanup":
            arguments = ["cleanup", "--prune=all"]
        case "service":
            guard let name, let serviceAction, ["start", "stop", "restart"].contains(serviceAction) else {
                throw ExtensionProviderError.operationFailed("A service name and action are required.")
            }
            arguments = ["services", serviceAction, try validatedName(name)]
        default:
            throw ExtensionProviderError.operationFailed("Unsupported Homebrew mutation.")
        }
        let result = try await run(arguments, timeout: 180)
        guard result.status == 0, !result.timedOut else {
            if result.timedOut { throw ExtensionProviderError.commandTimedOut(path: executablePath) }
            if result.stderr.localizedCaseInsensitiveContains("lock") {
                throw ExtensionProviderError.operationFailed(
                    "Homebrew is locked by another operation. Try again when it finishes.")
            }
            throw ExtensionProviderError.commandFailed(
                path: executablePath, status: result.status, stderr: result.stderr)
        }
        cache.removeAll()
        return result
    }

    private var executablePath: String {
        Self.executableCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            ?? Self.executableCandidates[0]
    }

    private func run(_ arguments: [String], timeout: TimeInterval) async throws
        -> ExtensionCommandResult
    {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw ExtensionProviderError.operationFailed("Homebrew is not installed.")
        }
        return try await ExtensionFixedCommand.run(
            path: executablePath,
            arguments: arguments,
            timeout: timeout,
            outputLimit: 512 * 1024,
            environment: ["HOMEBREW_NO_AUTO_UPDATE": "1"]
        )
    }

    private func validatedName(_ name: String) throws -> String {
        guard !name.isEmpty, name.count <= 128,
            name.allSatisfy({ $0.isASCII && $0.isLetter || $0.isNumber || ".@+/_-".contains($0) })
        else { throw ExtensionProviderError.operationFailed("Invalid Homebrew package name.") }
        return name
    }

    private func validatedKind(_ kind: String) throws -> String {
        guard ["formula", "cask"].contains(kind) else {
            throw ExtensionProviderError.operationFailed("Invalid Homebrew package kind.")
        }
        return "--" + kind
    }

    private func parseDetail(_ output: String, name: String, kind: String) throws
        -> ExtensionBrewPackageDetail
    {
        guard let data = output.data(using: .utf8),
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ExtensionProviderError.invalidOutput("Homebrew returned invalid package metadata.")
        }
        let key = kind == "cask" ? "casks" : "formulae"
        let item = (root[key] as? [[String: Any]])?.first ?? [:]
        let versions = (item["versions"] as? [String: Any])?["stable"] as? String
        let installed =
            (item["installed"] as? [[String: Any]])?.compactMap { $0["version"] as? String } ?? []
        return ExtensionBrewPackageDetail(
            name: item["name"] as? String ?? name,
            kind: kind,
            summary: (item["desc"] as? String) ?? (item["description"] as? String),
            version: versions,
            homepage: item["homepage"] as? String,
            installedVersions: installed
        )
    }

    private func cachedValue(for key: String) -> [ExtensionBrewPackage]? {
        guard let entry = cache[key], entry.expiresAt > Date() else { return nil }
        return entry.value
    }

    private func staleValue(for key: String) -> [ExtensionBrewPackage]? {
        guard let entry = cache[key], entry.staleAt > Date() else { return nil }
        return entry.value
    }

    private func store(_ value: [ExtensionBrewPackage], for key: String) {
        cache[key] = CacheEntry(
            value: Array(value.prefix(500)),
            expiresAt: Date().addingTimeInterval(cacheLifetime),
            staleAt: Date().addingTimeInterval(staleLifetime)
        )
        if cache.count > 32 {
            cache.removeValue(forKey: cache.keys.sorted().first!)
        }
    }

    private nonisolated func parseNames(_ output: String, limit: Int) -> [ExtensionBrewPackage] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("==>") else { return nil }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let name = parts[0]
            guard name.allSatisfy({ $0.isLetter || $0.isNumber || ".@+-_".contains($0) }) else {
                return nil
            }
            return ExtensionBrewPackage(
                name: name, version: parts.count > 1 ? parts[1] : nil, installed: false, outdated: false,
                kind: name.contains("/") ? "cask" : "formula")
        }.prefix(limit).map { $0 }
    }

    private nonisolated func parseInstalled(_ output: String, kind: String) -> [ExtensionBrewPackage] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let parts = rawLine.split(separator: " ", maxSplits: 1).map(String.init)
            guard let name = parts.first, !name.isEmpty else { return nil }
            return ExtensionBrewPackage(
                name: name, version: parts.count > 1 ? parts[1] : nil, installed: true, outdated: false,
                kind: kind)
        }
    }
}
