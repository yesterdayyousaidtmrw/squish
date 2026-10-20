import Foundation

public struct DiskUsage: Equatable {
    public var fileCount = 0
    public var compressedFileCount = 0
    public var logicalBytes: Int64 = 0
    public var allocatedBytes: Int64 = 0
    /// Logical size of regular files not yet compressed: the work left to do.
    public var uncompressedLogicalBytes: Int64 = 0

    public init() {}

    /// Sums every regular file at or under `url` without following symlinks.
    public static func measure(_ url: URL) throws -> DiskUsage {
        var usage = DiskUsage()
        let root = try FileFacts.read(url)
        guard root.isDirectory else {
            usage.add(root)
            return usage
        }
        // The errorHandler matters: without one an unreadable subfolder is skipped
        // in silence and the totals come out low.
        var walkError: Error?
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil, options: [],
            errorHandler: { _, error in
                walkError = error
                return false
            }
        ) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        for case let child as URL in walker {
            usage.add(try FileFacts.read(child))
        }
        if let walkError { throw walkError }
        return usage
    }

    mutating func add(_ facts: FileFacts) {
        guard facts.isRegularFile else { return }
        fileCount += 1
        logicalBytes += facts.logicalBytes
        allocatedBytes += facts.allocatedBytes
        if facts.isCompressed {
            compressedFileCount += 1
        } else {
            uncompressedLogicalBytes += facts.logicalBytes
        }
    }
}
