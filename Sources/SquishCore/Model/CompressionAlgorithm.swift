public enum CompressionAlgorithm: String, Codable, CaseIterable {
    /// Apple's default: good ratio, fast to read. What macOS uses for its own apps.
    case lzfse
    /// Fastest to decompress, lowest ratio.
    case lzvn
    /// Best ratio at level 9, slowest to read. Suits files that are almost never opened.
    case zlib

    var afsctoolName: String { rawValue.uppercased() }
}
