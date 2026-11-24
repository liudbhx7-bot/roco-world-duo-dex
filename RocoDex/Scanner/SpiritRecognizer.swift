import CoreGraphics
import Foundation
import Vision
#if canImport(UIKit)
import UIKit
#endif

enum ScanResult: Equatable, Sendable {
    case match(Int)
    case candidates([Int])
    case unknown
}

enum ScanIssue: LocalizedError {
    case image, database
    var errorDescription: String? {
        switch self {
        case .image: "图片无法读取，请重新选择。"
        case .database: "本地图鉴图片未载入，请重试。"
        }
    }
}

#if canImport(UIKit)
/// Holds reference images on a private serial queue. Vision requests never block the UI.
final class SpiritRecognizer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "roco.scanner.match", qos: .userInitiated)
    private let references: ScanLibrary
    private var matcher: LibraryMatcher?

    init(references: ScanLibrary) { self.references = references }

    func identify(_ image: UIImage) async throws -> ScanResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                autoreleasepool {
                    do {
                        if matcher == nil {
                            matcher = try LibraryMatcher(library: references)
                        }
                        guard let matcher, let cgImage = image.normalizedScanImage() else { throw ScanIssue.image }
                        continuation.resume(returning: try matcher.identify(cgImage))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
    }
}

private extension UIImage {
    func normalizedScanImage() -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        if imageOrientation == .up, let cgImage { return cgImage }
        let ratio = min(1, 1200 / max(size.width, size.height))
        let size = CGSize(width: size.width * ratio, height: size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
#endif

/// Reference matching uses visible artwork, without reading labels or file names.
struct ReferenceMatcher {
    struct Prepared {
        let local: LocalArtLocator.Prepared
        fileprivate let descriptor: ScanDescriptor

        init?(_ image: CGImage) {
            guard let subject = NormalizedSubject(image) else { return nil }
            descriptor = ScanDescriptor(subject)
            local = LocalArtLocator.Prepared(image)
        }
    }

    init(prepared: [(Int, Prepared)]) throws {
        guard !prepared.isEmpty else { throw ScanIssue.database }
        locator = LocalArtLocator(prepared: prepared.map { ($0.0, $0.1.local) })
        index = prepared.map { ($0.0, $0.1.descriptor) }
    }

    private let locator: LocalArtLocator
    private let index: [(id: Int, descriptor: ScanDescriptor)]

    init(references: [(Int, CGImage)]) throws {
        try self.init(prepared: references.compactMap { id, image in
            Prepared(image).map { (id, $0) }
        })
    }

    func identify(_ image: CGImage) throws -> ScanResult {
        Self.classify(try ranked(image))
    }

    static func classify(_ scores: [(Int, Double)]) -> ScanResult {
        guard let best = scores.first, best.1 < 0.48 else { return .unknown }
        let gap = (scores.dropFirst().first?.1 ?? 1) - best.1
        if best.1 < 0.345 && gap > 0.080 { return .match(best.0) }
        return .candidates(Array(scores.prefix(3).filter { $0.1 < 0.53 && $0.1 <= best.1 + 0.105 }.map(\.0)))
    }

    static func subjects(in image: CGImage) -> [NormalizedSubject] {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        guard min(width, height) > 12 else { return [] }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let sizes: [CGFloat] = [1, 0.77, 0.55]
        var regions = [full]
        for size in sizes {
            let side = min(width, height) * size
            let region = CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side).integral
            if region != full { regions.append(region) }
        }
        return regions.compactMap { rect in image.cropping(to: rect).flatMap(NormalizedSubject.init) }
    }

    func ranked(_ image: CGImage) throws -> [(Int, Double)] {
        ranked(subjects: Self.subjects(in: image), probe: LocalArtLocator.Probe(image))
    }

    func ranked(subjects: [NormalizedSubject], probe: LocalArtLocator.Probe) -> [(Int, Double)] {
        var scores = locator.evidence(for: probe)
        for (cropIndex, subject) in subjects.enumerated() {
            let query = ScanDescriptor(subject)
            for item in index {
                // Extreme zooms may contain a fragment of an unrelated subject.
                let penalty = cropIndex == subjects.count - 1 ? 0.025 : 0
                let score = query.distance(to: item.descriptor) + penalty
                scores[item.id] = min(scores[item.id] ?? .infinity, score)
            }
        }
        return scores.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }
            .map { ($0.key, $0.value) }
    }
}

private let scanColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
private let scanBitmapFlags = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
private let neutral: UInt8 = 146

