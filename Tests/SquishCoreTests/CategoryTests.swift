import XCTest
@testable import SquishCore

final class CategoryTests: XCTestCase {
    func testDevArtifactsMatchOnFolderBelowTheScanRoot() throws {
        let dev = try XCTUnwrap(Categories.named("devArtifacts"))
        XCTAssertTrue(dev.matches(fileExtension: "", directories: ["app", "node_modules", "lodash"]))
        XCTAssertFalse(dev.matches(fileExtension: "js", directories: ["src"]))
    }

    func testExtensionCategories() throws {
        let code = try XCTUnwrap(Categories.named("code"))
        XCTAssertTrue(code.matches(fileExtension: "swift", directories: []))
        XCTAssertFalse(code.matches(fileExtension: "txt", directories: []))
    }

    func testCatchAllMatchesAnything() throws {
        let other = try XCTUnwrap(Categories.named("other"))
        XCTAssertTrue(other.matches(fileExtension: "", directories: []))
    }

    func testCategoryIDsAreUnique() {
        let ids = Categories.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
