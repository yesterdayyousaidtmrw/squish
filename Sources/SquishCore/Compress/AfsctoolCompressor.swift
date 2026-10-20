import Foundation

public protocol Compressor {
    func compress(_ urls: [URL]) throws
}

/// Compresses in place with afsctool, which keeps the inode, xattrs and code
/// signatures, verifies each file after writing it, and leaves a file alone when
/// its savings fall short of -s.
public struct AfsctoolCompressor: Compressor {
    static let searchPaths = ["/opt/homebrew/bin/afsctool", "/usr/local/bin/afsctool"]

    public let executable: URL
    public let algorithm: CompressionAlgorithm
    public let zlibLevel: Int
    public let minSavingsPercent: Int
    public let threads: Int

    public init(executable: URL, config: SquishConfig, threads: Int = ProcessInfo.processInfo.activeProcessorCount) {
        self.executable = executable
        algorithm = config.algorithm
        zlibLevel = config.zlibLevel
        minSavingsPercent = config.minSavingsPercent
        self.threads = threads
    }

    public static func locate() throws -> URL {
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/afsctool" }
        guard let path = (searchPaths + pathEntries).first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw CompressorError.afsctoolMissing
        }
        return URL(fileURLWithPath: path)
    }

    /// -c compress, -f skip hard-linked files.
    public func arguments(for urls: [URL]) -> [String] {
        var args = ["-c", "-f", "-T", algorithm.afsctoolName, "-j\(threads)", "-s", String(minSavingsPercent)]
        if algorithm == .zlib { args.append("-\(zlibLevel)") }
        return args + urls.map(\.path)
    }

    public func compress(_ urls: [URL]) throws {
        let outcome = try ProcessRunner.run(executable, arguments: arguments(for: urls))
        guard outcome.status == 0 else {
            throw CompressorError.failed(status: outcome.status, output: outcome.stderr.isEmpty ? outcome.stdout : outcome.stderr)
        }
    }
}

public enum CompressorError: LocalizedError {
    case afsctoolMissing
    case failed(status: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .afsctoolMissing:
            return "afsctool not found; install it with `brew install afsctool`"
        case .failed(let status, let output):
            return "exited \(status): \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}
