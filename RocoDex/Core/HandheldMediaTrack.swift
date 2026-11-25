import AVFAudio
import UIKit

enum HandheldPlaybackError: Error {
    case mediaOutput, recording
}

// AVAudioSession belongs to the application. Only release it after *all* players,
// including short-lived button sounds, have given up their requests.
private final class HandheldMediaSession: @unchecked Sendable {
    static let shared = HandheldMediaSession()
    private let queue = DispatchQueue(label: "roco.handheld.media", qos: .userInitiated)
    private var requests = Set<UUID>()

    func prepare(_ url: URL, for id: UUID,
                 completion: @escaping @MainActor (Result<AVAudioPlayer, HandheldPlaybackError>) -> Void) {
        queue.async {
            if self.requests.isEmpty {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .default, options: .duckOthers)
                    try session.setActive(true)
                } catch {
                    DispatchQueue.main.async { completion(.failure(.mediaOutput)) }
                    return
                }
            }

            self.requests.insert(id)
            let player = try? AVAudioPlayer(contentsOf: url)
            let result: Result<AVAudioPlayer, HandheldPlaybackError>
            if let player, player.prepareToPlay() { result = .success(player) }
            else { result = .failure(.recording) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func release(_ id: UUID) {
        queue.async {
            guard self.requests.remove(id) != nil, self.requests.isEmpty else { return }
            // Keep the route warm through a quick second press or a track change.
            self.queue.asyncAfter(deadline: .now() + .milliseconds(180)) {
                guard self.requests.isEmpty else { return }
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }
}

@MainActor
final class HandheldMediaTrack: NSObject, AVAudioPlayerDelegate {
    private var request: UUID?
    private var player: AVAudioPlayer?
    private var finished: ((HandheldPlaybackError?) -> Void)?
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification,
                                           object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            guard let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext,
                  context.source == .system else { return }
            MainActor.assumeIsolated { self?.finish() }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        if let request { HandheldMediaSession.shared.release(request) }
    }

    func play(_ url: URL, shouldStart: @escaping @MainActor () -> Bool = { true },
              onFinish: ((HandheldPlaybackError?) -> Void)? = nil) {
        stop()
        let id = UUID()
        request = id
        finished = onFinish
        HandheldMediaSession.shared.prepare(url, for: id) { [weak self] result in
            guard let self, self.request == id else { return }
            guard shouldStart() else { self.finish(); return }
            switch result {
            case .success(let prepared):
                self.player = prepared
                prepared.delegate = self
                if !prepared.play() { self.finish(.recording) }
            case .failure(let error):
                self.finish(error)
            }
        }
    }

    func stop() {
        player?.delegate = nil
        player?.stop()
        player = nil
        if let request { HandheldMediaSession.shared.release(request) }
        request = nil
        finished = nil
    }

    func playbackLevels() -> (peak: Float, average: Float)? {
        guard let player, player.isPlaying else { return nil }
        player.isMeteringEnabled = true
        player.updateMeters()
        return (player.peakPower(forChannel: 0), player.averagePower(forChannel: 0))
    }

    private func finish(_ error: HandheldPlaybackError? = nil) {
        let callback = finished
        stop()
        callback?(error)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.finish(flag ? nil : .recording)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.finish(.recording)
        }
    }
}
