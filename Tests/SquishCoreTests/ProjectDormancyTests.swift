import XCTest
@testable import SquishCore

final class ProjectDormancyTests: XCTestCase {
    private let now = Date()
    private var tree: TestTree!

    override func setUpWithError() throws {
        tree = try TestTree()
    }

    private func path(_ relative: String) -> URL {
        tree.root.appendingPathComponent(relative)
    }

    private func pickedPaths(scanning location: String) -> Set<String> {
        var config = SquishConfig.standard
        config.fileLocations = [path(location).path]
        config.categories = ["devArtifacts", "code"]
        let result = CandidateScanner(
            config: config, probe: FakeProbe(), isAppRunning: { _ in false }, canModify: { _ in true },
            projectBoundary: tree.root, now: now
        ).scan()
        let prefix = Paths.canonical(tree.root).path + "/"
        return Set(result.candidates.map { String($0.url.path.dropFirst(prefix.count)) })
    }

    func testActiveProjectKeepsItsDependenciesUncompressed() throws {
        try tree.file("Code/active/package.json")
        try tree.file("Code/active/src/index.js")
        try tree.file("Code/active/node_modules/lib/index.js")
        try tree.file("Code/dormant/package.json")
        try tree.file("Code/dormant/node_modules/lib/index.js")
        try tree.ageEverything(to: daysAgo(100, from: now))
        try tree.setTimes(path("Code/active/src/index.js"), to: daysAgo(2, from: now))

        let picked = pickedPaths(scanning: "Code")
        XCTAssertFalse(picked.contains("Code/active/node_modules/lib/index.js"), "edited 2 days ago, so its dependencies are in use")
        XCTAssertFalse(picked.contains("Code/active/package.json"), "old files of an active project stay too")
        XCTAssertTrue(picked.contains("Code/dormant/node_modules/lib/index.js"))
        XCTAssertTrue(picked.contains("Code/dormant/package.json"))
    }

    func testGitReflogCountsAsProjectActivity() throws {
        try tree.file("Code/repo/.git/HEAD", bytes: 32)
        try tree.file("Code/repo/.git/logs/HEAD", bytes: 200)
        try tree.file("Code/repo/main.swift")
        try tree.file("Code/repo/.build/debug/output.json")
        try tree.ageEverything(to: daysAgo(100, from: now))
        try tree.setTimes(path("Code/repo/.git/logs/HEAD"), to: daysAgo(1, from: now))

        XCTAssertEqual(pickedPaths(scanning: "Code"), [], "a checkout or commit yesterday keeps the whole repo")
    }

    func testScanRootThatIsItselfAProject() throws {
        try tree.file("Code/active/Package.swift")
        try tree.file("Code/active/Sources/main.swift")
        try tree.file("Code/active/.build/debug/output.json")
        try tree.ageEverything(to: daysAgo(100, from: now))
        try tree.setTimes(path("Code/active/Sources/main.swift"), to: daysAgo(3, from: now))

        XCTAssertEqual(pickedPaths(scanning: "Code/active"), [])
    }

    func testScanLocationInsideAnActiveProject() throws {
        try tree.file("Code/active/package.json")
        try tree.file("Code/active/src/index.js")
        try tree.file("Code/active/node_modules/lib/index.js")
        try tree.file("Code/active/node_modules/dep/package.json")
        try tree.ageEverything(to: daysAgo(100, from: now))
        try tree.setTimes(path("Code/active/src/index.js"), to: daysAgo(2, from: now))

        XCTAssertEqual(pickedPaths(scanning: "Code/active/node_modules"), [], "the enclosing project is in use")
        XCTAssertEqual(pickedPaths(scanning: "Code/active/node_modules/dep"), [], "even from inside a dependency")
    }

    func testPackagesInsideDependenciesDoNotCountAsProjects() throws {
        // node_modules/pkg has a package.json. Treated as a project, its 10-day-old file
        // would make the whole package look active and keep the old index.js.
        try tree.file("Code/loose/node_modules/pkg/package.json")
        try tree.file("Code/loose/node_modules/pkg/index.js")
        try tree.file("Code/loose/node_modules/pkg/src/new.js")
        try tree.ageEverything(to: daysAgo(100, from: now))
        try tree.setTimes(path("Code/loose/node_modules/pkg/src/new.js"), to: daysAgo(10, from: now))

        let picked = pickedPaths(scanning: "Code")
        XCTAssertTrue(picked.contains("Code/loose/node_modules/pkg/index.js"))
        XCTAssertFalse(picked.contains("Code/loose/node_modules/pkg/src/new.js"), "10d < devArtifacts' 14d")
    }
}
