import XCTest
@testable import SquishCore

final class OpenFileAndGainTests: XCTestCase {
    private let now = Date()
    private var tree: TestTree!

    override func setUpWithError() throws {
        tree = try TestTree()
    }

    private func scan() -> ScanResult {
        var config = SquishConfig.standard
        config.fileLocations = [tree.root.appendingPathComponent("Files").path]
        config.categories = ["code"]
        return CandidateScanner(
            config: config, probe: FakeProbe(), isAppRunning: { _ in false }, canModify: { _ in true },
            projectBoundary: tree.root, now: now
        ).scan()
    }

    /// A child process holding the file open, the way a database or a log writer would.
    private func holdOpen(_ url: URL) throws -> Process {
        let holder = Process()
        holder.executableURL = URL(fileURLWithPath: "/bin/sh")
        holder.arguments = ["-c", "exec 3< \"$0\"; echo ready; sleep 30", url.path]
        let ready = Pipe()
        holder.standardOutput = ready
        try holder.run()
        _ = ready.fileHandleForReading.availableData
        return holder
    }

    func testFileOpenInAnotherProcessIsLeftAlone() throws {
        let busy = try tree.textFile("Files/busy.json", bytes: 100_000)
        try tree.textFile("Files/idle.json", bytes: 100_000)
        try tree.ageEverything(to: daysAgo(100, from: now))
        let holder = try holdOpen(busy)
        defer { holder.terminate() }

        let result = scan()
        XCTAssertEqual(result.candidates.map(\.url.lastPathComponent), ["idle.json"])
        XCTAssertEqual(result.skips[.openElsewhere], 1)
    }

    /// Anything of 4 KB or less still takes a whole block after compression.
    func testFileThatCannotFreeAFullBlockIsSkipped() throws {
        // Compressible, so the sampler passes it and only the block rule can stop it.
        try tree.file("Files/small.json", bytes: 3_000)
        try tree.textFile("Files/large.json", bytes: 100_000)
        try tree.ageEverything(to: daysAgo(100, from: now))

        let result = scan()
        XCTAssertEqual(result.candidates.map(\.url.lastPathComponent), ["large.json"])
        XCTAssertEqual(result.skips[.tooLittleGain], 1)
    }

    func testFileOpenedAfterTheScanIsLeftAlone() throws {
        let busy = try tree.textFile("busy.json", bytes: 100_000)
        let idle = try tree.textFile("idle.json", bytes: 100_000)
        let candidates = try [busy, idle].map { url in
            Candidate(url: url, kind: .file, categoryID: "code", lastActivity: now, compressibleBytes: 0,
                      allocatedBytes: try FileFacts.read(url).allocatedBytes)
        }
        let compressor = RecordingCompressor()
        let report = CompressionRun(
            compressor: compressor, runningApps: { { _ in false } },
            openFiles: FakeOpenFiles(open: [busy.path])
        ).execute(candidates)
        XCTAssertEqual(compressor.calls, [["idle.json"]])
        XCTAssertEqual(report.problems, [])
    }
}

struct FakeOpenFiles: OpenFileProbe {
    var open: Set<String> = []

    func openPaths() throws -> Set<String> {
        open
    }
}
