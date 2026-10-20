import XCTest
@testable import SquishCore

final class CandidateScannerTests: XCTestCase {
    private let now = Date()
    private var tree: TestTree!

    override func setUpWithError() throws {
        tree = try TestTree()
        try tree.file("Files/old.swift")
        try tree.file("Files/recent.swift")
        try tree.file("Files/photo.jpg")
        try tree.file("Files/.git/objects/ab/cdef")
        try tree.file("Files/empty.txt", bytes: 0)
        try tree.file("Files/proj/node_modules/lib/index")
        try tree.file("Files/notes.md")
        try tree.file("Files/private/secret.txt")
        try tree.file("Files/keep-as-is.swift")
        let linked = try tree.file("Files/linked.txt")
        try FileManager.default.linkItem(at: linked, to: tree.root.appendingPathComponent("Files/linked-twin.txt"))
        try tree.file("Files/spotlit.txt")
        try tree.file("Files/blob.bin")
        for app in ["Old", "Running", "Updated", "Utilities/Nested"] {
            try tree.file("Apps/\(app).app/Contents/MacOS/binary")
            try tree.file("Apps/\(app).app/Contents/Info.plist", bytes: 512)
        }

        try tree.ageEverything(to: daysAgo(100, from: now))
        try tree.setTimes(path("Files/recent.swift"), to: daysAgo(5, from: now))
        try tree.setTimes(path("Files/proj/node_modules/lib/index"), to: daysAgo(20, from: now))
        try tree.setTimes(path("Files/notes.md"), to: daysAgo(20, from: now))
        try tree.setTimes(path("Apps/Updated.app/Contents/Info.plist"), to: daysAgo(3, from: now))
    }

    private func path(_ relative: String) -> URL {
        tree.root.appendingPathComponent(relative)
    }

    private func scanner(categories: [String]? = nil, canModify: Bool = true) -> CandidateScanner {
        var config = SquishConfig.standard
        config.appLocations = [path("Apps").path]
        config.fileLocations = [path("Files").path]
        config.excludedPaths = [path("Files/private").path, path("Files/keep-as-is.swift").path]
        if let categories { config.categories = categories }
        return CandidateScanner(
            config: config,
            probe: FakeProbe(dates: ["spotlit.txt": daysAgo(2, from: now)]),
            isAppRunning: { $0.lastPathComponent == "Running.app" },
            canModify: { _ in canModify },
            now: now
        )
    }

    func testPicksDormantItemsAndSaysWhyTheRestWereSkipped() {
        let result = scanner().scan()

        let picked = Dictionary(uniqueKeysWithValues: result.candidates.map { ($0.url.lastPathComponent, $0.categoryID) })
        XCTAssertEqual(picked, ["old.swift": "code", "index": "devArtifacts", "Old.app": "apps", "Nested.app": "apps"])
        XCTAssertEqual(result.skips[.recentlyUsed], 4, "recent.swift, notes.md (20d < 30d), spotlit.txt, Updated.app")
        XCTAssertEqual(result.skips[.excludedType], 1)
        XCTAssertEqual(result.skips[.tooSmall], 1)
        XCTAssertEqual(result.skips[.hardLinked], 2)
        XCTAssertEqual(result.skips[.running], 1)
        XCTAssertEqual(result.skips[.excludedPath], 2, "the private/ folder and the single excluded file")
        XCTAssertEqual(result.skips[.noMatchingCategory], 1, "blob.bin, with the catch-all off")
        XCTAssertEqual(result.problems, [])
    }

    func testGitObjectsAreNeverConsidered() {
        let result = scanner().scan()
        XCTAssertFalse(result.candidates.contains { $0.url.path.contains("/.git/") })
    }

    func testCatchAllCategoryTakesFilesNoOtherCategoryClaims() {
        let result = scanner(categories: ["code", "other"]).scan()
        let picked = Dictionary(uniqueKeysWithValues: result.candidates.map { ($0.url.lastPathComponent, $0.categoryID) })
        XCTAssertEqual(picked["blob.bin"], "other")
        XCTAssertEqual(picked["old.swift"], "code")
        XCTAssertFalse(result.candidates.contains { $0.kind == .app }, "apps category is off")
    }

    func testItemsItCannotWriteAreReportedAsNeedingAdmin() {
        let result = scanner(canModify: false).scan()
        XCTAssertEqual(result.candidates, [])
        XCTAssertEqual(result.skips[.needsAdmin], 4)
    }

    func testAlreadyCompressedAppIsSkipped() throws {
        let compressor = try AfsctoolCompressor(executable: AfsctoolCompressor.locate(), config: .standard, threads: 1)
        let binary = path("Apps/Old.app/Contents/MacOS/binary")
        try Data(String(repeating: "compress me ", count: 10_000).utf8).write(to: binary)
        try compressor.compress([path("Apps/Old.app")])
        try tree.ageEverything(to: daysAgo(100, from: now))

        let result = scanner().scan()
        XCTAssertFalse(result.candidates.contains { $0.url.lastPathComponent == "Old.app" })
        XCTAssertEqual(result.skips[.alreadyCompressed], 1)
    }
}
