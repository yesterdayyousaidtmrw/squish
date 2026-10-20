import XCTest
@testable import SquishCore

final class ChurnTests: XCTestCase {
    private let now = Date()
    private var tree: TestTree!

    override func setUpWithError() throws {
        tree = try TestTree()
    }

    private func scan(with ledger: ChurnLedger) -> ScanResult {
        var config = SquishConfig.standard
        config.fileLocations = [tree.root.appendingPathComponent("Files").path]
        config.categories = ["code"]
        return CandidateScanner(
            config: config, probe: FakeProbe(), isAppRunning: { _ in false }, canModify: { _ in true },
            ledger: ledger, projectBoundary: tree.root, now: now
        ).scan()
    }

    /// New content under the same name: something keeps rewriting this file.
    private func rewrite(_ url: URL, ageDays: Double) throws {
        try Data(repeating: UInt8(ascii: "b"), count: 70_000).write(to: url, options: .atomic)
        try tree.setTimes(url, to: daysAgo(ageDays, from: now))
    }

    func testRewrittenFileWaitsTwiceAsLong() throws {
        // The scanner reports real paths (/private/var/…), and the ledger is keyed by them.
        let url = Paths.canonical(try tree.file("Files/cache.json"))
        var ledger = ChurnLedger()
        ledger.recordCompressed(url.path, facts: try FileFacts.read(url))
        try rewrite(url, ageDays: 40)

        let result = scan(with: ledger)
        XCTAssertEqual(result.candidates, [], "40 days < 30 × 2")
        XCTAssertEqual(result.skips[.recentlyUsed], 1)
        XCTAssertEqual(result.rewrittenPaths, [url.path])
    }

    func testEachRewriteDoublesAgain() throws {
        // The scanner reports real paths (/private/var/…), and the ledger is keyed by them.
        let url = Paths.canonical(try tree.file("Files/cache.json"))
        var ledger = ChurnLedger()
        ledger.recordCompressed(url.path, facts: try FileFacts.read(url))
        ledger.recordRewrite(url.path)
        ledger.recordCompressed(url.path, facts: try FileFacts.read(url))
        try rewrite(url, ageDays: 100)

        XCTAssertEqual(scan(with: ledger).candidates, [], "second rewrite: 100 days < 30 × 4")
        try tree.setTimes(url, to: daysAgo(130, from: now))
        XCTAssertEqual(scan(with: ledger).candidates.count, 1)
    }

    func testDecompressedButUnchangedIsNotARewrite() throws {
        let url = Paths.canonical(try tree.file("Files/stable.json"))
        try tree.ageEverything(to: daysAgo(40, from: now))
        var ledger = ChurnLedger()
        ledger.recordCompressed(url.path, facts: try FileFacts.read(url))

        let result = scan(with: ledger)
        XCTAssertEqual(result.candidates.count, 1, "same inode, size and mtime: restored, not rewritten")
        XCTAssertEqual(result.rewrittenPaths, [])
    }

    func testBackOffIsCapped() {
        var ledger = ChurnLedger()
        for _ in 0..<20 { ledger.recordRewrite("/x") }
        XCTAssertEqual(ledger.files["/x"]?.rewrites, ChurnLedger.maxRewrites)
    }

    func testLedgerFollowsARun() throws {
        let executable: URL
        do { executable = try AfsctoolCompressor.locate() } catch { throw XCTSkip("afsctool not installed") }
        let compressed = try tree.textFile("Files/a.json", bytes: 100_000)
        let untouched = try tree.randomFile("Files/b.bin", bytes: 100_000)
        try AfsctoolCompressor(executable: executable, config: .standard, threads: 1).compress([compressed])
        let candidates = try [compressed, untouched].map { url in
            Candidate(url: url, kind: .file, categoryID: "code", lastActivity: now, compressibleBytes: 0,
                      allocatedBytes: try FileFacts.read(url).allocatedBytes)
        }
        let report = RunReport(outcomes: candidates.map { CandidateOutcome(candidate: $0, allocatedAfter: 0) }, problems: [])
        var ledger = ChurnLedger()
        ledger.recordCompressed("/gone/file", facts: try FileFacts.read(compressed))

        try ledger.update(after: report, rewritten: [untouched.path])
        XCTAssertEqual(ledger.files[compressed.path]?.compressed, true)
        XCTAssertEqual(ledger.files[untouched.path]?.rewrites, 1)
        XCTAssertEqual(ledger.files[untouched.path]?.compressed, false)
        XCTAssertNil(ledger.files["/gone/file"], "paths that no longer exist are pruned")
    }

    /// One file deleted mid-run must not cost the history of everything else.
    func testFileDeletedDuringTheRunIsDropped() throws {
        let kept = try tree.textFile("Files/kept.json", bytes: 100_000)
        let deleted = try tree.textFile("Files/deleted.json", bytes: 100_000)
        let candidates = try [kept, deleted].map { url in
            Candidate(url: url, kind: .file, categoryID: "code", lastActivity: now, compressibleBytes: 0,
                      allocatedBytes: try FileFacts.read(url).allocatedBytes)
        }
        try FileManager.default.removeItem(at: deleted)
        var ledger = ChurnLedger()

        try ledger.update(
            after: RunReport(outcomes: candidates.map { CandidateOutcome(candidate: $0, allocatedAfter: 0) }, problems: []),
            rewritten: [kept.path]
        )
        XCTAssertEqual(ledger.files[kept.path]?.rewrites, 1)
        XCTAssertNil(ledger.files[deleted.path])
    }

    func testStoreRoundTripsAndStartsEmpty() throws {
        let store = LedgerStore(configURL: tree.root.appendingPathComponent("cfg/config.json"))
        XCTAssertEqual(try store.load(), ChurnLedger())
        var ledger = ChurnLedger()
        ledger.recordRewrite("/some/file")
        try store.save(ledger)
        XCTAssertEqual(try store.load(), ledger)
        XCTAssertEqual(store.url.lastPathComponent, "state.json")
    }
}
