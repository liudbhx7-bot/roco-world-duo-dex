import CoreGraphics
import Foundation

/// Finds repeatable details of a reference illustration in a full photograph.
/// All locations use longest-side-normalized image coordinates. No centered crop is assumed.
struct LocalArtLocator {
    struct Prepared {
        fileprivate let points: [ArtPoint]
        fileprivate let samples: [ArtSample]
        init(_ image: CGImage) {
            points = LocalArtLocator.points(in: image, reference: true)
            samples = ArtRaster(image, side: 96)?.samples() ?? []
        }
    }

    struct Probe {
        fileprivate let points: [ArtPoint]
        fileprivate let raster: ArtRaster?
        init(_ image: CGImage) {
            points = LocalArtLocator.points(in: image, reference: false)
            raster = ArtRaster(image, side: 640)
        }

        var tokens: [ScanToken] { LocalArtLocator.tokens(points, reference: false) }
    }

    private static func tokens(_ points: [ArtPoint], reference: Bool) -> [ScanToken] {
        points.map { point in
            let bits = point.bits[reference ? 1 : 0]
            return ScanToken(bits: bits, x: point.x, y: point.y, scale: point.scale,
                             rg: point.rg, bg: point.bg)
        }
    }

    static func referenceTokens(_ image: CGImage) -> [ScanToken] {
        tokens(points(in: image, reference: true), reference: true)
    }

    func evidence(for probe: Probe) -> [Int: Double] {
        guard probe.points.count >= 7, let raster = probe.raster else { return [:] }
        var result: [Int: Double] = [:]
        for (id, reference) in referenceSets {
            let matches = Self.correspondences(from: reference.points, to: probe.points)
            if let score = Self.geometricDistance(matches, samples: reference.samples, raster: raster) {
                result[id] = min(result[id] ?? 1, score)
            }
        }
        return result
    }

    private let referenceSets: [(id: Int, reference: Prepared)]
    init(prepared: [(Int, Prepared)]) { referenceSets = prepared }


    init(_ references: [(Int, CGImage)]) {
        referenceSets = references.map { ($0.0, Prepared($0.1)) }
    }

    func evidence(in image: CGImage) -> [Int: Double] { evidence(for: Probe(image)) }

    private static let neutral = 146
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let flags = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

