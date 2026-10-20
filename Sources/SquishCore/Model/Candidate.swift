import Foundation

public struct Candidate: Equatable {
    public enum Kind: String {
        case app
        case file
    }

    public let url: URL
    public let kind: Kind
    public let categoryID: String
    public let lastActivity: Date
    /// Logical size of the files not yet compressed.
    public let compressibleBytes: Int64
    public let allocatedBytes: Int64
    /// Disk space compression should free, from a sampled compression ratio.
    public var estimatedSavedBytes: Int64 = 0
}

public enum SkipReason: String, CaseIterable {
    case recentlyUsed
    case alreadyCompressed
    case excludedType
    case incompressible
    case tooLittleGain
    case openElsewhere
    case excludedPath
    case noMatchingCategory
    case tooSmall
    case hardLinked
    case running
    case needsAdmin
    case unreadable
}

public struct ScanResult {
    public var candidates: [Candidate] = []
    public var skips: [SkipReason: Int] = [:]
    public var problems: [String] = []
    /// Files Squish compressed that have since been replaced with new content.
    public var rewrittenPaths: [String] = []

    public init() {}

    mutating func skip(_ reason: SkipReason) {
        skips[reason, default: 0] += 1
    }
}
