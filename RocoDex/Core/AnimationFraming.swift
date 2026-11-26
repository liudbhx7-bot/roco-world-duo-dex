import Foundation
import CoreGraphics

/// Coordinates use the upper-left origin of the full, composited APNG canvas.
struct AnimationFraming: Decodable, Equatable {
    private struct Box: Decodable {
        let x, y, width, height: CGFloat

        var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
        var isValid: Bool { width > 0 && height > 0 && rect.maxX.isFinite && rect.maxY.isFinite }
    }

    private struct Keyframe: Decodable, Equatable {
        let frame: Int
        let rect: CGRect

        private enum CodingKeys: CodingKey { case frame }

        init(from decoder: Decoder) throws {
            frame = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .frame)
            let box = try Box(from: decoder)
            guard frame >= 0, box.isValid else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid entry framing key"))
            }
            rect = box.rect
        }
    }

    private enum CodingKeys: CodingKey { case entryKeys, idleKeys }
    private let settled: CGRect
    private let entryKeys: [Keyframe]
    private let idleKeys: [Keyframe]

    static let fullCanvas = AnimationFraming(settled: CGRect(x: 0, y: 0, width: 1, height: 1), entryKeys: [], idleKeys: [])

    private init(settled: CGRect, entryKeys: [Keyframe], idleKeys: [Keyframe]) {
        self.settled = settled
        self.entryKeys = entryKeys
        self.idleKeys = idleKeys
    }

    init(from decoder: Decoder) {
        do {
            let box = try Box(from: decoder)
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            let entry = try fields.decodeIfPresent([Keyframe].self, forKey: .entryKeys) ?? []
            let idle = try fields.decodeIfPresent([Keyframe].self, forKey: .idleKeys) ?? []
            func returnsToSettled(_ keys: [Keyframe]) -> Bool {
                zip(keys, keys.dropFirst()).allSatisfy { $0.frame < $1.frame }
                    && (keys.last.map { $0.rect == box.rect } ?? true)
            }
            guard box.isValid, returnsToSettled(entry), returnsToSettled(idle),
                  idle.first.map({ $0.frame == 0 && $0.rect == box.rect }) ?? true else {
                self = .fullCanvas
                return
            }
            self.init(settled: box.rect, entryKeys: entry, idleKeys: idle)
        } catch {
            // An invalid row must not disable animations or framing for other forms.
            self = .fullCanvas
        }
    }

    func validated(entryFrameCount: Int?, idleFrameCount: Int?) -> Self {
        if let count = entryFrameCount, let last = entryKeys.last, last.frame >= count { return .fullCanvas }
        if let count = idleFrameCount, let last = idleKeys.last, last.frame >= count { return .fullCanvas }
        return self
    }

    func viewport(for frame: Int, isEntry: Bool) -> CGRect {
        let keys = isEntry ? entryKeys : idleKeys
        guard let upper = keys.firstIndex(where: { $0.frame >= frame }) else { return settled }
        let next = keys[upper]
        guard upper > 0, next.frame != frame else { return next.rect }
        let previous = keys[upper - 1]
        let fraction = CGFloat(frame - previous.frame) / CGFloat(next.frame - previous.frame)
        func blend(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * fraction }
        return CGRect(x: blend(previous.rect.minX, next.rect.minX), y: blend(previous.rect.minY, next.rect.minY),
                      width: blend(previous.rect.width, next.rect.width), height: blend(previous.rect.height, next.rect.height))
    }

    /// Fit the view box into the slot, then draw the entire source around that box.
    /// Extra horizontal or vertical room stays available for the wings or tail.
    static func imageFrame(canvas: CGSize, viewport: CGRect, in slot: CGRect) -> CGRect {
        guard canvas.width > 0, canvas.height > 0, slot.width > 0, slot.height > 0 else { return .zero }
        let scale = min(slot.width / (viewport.width * canvas.width), slot.height / (viewport.height * canvas.height))
        let width = canvas.width * scale
        let height = canvas.height * scale
        return CGRect(x: slot.midX - viewport.midX * width, y: slot.midY - viewport.midY * height,
                      width: width, height: height)
    }
}
