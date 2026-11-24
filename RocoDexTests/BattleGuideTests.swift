import XCTest
@testable import RocoDex

final class BattleGuideTests: XCTestCase {
    func testEveryFormResolvesItsLocalSkillsAndImages() throws {
        let guide = BattleGuide.shared
        let catalog = try Catalog()
        var icons = Set<String>()
        var elements = Set<String>()
        for spirit in catalog.entries {
            let profile = try XCTUnwrap(guide.profile(for: spirit.id), spirit.formattedName)
            XCTAssertNotNil(profile.height)
            XCTAssertNotNil(profile.weight)
            let trait = try XCTUnwrap(guide.trait(for: spirit.id))
            XCTAssertEqual(trait.name, spirit.trait)
            icons.insert(trait.icon)
            elements.formUnion(spirit.type.components(separatedBy: "／"))
            let rows = guide.skills(for: spirit.id)
            XCTAssertFalse(rows.isEmpty, spirit.formattedName)
            XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, spirit.formattedName)
            for row in rows {
                let skill = try XCTUnwrap(guide.skill(row.skill))
                icons.insert(skill.icon)
                XCTAssertFalse(skill.effect.isEmpty, skill.name)
            }
        }
        XCTAssertEqual(elements.count, 18)
        for element in elements { XCTAssertNotNil(guide.typeImage(element), element) }
        for icon in icons { XCTAssertNotNil(guide.image(icon), icon) }
    }

    func testKakakesBubbleMatchesThePublishedSkillCard() throws {
        let guide = BattleGuide.shared
        let rows = guide.skills(for: 13)
        XCTAssertEqual(Dictionary(grouping: rows, by: \.source).mapValues(\.count),
                       [.level: 13, .machine: 14, .blood: 18])
        let bubble = try XCTUnwrap(rows.first { guide.skill($0.skill)?.name == "肥皂泡" })
        XCTAssertEqual(bubble.source, .level)
        XCTAssertEqual(bubble.level, 1)
        let detail = try XCTUnwrap(guide.skill(bubble.skill))
        XCTAssertEqual(detail.element, "水系")
        XCTAssertEqual(detail.category, "魔攻")
        XCTAssertEqual(detail.power, "60")
        XCTAssertEqual(detail.energy, 1)
        XCTAssertEqual(detail.effect, "对敌方精灵造成魔法伤害。")
    }

    func testFormsWithTheSamePublicNumberKeepDistinctMoves() {
        let guide = BattleGuide.shared
        let white = Set(guide.skills(for: 191).map(\.id))
        let black = Set(guide.skills(for: 10441).map(\.id))
        XCTAssertEqual(white.count, 58)
        XCTAssertEqual(black.count, 57)
        XCTAssertNotEqual(white, black)
    }
}
