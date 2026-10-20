import XCTest
@testable import SquishCore

final class CompressibilityTests: XCTestCase {
    private let now = Date()
    private var tree: TestTree!

    override func setUpWithError() throws {
        tree = try TestTree()
    }

    private func scan(categories: [String] = ["code", "other"]) -> ScanResult {
        var config = SquishConfig.standard
        config.fileLocations = [tree.root.appendingPathComponent("Files").path]
        config.categories = categories
        return CandidateScanner(
            config: config, probe: FakeProbe(), isAppRunning: { _ in false }, canModify: { _ in true },
            projectBoundary: tree.root, now: now
        ).scan()
    }

    func testFilesThatWouldNotShrinkAreSkipped() throws {
        try tree.randomFile("Files/blob.bin", bytes: 200_000)
        try tree.textFile("Files/notes.json", bytes: 200_000)
        try tree.ageEverything(to: daysAgo(100, from: now))

        let result = scan()
        XCTAssertEqual(result.candidates.map(\.url.lastPathComponent), ["notes.json"])
        XCTAssertEqual(result.skips[.incompressible], 1)
    }

    /// The estimate must match what afsctool really frees, not a guess.
    func testEstimateIsWithinFifteenPercentOfTheRealSaving() throws {
        let executable: URL
        do { executable = try AfsctoolCompressor.locate() } catch { throw XCTSkip("afsctool not installed") }
        for (index, size) in [6_000, 20_000, 150_000, 900_000].enumerated() {
            try tree.textFile("Files/text\(index).json", bytes: size)
        }
        try tree.ageEverything(to: daysAgo(100, from: now))

        let candidates = scan().candidates
        XCTAssertEqual(candidates.count, 4)
        let estimated = candidates.reduce(Int64(0)) { $0 + $1.estimatedSavedBytes }
        let report = CompressionRun(
            compressor: AfsctoolCompressor(executable: executable, config: .standard, threads: 1),
            runningApps: { { _ in false } }
        ).execute(candidates)
        XCTAssertEqual(report.problems, [])
        XCTAssertGreaterThan(report.savedBytes, 0)
        XCTAssertEqual(Double(estimated), Double(report.savedBytes), accuracy: Double(report.savedBytes) * 0.15)
    }

    /// Reading a file updates its access time, which would make every sampled file
    /// look freshly used on the next scan.
    func testSamplingLeavesTheAccessTimeAlone() throws {
        let url = try tree.textFile("Files/old.json", bytes: 100_000)
        try tree.ageEverything(to: daysAgo(100, from: now))
        let before = try FileFacts.read(url).accessed

        _ = scan()
        XCTAssertEqual(try FileFacts.read(url).accessed.timeIntervalSince1970, before.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(scan().candidates.count, 1, "still dormant on the second scan")
    }

    func testBlockMathMatchesAPFS() {
        XCTAssertEqual(SavingsEstimate.allocatedAfter(logicalBytes: 500, ratio: 0.1), 4096, "never below one block")
        XCTAssertEqual(SavingsEstimate.allocatedAfter(logicalBytes: 4096, ratio: 0.1), 4096)
        XCTAssertEqual(SavingsEstimate.allocatedAfter(logicalBytes: 100_000, ratio: 0.5), 53_248)
    }
}
