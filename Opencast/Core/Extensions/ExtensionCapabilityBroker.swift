import AppKit
import Combine
import Darwin
import Foundation

struct ExtensionCapabilityResult: Sendable {
    let ok: Bool
    let value: AnySendable?
    let error: String?

    static func success(_ value: AnySendable? = nil) -> Self {
        Self(ok: true, value: value, error: nil)
    }

    static func denied(_ message: String) -> Self {
        Self(ok: false, value: nil, error: message)
    }
}

struct AnySendable: @unchecked Sendable {
    let value: Any
}

@MainActor
final class ExtensionCapabilityBroker: ObservableObject {
    private static let persistentStorageQuota = 4 * 1024 * 1024
    private static let cacheStorageQuota = 16 * 1024 * 1024
    private static let allowedProcessExecutables: Set<String> = [
        "/bin/cat",
        "/bin/echo",
        "/bin/kill",
        "/bin/ps",
        "/opt/homebrew/bin/brew",
        "/usr/bin/brew",
        "/usr/bin/killall",
        "/usr/bin/pmset",
        "/usr/local/bin/brew",
        "/usr/sbin/lsof",
    ]

    private let storageDirectory: URL
    private let auditURL: URL
    private let processProvider: ExtensionProcessProvider
    private let portProvider: ExtensionPortProvider
    private let metricsProvider: ExtensionSystemMetricsProvider
    private let brewProvider: ExtensionBrewProvider
    private let jobManager: ExtensionProcessJobManager
    private let networkSession: URLSession
    private let networkConsentKey: String
    private var networkConsentGranted: Bool

    init(storageDirectory: URL? = nil) {
        let base =
            storageDirectory ?? FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.opencast.app"
        self.storageDirectory = base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("ExtensionStorage", isDirectory: true)
        auditURL = self.storageDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("ExtensionCapabilityAudit.jsonl")
        networkConsentKey = "extensionNetworkConsent." + bundleID
        networkConsentGranted = UserDefaults.standard.bool(forKey: networkConsentKey)
        let protectedPID = Int32(getpid())
        processProvider = ExtensionProcessProvider(protectedPIDs: [protectedPID])
        portProvider = ExtensionPortProvider()
        metricsProvider = ExtensionSystemMetricsProvider()
        brewProvider = ExtensionBrewProvider()
        jobManager = ExtensionProcessJobManager()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        networkSession = URLSession(configuration: configuration)
    }

    func setNetworkConsent(_ granted: Bool) {
        networkConsentGranted = granted
        UserDefaults.standard.set(granted, forKey: networkConsentKey)
    }