    private static func points(in image: CGImage, reference: Bool) -> [ArtPoint] {
        let originalSide = max(image.width, image.height)
        let base = min(originalSide, reference ? 320 : 820)
        var all: [ArtPoint] = []
        for factor in [1.0, 0.69, 0.47, 0.325, 0.224] {
            let side = Int(Double(base)*factor)
            if side < 64 { break }
            let ratio = Double(side) / Double(originalSide)
            let width = max(1, Int(Double(image.width) * ratio))
            let height = max(1, Int(Double(image.height) * ratio))
            guard min(width, height) > 30,
                  let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width*4, space: srgb, bitmapInfo: flags),
                  let raw = ctx.data?.assumingMemoryBound(to: UInt8.self) else { continue }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var gray = [Int](repeating: 0, count: width*height)
            for i in gray.indices {
                let j = i*4
                gray[i] = (Int(raw[j])*77 + Int(raw[j+1])*150 + Int(raw[j+2])*29)/256
                    + neutral*(255-Int(raw[j+3]))/255
            }
            // An integral image averages each small sampling patch in constant time.
            let stride = width+1
            var integral = [Int](repeating: 0, count: stride*(height+1))
            for y in 0..<height {
                var row = 0
                for x in 0..<width {
                    row += gray[y*width+x]
                    integral[(y+1)*stride+x+1] = integral[y*stride+x+1]+row
                }
            }
            let corners = Self.corners(gray, width: width, height: height, alpha: raw,
                                       limit: reference ? 70 : 260)
            for corner in corners {
                let x = corner.x, y = corner.y
                let index = (y*width+x)*4
                var descriptors: [ArtBits] = []
                for pattern in (reference ? descriptorsByAngle : [descriptorsByAngle[1]]) {
                    var bits = ArtBits()
                    for (j, pair) in pattern.enumerated() {
                        let p = (y+pair.ay)*stride+x+pair.ax
                        let q = (y+pair.by)*stride+x+pair.bx
                        let ia = p+stride*3+3, ib = q+stride*3+3
                        let a = integral[ia]-integral[ia-3]-integral[p+3]+integral[p]
                        let b = integral[ib]-integral[ib-3]-integral[q+3]+integral[q]
                        let valid = !reference ||
                            (raw[((y+pair.ay+1)*width+x+pair.ax+1)*4+3] > 140 &&
                             raw[((y+pair.by+1)*width+x+pair.bx+1)*4+3] > 140)
                        if valid && abs(a-b) > 30 {
                            bits.set(j, positive: a>b)
                        }
                    }
                    descriptors.append(bits)
                }
                // Reject textureless and fully transparent border patches.
                if descriptors[reference ? 1 : 0].validCount < (reference ? 45 : 35) { continue }
                let r = Float(raw[index]), g = Float(raw[index+1]), b = Float(raw[index+2])
                all.append(ArtPoint(x: Float(x)/Float(side), y: Float(y)/Float(side),
                                    scale: 1/Float(side), rg: (r-g)/255, bg: (b-g)/255, bits: descriptors))
            }
        }
        return all
    }

    /// Local structure tensor response followed by spatially balanced nonmaximum suppression.
    private static func corners(_ gray: [Int], width: Int, height: Int,
                                alpha: UnsafeMutablePointer<UInt8>, limit: Int) -> [ArtCorner] {
        var candidates: [ArtCorner] = []
        let border = 14, step = width > 420 ? 2 : 1
        var scores = [Float](repeating: 0, count: width*height)
        for y in Swift.stride(from: border, to: height-border, by: step) {
            for x in Swift.stride(from: border, to: width-border, by: step) {
                let index = y*width+x
                if alpha[index*4+3] < 150 { continue }
                var xx = 0, yy = 0, xy = 0
                for dy in [-2,0,2] {
                    for dx in [-2,0,2] {
                        let i = index+dy*width+dx
                        let gx = gray[i+1]-gray[i-1], gy = gray[i+width]-gray[i-width]
                        xx += gx*gx; yy += gy*gy; xy += gx*gy
                    }
                }
                let trace = Float(xx+yy)
                if trace < 1200 { continue }
                let score = (Float(xx)*Float(yy)-Float(xy)*Float(xy))/trace
                if score > 170 { scores[index] = score }
            }
        }
        for y in Swift.stride(from: border, to: height-border, by: step) {
            for x in Swift.stride(from: border, to: width-border, by: step) {
                let index = y*width+x, score = scores[index]
                guard score > 0,
                      score >= scores[index-step], score > scores[index+step],
                      score >= scores[index-width*step], score > scores[index+width*step] else { continue }
                candidates.append(ArtCorner(x: x, y: y, score: score))
            }
        }
        candidates.sort { $0.score > $1.score }
        var points: [ArtCorner] = []
        let spacing = 5
        let columns = (width+spacing-1)/spacing
        var occupied = [Bool](repeating: false, count: columns*((height+spacing-1)/spacing))
        let cellSize = 36, gridWidth = (width+cellSize-1)/cellSize
        var cells = [Int](repeating: 0, count: gridWidth*((height+cellSize-1)/cellSize))
        for p in candidates {
            let cell = (p.y/cellSize)*gridWidth+p.x/cellSize
            let bucket = (p.y/spacing)*columns+p.x/spacing
            if occupied[bucket] || cells[cell] >= 8 { continue }
            occupied[bucket] = true; cells[cell] += 1
            points.append(p)
            if points.count == limit { break }
        }
        return points
    }

    private static let descriptorsByAngle: [[ArtPair]] = {
        var seed: UInt64 = 0x92a8f184d2
        func sample() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 32)/Double(UInt32.max)
        }
        func point() -> (Double,Double) {
            let angle = sample()*2*Double.pi
            let radius = sqrt(sample())*10
            return (cos(angle)*radius, sin(angle)*radius)
        }
        let pairs = (0..<128).map { _ -> ((Double,Double),(Double,Double)) in
            let a = point()
            var b = point()
            while hypot(a.0-b.0, a.1-b.1) < 3 { b=point() }
            return (a,b)
        }
        return [-18.0, 0.0, 18.0].map { degrees in
            let a = degrees*Double.pi/180
            func rotate(_ p: (Double,Double)) -> (Int,Int) {
                (Int((p.0*cos(a)-p.1*sin(a)).rounded())-1,
                 Int((p.0*sin(a)+p.1*cos(a)).rounded())-1)
            }
            return pairs.map { pair in
                let p = rotate(pair.0), q = rotate(pair.1)
                return ArtPair(ax:p.0, ay:p.1, bx:q.0, by:q.1)
            }
        }
    }()

    private static func correspondences(from reference: [ArtPoint], to query: [ArtPoint]) -> [ArtMatch] {
        var matches: [ArtMatch] = []
        for a in reference {
            // Find the best local binary descriptor. Similar edge corners are later
            // disambiguated by their geometry across the image.
            var best: Float = 0.255, next: Float = 1
            var chosen: ArtPoint?
            for b in query {
                let localScale = b.scale/a.scale
                if localScale < 0.10 || localScale > 1.9 || abs(a.rg-b.rg)+abs(a.bg-b.bg) > 0.67 { continue }
                let target = b.bits[0]
                var distance: Float = 1
                for bits in a.bits { distance = min(distance, bits.distance(to: target)) }
                if distance < best {
                    if let old = chosen, hypotf(old.x-b.x, old.y-b.y) > b.scale*5 { next = best }
                    best = distance; chosen = b
                } else if let old = chosen, distance < next, hypotf(old.x-b.x, old.y-b.y) > b.scale*5 {
                    next = distance
                }
            }
            if let b = chosen, best < 0.17 || best+0.033 < next {
                matches.append(ArtMatch(ax: a.x, ay: a.y, bx: b.x, by: b.y,
                                        scale: b.scale/a.scale, distance: best))
            }
        }
        return Array(matches.sorted { $0.distance < $1.distance }.prefix(70))
    }

    static func coarseGeometry(_ pairs: [ArtMatch]) -> Double? {
        geometricDistance(Array(pairs.sorted { $0.distance < $1.distance }.prefix(75)),
                          samples: [], raster: nil)
    }

    private static func geometricDistance(_ matches: [ArtMatch], samples: [ArtSample], raster: ArtRaster?) -> Double? {
        guard matches.count >= (raster == nil ? 4 : 5) else { return nil }
        var best = 1.0
        let count = min(raster == nil ? 42 : 34, matches.count)
        for i in 0..<(count-1) {
            let a = matches[i]
            for j in (i+1)..<count {
                let b = matches[j], dx = b.ax-a.ax, dy = b.ay-a.ay
                let span = dx*dx+dy*dy
                if span < 0.005 { continue }
                let x = b.bx-a.bx, y = b.by-a.by
                let u = (x*dx+y*dy)/span, v = (y*dx-x*dy)/span
                let scale = hypotf(u,v)
                // Reference art is upright; allow perspective and practical handheld rotation.
                if scale < 0.08 || scale > 2.2 || u < 0.66*scale { continue }
                let tx = a.bx-u*a.ax+v*a.ay, ty = a.by-v*a.ax-u*a.ay
                let tolerance = max(0.006,min(0.032, scale*0.055))
                var accepted: [ArtMatch] = []
                var minX: Float = 2, maxX: Float = -2, minY: Float = 2, maxY: Float = -2
                var total: Float = 0
                for p in matches {
                    let px = u*p.ax-v*p.ay+tx, py = v*p.ax+u*p.ay+ty
                    let rx = px-p.bx, ry = py-p.by
                    if rx*rx+ry*ry > tolerance*tolerance || p.scale < scale*0.45 || p.scale > scale*2.4 { continue }
                    if accepted.contains(where: { q in
                        hypotf(p.ax-q.ax,p.ay-q.ay) < 0.048 || hypotf(p.bx-q.bx,p.by-q.by) < scale*0.036
                    }) { continue }
                    accepted.append(p); total += p.distance
                    minX = min(minX,p.ax); maxX = max(maxX,p.ax); minY = min(minY,p.ay); maxY = max(maxY,p.ay)
                }
                let k = accepted.count
                guard k >= (raster == nil ? 4 : 5), (maxX-minX)*(maxY-minY) > 0.032,
                      min(maxX-minX,maxY-minY) > 0.115 else { continue }
                let mean = total/Float(k)
                guard mean < 0.195,
                      raster?.agrees(with: samples, u: u, v: v, tx: tx, ty: ty, scale: scale) != false else { continue }
                if raster == nil {
                    best = min(best, 1.0/Double(k) + Double(mean)*0.22)
                    continue
                }
                let score = (k >= 9 ? 0.095 : k >= 7 ? 0.16 : k == 6 ? 0.25 : 0.36) + Double(mean)*0.35
                best = min(best,score)
                if k >= 13 && mean < 0.14 { return best }
            }
        }
        return best < 1 ? best : nil
    }
}

