import Foundation

public struct ProcessOutcome {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

public enum ProcessRunner {
    public static func run(_ executable: URL, arguments: [String]) throws -> ProcessOutcome {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        // Drain both pipes at once: a child blocked on a full stderr pipe never
        // closes stdout, and a sequential read would wait forever.
        var errData = Data()
        let drained = DispatchGroup()
        drained.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            drained.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        drained.wait()
        process.waitUntilExit()

        return ProcessOutcome(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
