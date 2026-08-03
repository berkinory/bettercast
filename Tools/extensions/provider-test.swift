import Darwin
import Foundation

@main
@MainActor
struct ExtensionProviderTest {
    static func main() async throws {
        let processProvider = ExtensionProcessProvider(
            protectedPIDs: [Int32(getpid())])
        let echoed = try await ExtensionFixedCommand.run(
            path: "/bin/cat",
            arguments: [],
            input: Data("phase1".utf8)
        )
        precondition(echoed.stdout == "phase1")
        let timedOut = try await ExtensionFixedCommand.run(
            path: "/bin/sleep",
            arguments: ["1"],
            timeout: 0.1
        )
        precondition(timedOut.timedOut)
        let processes = try await processProvider.snapshot()
        precondition(!processes.isEmpty, "process snapshot is empty")
        precondition(processes.contains { $0.pid == Int32(getpid()) }, "current process is missing")

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
        let termination = try await processProvider.terminate(
            pid: child.processIdentifier,
            signal: .term,
            includeDescendants: false
        )
        precondition(termination.terminatedPIDs == [child.processIdentifier])

        let ports = try await ExtensionPortProvider().snapshot()
        precondition(ports.allSatisfy { $0.port > 0 && $0.pid > 1 })

        let metrics = await ExtensionSystemMetricsProvider().snapshot()
        precondition(metrics.memoryTotalBytes > 0, "memory metrics are unavailable")
        precondition(metrics.diskTotalBytes > 0, "disk metrics are unavailable")

        let jobManager = ExtensionProcessJobManager()
        var events: [[String: Any]] = []
        _ = try jobManager.start(
            path: "/bin/echo",
            arguments: ["stream-ok"],
            input: nil,
            timeout: 2,
            owner: "provider-test",
            requestID: "provider-test-request",
            progress: { events.append($0) }
        )
        try await Task.sleep(for: .milliseconds(200))
        precondition(events.contains { ($0["stream"] as? String) == "stdout" })
        precondition(events.contains { ($0["done"] as? Bool) == true })

        var cancellationEvents: [[String: Any]] = []
        let cancellableJob = try jobManager.start(
            path: "/bin/sleep",
            arguments: ["30"],
            input: nil,
            timeout: 30,
            owner: "provider-test",
            requestID: "provider-test-cancel",
            progress: { cancellationEvents.append($0) }
        )
        precondition(jobManager.cancel(jobID: cancellableJob.jobID, owner: "provider-test"))
        try await Task.sleep(for: .milliseconds(100))
        precondition(cancellationEvents.contains { ($0["cancelled"] as? Bool) == true })
        print(
            "extension providers passed: " + String(processes.count)
                + " processes, " + String(ports.count) + " ports"
        )
    }
}
