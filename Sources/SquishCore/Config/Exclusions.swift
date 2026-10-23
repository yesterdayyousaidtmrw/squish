import Foundation

/// The user's excludedPaths, resolved the way the filesystem walk reports paths.
public struct Exclusions {
    private let roots: [String]

    public init(_ config: SquishConfig) {
        roots = config.excludedPaths.map { Paths.canonical(Paths.expand($0)).path }
    }

    public func contains(_ url: URL) -> Bool {
        let path = url.path
        return roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
