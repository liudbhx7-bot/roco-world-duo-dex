import AVFoundation
import XCTest
@testable import RocoDex

@MainActor
final class DeckSoundTests: XCTestCase {
    func testFeedbackResourcesAndMuteSwitch() throws {
        let defaults = UserDefaults.standard
        let key = DeckSound.preferenceKey
        let previous = defaults.object(forKey: key)
        defer { defaults.set(previous, forKey: key) }

        defaults.set(true, forKey: key)
        for cue in DeckSound.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: cue.rawValue, withExtension: "wav", subdirectory: "Sounds"))
            let audio = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(audio.duration, 0.025)
            XCTAssertLessThan(audio.duration, cue == .found ? 0.54 : 0.30)
            XCTAssertTrue(cue.play(), "Request the bundled \(cue.rawValue) cue on the media output")
        }

        defaults.set(false, forKey: key)
        for cue in DeckSound.allCases {
            XCTAssertFalse(cue.play())
        }
    }

    func testPageProducesAudibleMediaAlongsideAndAfterNarration() async throws {
        let key = DeckSound.preferenceKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }

        let narrator = DexNarrator()
        defer { narrator.stop() }
        let water = try XCTUnwrap(Catalog().entries.first { $0.id == 8 })
        try await assertPageAudible("standalone")
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)

        narrator.speak(water)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (narrator.playbackLevels()?.peak ?? -160) < -40, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(8))
        }
        XCTAssertNotNil(narrator.playbackLevels(), "The narrator must already be playing on the media route")
        try await assertPageAudible("over narration")
        XCTAssertTrue(narrator.isSpeaking)
        XCTAssertNotNil(narrator.playbackLevels())

        XCTAssertTrue(DeckSound.page.play())
        narrator.stop()
        try await assertPageAudible("narration stopped", start: false)
        XCTAssertNil(narrator.playbackLevels())
        try await Task.sleep(for: .milliseconds(550))
        try await assertPageAudible("after idle")
    }

    private func assertPageAudible(_ context: String, start: Bool = true) async throws {
        if start { XCTAssertTrue(DeckSound.page.play()) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        var peak: Float = -160
        while ContinuousClock.now < deadline && peak < -40 {
            if let level = DeckSound.page.playbackLevels() { peak = max(peak, level.peak) }
            try await Task.sleep(for: .milliseconds(6))
        }
        print("Page audio (\(context)): \(peak) dBFS")
        XCTAssertGreaterThan(peak, -40, context)
    }
}
