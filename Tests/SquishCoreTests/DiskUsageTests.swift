import XCTest
@testable import SquishCore

final class DiskUsageTests: XCTestCase {
    func testSumsRegularFilesAndIgnoresSymlinks() throws {
        let tree = try TestTree()
        try tree.file("dir/a", bytes: 1000)
        let b = try tree.file("dir/sub/b", bytes: 3000)
        try FileManager.default.createSymbolicLink(at: tree.root.appendingPathComponent("dir/link"), withDestinationURL: b)
        try FileManager.default.createSymbolicLink(
            at: tree.root.appendingPathComponent("dir/sublink"),
            withDestinationURL: tree.root.appendingPathComponent("dir/sub")
        )

        let usage = try DiskUsage.measure(tree.root.appendingPathComponent("dir"))
        XCTAssertEqual(usage.fileCount, 2)
        XCTAssertEqual(usage.logicalBytes, 4000)
        XCTAssertEqual(usage.uncompressedLogicalBytes, 4000)
        XCTAssertEqual(usage.compressedFileCount, 0)
    }

    func testUnreadableSubfolderIsAnErrorNotALowTotal() throws {
        let tree = try TestTree()
        try tree.file("dir/a", bytes: 1000)
        try tree.file("dir/locked/b", bytes: 1000)
        let locked = tree.root.appendingPathComponent("dir/locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        XCTAssertThrowsError(try DiskUsage.measure(tree.root.appendingPathComponent("dir")))
    }
}