    func handle(
        capability: String,
        payload: [String: Any],
        command: ExtensionCommand,
        requestID: String? = nil,
        onProgress: ExtensionProcessJobManager.ProgressHandler? = nil
    ) async -> ExtensionCapabilityResult {
        guard command.capabilities.contains(capability) else {
            audit(capability: capability, command: command, outcome: "undeclared")
            return .denied("Capability " + capability + " is not declared by this extension.")
        }

        switch capability {
        case "clipboard.read":
            return .success(AnySendable(value: NSPasteboard.general.string(forType: .string) ?? ""))
        case "clipboard.write":
            guard let text = payload["text"] as? String else {
                return .denied("clipboard.write requires a text value.")
            }
            Paster.copyString(text)
            return .success(AnySendable(value: true))
        case "clipboard.paste", "selectedText.read":
            return .denied("This capability requires an explicit Opencast focus and Accessibility flow.")
        case "open.url":
            guard let rawURL = payload["url"] as? String, let url = URL(string: rawURL),
                ["http", "https"].contains(url.scheme?.lowercased())
            else { return .denied("Only http and https URLs can be opened.") }
            return .success(AnySendable(value: NSWorkspace.shared.open(url)))
        case "open.application":
            guard let path = payload["path"] as? String else {
                return .denied("open.application requires a path.")
            }
            return .success(AnySendable(value: NSWorkspace.shared.open(URL(fileURLWithPath: path))))
        case "finder.reveal":
            guard let path = payload["path"] as? String else {
                return .denied("finder.reveal requires a path.")
            }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return .success(AnySendable(value: true))
        case "preferences.read":
            return .success(AnySendable(value: preferenceValues(for: command)))
        case "storage.read":
            return readStorage(payload: payload, command: command)
        case "storage.write":
            return writeStorage(payload: payload, command: command)
        case "storage.delete":
            return deleteStorage(payload: payload, command: command)
        case "process.execute":
            return await executeProcess(
                payload: payload, command: command, requestID: requestID, onProgress: onProgress)
        case "process.cancel":
            guard let jobID = payload["jobID"] as? String, !jobID.isEmpty else {
                return .denied("process.cancel requires a job ID.")
            }
            guard jobManager.cancel(jobID: jobID, owner: command.extensionName) else {
                return .denied("The process job was not found for this extension.")
            }
            return .success(AnySendable(value: true))
        case "process.inspect":
            return await inspectProcesses(payload: payload, command: command)
        case "process.terminate":
            return await terminateProcess(payload: payload, command: command)
        case "process.restart":
            return await restartProcess(payload: payload, command: command)
        case "ports.inspect":
            return await inspectPorts(payload: payload, command: command)
        case "system.metrics.read":
            let snapshot = await metricsProvider.snapshot()
            return encoded(snapshot)
        case "brew.read":
            return await readBrew(payload: payload)
        case "brew.detail":
            return await readBrewDetail(payload: payload)
        case "brew.manage":
            return await manageBrew(payload: payload, command: command)
        case "network.request":
            return await requestNetwork(payload: payload, command: command)
        case "menuBar.publishSnapshot":
            return .denied("Menu-bar publishing is handled by the scheduler, not a direct capability call.")
        default:
            return .denied("Unsupported capability: " + capability)
        }
    }

    private func readBrew(payload: [String: Any]) async -> ExtensionCapabilityResult {
        do {
            let operation = payload["operation"] as? String ?? "search"
            let limit = min(max(payload["limit"] as? Int ?? 100, 1), 500)
            switch operation {
            case "search":
                let query = payload["query"] as? String ?? ""
                return encoded(try await brewProvider.search(query: query, limit: limit))
            case "installed":
                return encoded(try await brewProvider.installed(limit: limit))
            case "outdated":
                return encoded(try await brewProvider.outdated(limit: limit))
            default:
                return .denied("Unsupported Brew read operation.")
            }
        } catch {
            return .denied(error.localizedDescription)
        }
    }

    private func readBrewDetail(payload: [String: Any]) async -> ExtensionCapabilityResult {
        guard let name = payload["name"] as? String, let kind = payload["kind"] as? String else {
            return .denied("brew.detail requires a package name and kind.")
        }
        do {
            return encoded(try await brewProvider.detail(name: name, kind: kind))
        } catch {
            return .denied(error.localizedDescription)
        }
    }

    private func manageBrew(payload: [String: Any], command: ExtensionCommand) async -> ExtensionCapabilityResult {
        let operation = payload["operation"] as? String ?? ""
        guard ["install", "upgrade", "cleanup", "service"].contains(operation) else {
            return .denied("Unsupported Homebrew mutation.")
        }
        guard
            NativeConfirmation.present(
                message: "\(operation.capitalized) with Homebrew?",
                informativeText: "Homebrew will change software or services on this Mac.",
                confirmTitle: operation.capitalized
            )
        else {
            return .denied("Homebrew operation was cancelled.")
        }
        do {
            let result = try await brewProvider.mutate(
                operation: operation,
                name: payload["name"] as? String,
                kind: payload["kind"] as? String,
                serviceAction: payload["serviceAction"] as? String
            )
            audit(capability: "brew.manage", command: command, outcome: "status-" + String(result.status))
            return .success(
                AnySendable(value: ["stdout": result.stdout, "stderr": result.stderr, "status": result.status]))
        } catch {
            audit(capability: "brew.manage", command: command, outcome: "failed")
            return .denied(error.localizedDescription)
        }
    }

