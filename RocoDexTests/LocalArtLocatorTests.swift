import UIKit
import XCTest
@testable import RocoDex

final class LocalArtLocatorTests: XCTestCase {
    func testSmallTiltedArtworkNearLeftEdge() async throws {
        let catalog = try Catalog()
        let water = try XCTUnwrap(catalog.pictures[8])
        let frame = makeFrame(artwork: water)
        let saved = try XCTUnwrap(frame.jpegData(compressionQuality: 0.64))
        let input = try XCTUnwrap(UIImage(data: saved))
        let result = try await SpiritRecognizer(references: catalog.references).identify(input)
        XCTAssertEqual(result, .match(8))
    }

    func testUnrelatedControlsAndColorBlocksAreRejected() async throws {
        let catalog = try Catalog()
        let frame = makeFrame(artwork: nil)
        let result = try await SpiritRecognizer(references: catalog.references).identify(frame)
        XCTAssertEqual(result, .unknown)
    }

    /// Common test backdrop has coloured controls and intersecting outlines. The subject
    /// occupies about a quarter of the frame height and lies outside the centre crop.
    private func makeFrame(artwork: UIImage?) -> UIImage {
        let size = CGSize(width: 820, height: 560)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { render in
            let ctx = render.cgContext
            ctx.setFillColor(UIColor(red: 0.24, green: 0.37, blue: 0.42, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            for row in 0..<5 {
                for column in 0..<8 {
                    let hue = CGFloat((row + column * 2) % 12) / 12
                    ctx.setFillColor(UIColor(hue: hue, saturation: 0.32, brightness: 0.55, alpha: 1).cgColor)
                    let rect = CGRect(x: 11 + column*105, y: 38 + row*120, width: 79, height: 78)
                    ctx.fillEllipse(in: rect)
                    ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.42).cgColor)
                    ctx.stroke(rect.insetBy(dx: -6, dy: -3))
                }
            }
            guard let artwork else { return }
            let factor = 168 / max(artwork.size.width, artwork.size.height)
            let width = artwork.size.width * factor, height = artwork.size.height * factor
            ctx.translateBy(x: 164, y: 191)
            ctx.rotate(by: -0.24)
            ctx.scaleBy(x: 0.95, y: 1)
            artwork.draw(in: CGRect(x: -width/2, y: -height/2, width: width, height: height))
        }
    }
}
