import Foundation

public struct PurgeItem: Equatable {
    public enum Kind: Equatable {
        /// Dependencies or build output of a project left alone for a long time.
        /// Moved to the Trash, so it can be put back.
        case folder
        /// A package manager's download cache, cleared with that tool's own command.
        case toolCache(command: [String])
    }

    public let url: URL
    public let kind: Kind
    public let bytes: Int64
    /// How to get it back, shown next to the item.
    public let rebuild: String
}

public struct PurgePlan {
    public var items: [PurgeItem] = []
    public var activeProjects = 0
    public var openFolders = 0
    public var problems: [String] = []

    public init() {}
}