private struct ArtPair { let ax, ay, bx, by: Int }
private struct ArtCorner { let x, y: Int; let score: Float }
fileprivate struct ArtPoint { let x, y, scale, rg, bg: Float; let bits: [ArtBits] }
struct ArtMatch { let ax, ay, bx, by, scale, distance: Float }

struct ArtBits {
    var low: UInt64 = 0, high: UInt64 = 0, lowMask: UInt64 = 0, highMask: UInt64 = 0
    var validCount: Int { lowMask.nonzeroBitCount + highMask.nonzeroBitCount }
    mutating func set(_ index: Int, positive: Bool) {
        let bit = UInt64(1) << (index & 63)
        if index < 64 {
            lowMask |= bit; if positive { low |= bit }
        } else {
            highMask |= bit; if positive { high |= bit }
        }
    }
    func distance(to other: Self) -> Float {
        let mask1 = lowMask & other.lowMask, mask2 = highMask & other.highMask
        let valid = mask1.nonzeroBitCount + mask2.nonzeroBitCount
        if valid < 44 { return 1 }
        let errors = ((low ^ other.low) & mask1).nonzeroBitCount + ((high ^ other.high) & mask2).nonzeroBitCount
        return Float(errors)/Float(valid) + 0.0006*Float(128-valid)
    }
}

