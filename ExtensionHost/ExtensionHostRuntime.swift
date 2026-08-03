import Foundation
import JavaScriptCore
import Darwin

@objc protocol ExtensionHostBridgeExport: JSExport {
    func emit(_ message: String) -> String
}

final class ExtensionHostBridge: NSObject, ExtensionHostBridgeExport {
    let emitMessage: (String) -> Void

    init(emitMessage: @escaping (String) -> Void) {
        self.emitMessage = emitMessage
    }

    func emit(_ message: String) -> String {
        emitMessage(message)
        return ""
    }
}

final class ExtensionHostRuntime {
    private static let maxEvaluationDuration: TimeInterval = 2
    private static let maxResidentMemoryBytes = 96 * 1024 * 1024
    private let write: (ExtensionJSON) throws -> Void
    private var context: JSContext?
    private var bridge: ExtensionHostBridge?
    private var bundlePath: URL?
    private var disposed = true
    private var pendingCompletion = false
    private var startedAt: Date?
    private var peakResidentBytes: Int?
    private var closeAfterRender = false

    init(write: @escaping (ExtensionJSON) throws -> Void) {
        self.write = write
    }

    func handle(_ message: ExtensionJSON) throws {
        guard let type = message["type"] as? String else {
            throw ExtensionHostError.invalidMessage
        }

        switch type {
        case "launch":
            try launch(message)
        case "event":
            try dispatch(message)
        case "capabilityResponse":
            try resolveCapability(message)
        case "capabilityProgress":
            try resolveCapabilityProgress(message)
        case "dispose":
            dispose(reason: message["reason"] as? String ?? "closed")
        default:
            sendError(requestID: message["requestID"] as? String, code: "invalidMessage", message: "Unsupported host message: \(type)")
        }
    }

    private func launch(_ message: ExtensionJSON) throws {
        let path = try stringValue(message, key: "bundlePath")
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let bundleURL = exists && isDirectory.boolValue ? url.appendingPathComponent("bundle.js") : url
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw ExtensionHostError.bundleNotFound(bundleURL.path)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: bundleURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= ExtensionHostLimits.maxBundleBytes else {
            throw ExtensionHostError.bundleTooLarge(size)
        }
        let source = try String(contentsOf: bundleURL, encoding: .utf8)

        dispose(reason: "closed", emit: false)
        disposed = false
        bundlePath = bundleURL
        pendingCompletion = false
        startedAt = Date()
        peakResidentBytes = nil
        closeAfterRender = boolValue(message, key: "background")

        let jsContext = JSContext() ?? JSContext(virtualMachine: JSVirtualMachine())!
        context = jsContext
        bridge = ExtensionHostBridge { [weak self] message in
            self?.handleBridgeMessage(message)
        }
        jsContext.exceptionHandler = { [weak self] _, exception in
            let message = exception?.toString() ?? "JavaScript exception"
            self?.sendError(requestID: nil, code: "runtime", message: message)
        }
        jsContext.setObject(bridge, forKeyedSubscript: "__opencastBridge" as NSString)
        let preferences = message["preferences"] as? [String: Any] ?? [:]
        jsContext.setObject(preferences, forKeyedSubscript: "__opencastPreferences" as NSString)
        jsContext.evaluateScript(Self.bootstrap)
        guard jsContext.exception == nil else {
            throw ExtensionHostError.runtime(jsContext.exception?.toString() ?? "Failed to initialize JavaScript runtime.")
        }

        let startedAt = Date()
        jsContext.evaluateScript(source, withSourceURL: bundleURL)
        if let exception = jsContext.exception {
            sendError(requestID: nil, code: "runtime", message: exception.toString() ?? "JavaScript exception")
        }
        enforceBudgets(startedAt: startedAt, requestID: message["requestID"] as? String)
        if pendingCompletion {
            dispose(reason: closeAfterRender ? "snapshot" : "completed")
        }
    }

    private func dispatch(_ message: ExtensionJSON) throws {
        guard let jsContext = context, !disposed else {
            sendError(requestID: message["requestID"] as? String, code: "runtime", message: "No extension command is running.")
            return
        }
        guard let function = jsContext.objectForKeyedSubscript("__opencastDispatch"), function.isObject else {
            return
        }
        let startedAt = Date()
        _ = function.call(withArguments: [message])
        if let exception = jsContext.exception {
            sendError(requestID: message["requestID"] as? String, code: "runtime", message: exception.toString() ?? "JavaScript exception")
            jsContext.exception = nil
        }
        enforceBudgets(startedAt: startedAt, requestID: message["requestID"] as? String)
        if pendingCompletion {
            dispose(reason: closeAfterRender ? "snapshot" : "completed")
        }
    }

    private func resolveCapability(_ message: ExtensionJSON) throws {
        guard let jsContext = context, !disposed else { return }
        guard let function = jsContext.objectForKeyedSubscript("__opencastResolveCapability"), function.isObject else { return }
        let requestID = try stringValue(message, key: "requestID")
        let ok = boolValue(message, key: "ok")
        let startedAt = Date()
        _ = function.call(withArguments: [requestID, ok, message["value"] ?? NSNull(), message["error"] ?? NSNull()])
        if let exception = jsContext.exception {
            sendError(requestID: requestID, code: "runtime", message: exception.toString() ?? "JavaScript exception")
            jsContext.exception = nil
        }
        enforceBudgets(startedAt: startedAt, requestID: requestID)
        if pendingCompletion {
            dispose(reason: closeAfterRender ? "snapshot" : "completed")
        }
    }

