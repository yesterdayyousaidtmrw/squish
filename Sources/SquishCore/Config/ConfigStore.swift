import Foundation

public struct ConfigStore {
    public let url: URL

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        Paths.home.appendingPathComponent("Library/Application Support/Squish/config.json")
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// No file yet means the standard settings, not an error.
    public func load() throws -> SquishConfig {
        guard exists else { return .standard }
        let config = try JSONDecoder().decode(SquishConfig.self, from: Data(contentsOf: url))
        try config.validate()
        return config
    }

    public func save(_ config: SquishConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encode(config).write(to: url, options: .atomic)
    }

    public static func encode(_ config: SquishConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(config)
    }
}
