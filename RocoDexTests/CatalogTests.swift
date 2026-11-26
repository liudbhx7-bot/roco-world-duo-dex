import XCTest
import UIKit
import ImageIO
@testable import RocoDex

final class CatalogTests: XCTestCase {
    func testCatalogContainsAllFormsAndKeepsStarterIdentity() throws {
        let c = try Catalog()
        XCTAssertEqual(c.entries.count, 665)
        let ids = Set(c.entries.map(\.id))
        XCTAssertEqual(ids.count, c.entries.count)
        XCTAssertEqual(c.pictures.urls.count, c.entries.count)
        let starters = c.entries.filter { (2...10).contains($0.id) }
        XCTAssertEqual(starters.map(\.name), ["喵喵","喵呜","魔力猫","火花","焰火","火神","水蓝蓝","波波拉","水灵"])
        for entry in c.entries {
            XCTAssertTrue(entry.evolution.allSatisfy(ids.contains), entry.name)
            XCTAssertTrue(c.forms(for: entry).contains { $0.id == entry.id })
        }
        let source = try XCTUnwrap(Bundle.main.url(forResource: "ScanIndex", withExtension: "json"))
        let index = try JSONDecoder().decode(ScanIndexFile.self, from: Data(contentsOf: source))
        XCTAssertEqual(index.version, ScanIndexFile.currentVersion)
        XCTAssertEqual(Set(index.records.map(\.asset)), Set(c.references.assets))
        for asset in index.records {
            let url = c.references.directory.appendingPathComponent(asset.asset.path)
            XCTAssertEqual(asset.fileSize, try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        }
        if let preview = c.pictures.thumbnail(8) {
            XCTAssertLessThanOrEqual(max(preview.size.width, preview.size.height), 96)
        } else { XCTFail("无法载入水蓝蓝缩略图") }
        let water = try XCTUnwrap(c.entries.first(where: { $0.id == 8 }))
        XCTAssertEqual(water.trait,"浸润")
        XCTAssertEqual(water.stats.reduce(0,+),372)
        XCTAssertEqual(water.evolution, [8, 9, 10, 10543])
        XCTAssertEqual(ArchivePage.profile.shifted(-1),.habitat)
    }

    func testBundledArtPassesThroughRecognition() async throws {
        let c = try Catalog()
        let model = SpiritRecognizer(references:c.references)
        for id in [2, 8, 10, 170, 321, 496] {
            let entry = try XCTUnwrap(c.entries.first { $0.id == id })
            let image = try XCTUnwrap(c.pictures[entry.id])
            switch try await model.identify(image) {
            case .match(let id): XCTAssertEqual(id,entry.id,entry.name)
            case .candidates(let ids): XCTAssertTrue(ids.contains(entry.id),entry.name)
            case .unknown: XCTFail("无法识别本身的参考图：" + entry.name)
            }
        }
        let blank = UIGraphicsImageRenderer(size:CGSize(width:280,height:240)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x:0,y:0,width:280,height:240))
        }
        if case .unknown = try await model.identify(blank) { } else { XCTFail("空白图应被拒绝") }
    }

    func testIdenticalArtworkOffersAllIndistinguishableForms() async throws {
        let catalog = try Catalog()
        let artwork = try XCTUnwrap(catalog.pictures[10574])
        let result = try await SpiritRecognizer(references: catalog.references).identify(artwork)
        guard case .candidates(let ids) = result else { return XCTFail("同图应由用户选择形态") }
        XCTAssertTrue(Set([10556, 10573, 10574, 10575, 10576, 10577, 10578, 10579]).isSubset(of: Set(ids)))
    }

    @MainActor
    func testEntryHandsOffToIdleAndSingleActionCardsHaveAFallback() async throws {
        let catalog = try Catalog()
        func open(_ id: Int, _ playback: PortraitPlayback) throws -> SpriteAnimationView {
            let view = SpriteAnimationView()
            view.open(try XCTUnwrap(catalog.animations[id]), playback: playback,
                      placeholder: try XCTUnwrap(catalog.pictures[id]))
            return view
        }
        func waitUntil(_ predicate: () -> Bool) async throws -> Bool {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(6)
            while clock.now < deadline {
                if predicate() { return true }
                try await Task.sleep(for: .milliseconds(20))
            }
            return predicate()
        }

        let card = PortraitPlayback()
        let sequence = try open(219, card)
        defer { sequence.close() }
        let entered = try await waitUntil { sequence.accessibilityValue?.hasPrefix("出场") == true }
        XCTAssertTrue(entered)
        sequence.setActive(true)
        let idling = try await waitUntil { sequence.accessibilityValue?.hasPrefix("待机") == true }
        XCTAssertTrue(idling)
        let frame = sequence.accessibilityValue
        let advanced = try await waitUntil { sequence.accessibilityValue != frame }
        XCTAssertTrue(advanced)
        sequence.close()

        let reopenedPanel = try open(219, card)
        defer { reopenedPanel.close() }
        let resumesIdle = try await waitUntil { reopenedPanel.accessibilityValue?.hasPrefix("待机") == true }
        XCTAssertTrue(resumesIdle)

        XCTAssertNil(catalog.animations[220]?.idle)
        let soloCard = PortraitPlayback()
        let entryOnly = try open(220, soloCard)
        defer { entryOnly.close() }
        entryOnly.setActive(true)
        let finished = try await waitUntil { soloCard.animationPreference == false }
        XCTAssertTrue(finished, "An entry without an idle clip must return to the still portrait")
        XCTAssertFalse(soloCard.failed)

        XCTAssertNil(catalog.animations[239]?.entry)
        let idleOnly = try open(239, PortraitPlayback())
        defer { idleOnly.close() }
        let startsIdle = try await waitUntil { idleOnly.accessibilityValue?.hasPrefix("待机") == true }
        XCTAssertTrue(startsIdle)
        XCTAssertNil(catalog.animations[5])
    }

    func testAnimationFramingKeepsTheEntryLandingAndIdleAtTheSameSize() throws {
        let json = """
        {
          "valid": {"x":0.25,"y":0.25,"width":0.5,"height":0.5,"entryKeys":[
            {"frame":0,"x":0,"y":0,"width":1,"height":1},
            {"frame":10,"x":0.25,"y":0.25,"width":0.5,"height":0.5}],"idleKeys":[
            {"frame":0,"x":0.25,"y":0.25,"width":0.5,"height":0.5},
            {"frame":4,"x":0,"y":0,"width":1,"height":1},
            {"frame":8,"x":0.25,"y":0.25,"width":0.5,"height":0.5}]},
          "badLoop": {"x":0.25,"y":0.25,"width":0.5,"height":0.5,"idleKeys":[
            {"frame":0,"x":0,"y":0,"width":1,"height":1}]},
          "invalid": {"x":0,"y":0,"width":0,"height":0.5}
        }
        """
        let rows = try JSONDecoder().decode([String: AnimationFraming].self, from: Data(json.utf8))
        let setting = try XCTUnwrap(rows["valid"])
        XCTAssertEqual(rows["invalid"], .fullCanvas)
        XCTAssertEqual(rows["badLoop"], .fullCanvas)
        XCTAssertEqual(setting.validated(entryFrameCount: 10, idleFrameCount: 9), .fullCanvas)
        XCTAssertEqual(setting.validated(entryFrameCount: 11, idleFrameCount: 8), .fullCanvas)
        let framing = setting.validated(entryFrameCount: 11, idleFrameCount: 9)
        let settled = framing.viewport(for: 0, isEntry: false)
        let middle = CGRect(x: 0.125, y: 0.125, width: 0.75, height: 0.75)
        XCTAssertEqual(framing.viewport(for: 5, isEntry: true), middle)
        XCTAssertEqual(framing.viewport(for: 2, isEntry: false), middle)
        XCTAssertEqual(framing.viewport(for: 10, isEntry: true), settled)
        XCTAssertEqual(framing.viewport(for: 8, isEntry: false), settled)
        let canvas = CGSize(width: 512, height: 416)
        let slot = CGRect(x: 0, y: 0, width: 512, height: 300)
        let result = AnimationFraming.imageFrame(canvas: canvas, viewport: settled, in: slot)
        XCTAssertEqual(result.height, 600, accuracy: 0.001)
        XCTAssertEqual(result.width / result.height, canvas.width / canvas.height, accuracy: 0.001)
        XCTAssertEqual(result.midX, slot.midX, accuracy: 0.001)
        XCTAssertEqual(result.midY, slot.midY, accuracy: 0.001)
    }

    func testWaterAnimationRetainsEveryFrameAndItsTiming() throws {
        let catalog = try Catalog()
        XCTAssertNil(catalog.animations[8]?.entry)
        let url = try XCTUnwrap(catalog.animations[8]?.idle)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 240)
        let properties = try XCTUnwrap(CGImageSourceCopyProperties(source, nil) as? [CFString: Any])
        let animation = try XCTUnwrap(properties[kCGImagePropertyPNGDictionary] as? [CFString: Any])
        XCTAssertEqual(animation[kCGImagePropertyAPNGLoopCount] as? Int, 0)
        var total = 0.0
        for index in 0..<CGImageSourceGetCount(source) {
            let frame = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])
            let png = try XCTUnwrap(frame[kCGImagePropertyPNGDictionary] as? [CFString: Any])
            total += try XCTUnwrap(png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double)
        }
        XCTAssertEqual(total, 4.8, accuracy: 0.001)
    }
}
