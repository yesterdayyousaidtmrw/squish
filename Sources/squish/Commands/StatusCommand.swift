import Foundation
import SquishCore

enum StatusCommand {
    static func run(_ invocation: Invocation) throws {
        guard !invocation.positionals.isEmpty else { throw UsageError("usage: squish status <path>…") }
        for path in invocation.positionals {
            let url = Paths.expand(path)
            print(describe(url, usage: try DiskUsage.measure(url)))
        }
    }

    static func describe(_ url: URL, usage: DiskUsage) -> String {
        "\(Paths.abbreviate(url)): \(usage.compressedFileCount)/\(usage.fileCount) files compressed · "
            + "\(Format.bytes(usage.logicalBytes)) of data · \(Format.bytes(usage.allocatedBytes)) on disk"
    }
}
