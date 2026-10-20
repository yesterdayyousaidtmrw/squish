public struct FileCategory: Equatable {
    public let id: String
    public let summary: String
    public let extensions: Set<String>
    public let directoryMarkers: Set<String>
    public let matchesAnyFile: Bool

    init(id: String, summary: String, extensions: Set<String> = [], directoryMarkers: Set<String> = [], matchesAnyFile: Bool = false) {
        self.id = id
        self.summary = summary
        self.extensions = extensions
        self.directoryMarkers = directoryMarkers
        self.matchesAnyFile = matchesAnyFile
    }

    /// `directories` are only the folders between the scan root and the file, so a
    /// marker in the root's own path (a home folder called "target") never matches.
    public func matches(fileExtension: String, directories: [String]) -> Bool {
        if matchesAnyFile { return true }
        if directories.contains(where: directoryMarkers.contains) { return true }
        return extensions.contains(fileExtension)
    }
}

public enum Categories {
    public static let appsID = "apps"

    // A file takes the first enabled category it matches, so specific categories
    // sit before the "other" catch-all.
    public static let all: [FileCategory] = [
        FileCategory(id: appsID, summary: "App bundles in appLocations, judged by last launch"),
        FileCategory(
            id: "devArtifacts",
            summary: "Everything under node_modules, DerivedData, .build, Pods, target, __pycache__, .venv",
            directoryMarkers: ["node_modules", "DerivedData", ".build", "Pods", "target", "__pycache__", ".venv"]
        ),
        FileCategory(
            id: "code",
            summary: "Source code and config files",
            extensions: [
                "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "rs", "go", "py", "rb", "java", "kt", "kts", "scala",
                "js", "mjs", "cjs", "ts", "tsx", "jsx", "vue", "svelte", "css", "scss", "less", "html", "htm", "php",
                "sh", "zsh", "bash", "fish", "sql", "json", "yaml", "yml", "toml", "xml", "plist", "ini", "cfg", "conf",
                "lock", "gradle", "cmake", "proto", "graphql", "ipynb",
            ]
        ),
        FileCategory(
            id: "text",
            summary: "Plain text, logs, CSV/TSV, Markdown, rich text, subtitles",
            extensions: ["txt", "log", "csv", "tsv", "md", "rtf", "tex", "srt", "vtt"]
        ),
        FileCategory(
            id: "uncompressedMedia",
            summary: "Uncompressed images, audio and design files (TIFF, BMP, WAV, AIFF, PSD, SVG, EPS)",
            extensions: ["tif", "tiff", "bmp", "wav", "aif", "aiff", "psd", "svg", "eps", "ai"]
        ),
        FileCategory(id: "other", summary: "Any file not in excludedExtensions", matchesAnyFile: true),
    ]

    public static func named(_ id: String) -> FileCategory? {
        all.first { $0.id == id }
    }
}
