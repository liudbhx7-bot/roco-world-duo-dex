import XCTest
@testable import RocoDex

@MainActor
final class HabitatCatalogTests: XCTestCase {
    func testEachFormReferencesValidMapGeometry() throws {
        let catalog = try Catalog()
        let habitats = HabitatCatalog.shared
        for spirit in catalog.entries {
            let entry = try XCTUnwrap(habitats.entry(for: spirit), spirit.formattedName)
            for key in entry.points {
                let point = try XCTUnwrap(habitats.point(key), spirit.formattedName)
                XCTAssertNotNil(habitats.map(point.map))
                XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y))
            }
            for key in entry.regions {
                let region = try XCTUnwrap(habitats.region(key), spirit.formattedName)
                XCTAssertNotNil(habitats.map(region.map))
                XCTAssertGreaterThanOrEqual(region.polygon.count, 3)
                XCTAssertTrue(region.polygon.allSatisfy { $0.count == 2 && $0.allSatisfy { (0...1).contains($0) } })
            }
        }
        XCTAssertNotNil(habitats.image(for: "mainland"))
        XCTAssertNotNil(habitats.image(for: "academy"))
    }

    func testVariantsKeepTheirOwnAcquisitionSourcesAndLocations() throws {
        let catalog = try Catalog()
        let habitats = HabitatCatalog.shared
        func entry(_ id: Int) throws -> HabitatEntry {
            let spirit = try XCTUnwrap(catalog.entries.first { $0.id == id })
            return try XCTUnwrap(habitats.entry(for: spirit))
        }
        let starter = try entry(8)
        XCTAssertTrue(starter.points.isEmpty)
        XCTAssertTrue(starter.sources.contains { $0.kind == "精灵果实" })
        let shell = try entry(12)
        let molting = try entry(10409)
        XCTAssertFalse(shell.points.isEmpty)
        XCTAssertTrue(molting.points.isEmpty)
        XCTAssertFalse(molting.regions.isEmpty)
        let sea = try entry(171)
        let polluted = try entry(10406)
        XCTAssertTrue(sea.areas.contains("咸水湾"))
        XCTAssertTrue(polluted.areas.contains("恶水沼泽"))
        XCTAssertTrue(Set(sea.points).isDisjoint(with: polluted.points))
    }
}
