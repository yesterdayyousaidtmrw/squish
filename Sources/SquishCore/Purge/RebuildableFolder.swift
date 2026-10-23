import Foundation

/// A folder purge may move to the Trash. The name alone is not enough: the tool
/// that recreates it must have left its marker, so a folder the user happened to
/// call "target" or ".build" is never mistaken for build output.
struct RebuildableFolder {
    let name: String
    let rebuild: String
    /// Files whose presence beside the folder (or inside it, for `.venv`) proves its origin.
    let markersBeside: [String]
    let markersInside: [String]

    static let all: [RebuildableFolder] = [
        RebuildableFolder(name: "node_modules", rebuild: "npm, yarn or pnpm install", markersBeside: ["package.json"], markersInside: []),
        RebuildableFolder(name: ".build", rebuild: "swift build", markersBeside: ["Package.swift"], markersInside: []),
        RebuildableFolder(name: "Pods", rebuild: "pod install", markersBeside: ["Podfile"], markersInside: []),
        RebuildableFolder(name: "target", rebuild: "cargo build or mvn package", markersBeside: ["Cargo.toml", "pom.xml"], markersInside: []),
        RebuildableFolder(name: ".venv", rebuild: "python3 -m venv .venv, then reinstall the requirements", markersBeside: [], markersInside: ["pyvenv.cfg"]),
        RebuildableFolder(name: "__pycache__", rebuild: "recreated by Python on the next run", markersBeside: [], markersInside: []),
        RebuildableFolder(name: "DerivedData", rebuild: "rebuilt by Xcode on the next build", markersBeside: [], markersInside: ["info.plist"]),
    ]

    /// The rule for `folder` if it really is what its name says, else nil.
    static func matching(_ folder: URL) -> RebuildableFolder? {
        guard let rule = all.first(where: { $0.name == folder.lastPathComponent }) else { return nil }
        let manager = FileManager.default
        let besideOK = rule.markersBeside.isEmpty
            || rule.markersBeside.contains { manager.fileExists(atPath: folder.deletingLastPathComponent().appendingPathComponent($0).path) }
        let insideOK = rule.markersInside.isEmpty
            || rule.markersInside.contains { manager.fileExists(atPath: folder.appendingPathComponent($0).path) }
        return besideOK && insideOK ? rule : nil
    }
}
