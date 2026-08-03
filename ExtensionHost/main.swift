import Foundation
import Darwin

struct OpencastExtensionHost {
    static func main() {
        do {
            let channel = try makeChannel(arguments: Array(CommandLine.arguments.dropFirst()))
            let runtime = ExtensionHostRuntime(write: { message in
                try channel.writeMessage(message)
            })

            while let message = try channel.readMessage() {
                try runtime.handle(message)
            }
        } catch {
            let output = "extension host error: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(output.utf8))
            exit(1)
        }
    }

    private static func makeChannel(arguments: [String]) throws -> ExtensionFrameChannel {
        guard let fdIndex = arguments.firstIndex(of: "--fd"), fdIndex + 1 < arguments.count,
              let descriptor = Int32(arguments[fdIndex + 1]), descriptor >= 0 else {
            return ExtensionFrameChannel(input: .standardInput, output: .standardOutput)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        return ExtensionFrameChannel(input: handle, output: handle)
    }
}

OpencastExtensionHost.main()
