import Foundation

enum SearchScopes {
    static let defaults: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
        "/System/Library/CoreServices/Finder.app",
        "~/Applications",
    ]

    static func abbreviate(_ path: String) -> String {
        let trimmed = trimTrailingSlash(path)
        return (trimmed as NSString).abbreviatingWithTildeInPath
    }

    static func expand(_ path: String) -> String {
        (trimTrailingSlash(path) as NSString).expandingTildeInPath
    }

    static func normalize(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.map(abbreviate).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func appBundles(in scopes: [String]) -> [URL] {
        let fileManager = FileManager.default
        var result: [URL] = []

        for scope in scopes {
            let url = URL(fileURLWithPath: expand(scope))
            if url.pathExtension.lowercased() == "app" {
                if fileManager.fileExists(atPath: url.path) { result.append(url) }
                continue
            }

            guard
                let items = try? fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            else { continue }
            result.append(contentsOf: items.filter { $0.pathExtension.lowercased() == "app" })
        }
        return result
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespaces)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