    private func resolveCapabilityProgress(_ message: ExtensionJSON) throws {
        guard let jsContext = context, !disposed else { return }
        guard let function = jsContext.objectForKeyedSubscript("__opencastProgressCapability"), function.isObject else {
            return
        }
        let requestID = try stringValue(message, key: "requestID")
        _ = function.call(withArguments: [requestID, message])
        if let exception = jsContext.exception {
            sendError(requestID: requestID, code: "runtime", message: exception.toString() ?? "JavaScript exception")
            jsContext.exception = nil
        }
        enforceBudgets(startedAt: Date(), requestID: requestID)
    }

    private func handleBridgeMessage(_ rawMessage: String) {
        guard let data = rawMessage.data(using: .utf8), data.count <= ExtensionHostLimits.maxFrameBytes else {
            sendError(requestID: nil, code: "invalidMessage", message: "Bridge message is too large.")
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: data), let message = object as? ExtensionJSON,
              let type = message["type"] as? String else {
            sendError(requestID: nil, code: "invalidMessage", message: "Bridge message is not a JSON object.")
            return
        }

        if type == "complete" {
            pendingCompletion = true
            return
        }
        if type == "render", let encoded = try? JSONSerialization.data(withJSONObject: message), encoded.count > ExtensionHostLimits.maxSnapshotBytes {
            sendError(requestID: message["requestID"] as? String, code: "runtime", message: "Render snapshot exceeds the 1 MB limit.")
            return
        }

        do {
            try write(message)
        } catch {
            sendError(requestID: message["requestID"] as? String, code: "runtime", message: error.localizedDescription)
        }
        if type == "render", closeAfterRender { pendingCompletion = true }
    }

    private func sendError(requestID: String?, code: String, message: String) {
        var error: ExtensionJSON = [
            "type": "error",
            "code": code,
            "message": String(message.prefix(1000))
        ]
        if let requestID { error["requestID"] = requestID }
        try? write(error)
    }

    private func enforceBudgets(startedAt: Date, requestID: String?) {
        if let residentMemory = residentMemoryBytes() {
            peakResidentBytes = max(peakResidentBytes ?? 0, residentMemory)
        }
        if Date().timeIntervalSince(startedAt) > Self.maxEvaluationDuration {
            sendError(requestID: requestID, code: "timeout", message: "JavaScript evaluation exceeded the 2 second host budget.")
            dispose(reason: "timeout")
            return
        }
        if let residentMemory = residentMemoryBytes(), residentMemory > Self.maxResidentMemoryBytes {
            sendError(requestID: requestID, code: "runtime", message: "Extension host exceeded the 96 MB memory budget.")
            dispose(reason: "memory")
        }
    }

    private func residentMemoryBytes() -> Int? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.resident_size)
    }

    private func dispose(reason: String, emit: Bool = true) {
        guard !disposed else { return }
        if let jsContext = context, let disposeFunction = jsContext.objectForKeyedSubscript("__opencastDispose"), disposeFunction.isObject {
            _ = disposeFunction.call(withArguments: [])
        }
        context = nil
        bridge = nil
        bundlePath = nil
        disposed = true
        pendingCompletion = false
        closeAfterRender = false
        let durationMS = startedAt.map { Int(Date().timeIntervalSince($0) * 1_000) } ?? 0
        var metrics: ExtensionJSON = ["durationMS": durationMS]
        if let peakResidentBytes { metrics["peakResidentBytes"] = peakResidentBytes }
        startedAt = nil
        peakResidentBytes = nil
        if emit {
            try? write(["type": "dispose", "reason": reason, "metrics": metrics])
        }
    }

    private static let bootstrap = """
    (function () {
      var nextRequest = 0;
      var pending = Object.create(null);
      function send(message) {
        __opencastBridge.emit(JSON.stringify(message));
      }
      globalThis.__opencast = {
        preferences: globalThis.__opencastPreferences || {},
        render: function (snapshot) {
          send(Object.assign({ type: "render", requestID: "render-" + (++nextRequest) }, snapshot));
        },
        log: function (level, message) {
          send({ type: "log", level: level, message: String(message) });
        },
        requestCapability: function (capability, payload, onProgress) {
          var requestID = "cap-" + (++nextRequest);
          return new Promise(function (resolve, reject) {
            pending[requestID] = {
              resolve: resolve,
              reject: reject,
              onProgress: onProgress,
              keepForProgress: !!(payload && payload.options && payload.options.stream)
            };
            send({ type: "capabilityRequest", requestID: requestID, capability: capability, payload: payload || {} });
          });
        },
        complete: function () {
          send({ type: "complete" });
        }
      };
      globalThis.__opencastResolveCapability = function (requestID, ok, value, error) {
        var request = pending[requestID];
        if (!request) return;
        if (!request.keepForProgress) delete pending[requestID];
        if (ok) request.resolve(value); else request.reject(new Error(String(error || "Capability denied")));
      };
      globalThis.__opencastProgressCapability = function (requestID, message) {
        var request = pending[requestID];
        if (!request) return;
        if (typeof request.onProgress === "function") request.onProgress(message);
        if (message && message.done) delete pending[requestID];
      };
      globalThis.__opencastDispatch = function (event) {
        if (typeof globalThis.__opencastOnEvent === "function") globalThis.__opencastOnEvent(event);
      };
      globalThis.__opencastDispose = function () {
        pending = Object.create(null);
        if (typeof globalThis.__opencastOnDispose === "function") globalThis.__opencastOnDispose();
      };
    }());
    """
}
