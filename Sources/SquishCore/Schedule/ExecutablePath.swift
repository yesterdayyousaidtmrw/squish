import Foundation

public enum ExecutablePath {
    /// The path a LaunchAgent should run. Homebrew's real binary sits in a versioned
    /// Cellar folder that `brew upgrade` and cleanup delete, so a PATH entry that
    /// links to this same binary (/opt/homebrew/bin/squish) outlives upgrades.
    public static func stable(executable: URL, searchPath: String) -> URL {
        let real = Paths.canonical(executable)
        for directory in searchPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(executable.lastPathComponent)
            if FileManager.default.isExecutableFile(atPath: candidate.path), Paths.canonical(candidate) == real {
                return candidate
            }
        }
        return real
    }
}
