import Foundation

typealias ExtensionJSON = [String: Any]

enum ExtensionHostError: LocalizedError {
    case invalidFrame
    case frameTooLarge(Int)
    case invalidMessage
    case missingField(String)
    case bundleTooLarge(Int)
    case bundleNotFound(String)
    case runtime(String)

    var errorDescription: String? {
        switch self {
        case .invalidFrame: return "The extension host received an invalid frame."
        case .frameTooLarge(let size): return "The extension host frame is too large: \(size) bytes."
        case .invalidMessage: return "The extension host received an invalid message."
        case .missingField(let field): return "The extension host message is missing \(field)."
        case .bundleTooLarge(let size): return "The extension bundle is too large: \(size) bytes."
        case .bundleNotFound(let path): return "The extension bundle was not found: \(path)."
        case .runtime(let message): return message
        }
    }
}

struct ExtensionHostLimits {
    static let maxFrameBytes = 4 * 1024 * 1024
    static let maxBundleBytes = 8 * 1024 * 1024
    static let maxSnapshotBytes = 1 * 1024 * 1024
    static let maxLogBytes = 2 * 1024
}

final class ExtensionFrameChannel {
    private let input: FileHandle
    private let output: FileHandle

    init(input: FileHandle, output: FileHandle) {
        self.input = input
        self.output = output
    }

    func readMessage() throws -> ExtensionJSON? {
        guard let header = try readExactly(4) else { return nil }
        guard header.count == 4 else { throw ExtensionHostError.invalidFrame }

        let size = header.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        let length = Int(size)
        guard length > 0 else { throw ExtensionHostError.invalidFrame }
        guard length <= ExtensionHostLimits.maxFrameBytes else {
            throw ExtensionHostError.frameTooLarge(length)
        }
        guard let payload = try readExactly(length) else { throw ExtensionHostError.invalidFrame }

        let object = try JSONSerialization.jsonObject(with: payload, options: [.fragmentsAllowed])
        guard let message = object as? ExtensionJSON else { throw ExtensionHostError.invalidMessage }
        return message
    }

    func writeMessage(_ message: ExtensionJSON) throws {
        let payload = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        guard payload.count <= ExtensionHostLimits.maxFrameBytes else {
            throw ExtensionHostError.frameTooLarge(payload.count)
        }

        var length = UInt32(payload.count).bigEndian
        let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        output.write(header)
        output.write(payload)
    }

    private func readExactly(_ count: Int) throws -> Data? {
        var data = Data()
        data.reserveCapacity(count)

        while data.count < count {
            let chunk = input.readData(ofLength: count - data.count)
            if chunk.isEmpty {
                if data.isEmpty { return nil }
                throw ExtensionHostError.invalidFrame
            }
            data.append(chunk)
        }
        return data
    }
}

func stringValue(_ message: ExtensionJSON, key: String) throws -> String {
    guard let value = message[key] as? String, !value.isEmpty else {
        throw ExtensionHostError.missingField(key)
    }
    return value
}

func boolValue(_ message: ExtensionJSON, key: String, default defaultValue: Bool = false) -> Bool {
    message[key] as? Bool ?? defaultValue
}
