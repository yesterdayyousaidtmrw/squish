import Foundation

/// A code project is judged as one unit: its dependencies and build output keep
/// their install date forever, so only the project's own edits say whether it is in use.
public enum ProjectActivity {
    static let rootMarkers = [".git", "package.json", "Package.swift"]

    public static func isProjectRoot(_ directory: URL) -> Bool {
        rootMarkers.contains { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    /// The outermost project at or above `directory`, so a scan location inside a
    /// project (its node_modules, a monorepo package) is judged by that project.
    /// The search climbs only within `boundary` (the home folder by default) and
    /// stops below it: a dotfiles repo in ~, or a stray package.json in /tmp,
    /// would otherwise turn everything under it into one "active" project.
    /// Outside the boundary only `directory` itself is considered. Folders
    /// inside dependencies never count as projects.
    public static func outermostRoot(containing directory: URL, below boundary: URL) -> URL? {
        let stop = Paths.canonical(boundary).path
        guard directory.path.hasPrefix(stop + "/") else {
            return isOwnProject(directory) ? directory : nil
        }
        var found: URL?
        var current = directory
        while current.path != stop {
            if isOwnProject(current) { found = current }
            current = current.deletingLastPathComponent()
        }
        return found
    }

    private static func isOwnProject(_ directory: URL) -> Bool {
        !directory.pathComponents.contains(where: Categories.artifactDirectoryNames.contains) && isProjectRoot(directory)
    }

    /// Newest mtime among the project's own files (artifact folders and .git
    /// internals excluded), and git's HEAD and reflog, which move on every
    /// checkout and commit.
    public static func lastActivity(of root: URL) throws -> Date {
        var newest = try FileFacts.read(root).modified
        for marker in [".git", ".git/HEAD", ".git/logs/HEAD"] {
            let url = root.appendingPathComponent(marker)
            if FileManager.default.fileExists(atPath: url.path) {
                newest = max(newest, try FileFacts.read(url).modified)
            }
        }

        var walkError: Error?
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [],
            errorHandler: { _, error in
                walkError = error
                return false
            }
        ) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: root.path])
        }
        for case let url as URL in walker {
            let facts = try FileFacts.read(url)
            if facts.isDirectory {
                let name = url.lastPathComponent
                if name == ".git" || Categories.artifactDirectoryNames.contains(name) { walker.skipDescendants() }
            } else if facts.isRegularFile {
                newest = max(newest, facts.modified)
            }
        }
        if let walkError { throw walkError }
        return newest
    }
}
