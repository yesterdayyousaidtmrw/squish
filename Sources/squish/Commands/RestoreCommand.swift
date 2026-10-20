import Foundation
import SquishCore

enum RestoreCommand {
    static func run(_ invocation: Invocation) throws {
        guard !invocation.positionals.isEmpty else { throw UsageError("usage: squish restore <path>…") }
        let urls = invocation.positionals.map(Paths.expand)
        try Decompressor.expand(urls)
        for url in urls {
            print(StatusCommand.describe(url, usage: try DiskUsage.measure(url)))
        }
    }
}
