import ImageIO
import UniformTypeIdentifiers
import UIKit
import XCTest
@testable import RocoDex

final class ScanFrameTests: XCTestCase {
    func testRotatedPhotoAndSelectionUseSameCoordinates() throws {
        let size = CGSize(width: 80, height: 40)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { canvas in
            canvas.cgContext.setFillColor(UIColor.red.cgColor)
            canvas.cgContext.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            canvas.cgContext.setFillColor(UIColor.blue.cgColor)
            canvas.cgContext.fill(CGRect(x: 40, y: 0, width: 40, height: 40))
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [kCGImagePropertyOrientation: 6]
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let upright = try XCTUnwrap(ScanFrame.load(data as Data, longestEdge: 80))
        XCTAssertEqual(upright.size, CGSize(width: 40, height: 80))
        XCTAssertEqual(upright.imageOrientation, .up)
        let top = try XCTUnwrap(ScanFrame.crop(upright, unitRect: CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.2)))
        let bottom = try XCTUnwrap(ScanFrame.crop(upright, unitRect: CGRect(x: 0.25, y: 0.7, width: 0.5, height: 0.2)))
        let upperPixel = try sample(top)
        let lowerPixel = try sample(bottom)
        XCTAssertGreaterThan(upperPixel[0], upperPixel[2])
        XCTAssertGreaterThan(lowerPixel[2], lowerPixel[0])
        let preview = ScanFrame.fitPreview(upright, aspect: 2)
        XCTAssertEqual(preview.size, CGSize(width: 40, height: 20))
        XCTAssertNil(ScanFrame.crop(upright, unitRect: CGRect(x: 1.2, y: 0, width: 1, height: 1)))
    }

    private func sample(_ image: UIImage) throws -> [UInt8] {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let flags = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                               bytesPerRow: 4, space: colorSpace, bitmapInfo: flags))
        context.draw(try XCTUnwrap(image.cgImage), in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pixel, count: 4))
    }
}
