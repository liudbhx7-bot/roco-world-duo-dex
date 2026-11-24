import UIKit
import ImageIO

struct Spirit: Codable, Identifiable {
    let id: Int
    let name, type, trait, traitDetail, summary, image: String
    let stats: [Int]
    let skills: [String]
    let evolution: [Int]
    let evolutionPaths: [[Int]]?

    let dexNumber: Int?
    let sourceURL: String?
    let form: String?

    var number: String { String(format: "%03d", dexNumber ?? id) }
    var distinctForm: String? {
        guard let form, !form.isEmpty, !name.contains(form) else { return nil }
        return form
    }
    var formattedName: String { distinctForm.map { name + "（" + $0 + "）" } ?? name }
    static let statNames = ["生命", "物攻", "物防", "魔攻", "魔防", "速度"]
}

/// ImageIO scales collection thumbnails without inflating a collection of full-size illustrations.
final class CatalogPictures {
    let urls: [Int: URL]
    private let full = NSCache<NSNumber, UIImage>()
    private let small = NSCache<NSNumber, UIImage>()

    init(urls: [Int: URL]) {
        self.urls = urls
        full.totalCostLimit = 16 * 1024 * 1024
        small.totalCostLimit = 5 * 1024 * 1024
    }

    subscript(_ id: Int) -> UIImage? { load(id, limit: 896, cache: full) }
    func thumbnail(_ id: Int) -> UIImage? { load(id, limit: 96, cache: small) }

    private func load(_ id: Int, limit: Int, cache: NSCache<NSNumber, UIImage>) -> UIImage? {
        let key = NSNumber(value: id)
        if let image = cache.object(forKey: key) { return image }
        guard let url = urls[id], let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceThumbnailMaxPixelSize: limit,
                                         kCGImageSourceCreateThumbnailWithTransform: true,
                                         kCGImageSourceShouldCacheImmediately: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
        return image
    }
}

struct Catalog {
    let entries: [Spirit]
    let pictures: CatalogPictures
    private let formsByNumber: [Int: [Spirit]]

    func forms(number: Int) -> [Spirit] { formsByNumber[number] ?? [] }
    func forms(for spirit: Spirit) -> [Spirit] { forms(number: spirit.dexNumber ?? spirit.id) }

    let references: ScanLibrary
    let animationURLs: [Int: URL]

    init(bundle: Bundle = .main) throws {
        guard let directory = bundle.resourceURL else { throw CocoaError(.fileNoSuchFile) }
        let data = try Data(contentsOf: directory.appendingPathComponent("Spirits.json"))
        let entries = try JSONDecoder().decode([Spirit].self, from: data).sorted {
            ($0.dexNumber ?? $0.id, $0.id) < ($1.dexNumber ?? $1.id, $1.id)
        }
        let ids = Set(entries.map(\.id))
        guard !entries.isEmpty, ids.count == entries.count,
              entries.allSatisfy({ $0.stats.count == 6 && $0.evolution.allSatisfy(ids.contains) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        func files(_ folder: String) -> Set<String> {
            Set((try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent(folder).path)) ?? [])
        }
        let artworks = files("Art"), heads = files("HeadArt"), animations = files("Animations")
        var urls: [Int: URL] = [:], motion: [Int: URL] = [:], samples: [ScanAsset] = []
        for spirit in entries {
            if !spirit.image.isEmpty {
                guard artworks.contains(spirit.image) else { throw CocoaError(.fileNoSuchFile) }
                let path = "Art/" + spirit.image
                urls[spirit.id] = directory.appendingPathComponent(path)
                samples.append(ScanAsset(id: spirit.id, path: path))
            }
            let key = String(format: "%03d", spirit.id)
            let head = "head-" + key + ".png"
            if heads.contains(head) { samples.append(ScanAsset(id: spirit.id, path: "HeadArt/" + head)) }
            if animations.contains(key + ".apng") {
                motion[spirit.id] = directory.appendingPathComponent("Animations/" + key + ".apng")
            }
        }
        self.entries = entries
        formsByNumber = Dictionary(grouping: entries) { $0.dexNumber ?? $0.id }
        pictures = CatalogPictures(urls: urls)
        references = ScanLibrary(directory: directory, assets: samples)
        animationURLs = motion
    }
}

enum ArchivePage: Int, CaseIterable {
    case profile, skills, family
    var title: String { ["档案", "技能", "进化"][rawValue] }
    func shifted(_ delta: Int) -> Self {
        let views = Self.allCases
        return views[(rawValue + delta + views.count) % views.count]
    }
}
