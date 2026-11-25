import Combine
import Foundation

/// Subscribed to by the small lens view; changes never invalidate the rest of the deck.
@MainActor
final class NarrationLampSignal: ObservableObject {
    @Published private(set) var level: Double = 0
    private var sampler: Task<Void, Never>?

    fileprivate func follow(_ track: HandheldMediaTrack) {
        reset()
        sampler = Task { [weak self, weak track] in
            while !Task.isCancelled {
                if let self, let track {
                    let db = Double(track.playbackLevels()?.average ?? -160)
                    let target = min(1, max(0, (db + 45) / 39))
                    // A short attack and slightly longer release keep syllables legible
                    // without turning the lens fully on and off at every consonant.
                    let next = self.level + (target - self.level) * (target > self.level ? 0.42 : 0.32)
                    if abs(next - self.level) >= 0.004 {
                        self.level = next
                    } else if target == 0 && self.level != 0 {
                        self.level = 0
                    }
                } else {
                    return
                }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    fileprivate func reset() {
        sampler?.cancel()
        sampler = nil
        if level != 0 { level = 0 }
    }

    deinit { sampler?.cancel() }
}

@MainActor
final class DexNarrator: ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published var unavailableMessage: String?

    let lamp = NarrationLampSignal()
    private let track = HandheldMediaTrack()

    func speak(_ spirit: Spirit) {
        stop()
        unavailableMessage = nil
        guard let url = Self.trackURL(for: spirit) else {
            report(.recording)
            return
        }
        isSpeaking = true
        lamp.follow(track)
        track.play(url, onFinish: { [weak self] error in
            self?.lamp.reset()
            self?.isSpeaking = false
            if let error { self?.report(error) }
        })
    }

    func stop() {
        lamp.reset()
        track.stop()
        isSpeaking = false
    }

    static func trackURL(for spirit: Spirit) -> URL? {
        // Alternate forms can share a printed number, but always have separate recordings.
        let recordingID = String(format: "%03d", spirit.id)
        return Bundle.main.url(forResource: recordingID, withExtension: "m4a", subdirectory: "Narration")
    }

    func playbackLevels() -> (peak: Float, average: Float)? {
        track.playbackLevels()
    }

    private func report(_ error: HandheldPlaybackError) {
        switch error {
        case .mediaOutput:
            unavailableMessage = "无法打开音频输出，请检查媒体音量及耳机连接后再试。"
        case .recording:
            unavailableMessage = "这份精灵介绍的录音无法播放，请检查应用资源后重试。"
        }
    }
}