struct NormalizedSubject {
    let pixels: [UInt8]
    let image: CGImage
    static let side = 128

    init?(_ source: CGImage) {
        let ratio = min(256.0 / Double(max(source.width, source.height)), 2)
        let w = max(1, Int(Double(source.width) * ratio))
        let h = max(1, Int(Double(source.height) * ratio))
        guard min(w, h) > 3,
              let buffer = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                     bytesPerRow: 4 * w, space: scanColorSpace, bitmapInfo: scanBitmapFlags),
              let raw = buffer.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        buffer.interpolationQuality = .medium
        buffer.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Remove transparent margins, or a connected, approximately uniform backdrop.
        let corners = [0, w-1, w*(h-1), w*h-1].map { RGB(raw, offset: $0 * 4) }
        let backdrop = corners.max { a, b in
            corners.filter { $0.close(to: a) }.count < corners.filter { $0.close(to: b) }.count
        }!
        let hasBackdrop = corners.filter { $0.close(to: backdrop) }.count >= 3
        var background = [Bool](repeating: false, count: w*h)
        var frontier = [Int]()
        func consider(_ i: Int) {
            if background[i] { return }
            let off = i*4
            guard raw[off+3] < 32 || (hasBackdrop && RGB(raw, offset: off).close(to: backdrop)) else { return }
            background[i] = true
            frontier.append(i)
        }
        for x in 0..<w { consider(x); consider((h-1)*w+x) }
        for y in 0..<h { consider(y*w); consider(y*w+w-1) }
        var position = 0
        while position < frontier.count {
            let i = frontier[position]
            position += 1
            if i % w > 0 { consider(i-1) }
            if i % w < w-1 { consider(i+1) }
            if i >= w { consider(i-w) }
            if i < w*(h-1) { consider(i+w) }
        }
        var left = w, top = h, right = -1, bottom = -1
        var valid = 0
        var rgbSum: Double = 0, rgbSquareSum: Double = 0
        for i in 0..<(w*h) {
            let offset = i*4
            if background[i] || raw[offset+3] < 32 {
                for c in 0..<3 { raw[offset+c] = neutral }
            } else {
                let x = i % w, y = i / w
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
                valid += 1
                for c in 0..<3 {
                    // Composite premultiplied edges over the common neutral background.
                    raw[offset+c] = UInt8(min(255, Int(raw[offset+c]) + Int(neutral) * (255-Int(raw[offset+3])) / 255))
                    let v = Double(raw[offset+c])
                    rgbSum += v
                    rgbSquareSum += v*v
                }
            }
            raw[offset+3] = 255
        }
        guard valid > max(28, w*h/75), right-left >= 4, bottom-top >= 4 else { return nil }
        let n = Double(valid*3)
        guard rgbSquareSum / n - pow(rgbSum/n, 2) > 60 else { return nil }
        let box = CGRect(x: left, y: top, width: right-left+1, height: bottom-top+1)
        guard let raster = buffer.makeImage()?.cropping(to: box),
              let canvas = CGContext(data: nil, width: Self.side, height: Self.side, bitsPerComponent: 8,
                                     bytesPerRow: Self.side*4, space: scanColorSpace, bitmapInfo: scanBitmapFlags),
              let out = canvas.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        canvas.setFillColor(gray: CGFloat(neutral)/255, alpha: 1)
        canvas.fill(CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
        let scale = CGFloat(Self.side - 12) / max(box.width, box.height)
        let extent = CGSize(width: box.width*scale, height: box.height*scale)
        canvas.interpolationQuality = .medium
        canvas.draw(raster, in: CGRect(x: (CGFloat(Self.side)-extent.width)/2,
                                       y: (CGFloat(Self.side)-extent.height)/2,
                                       width: extent.width, height: extent.height))
        guard let image = canvas.makeImage() else { return nil }
        self.image = image
        self.pixels = Array(UnsafeBufferPointer(start: out, count: Self.side*Self.side*4))
    }
}

private struct RGB {
    let red: Int, green: Int, blue: Int, alpha: Int
    init(_ raw: UnsafeMutablePointer<UInt8>, offset: Int) {
        red = Int(raw[offset]); green = Int(raw[offset+1]); blue = Int(raw[offset+2]); alpha = Int(raw[offset+3])
    }
    func close(to other: RGB) -> Bool {
        if alpha < 32 || other.alpha < 32 { return alpha < 32 && other.alpha < 32 }
        return max(abs(red-other.red), abs(green-other.green), abs(blue-other.blue)) < 34
    }
}

