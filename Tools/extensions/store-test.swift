import Foundation

let packageURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/extensions/list-clipboard.ocx")
let validator = ExtensionPackageValidator()
let report = try validator.validate(packageURL: packageURL)
precondition(report.isInstallable)
precondition(report.channel == (report.version == nil ? .community : .partial))
precondition(report.bundleBytes > 0)

let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent("store-test-\(UUID().uuidString).ocx")
try FileManager.default.copyItem(at: packageURL, to: temporaryURL)
defer { try? FileManager.default.removeItem(at: temporaryURL) }
let bundleURL = temporaryURL.appendingPathComponent("bundle.js")
try FileHandle(forWritingTo: bundleURL).seekToEnd()
try Data([0x20]).write(to: bundleURL, options: .atomic)
do {
    _ = try validator.validate(packageURL: temporaryURL)
    fatalError("tampered package was accepted")
} catch ExtensionPackageValidationError.hashMismatch {
} catch {
    fatalError("unexpected tamper error: \(error)")
}
print("extension store validation passed")
