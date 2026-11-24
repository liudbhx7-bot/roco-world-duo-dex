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

    func testWaterAnimationRetainsEveryFrameAndItsTiming() throws {
        let catalog = try Catalog()
        XCTAssertEqual(Set(catalog.animationURLs.keys), [8])
        let url = try XCTUnwrap(catalog.animationURLs[8])
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
