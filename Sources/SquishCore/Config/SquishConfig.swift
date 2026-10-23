import Foundation

public struct SquishConfig: Codable, Equatable {
    public var appLocations: [String]
    public var fileLocations: [String]
    public var categories: [String]
    public var dormantDays: Int
    public var dormantDaysByCategory: [String: Int]
    public var algorithm: CompressionAlgorithm
    public var zlibLevel: Int
    public var minSavingsPercent: Int
    public var minFileBytes: Int64
    public var excludedPaths: [String]
    public var excludedExtensions: [String]
    /// `squish purge`: days a project must sit untouched before its rebuildable folders go.
    public var purgeAfterDays: Int

    public static let standard = SquishConfig(
        appLocations: ["/Applications", "~/Applications"],
        fileLocations: ["~/Documents", "~/Downloads", "~/Developer"],
        categories: ["apps", "devArtifacts", "code", "text", "uncompressedMedia"],
        dormantDays: 30,
        dormantDaysByCategory: ["apps": 21, "devArtifacts": 14],
        algorithm: .lzfse,
        zlibLevel: 9,
        minSavingsPercent: 10,
        minFileBytes: 1,
        excludedPaths: [],
        excludedExtensions: [
            "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "avif", "jxl",
            "mp4", "mov", "m4v", "mkv", "avi", "webm", "mp3", "m4a", "aac", "ogg", "opus", "flac",
            "zip", "gz", "tgz", "bz2", "xz", "zst", "lz4", "7z", "rar", "dmg", "pkg", "xip", "iso",
            "jar", "war", "apk", "ipa", "docx", "xlsx", "pptx", "pages", "numbers", "key", "epub",
            "woff", "woff2", "pack", "sparseimage",
        ],
        purgeAfterDays: 90
    )

    public func dormantDays(forCategory id: String) -> Int {
        dormantDaysByCategory[id] ?? dormantDays
    }

    /// Enabled categories in `Categories.all` order, which is the match order.
    public var enabledCategories: [FileCategory] {
        Categories.all.filter { categories.contains($0.id) }
    }

    public func validate() throws {
        let known = Set(Categories.all.map(\.id))
        for id in categories + Array(dormantDaysByCategory.keys) where !known.contains(id) {
            throw ConfigError.unknownCategory(id)
        }
        guard dormantDays >= 0, purgeAfterDays >= 0, dormantDaysByCategory.values.allSatisfy({ $0 >= 0 }) else {
            throw ConfigError.invalid("dormant days cannot be negative")
        }
        guard (1...9).contains(zlibLevel) else { throw ConfigError.invalid("zlibLevel must be 1-9") }
        guard (0...99).contains(minSavingsPercent) else { throw ConfigError.invalid("minSavingsPercent must be 0-99") }
    }
}

// Lives in an extension so the memberwise init above survives. Missing keys
// take the standard value, so a config only has to list what it changes.
extension SquishConfig {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SquishConfig.standard
        appLocations = try c.decodeIfPresent([String].self, forKey: .appLocations) ?? d.appLocations
        fileLocations = try c.decodeIfPresent([String].self, forKey: .fileLocations) ?? d.fileLocations
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? d.categories
        dormantDays = try c.decodeIfPresent(Int.self, forKey: .dormantDays) ?? d.dormantDays
        dormantDaysByCategory = try c.decodeIfPresent([String: Int].self, forKey: .dormantDaysByCategory) ?? d.dormantDaysByCategory
        algorithm = try c.decodeIfPresent(CompressionAlgorithm.self, forKey: .algorithm) ?? d.algorithm
        zlibLevel = try c.decodeIfPresent(Int.self, forKey: .zlibLevel) ?? d.zlibLevel
        minSavingsPercent = try c.decodeIfPresent(Int.self, forKey: .minSavingsPercent) ?? d.minSavingsPercent
        minFileBytes = try c.decodeIfPresent(Int64.self, forKey: .minFileBytes) ?? d.minFileBytes
        excludedPaths = try c.decodeIfPresent([String].self, forKey: .excludedPaths) ?? d.excludedPaths
        excludedExtensions = (try c.decodeIfPresent([String].self, forKey: .excludedExtensions) ?? d.excludedExtensions)
            .map { $0.lowercased() }
        purgeAfterDays = try c.decodeIfPresent(Int.self, forKey: .purgeAfterDays) ?? d.purgeAfterDays
    }
}

public enum ConfigError: LocalizedError, Equatable {
    case unknownCategory(String)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .unknownCategory(let id):
            return "unknown category \"\(id)\" (known: \(Categories.all.map(\.id).joined(separator: ", ")))"
        case .invalid(let message):
            return message
        }
    }
}
