import XCTest
@testable import SquishCore

final class CompressorTests: XCTestCase {
    private let path = URL(fileURLWithPath: "/tmp/a b.txt")

    func testLZFSEArguments() {
        let compressor = AfsctoolCompressor(executable: path, config: .standard, threads: 4)
        XCTAssertEqual(compressor.arguments(for: [path]), ["-c", "-f", "-T", "LZFSE", "-j4", "-s", "10", "/tmp/a b.txt"])
    }

    func testZlibPassesItsLevel() {
        var config = SquishConfig.standard
        config.algorithm = .zlib
        config.zlibLevel = 7
        let args = AfsctoolCompressor(executable: path, config: config, threads: 1).arguments(for: [path])
        XCTAssertEqual(Array(args.suffix(2)), ["-7", "/tmp/a b.txt"])
        XCTAssertTrue(args.contains("ZLIB"))
    }

    /// Real afsctool on a real APFS file: the bytes must survive both directions.
    func testCompressesAndRestoresARealFile() throws {
        let executable: URL
        do { executable = try AfsctoolCompressor.locate() } catch { throw XCTSkip("afsctool not installed") }
        let tree = try TestTree()
        let url = tree.root.appendingPathComponent("big.txt")
        let original = Data(String(repeating: "squish me ", count: 100_000).utf8)
        try original.write(to: url)
        let before = try FileFacts.read(url)

        try AfsctoolCompressor(executable: executable, config: .standard, threads: 1).compress([url])
        let compressed = try FileFacts.read(url)
        XCTAssertTrue(compressed.isCompressed)
        XCTAssertEqual(compressed.logicalBytes, before.logicalBytes)
        XCTAssertLessThan(compressed.allocatedBytes, before.allocatedBytes / 10)
        XCTAssertEqual(try Data(contentsOf: url), original)

        try Decompressor.expand([url])
        XCTAssertFalse(try FileFacts.read(url).isCompressed)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
