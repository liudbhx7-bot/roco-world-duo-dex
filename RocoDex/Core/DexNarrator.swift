import AVFoundation
import Combine
import Foundation

@MainActor
final class DexNarrator: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isSpeaking = false
    @Published var unavailableMessage: String?

    private let sessionQueue = DispatchQueue(label: "roco.narration.audio-session", qos: .userInitiated)
    private var player: AVAudioPlayer?
    private var currentRequest = UUID()
    private var needsSessionRelease = false
    private var interruption: NSObjectProtocol?

    override init() {
        super.init()
        interruption = NotificationCenter.default.addObserver(
            forName: AVAudioSession.didBecomeInactiveNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            guard let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext,
                  context.source == .system else { return }
            Task { @MainActor in self?.stop() }
        }
    }

    deinit {
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
    }

    func speak(_ spirit: Spirit) {
        stop()
        unavailableMessage = nil
        let id = currentRequest
        isSpeaking = true
        needsSessionRelease = true
        sessionQueue.async { [weak self] in
            do {
                let session = AVAudioSession.sharedInstance()
                // Use the current media output, including when the Ring/Silent switch is set to silent.
                try session.setCategory(.playback, mode: .default, options: .duckOthers)
                try session.setActive(true)
                DispatchQueue.main.async {
                    guard let self, self.currentRequest == id else { return }
                    self.play(spirit)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.currentRequest == id else { return }
                    self.fail("无法打开音频输出，请检查媒体音量及耳机连接后再试。")
                }
            }
        }
    }

    func stop() {
        currentRequest = UUID()
        player?.delegate = nil
        player?.stop()
        player = nil
        isSpeaking = false
        if needsSessionRelease {
            needsSessionRelease = false
            sessionQueue.async {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    private func play(_ spirit: Spirit) {
        if let file = Self.trackURL(for: spirit), let track = try? AVAudioPlayer(contentsOf: file) {
            track.delegate = self
            if track.prepareToPlay(), track.play() {
                player = track
                return
            }
        }
        fail("这份精灵介绍的录音无法播放，请检查应用资源后重试。")
    }

    static func trackURL(for spirit: Spirit) -> URL? {
        // Alternate forms can share a printed number, but always have separate recordings.
        let recordingID = String(format: "%03d", spirit.id)
        return Bundle.main.url(forResource: recordingID, withExtension: "m4a", subdirectory: "Narration")
    }

    // Sample the active playback path on demand. Metering stays disabled in normal use.
    func playbackLevels() -> (peak: Float, average: Float)? {
        guard let player, player.isPlaying else { return nil }
        player.isMeteringEnabled = true
        player.updateMeters()
        return (player.peakPower(forChannel: 0), player.averagePower(forChannel: 0))
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            if flag { self.stop() } else { self.fail("音轨播放中断，请再试一次。") }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.fail("音轨读取失败，请再试一次。")
        }
    }

    private func fail(_ message: String) {
        stop()
        unavailableMessage = message
    }
}