fileprivate struct ScanDescriptor {
    let feature: VNFeaturePrintObservation?
    let tiles: [Float]
    let histogram: [Float]
    let patchPixels: [Float]
    let subjectIndices: [Int]

    init(_ subject: NormalizedSubject) {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: subject.image)
        try? handler.perform([request])
        feature = request.results?.first
        let side = NormalizedSubject.side
        var tiles = [Float](repeating: 0, count: 8*8*3)
        // A coarse RGB histogram retains colour information that Vision embeddings may ignore.
        var histogram = [Float](repeating: 0, count: 4*4*4)
        var count: Float = 0
        for y in 0..<side {
            for x in 0..<side {
                let off = 4 * (y*side+x)
                let r = Int(subject.pixels[off]), g = Int(subject.pixels[off+1]), b = Int(subject.pixels[off+2])
                let tile = ((y*8/side)*8+x*8/side)*3
                for k in 0..<3 { tiles[tile+k] += Float(subject.pixels[off+k]) / Float(255*(side/8)*(side/8)) }
                if max(abs(r-Int(neutral)), abs(g-Int(neutral)), abs(b-Int(neutral))) > 14 {
                    histogram[(r/64)*16+(g/64)*4+b/64] += 1
                    count += 1
                }
            }
        }
        // Low-resolution templates compare only pixels inside the reference silhouette.
        // This keeps the scenery between the limbs from dominating a matching capture.
        let patchSide = 24
        var patchPixels = [Float](repeating: 0, count: patchSide*patchSide*3)
        var subjectIndices: [Int] = []
        for y in 0..<patchSide {
            for x in 0..<patchSide {
                let base = (y*patchSide+x)*3
                let sx = (2*x+1)*side/(2*patchSide), sy = (2*y+1)*side/(2*patchSide)
                var foreground = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let i = ((sy+dy)*side+sx+dx)*4
                        if (0..<3).contains(where: { abs(Int(subject.pixels[i+$0])-Int(neutral)) > 22 }) {
                            foreground += 1
                        }
                        for c in 0..<3 { patchPixels[base+c] += Float(subject.pixels[i+c])/(9*255) }
                    }
                }
                if foreground >= 8 { subjectIndices.append(y*patchSide+x) }
            }
        }
        self.patchPixels = patchPixels
        self.subjectIndices = subjectIndices
        self.tiles = tiles
        self.histogram = histogram.map { $0/max(count,1) }
    }

    func distance(to other: Self) -> Double {
        let grid = zip(tiles, other.tiles).reduce(Float.zero) { $0 + abs($1.0 - $1.1) } / Float(tiles.count)
        let colour = max(0, 1 - zip(histogram, other.histogram).reduce(Float.zero) { $0 + sqrt($1.0 * $1.1) })
        var semantic: Float = .infinity
        if let feature, let ref = other.feature { try? feature.computeDistance(&semantic, to: ref) }
        if semantic.isFinite {
            let global = 0.67 * semantic + 0.20 * colour + 0.13 * min(1, grid*3)
            // Close colour/structure agreement can corroborate Vision under clutter.
            // The semantic threshold keeps accidental small colour patches from winning.
            if global < 0.72 {
                let template = maskedTemplateDistance(to: other)
                if template < 0.15 {
                    return Double(min(global, global * 0.52 + template * 0.95))
                }
            }
            return Double(global)
        }
        // Without a Vision observation, only near-identical visual templates get low distances.
        return Double(2.65 * (min(1, grid*3.5) * 0.68 + colour * 0.32))
    }

    private func maskedTemplateDistance(to reference: Self) -> Float {
        guard reference.subjectIndices.count >= 35 else { return 1 }
        let side = 24, center: Float = 11.5
        var best: Float = 1
        for scale: Float in [0.65, 0.80, 0.95, 1.1] {
            for dy in -1...1 {
                for dx in -1...1 {
                    var total: Float = 0
                    var count = 0
                    for index in reference.subjectIndices {
                        let x = Int(((Float(index % side)-center)*scale+center).rounded())+dx
                        let y = Int(((Float(index / side)-center)*scale+center).rounded())+dy
                        guard x >= 0, x < side, y >= 0, y < side else { continue }
                        let a = (y*side+x)*3, b = index*3
                        for c in 0..<3 { total += abs(patchPixels[a+c]-reference.patchPixels[b+c]) }
                        count += 1
                    }
                    if count*10 >= reference.subjectIndices.count*9 {
                        best = min(best, total / Float(count*3))
                    }
                }
            }
        }
        return best
    }

}
