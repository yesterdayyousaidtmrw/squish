import Foundation

/// Apple's own afscexpand: rewrites every compressed file under the given paths
/// back to plain data, including files that shipped compressed.
public enum Decompressor {
    static let executable = URL(fileURLWithPath: "/usr/bin/afscexpand")

    public static func expand(_ urls: [URL]) throws {
        let outcome = try ProcessRunner.run(executable, arguments: urls.map(\.path))
        guard outcome.status == 0 else {
            throw CompressorError.failed(status: outcome.status, output: outcome.stderr.isEmpty ? outcome.stdout : outcome.stderr)
        }
    }
}