    func preferenceValues(for command: ExtensionCommand) -> [String: Any] {
        Dictionary(
            uniqueKeysWithValues: command.preferences.compactMap { preference in
                guard let rawValue = preference.defaultValue else { return nil }
                if preference.type == "checkbox" {
                    return (preference.name, rawValue == "true")
                }
                return (preference.name, rawValue)
            })
    }

    private func storageRoot(payload: [String: Any], command: ExtensionCommand) -> URL {
        let namespace = (payload["namespace"] as? String) == "cache" ? "cache" : "persistent"
        return
            storageDirectory
            .appendingPathComponent(command.extensionName, isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)
    }

    private func storageURL(payload: [String: Any], command: ExtensionCommand) -> URL {
        let key = (payload["key"] as? String ?? "value")
            .replacingOccurrences(of: "/", with: "_")
            .prefix(120)
        return storageRoot(payload: payload, command: command)
            .appendingPathComponent(String(key) + ".json")
    }

    private func readStorage(payload: [String: Any], command: ExtensionCommand) -> ExtensionCapabilityResult {
        let url = storageURL(payload: payload, command: command)
        guard let data = try? Data(contentsOf: url),
            let value = try? JSONSerialization.jsonObject(with: data)
        else { return .success(AnySendable(value: NSNull())) }
        return .success(AnySendable(value: value))
    }

