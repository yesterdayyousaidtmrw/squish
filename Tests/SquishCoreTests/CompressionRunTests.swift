import XCTest
@testable import SquishCore

private final class RecordingCompressor: Compressor {
    var calls: [[String]] = []
    var failingNames: Set<String> = []

    func compress(_ urls: [URL]) throws {
        calls.append(urls.map(\.lastPathComponent))
        if urls.contains(where: { failingNames.contains($0.lastPathComponent) }) {
            throw CompressorError.failed(status: 1, output: "boom")
        }
    }
}

final class CompressionRunTests: XCTestCase {
    private func candidate(_ url: URL, _ kind: Candidate.Kind) throws -> Candidate {
        let usage = try DiskUsage.measure(url)
        return Candidate(url: url, kind: kind, categoryID: "x", lastActivity: Date(),
                         compressibleBytes: usage.uncompressedLogicalBytes, allocatedBytes: usage.allocatedBytes)
    }

    func testAppsGoAloneAndFilesGoInBatches() throws {
        let tree = try TestTree()
        let candidates = [
            try candidate(try tree.file("a.txt"), .file),
            try candidate(try tree.file("b.txt"), .file),
            try candidate(try tree.file("c.txt"), .file),
            try candidate(try tree.file("Tool.app/Contents/MacOS/tool").deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(), .app),
        ]
        let compressor = RecordingCompressor()
        _ = CompressionRun(compressor: compressor, batchSize: 2, runningApps: { { _ in false } }).execute(candidates)
        XCTAssertEqual(compressor.calls, [["Tool.app"], ["a.txt", "b.txt"], ["c.txt"]])
    }

    func testAppLaunchedAfterTheScanIsLeftAlone() throws {
        let tree = try TestTree()
        let binary = try tree.file("Tool.app/Contents/MacOS/tool")
        let app = binary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [try candidate(app, .app), try candidate(try tree.file("a.txt"), .file)]
        let compressor = RecordingCompressor()
        var messages: [String] = []
        let report = CompressionRun(
            compressor: compressor, progress: { messages.append($0) },
            runningApps: { { $0.lastPathComponent == "Tool.app" } }
        ).execute(candidates)
        XCTAssertEqual(compressor.calls, [["a.txt"]])
        XCTAssertTrue(messages.contains { $0.contains("Tool.app is running now") })
        XCTAssertEqual(report.problems, [])
    }

    func testFailedBatchIsReportedAndTheRestStillRun() throws {
        let tree = try TestTree()
        let candidates = [try candidate(try tree.file("a.txt"), .file), try candidate(try tree.file("b.txt"), .file)]
        let compressor = RecordingCompressor()
        compressor.failingNames = ["a.txt"]
        let report = CompressionRun(compressor: compressor, batchSize: 1).execute(candidates)
        XCTAssertEqual(compressor.calls.count, 2)
        XCTAssertEqual(report.problems.count, 1)
        XCTAssertTrue(report.problems[0].contains("boom"))
        XCTAssertEqual(report.savedBytes, 0, "nothing changed on disk")
    }

    func testSavingsAreMeasuredFromDisk() throws {
        let executable: URL
        do { executable = try AfsctoolCompressor.locate() } catch { throw XCTSkip("afsctool not installed") }
        let tree = try TestTree()
        let url = tree.root.appendingPathComponent("log.txt")
        try Data(String(repeating: "GET /health 200\n", count: 50_000).utf8).write(to: url)
        let report = CompressionRun(compressor: AfsctoolCompressor(executable: executable, config: .standard, threads: 1))
            .execute([try candidate(url, .file)])
        XCTAssertEqual(report.problems, [])
        XCTAssertEqual(report.compressedCount, 1)
        XCTAssertGreaterThan(report.savedBytes, 500_000)
    }
}
