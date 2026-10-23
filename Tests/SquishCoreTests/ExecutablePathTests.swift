import XCTest
@testable import SquishCore

final class ExecutablePathTests: XCTestCase {
    /// Homebrew runs /opt/homebrew/bin/squish, a link into a versioned Cellar folder
    /// that `brew upgrade` deletes. The schedule must keep the link, not the target.
    func testPrefersTheLinkOnPathOverTheVersionedBinary() throws {
        let tree = try TestTree()
        let real = try tree.file("Cellar/squish/0.1.0/bin/squish", bytes: 16)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: real.path)
        let bin = tree.root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("squish"), withDestinationURL: real)

        let chosen = ExecutablePath.stable(executable: real, searchPath: "/nonexistent:\(bin.path)")
        XCTAssertEqual(chosen.path, bin.appendingPathComponent("squish").path)
    }

    func testFallsBackToTheBinaryItselfWhenNothingOnPathMatches() throws {
        let tree = try TestTree()
        let real = try tree.file("build/squish", bytes: 16)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: real.path)
        let other = try tree.file("bin/squish", bytes: 16)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: other.path)

        let chosen = ExecutablePath.stable(executable: real, searchPath: other.deletingLastPathComponent().path)
        XCTAssertEqual(chosen.path, Paths.canonical(real).path, "a different squish on PATH is not this one")
    }
}
