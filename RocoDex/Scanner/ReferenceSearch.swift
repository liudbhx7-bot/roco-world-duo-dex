import Foundation
import CoreGraphics
import ImageIO
import CryptoKit

struct ScanAsset: Codable, Hashable {
    let id: Int
    let path: String
}

struct ScanLibrary {
    let directory: URL
    let assets: [ScanAsset]
}

/// Local search uses a coarse colour grid for centered art and indexed keypoint votes
/// for subjects surrounded by a busy background. Vision and geometry rerank the union.
struct ScanIndexRecord: Codable {
    let asset: ScanAsset
    let color: Data
    let corners: Data
    let digest: String
    let fileSize: Int

    static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    init?(asset: ScanAsset, directory: URL) {
        let url = directory.appendingPathComponent(asset.path)
        guard let image = Self.loadImage(at: url) else { return nil }
        self.asset = asset
        fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        color = NormalizedSubject(image).map(Self.grid) ?? Data()
        guard let bytes = try? Data(contentsOf: url) else { return nil }
        digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        var packed = Data()
        for token in LocalArtLocator.referenceTokens(image) { token.encode(into: &packed) }
        corners = packed
    }

    static func grid(_ subject: NormalizedSubject) -> Data {
        let tiles = 8, side = NormalizedSubject.side, tile = side / tiles
        var sums = [Int](repeating: 0, count: tiles * tiles * 3)
        for y in stride(from: 0, to: side, by: 2) {
            for x in stride(from: 0, to: side, by: 2) {
                let source = (y * side + x) * 4
                let dest = (y / tile * tiles + x / tile) * 3
                for channel in 0..<3 { sums[dest + channel] += Int(subject.pixels[source + channel]) }
            }
        }
        return Data(sums.map { UInt8($0 / (tile * tile / 4)) })
    }
}

struct ScanIndexFile: Codable {
    static let currentVersion = 2
    let version: Int
    let records: [ScanIndexRecord]
}

final class LibraryMatcher {
    private let directory: URL
    private let records: [ScanIndexRecord]
    private let postings: [[Int32]]
    private let tokens: [(record: Int, point: ScanToken)]
    private let labels: [[Int]]
    private let cache = NSCache<NSNumber, PreparedBox>()

    private final class PreparedBox: NSObject {
        let value: ReferenceMatcher.Prepared
        init(_ value: ReferenceMatcher.Prepared) { self.value = value }
    }

