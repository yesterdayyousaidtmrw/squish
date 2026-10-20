import XCTest
@testable import SquishCore

final class ConfigTests: XCTestCase {
    func testPartialConfigFillsTheRestFromDefaults() throws {
        let json = #"{"dormantDays": 7, "excludedExtensions": ["JPG"]}"#
        let config = try JSONDecoder().decode(SquishConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.dormantDays, 7)
        XCTAssertEqual(config.excludedExtensions, ["jpg"])
        XCTAssertEqual(config.categories, SquishConfig.standard.categories)
        XCTAssertEqual(config.algorithm, .lzfse)
    }

    func testPerCategoryDormancyFallsBackToTheDefault() {
        let config = SquishConfig.standard
        XCTAssertEqual(config.dormantDays(forCategory: "apps"), 21)
        XCTAssertEqual(config.dormantDays(forCategory: "text"), 30)
    }

    func testValidationRejectsUnknownCategoriesAndBadLevels() {
        var config = SquishConfig.standard
        config.categories.append("videos")
        XCTAssertThrowsError(try config.validate()) { XCTAssertEqual($0 as? ConfigError, .unknownCategory("videos")) }

        config = .standard
        config.dormantDaysByCategory["vidoes"] = 3
        XCTAssertThrowsError(try config.validate()) { XCTAssertEqual($0 as? ConfigError, .unknownCategory("vidoes")) }

        config = .standard
        config.zlibLevel = 12
        XCTAssertThrowsError(try config.validate())
    }

    func testStoreRoundTripsAndTreatsMissingFileAsDefaults() throws {
        let tree = try TestTree()
        let store = ConfigStore(url: tree.root.appendingPathComponent("nested/config.json"))
        XCTAssertEqual(try store.load(), .standard)

        var config = SquishConfig.standard
        config.algorithm = .zlib
        config.fileLocations = ["~/Old Projects"]
        try store.save(config)
        XCTAssertEqual(try store.load(), config)
    }

    func testEnabledCategoriesFollowMatchOrderNotConfigOrder() {
        var config = SquishConfig.standard
        config.categories = ["other", "code", "devArtifacts"]
        XCTAssertEqual(config.enabledCategories.map(\.id), ["devArtifacts", "code", "other"])
    }
}
