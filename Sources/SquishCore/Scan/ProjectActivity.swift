import Foundation

/// A code project is judged as one unit: its dependencies and build output keep
/// their install date forever, so only the project's own edits say whether it is in use.
public enum ProjectActivity {
    static let rootMarkers = [".git", "package.json", "Package.swift"]

    public static func isProjectRoot(_ directory: URL) -> Bool {
        rootMarkers.contains { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
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
