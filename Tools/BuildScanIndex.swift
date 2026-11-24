import Foundation

@main
enum BuildScanIndex {
    private struct Entry: Decodable { let id: Int; let image: String }
    static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: base.appendingPathComponent("Spirits.json")))
        var records: [ScanIndexRecord] = []
        for entry in entries {
            let head = String(format: "HeadArt/head-%03d.png", entry.id)
            let paths = [entry.image.isEmpty ? nil : "Art/" + entry.image, head].compactMap { $0 }
            for path in paths where FileManager.default.fileExists(atPath: base.appendingPathComponent(path).path) {
                let asset = ScanAsset(id: entry.id, path: path)
                guard let record = autoreleasepool(invoking: { ScanIndexRecord(asset: asset, directory: base) }) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                records.append(record)
            }
        }
        let file = ScanIndexFile(version: ScanIndexFile.currentVersion, records: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(file).write(to: base.appendingPathComponent("ScanIndex.json"), options: .atomic)
        print("Indexed \(records.count) references for \(Set(records.map { $0.asset.id }).count) entries.")
    }
}