    init(library: ScanLibrary) throws {
        directory = library.directory
        let url = directory.appendingPathComponent("ScanIndex.json")
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(ScanIndexFile.self, from: $0) }
        var indexed: [ScanAsset: ScanIndexRecord] = [:]
        if let stored, stored.version == ScanIndexFile.currentVersion {
            for record in stored.records { indexed[record.asset] = record }
        }
        let base = library.directory
        let loaded: [ScanIndexRecord] = library.assets.compactMap { asset in
            if let record = indexed[asset], record.corners.count.isMultiple(of: ScanToken.stride),
               record.color.count == 192 || record.color.isEmpty,
               let size = try? base.appendingPathComponent(asset.path).resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size == record.fileSize { return record }
            // Allow the art in a development build to be replaced independently of the index.
            return autoreleasepool { ScanIndexRecord(asset: asset, directory: base) }
        }
        guard !loaded.isEmpty else { throw ScanIssue.database }
        var unique: [ScanIndexRecord] = [], indexByDigest: [String: Int] = [:], owners: [[Int]] = []
        for record in loaded {
            if let i = indexByDigest[record.digest] {
                if !owners[i].contains(record.asset.id) { owners[i].append(record.asset.id) }
            } else {
                indexByDigest[record.digest] = unique.count
                unique.append(record)
                owners.append([record.asset.id])
            }
        }
        records = unique
        labels = owners
        var table = [[Int32]](repeating: [], count: 8 * 4096)
        var all: [(record: Int, point: ScanToken)] = []
        for (index, record) in records.enumerated() {
            record.corners.withUnsafeBytes { raw in
                for offset in stride(from: 0, to: raw.count, by: ScanToken.stride) {
                    let point = ScanToken.decode(raw, at: offset)
                    let ref = Int32(all.count)
                    for band in 0..<8 {
                        if let key = point.key(band) { table[key].append(ref) }
                    }
                    all.append((index, point))
                }
            }
        }
        tokens = all
        postings = table
        cache.countLimit = 48
    }

    func identify(_ image: CGImage) throws -> ScanResult {
        let subjects = ReferenceMatcher.subjects(in: image)
        let probe = LocalArtLocator.Probe(image)
        let shortlist = candidates(for: subjects, probe: probe)
        let prepared: [(Int, ReferenceMatcher.Prepared)] = shortlist.compactMap { index in
            let record = records[index]
            let key = NSNumber(value: index)
            if let box = cache.object(forKey: key) { return (index, box.value) }
            return autoreleasepool {
                let url = directory.appendingPathComponent(record.asset.path)
                guard let image = ScanIndexRecord.loadImage(at: url),
                      let reference = ReferenceMatcher.Prepared(image) else { return nil }
                cache.setObject(PreparedBox(reference), forKey: key)
                return (index, reference)
            }
        }
        return try classify(prepared, subjects, probe)
    }

    private func classify(_ prepared: [(Int, ReferenceMatcher.Prepared)], _ subjects: [NormalizedSubject],
                          _ probe: LocalArtLocator.Probe) throws -> ScanResult {
        if prepared.isEmpty { return .unknown }
        let verified = try ReferenceMatcher(prepared: prepared)
        let ranked = verified.ranked(subjects: subjects, probe: probe)
        var scores: [Int: Double] = [:]
        for (index, score) in ranked {
            for id in labels[index] { scores[id] = min(scores[id] ?? 1, score) }
        }
        let sorted = scores.sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value < rhs.value
        }.map { ($0.key, $0.value) }
        // With hundreds of possible matches, weak five-corner agreements are common.
        // Keep suggestions for well-supported matches and for genuinely similar forms.
        if records.count > 200, let best = sorted.first, best.1 > 0.365 { return .unknown }
        let result = ReferenceMatcher.classify(sorted)
        guard case .candidates(let ids) = result, let best = ranked.first,
              !Set(labels[best.0]).isDisjoint(with: ids) else { return result }
        return .candidates(ids + labels[best.0].filter { !ids.contains($0) }.sorted())
    }

    private func candidates(for subjects: [NormalizedSubject], probe: LocalArtLocator.Probe) -> [Int] {
        if records.count <= 24 { return Array(records.indices) }
        var selected = Set<Int>()
        for query in subjects.map(ScanIndexRecord.grid) {
            var ranked: [(index: Int, distance: Int)] = []
            for i in records.indices {
                ranked.append((i, Self.gridDistance(query, records[i].color)))
            }
            ranked.sort { lhs, rhs in
                if lhs.distance == rhs.distance { return lhs.index < rhs.index }
                return lhs.distance < rhs.distance
            }
            selected.formUnion(ranked.prefix(5).map { $0.index })
        }
        selected.formUnion(localCandidates(probe.tokens))
        return selected.sorted()
    }
    /// Rerank only illustrations that receive consistent local correspondences.
    /// Each query corner can vote once per reference; a coarse Hough cell accumulates
    /// translations and relative scales before the precise geometric verification.
    private func localCandidates(_ query: [ScanToken]) -> [Int] {
        var votes = [Float](repeating: 0, count: records.count)
        var peaks = votes, cells: [Int: Float] = [:]
        var closest = [Float](repeating: 0.255, count: tokens.count)
        var partner = [Int32](repeating: -1, count: tokens.count)
        for (qi, point) in query.enumerated() {
            var best: [Int: (Float, ScanToken)] = [:]
            for band in 0..<8 {
                guard let key = point.key(band) else { continue }
                let hits = postings[key]
                if hits.count > 350 { continue }
                for slot in hits {
                    let (record, ref) = tokens[Int(slot)]
                    let scale = point.scale / ref.scale
                    if scale < 0.10 || scale > 1.9 || abs(ref.rg - point.rg) + abs(ref.bg - point.bg) > 0.6 { continue }
                    let d = ref.bits.distance(to: point.bits)
                    if d < closest[Int(slot)] {
                        closest[Int(slot)] = d
                        partner[Int(slot)] = Int32(qi)
                    }
                    if d >= 0.23 { continue }
                    if d < (best[record]?.0 ?? 1) { best[record] = (d, ref) }
                }
            }
            for (id, pair) in best {
                let (d, ref) = pair, scale = point.scale / ref.scale
                let weight = powf(1 - d / 0.25, 2)
                votes[id] += weight
                let x = min(31, max(0, Int((point.x - ref.x * scale + 2) * 8)))
                let y = min(31, max(0, Int((point.y - ref.y * scale + 2) * 8)))
                let level = min(15, max(0, Int((log2f(scale) + 4) * 2)))
                let cell = ((id * 16 + level) * 32 + y) * 32 + x
                cells[cell, default: 0] += weight
                peaks[id] = max(peaks[id], cells[cell] ?? 0)
            }
        }
        for i in votes.indices { votes[i] = peaks[i] + votes[i] * 0.1 }
        let hough = votes.indices.filter { votes[$0] > 0 }.sorted {
            votes[$0] == votes[$1] ? $0 < $1 : votes[$0] > votes[$1]
        }
        var pairs = [[ArtMatch]](repeating: [], count: records.count)
        for i in partner.indices where partner[i] >= 0 {
            let (id, ref) = tokens[i], q = query[Int(partner[i])]
            pairs[id].append(ArtMatch(ax: ref.x, ay: ref.y, bx: q.x, by: q.y,
                                      scale: q.scale / ref.scale, distance: closest[i]))
        }
        var geo: [(id: Int, score: Double)] = []
        for i in pairs.indices where pairs[i].count >= 5 {
            if let score = LocalArtLocator.coarseGeometry(pairs[i]) { geo.append((i, score)) }
        }
        geo.sort { $0.score < $1.score }
        return Array(Set(hough.prefix(12)).union(geo.prefix(8).map { $0.id }))
    }

    private static func gridDistance(_ query: Data, _ reference: Data) -> Int {
        guard reference.count == query.count else { return Int.max }
        return query.withUnsafeBytes { (lhs: UnsafeRawBufferPointer) -> Int in
            reference.withUnsafeBytes { (rhs: UnsafeRawBufferPointer) -> Int in
                var sum = 0
                for c in 0..<lhs.count { sum += abs(Int(lhs[c]) - Int(rhs[c])) }
                return sum
            }
        }
    }
}
