import ImageIO
import UIKit

enum ScanFrame {
    /// Apply the image's EXIF orientation once, before using any view coordinates.
    static func load(_ data: Data, longestEdge: Int = 2400) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestEdge,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: pixels)
    }

    /// Normalized, top-left coordinates in the upright image, shared with the crop editor.
    static func crop(_ frame: UIImage, unitRect: CGRect) -> UIImage? {
        guard let pixels = frame.cgImage, frame.imageOrientation == .up else { return nil }
        let rect = unitRect.intersection(CGRect(x:0, y:0, width:1, height:1))
        guard !rect.isNull, !rect.isEmpty else { return nil }
        let w = CGFloat(pixels.width), h = CGFloat(pixels.height)
        let area = CGRect(x:rect.minX*w, y:rect.minY*h, width:rect.width*w, height:rect.height*h).integral
        return pixels.cropping(to:area).map { UIImage(cgImage:$0) }
    }

    static func fitPreview(_ image: UIImage, aspect: CGFloat?) -> UIImage {
        guard let aspect, aspect > 0 else { return image }
        let sourceAspect = image.size.width / image.size.height
        let w = min(1, aspect / sourceAspect), h = min(1, sourceAspect / aspect)
        return crop(image, unitRect:CGRect(x:(1-w)/2, y:(1-h)/2, width:w, height:h)) ?? image
    }
}
