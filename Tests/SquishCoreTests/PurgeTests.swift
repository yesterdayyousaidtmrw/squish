import XCTest
@testable import SquishCore

final class PurgeTests: XCTestCase {
    private let now = Date()
    private var tree: TestTree!

    override func setUpWithError() throws {
        tree = try TestTree()
    }

    private func path(_ relative: String) -> URL {
        tree.root.appendingPathComponent(relative)
    }

    private func plan(openPaths: Set<String> = [], excluded: [String] = []) -> PurgePlan {
        var config = SquishConfig.standard
        config.fileLocations = [path("Code").path]
        config.excludedPaths = excluded
        return PurgePlanner(
            config: config, openFiles: FakeOpenFiles(open: openPaths), projectBoundary: tree.root, now: now
        ).plan()
    }

    private func relative(_ items: [PurgeItem]) -> [String] {
        let prefix = Paths.canonical(tree.root).path + "/"
        return items.map { String($0.url.path.dropFirst(prefix.count)) }.sorted()
    }

    func testDormantProjectsLoseTheirDependenciesAndBuildOutput() throws {
        try tree.file("Code/old-web/package.json")
        try tree.file("Code/old-web/src/app.js")
        try tree.file("Code/old-web/node_modules/lib/index.js")
        try tree.file("Code/old-swift/Package.swift")
        try tree.file("Code/old-swift/.build/debug/app")
        try tree.file("Code/new-web/package.json")
        try tree.file("Code/new-web/src/app.js")
        try tree.file("Code/new-web/node_modules/lib/index.js")
        try tree.ageEverything(to: daysAgo(200, from: now))
        try tree.setTimes(path("Code/new-web/src/app.js"), to: daysAgo(3, from: now))

        let result = plan()
        XCTAssertEqual(relative(result.items), ["Code/old-swift/.build", "Code/old-web/node_modules"])
        XCTAssertEqual(result.activeProjects, 1)
        let modules = try XCTUnwrap(result.items.first { $0.url.lastPathComponent == "node_modules" })
        XCTAssertEqual(modules.bytes, try DiskUsage.measure(modules.url).allocatedBytes)
        XCTAssertEqual(result.problems, [])
    }

    /// Moving to the Trash is not forgiving like compression: a folder that only
    /// shares the name of a build folder is the user's own work.
    func testFolderOnlyNamedLikeBuildOutputIsKept() throws {
        try tree.file("Code/design/.git/HEAD", bytes: 32)
        try tree.file("Code/design/target/logo.svg")
        try tree.file("Code/crate/.git/HEAD", bytes: 32)
        try tree.file("Code/crate/Cargo.toml")
        try tree.file("Code/crate/target/release/app")
        try tree.file("Code/loose/node_modules/lib/index.js")
        try tree.ageEverything(to: daysAgo(200, from: now))

        XCTAssertEqual(relative(plan().items), ["Code/crate/target"], "no Cargo.toml beside design/target, no project around loose/")
    }

    func testOpenOrExcludedFoldersAreKept() throws {
        try tree.file("Code/old-web/package.json")
        try tree.file("Code/old-web/node_modules/lib/index.js")
        try tree.file("Code/other/package.json")
        try tree.file("Code/other/node_modules/lib/index.js")
        try tree.ageEverything(to: daysAgo(200, from: now))
        let open = Paths.canonical(path("Code/old-web/node_modules/lib/index.js")).path

        let result = plan(openPaths: [open], excluded: [path("Code/other").path])
        XCTAssertEqual(result.items, [])
        XCTAssertEqual(result.openFolders, 1)
    }

    func testRunTrashesFoldersAndClearsCaches() throws {
        let modules = try tree.file("Code/old-web/node_modules/lib/index.js").deletingLastPathComponent().deletingLastPathComponent()
        let trash = FakeTrash()
        var commands: [[String]] = []
        let items = [
            PurgeItem(url: modules, kind: .folder(lastActivity: daysAgo(200, from: now)), bytes: 65_536, rebuild: "npm install"),
            PurgeItem(url: path("cache"), kind: .toolCache(command: ["/usr/bin/true", "clean"]), bytes: 1_000, rebuild: "re-downloaded"),
        ]

        let report = PurgeRun(trash: trash, openFiles: FakeOpenFiles(), run: { executable, arguments in
            commands.append([executable.path] + arguments)
            return ProcessOutcome(status: 0, stdout: "", stderr: "")
        }).execute(items)

        XCTAssertEqual(trash.trashed, [modules])
        XCTAssertEqual(commands, [["/usr/bin/true", "clean"]])
        XCTAssertEqual(report.done.count, 2)
        XCTAssertEqual(report.problems, [])
    }

    func testFolderOpenedAfterPlanningIsKept() throws {
        let file = try tree.file("Code/old-web/node_modules/lib/index.js")
        let modules = file.deletingLastPathComponent().deletingLastPathComponent()
        let trash = FakeTrash()
        let item = PurgeItem(url: modules, kind: .folder(lastActivity: now), bytes: 1, rebuild: "npm install")

        let report = PurgeRun(trash: trash, openFiles: FakeOpenFiles(open: [file.path]), run: { _, _ in
            XCTFail("no command expected")
            return ProcessOutcome(status: 0, stdout: "", stderr: "")
        }).execute([item])
        XCTAssertEqual(trash.trashed, [])
        XCTAssertEqual(report.done, [])
    }

    func testFailedCacheCommandIsReported() throws {
        let item = PurgeItem(url: path("cache"), kind: .toolCache(command: ["/usr/bin/false"]), bytes: 1, rebuild: "")
        let report = PurgeRun(trash: FakeTrash(), openFiles: FakeOpenFiles(), run: { _, _ in
            ProcessOutcome(status: 1, stdout: "", stderr: "boom")
        }).execute([item])
        XCTAssertEqual(report.done, [])
        XCTAssertTrue(report.problems.first?.contains("boom") ?? false)
    }

    func testCachesAreListedOnlyForInstalledTools() throws {
        let bin = path("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let brew = bin.appendingPathComponent("brew")
        try Data("#!/bin/sh\n".utf8).write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        try tree.file("brew-cache/bottle.tar.gz")

        var problems: [String] = []
        let caches = ToolCacheFinder(searchPath: bin.path, run: { executable, arguments in
            XCTAssertEqual(executable, brew)
            XCTAssertEqual(arguments, ["--cache"])
            return ProcessOutcome(status: 0, stdout: self.path("brew-cache").path + "\n", stderr: "")
        }).find(problems: &problems)

        XCTAssertEqual(caches.map(\.url.lastPathComponent), ["brew-cache"])
        XCTAssertEqual(caches.first?.kind, .toolCache(command: [brew.path, "cleanup", "--prune=all"]))
        XCTAssertGreaterThan(caches.first?.bytes ?? 0, 0)
        XCTAssertEqual(problems, [])
    }
}

final class FakeTrash: Trasher {
    var trashed: [URL] = []

    func trash(_ url: URL) throws {
        trashed.append(url)
    }
}
