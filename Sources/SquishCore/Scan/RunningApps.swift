import AppKit

public enum RunningApps {
    /// An app counts as running when it, or any helper app inside its bundle
    /// (Contents/Library/LoginItems/…), is running.
    public static func snapshot() -> (URL) -> Bool {
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL.path }
        return { app in
            let root = app.standardizedFileURL.path
            return running.contains { $0 == root || $0.hasPrefix(root + "/") }
        }
    }
}
