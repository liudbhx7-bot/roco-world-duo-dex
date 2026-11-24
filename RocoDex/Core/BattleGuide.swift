import UIKit

enum SkillSource: String, Codable, CaseIterable, Identifiable {
    case level, machine, blood, legendary

    var id: Self { self }

    var title: String {
        switch self {
        case .level: "自学"
        case .machine: "技能石"
        case .blood: "血脉"
        case .legendary: "传说"
        }
    }
}

struct BattleSkill: Decodable {
    let name, icon, element, category, effect: String
    let power: String?
    let energy: Int
}

struct LearnedSkill: Decodable, Identifiable {
    let skill: String
    let source: SkillSource
    let level: Int?
    let blood, requirement: String?

    var id: String {
        [source.rawValue, skill, level.map(String.init), blood, requirement]
            .compactMap { $0 }.joined(separator: "/")
    }

    var learningDescription: String {
        var words = [blood.map { $0 + "血脉" } ?? source.title]
        if let level { words.append("Lv.\(level)") }
        if let requirement { words.append("需要" + requirement) }
        return words.joined(separator: " · ")
    }
}

struct BattleProfile: Decodable {
    let height, weight: String?
    let trait, learnset: String
}

final class BattleGuide {
    private struct Reference: Decodable {
        let types: [String: String]
        let profiles: [String: BattleProfile]
        let skills: [String: BattleSkill]
        let learnsets: [String: [LearnedSkill]]
    }

    static let shared = BattleGuide(bundle: .main)

    private let reference: Reference?
    private let iconsDirectory: URL?
    private let images = NSCache<NSString, UIImage>()

    init(bundle: Bundle) {
        let directory = bundle.resourceURL?.appendingPathComponent("BattleGuide", isDirectory: true)
        iconsDirectory = directory?.appendingPathComponent("Icons", isDirectory: true)
        let url = directory?.appendingPathComponent("catalog.json")
        let data = url.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
        reference = data.flatMap { try? JSONDecoder().decode(Reference.self, from: $0) }
        images.totalCostLimit = 8 * 1024 * 1024
    }

    func profile(for spiritID: Int) -> BattleProfile? { reference?.profiles[String(spiritID)] }
    func skill(_ id: String) -> BattleSkill? { reference?.skills[id] }

    func skills(for spiritID: Int) -> [LearnedSkill] {
        guard let profile = profile(for: spiritID) else { return [] }
        return reference?.learnsets[profile.learnset] ?? []
    }

    func trait(for spiritID: Int) -> BattleSkill? {
        profile(for: spiritID).flatMap { skill($0.trait) }
    }

    func typeImage(_ type: String) -> UIImage? {
        let key = type.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "系", with: "")
        return reference?.types[key].flatMap { image($0) }
    }

    func image(_ filename: String) -> UIImage? {
        let key = filename as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let url = iconsDirectory?.appendingPathComponent(filename),
              let bitmap = UIImage(contentsOfFile: url.path) else { return nil }
        let cost = bitmap.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        images.setObject(bitmap, forKey: key, cost: cost)
        return bitmap
    }
}