    private func writeStorage(payload: [String: Any], command: ExtensionCommand) -> ExtensionCapabilityResult {
        guard let value = payload["value"], JSONSerialization.isValidJSONObject(value) else {
            return .denied("storage.write requires a JSON value.")
        }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
            data.count <= 512 * 1024
        else { return .denied("storage values are limited to 512 KB.") }
        let url = storageURL(payload: payload, command: command)
        let previousData = try? Data(contentsOf: url)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            try enforceStorageQuota(command: command, namespace: payload["namespace"] as? String)
            return .success(AnySendable(value: true))
        } catch {
            if let previousData {
                try? previousData.write(to: url, options: [.atomic])
            } else {
                try? FileManager.default.removeItem(at: url)
            }
            return .denied("Extension storage quota exceeded.")
        }
    }

    private func deleteStorage(payload: [String: Any], command: ExtensionCommand) -> ExtensionCapabilityResult {
        let url = storageURL(payload: payload, command: command)
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
        } catch {
            return .denied("Could not delete extension storage.")
        }
        return .success(AnySendable(value: true))
    }

    private func enforceStorageQuota(command: ExtensionCommand, namespace: String?) throws {
        let isCache = namespace == "cache"
        let root = storageRoot(payload: ["namespace": isCache ? "cache" : "persistent"], command: command)
        let quota = isCache ? Self.cacheStorageQuota : Self.persistentStorageQuota
        var files = try storageFiles(in: root)
        var total = files.reduce(0) { $0 + $1.size }
        guard total > quota else { return }
        if isCache {
            for file in files.sorted(by: { $0.date < $1.date }) {
                try? FileManager.default.removeItem(at: file.url)
                total -= file.size
                if total <= quota { return }
            }
        }
        throw NSError(domain: "OpencastExtensionStorage", code: 1)
    }

    private func storageFiles(in root: URL) throws -> [(url: URL, size: Int, date: Date)] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
            )
        else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                let size = values.fileSize,
                let date = values.contentModificationDate
            else { return nil }
            return (url, size, date)
        }
    }

    private func executeProcess(
        payload: [String: Any],
        command: ExtensionCommand,
        requestID: String?,
        onProgress: ExtensionProcessJobManager.ProgressHandler?
    ) async -> ExtensionCapabilityResult {
        guard let rawCommand = payload["command"] as? String,
            rawCommand.hasPrefix("/"),
            rawCommand.count <= 512,
            let args = payload["args"] as? [String],
            args.count <= 64,
            args.allSatisfy({ $0.count <= 4096 && !$0.contains("\0") }),
            args.joined().count <= 64 * 1024
        else {
            return .denied("process.execute requires an absolute command and bounded arguments.")
        }

        let executable = URL(fileURLWithPath: rawCommand).standardizedFileURL.path
        guard Self.allowedProcessExecutables.contains(executable) else {
            audit(capability: "process.execute", command: command, outcome: "blocked-executable")
            return .denied("This executable is not allowed for extensions.")
        }

        let options = payload["options"] as? [String: Any] ?? [:]
        let streaming = options["stream"] as? Bool == true
        let timeoutLimit = streaming ? 120 : 30
        let timeout = min(max(options["timeout"] as? Double ?? 5, 0.1), Double(timeoutLimit))
        var input: Data?
        if let rawInput = options["input"] as? String {
            guard rawInput.utf8.count <= 64 * 1024 else {
                return .denied("process.execute input is too large.")
            }
            input = rawInput.data(using: .utf8)
        } else {
            input = nil
        }

        if streaming {
            guard let onProgress else {
                return .denied("Streaming process execution is unavailable in this host.")
            }
            do {
                let job = try jobManager.start(
                    path: executable,
                    arguments: args,
                    input: input,
                    timeout: timeout,
                    owner: command.extensionName,
                    requestID: requestID ?? "process-execute",
                    progress: onProgress
                )
                audit(capability: "process.execute", command: command, outcome: "started-" + job.jobID)
                return encoded(job)
            } catch {
                audit(capability: "process.execute", command: command, outcome: "failed")
                return .denied(error.localizedDescription)
            }
        }

        do {
            let result = try await ExtensionFixedCommand.run(
                path: executable,
                arguments: args,
                timeout: timeout,
                input: input,
                outputLimit: 256 * 1024
            )
            audit(capability: "process.execute", command: command, outcome: "status-" + String(result.status))
            return .success(
                AnySendable(value: [
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                    "status": result.status,
                    "timedOut": result.timedOut,
                ]))
        } catch {
            audit(capability: "process.execute", command: command, outcome: "failed")
            return .denied(error.localizedDescription)
        }
    }

    private func inspectProcesses(
        payload: [String: Any], command: ExtensionCommand
    ) async -> ExtensionCapabilityResult {
        do {
            let processes = try await processProvider.snapshot()
            let sortBy = payload["sortBy"] as? String
            let sorted = processes.sorted { left, right in
                switch sortBy {
                case "memory": return left.memoryPercent > right.memoryPercent
                case "name": return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                default: return left.cpuPercent > right.cpuPercent
                }
            }
            let limit = min(max(payload["limit"] as? Int ?? 256, 1), 512)
            audit(capability: "process.inspect", command: command, outcome: "success")
            return encoded(Array(sorted.prefix(limit)))
        } catch {
            audit(capability: "process.inspect", command: command, outcome: "failed")
            return .denied(error.localizedDescription)
        }
    }

    private func terminateProcess(
        payload: [String: Any], command: ExtensionCommand
    ) async -> ExtensionCapabilityResult {
        guard let pid = payload["pid"] as? Int, pid > 1, pid <= Int(Int32.max) else {
            return .denied("process.terminate requires a valid PID.")
        }
        let signal = processSignal(payload["signal"])
        let includeDescendants = payload["includeDescendants"] as? Bool ?? false
        let title = signal == .kill ? "Force Kill Process" : "Terminate Process"
        let message = "PID " + String(pid) + (includeDescendants ? " and its descendants" : "") + " will be terminated."
        guard NativeConfirmation.present(message: title, informativeText: message, confirmTitle: title) else {
            return .denied("Process termination was cancelled.")
        }

        do {
            let termination = try await processProvider.terminate(
                pid: Int32(pid), signal: signal, includeDescendants: includeDescendants)
            audit(capability: "process.terminate", command: command, outcome: "success")
            return encoded(termination)
        } catch {
            audit(capability: "process.terminate", command: command, outcome: "failed")
            return .denied(error.localizedDescription)
        }
    }

    private func restartProcess(
        payload: [String: Any], command: ExtensionCommand
    ) async -> ExtensionCapabilityResult {
        guard let pid = payload["pid"] as? Int, pid > 1, pid <= Int(Int32.max) else {
            return .denied("process.restart requires a valid PID.")
        }
        let force = payload["force"] as? Bool ?? false
        let title = force ? "Force Restart Process" : "Restart Process"
        guard
            NativeConfirmation.present(
                message: title,
                informativeText: "PID \(pid) will be terminated and relaunched.",
                confirmTitle: title
            )
        else {
            return .denied("Process restart was cancelled.")
        }
        do {
            return encoded(try await processProvider.restart(pid: Int32(pid), force: force))
        } catch {
            return .denied(error.localizedDescription)
        }
    }

    private func inspectPorts(
        payload: [String: Any], command: ExtensionCommand
    ) async -> ExtensionCapabilityResult {
        do {
            let ports = try await portProvider.snapshot()
            let limit = min(max(payload["limit"] as? Int ?? 256, 1), 512)
            audit(capability: "ports.inspect", command: command, outcome: "success")
            return encoded(Array(ports.prefix(limit)))
        } catch {
            audit(capability: "ports.inspect", command: command, outcome: "failed")
            return .denied(error.localizedDescription)
        }
    }

    private func processSignal(_ value: Any?) -> ExtensionProcessSignal {
        if let raw = value as? Int, let signal = ExtensionProcessSignal(rawValue: Int32(raw)) {
            return signal
        }
        if let raw = value as? String {
            switch raw.uppercased() {
            case "SIGKILL", "KILL", "9": return .kill
            default: return .term
            }
        }
        return .term
    }

    private func requestNetwork(
        payload: [String: Any], command: ExtensionCommand
    ) async -> ExtensionCapabilityResult {
        guard networkConsentGranted else {
            return .denied("Network access is disabled in Opencast settings.")
        }
        guard let rawURL = payload["url"] as? String,
            let url = URL(string: rawURL),
            let host = url.host?.lowercased(),
            ["http", "https"].contains(url.scheme?.lowercased()),
            command.networkDomains.contains(host)
        else {
            return .denied("network.request requires an allowed declared domain.")
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = (payload["method"] as? String ?? "GET").uppercased()
        guard ["GET", "HEAD"].contains(request.httpMethod ?? "GET") else {
            return .denied("Only GET and HEAD network requests are enabled in Phase 1.")
        }
        request.timeoutInterval = 15

        do {
            let (data, response) = try await networkSession.data(for: request)
            guard networkConsentGranted else {
                return .denied("Network consent was withdrawn while the request was running.")
            }
            guard data.count <= 1 * 1024 * 1024 else {
                return .denied("Network response exceeds the 1 MB limit.")
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            audit(capability: "network.request", command: command, outcome: "status-" + String(status))
            return .success(
                AnySendable(value: [
                    "status": status,
                    "body": String(decoding: data, as: UTF8.self),
                ]))
        } catch {
            audit(capability: "network.request", command: command, outcome: "failed")
            return .denied(error.localizedDescription)
        }
    }

    private func encoded<T: Encodable>(_ value: T) -> ExtensionCapabilityResult {
        guard let data = try? JSONEncoder().encode(value),
            let object = try? JSONSerialization.jsonObject(with: data)
        else { return .denied("The capability returned an invalid JSON value.") }
        return .success(AnySendable(value: object))
    }

    private func audit(capability: String, command: ExtensionCommand, outcome: String) {
        let record: [String: Any] = [
            "capability": capability,
            "extension": command.extensionName,
            "outcome": outcome,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        do {
            try FileManager.default.createDirectory(
                at: auditURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var existing = (try? Data(contentsOf: auditURL)) ?? Data()
            existing.append(data)
            existing.append(0x0A)
            if existing.count > 256 * 1024 {
                existing = Data(existing.suffix(256 * 1024))
            }
            try existing.write(to: auditURL, options: [.atomic])
        } catch {
            return
        }
    }
}