fileprivate struct ArtSample { let x, y: Float; let color: SIMD3<Float> }

fileprivate struct ArtRaster {
    let width, height: Int
    let bytes: [UInt8]
    var side: Int { max(width, height) }

    init?(_ image: CGImage, side limit: Int) {
        let scale = min(1, Double(limit)/Double(max(image.width,image.height)))
        width = max(1, Int(Double(image.width)*scale))
        height = max(1, Int(Double(image.height)*scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width*4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let ptr = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        bytes = Array(UnsafeBufferPointer(start:ptr,count:width*height*4))
    }

    private func color(_ index: Int) -> SIMD3<Float> {
        SIMD3(Float(bytes[index]), Float(bytes[index+1]), Float(bytes[index+2])) / 255
    }

    func samples() -> [ArtSample] {
        var points: [ArtSample] = []
        let step = max(2, side/13)
        for y in Swift.stride(from: step/2, to: height, by: step) {
            for x in Swift.stride(from: step/2, to: width, by: step) {
                let p = (y*width+x)*4
                if bytes[p+3] >= 235 {
                    points.append(ArtSample(x: Float(x)/Float(side), y: Float(y)/Float(side), color: color(p)))
                }
            }
        }
        return points
    }

    /// Reproject held-out interior pixels across the predicted object, independent of
    /// binary corner descriptors. This rejects chance alignments of shared eye outlines.
    func agrees(with samples: [ArtSample], u: Float, v: Float,
                tx: Float, ty: Float, scale: Float) -> Bool {
        let pixels = Float(side)
        let radius = max(1,min(8,Int(scale*pixels*0.012)))
        var evaluated = 0, supporting = 0
        var error: Float = 0
        for sample in samples {
            let x = Int(((u*sample.x-v*sample.y+tx)*pixels).rounded())
            let y = Int(((v*sample.x+u*sample.y+ty)*pixels).rounded())
            guard x >= radius, x+radius < width, y >= radius, y+radius < height else { continue }
            var closest: Float = 3
            for (dx,dy) in [(0,0),(-radius,0),(radius,0),(0,radius),(0,-radius)] {
                let candidate = color(((y+dy)*width+x+dx)*4)
                let delta = candidate-sample.color
                // Absorb a moderate neutral exposure shift, preserving chromatic differences.
                let bias = max(-0.12, min(0.12, (delta.x+delta.y+delta.z)/3))
                let distance = (abs(delta.x-bias)+abs(delta.y-bias)+abs(delta.z-bias))/3 + abs(bias)*0.30
                closest = min(closest,distance)
            }
            error += min(closest,0.35)
            if closest < 0.13 { supporting += 1 }
            evaluated += 1
        }
        return evaluated >= max(15, samples.count/2) &&
            Float(supporting)/Float(evaluated) >= 0.65 && error/Float(evaluated) < 0.12
    }
}

/// Stored little-endian in 42 bytes per corner. UInt16 and Int16 values keep the
/// file independent of Swift's struct layout and preserve normalized geometry.
struct ScanToken {
    let bits: ArtBits
    let x, y, scale, rg, bg: Float
    static let stride = 42

    func encode(into data: inout Data) {
        for word in [bits.low, bits.high, bits.lowMask, bits.highMask] {
            var little = word.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        for v in [x, y, scale, rg, bg] {
            var short = Float16(v).bitPattern.littleEndian
            withUnsafeBytes(of: &short) { data.append(contentsOf: $0) }
        }
    }

    static func decode(_ bytes: UnsafeRawBufferPointer, at p: Int) -> Self {
        func u64(_ d: Int) -> UInt64 { UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: p+d, as: UInt64.self)) }
        func f16(_ d: Int) -> Float {
            Float(Float16(bitPattern: UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: p+d, as: UInt16.self))))
        }
        return Self(bits: ArtBits(low: u64(0), high: u64(8), lowMask: u64(16), highMask: u64(24)),
                    x: f16(32), y: f16(34), scale: f16(36), rg: f16(38), bg: f16(40))
    }

    func key(_ band: Int) -> Int? {
        let shift = (band % 4) * 16
        let mask = ((band < 4 ? bits.lowMask : bits.highMask) >> shift) & 0xfff
        guard mask.nonzeroBitCount >= 8 else { return nil }
        let word = ((band < 4 ? bits.low : bits.high) >> shift) & 0xfff
        return band * 4096 + Int(word)
    }
}
