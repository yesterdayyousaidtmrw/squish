import Foundation

public enum Paths {
    /// Under sudo this is still the invoking user's home, so "~/Applications"
    /// means the same folder with or without admin rights.
    public static var home: URL {
        if geteuid() == 0,
           let user = ProcessInfo.processInfo.environment["SUDO_USER"],
           let dir = FileManager.default.homeDirectory(forUser: user) {
            return dir
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static func expand(_ path: String) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2))) }
        return URL(fileURLWithPath: path)
    }

    /// realpath(3), which is what FileManager's enumerator reports. Foundation's
    /// resolvingSymlinksInPath strips "/private" and so disagrees with it.
    /// A path that does not exist (an exclusion for a folder not made yet) stays as written.
    public static func canonical(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }

    public static func abbreviate(_ url: URL) -> String {
        let homePath = home.path
        return url.path.hasPrefix(homePath + "/") ? "~" + url.path.dropFirst(homePath.count) : url.path
    }
}
