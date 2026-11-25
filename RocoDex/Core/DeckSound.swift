import SwiftUI

enum DeckSound: String, CaseIterable {
    case key, page, scan, found, choice, miss

    static let preferenceKey = "feedbackSoundEnabled"
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    @MainActor private static var tracks: [DeckSound: HandheldMediaTrack] = [:]

    @MainActor @discardableResult
    func play() -> Bool {
        guard Self.enabled, UIApplication.shared.applicationState == .active,
              let url = Bundle.main.url(forResource: rawValue, withExtension: "wav", subdirectory: "Sounds") else {
            return false
        }
        let track = Self.tracks[self] ?? HandheldMediaTrack()
        Self.tracks[self] = track
        track.play(url, shouldStart: { Self.enabled && UIApplication.shared.applicationState == .active })
        return true
    }

    @MainActor func playbackLevels() -> (peak: Float, average: Float)? {
        Self.tracks[self]?.playbackLevels()
    }
}

extension Button {
    // Trigger inside the action, so VoiceOver works and canceled presses stay silent.
    init(feedback sound: DeckSound, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {
        self.init {
            sound.play()
            action()
        } label: { label() }
    }
}
