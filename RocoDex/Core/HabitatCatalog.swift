import UIKit

struct HabitatSource: Decodable {
    let kind: String
    let name: String
    let detail: String
}

struct HabitatEntry: Decodable {
    let habitat: String
    let areas: [String]
    let sources: [HabitatSource]
    let points: [String]
    let regions: [String]
}

struct HabitatPoint: Decodable {
    let map, kind, name, region, province, level: String
    let x, y: CGFloat

    var isHabitat: Bool { kind == "精灵栖息地" }
    var label: String { isHabitat ? region : name }
}

struct HabitatRegion: Decodable {
    let map, name: String
    let polygon: [[CGFloat]]
}

struct HabitatMap: Decodable {
    let name, season: String
}

final class HabitatCatalog {
    private struct FileContents: Decodable {
        let maps: [String: HabitatMap]
        let entries: [String: HabitatEntry]
        let points: [String: HabitatPoint]
        let regions: [String: HabitatRegion]
    }

    static let shared = HabitatCatalog()
    private let records: FileContents?
    private let folder: URL?
    private let images = NSCache<NSString, UIImage>()

    init(bundle: Bundle = .main) {
        folder = bundle.resourceURL?.appendingPathComponent("FieldMaps", isDirectory: true)
        if let file = folder?.appendingPathComponent("Habitats.json"),
           let data = try? Data(contentsOf: file) {
            records = try? JSONDecoder().decode(FileContents.self, from: data)
        } else {
            records = nil
        }
        images.countLimit = 2
    }

    func entry(for spirit: Spirit) -> HabitatEntry? { records?.entries[String(spirit.id)] }
    func map(_ id: String) -> HabitatMap? { records?.maps[id] }
    func point(_ id: String) -> HabitatPoint? { records?.points[id] }
    func region(_ id: String) -> HabitatRegion? { records?.regions[id] }

    func image(for id: String) -> UIImage? {
        if let cached = images.object(forKey: id as NSString) { return cached }
        guard map(id) != nil, let url = folder?.appendingPathComponent(id + ".jpg"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        images.setObject(image, forKey: id as NSString)
        return image
    }
}
