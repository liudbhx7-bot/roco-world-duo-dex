import AVFoundation
import UIKit
import XCTest
@testable import RocoDex

@MainActor
final class DexNarratorTests: XCTestCase {
    func testEveryFormHasItsOwnOfflineRecording() throws {
        let entries = try Catalog().entries
        let locations = try entries.map { entry in
            try XCTUnwrap(DexNarrator.trackURL(for: entry), entry.name)
        }
        XCTAssertEqual(Set(locations).count, entries.count)
        for (entry, url) in zip(entries, locations) {
            let properties = try url.resourceValues(forKeys: [.fileSizeKey])
            XCTAssertGreaterThan(properties.fileSize ?? 0, 2_000, entry.name)
        }
    }

    func testEveryIntroductionContainsItsOpeningAndClosingSounds() throws {
        for spirit in try Catalog().entries {
            let url = try XCTUnwrap(DexNarrator.trackURL(for: spirit))
            let audio = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let duration = Double(audio.length) / audio.processingFormat.sampleRate
            // The sounds are part of the recording, so exporting a single form must keep both.
            XCTAssertGreaterThan(try rms(audio, start: 0.100, seconds: 0.270), 0.07, "Opening: \(spirit.name)")
            XCTAssertGreaterThan(try rms(audio, start: duration - 0.342, seconds: 0.234), 0.05, "Closing: \(spirit.name)")
        }
    }

    private func rms(_ file: AVAudioFile, start: Double, seconds: Double) throws -> Float {
        let format = file.processingFormat
        let count = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count))
        file.framePosition = AVAudioFramePosition(start * format.sampleRate)
        try file.read(into: buffer, frameCount: count)
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        XCTAssertEqual(buffer.frameLength, count)
        let total = (0..<Int(buffer.frameLength)).reduce(Float.zero) { $0 + samples[$1] * samples[$1] }
        return sqrt(total / Float(count))
    }

    func testRecordingsContainSpeech() throws {
        let entries = try Catalog().entries
        let samples = entries.enumerated().filter { $0.offset % 97 == 0 || $0.element.id == 8 || $0.offset == entries.count - 1 }
        for (_, entry) in samples {
            let url = try XCTUnwrap(DexNarrator.trackURL(for: entry))
            let track = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let count = AVAudioFrameCount(track.length)
            let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: track.processingFormat, frameCapacity: count))
            try track.read(into: pcm)
            let samples = try XCTUnwrap(pcm.floatChannelData)[0]
            let lead = Int(track.processingFormat.sampleRate * 0.05)
            XCTAssertGreaterThan(Int(pcm.frameLength), lead)
            let backgroundPeak = (0..<lead).reduce(Float.zero) { max($0, abs(samples[$1])) }
            let rate = track.processingFormat.sampleRate
            let speechRange = Int(rate * 0.56)..<(Int(pcm.frameLength) - Int(rate * 0.47))
            let speechSamples = speechRange.filter { abs(samples[$0]) > 0.035 }.count
            XCTAssertLessThan(backgroundPeak, 0.004, entry.number)
            XCTAssertGreaterThan(speechSamples, Int(track.processingFormat.sampleRate), entry.number)
        }
    }

    func testNarrationPlaysToCompletion() async throws {
        let water = try XCTUnwrap(Catalog().entries.first { $0.id == 8 })
        let narrator = DexNarrator()
        narrator.speak(water)
        XCTAssertTrue(narrator.isSpeaking)
        let clock = ContinuousClock()
        let start = clock.now
        var maxPeak: Float = -160
        var audibleIntervals = 0
        var metered: [(time: ContinuousClock.Instant, average: Float, lamp: Double)] = []
        var route = ""
        var volume: Float = -1
        while narrator.isSpeaking && start.duration(to: clock.now) < .seconds(30) {
            try await Task.sleep(for: .milliseconds(16))
            if let levels = narrator.playbackLevels() {
                if route.isEmpty {
                    let audio = AVAudioSession.sharedInstance()
                    route = audio.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
                    volume = audio.outputVolume
                }
                metered.append((clock.now, levels.average, narrator.lamp.level))
                maxPeak = max(maxPeak, levels.peak)
                if levels.average > -40 { audibleIntervals += 1 }
            }
        }
        let first = try XCTUnwrap(metered.first).time
        let last = try XCTUnwrap(metered.last).time
        let opening = metered.filter { first.duration(to: $0.time) < .milliseconds(430) }.map(\.average).max() ?? -160
        let closing = metered.filter { $0.time.duration(to: last) < .milliseconds(350) }.map(\.average).max() ?? -160
        XCTAssertGreaterThan(opening, -35, "The opening sound must reach the actual introduction player")
        XCTAssertGreaterThan(closing, -35, "Playback must continue through the closing sound")
        let openingLight = metered.filter { first.duration(to: $0.time) < .milliseconds(430) }.map(\.lamp).max() ?? 0
        let closingLight = metered.filter { $0.time.duration(to: last) < .milliseconds(350) }.map(\.lamp).max() ?? 0
        XCTAssertGreaterThan(openingLight, 0.2)
        XCTAssertGreaterThan(closingLight, 0.2)
        let spoken = metered.filter {
            first.duration(to: $0.time) > .seconds(1) && $0.time.duration(to: last) > .seconds(1)
        }
        var deepestPauseDip = 0.0
        for pause in spoken where pause.average < -36 {
            let recentSpeech = spoken.filter {
                $0.average > -30 && $0.time <= pause.time && $0.time.duration(to: pause.time) < .milliseconds(500)
            }
            let previousBrightness = recentSpeech.map(\.lamp).max() ?? 0
            deepestPauseDip = max(deepestPauseDip, previousBrightness - pause.lamp)
        }
        XCTAssertGreaterThan(spoken.map(\.lamp).max() ?? 0, 0.35)
        XCTAssertGreaterThan(deepestPauseDip, 0.12, "The lamp should dim between spoken phrases")
        XCTAssertEqual(narrator.lamp.level, 0)
        print("Lamp: opening=\(openingLight) closing=\(closingLight) phraseDip=\(deepestPauseDip)")
        print("Narration effects opening=\(opening) dBFS closing=\(closing) dBFS")
        print("RocoDex AUDIO_CHECK track=008.m4a route=\(route) mediaVolume=\(volume) peakDBFS=\(maxPeak) audibleIntervals=\(audibleIntervals)")
        XCTAssertNil(narrator.unavailableMessage)
        XCTAssertFalse(narrator.isSpeaking)
        XCTAssertFalse(route.isEmpty)
        XCTAssertGreaterThan(maxPeak, -30)
        XCTAssertGreaterThan(audibleIntervals, 12)
        XCTAssertGreaterThan(start.duration(to: clock.now), .seconds(3))
    }

    func testLampResetsOnStopAndBackgroundInterruption() async throws {
        let water = try XCTUnwrap(Catalog().entries.first { $0.id == 8 })
        let narrator = DexNarrator()
        for background in [false, true] {
            narrator.speak(water)
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while narrator.lamp.level < 0.1 && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertGreaterThan(narrator.lamp.level, 0)
            if background {
                NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            } else {
                narrator.stop()
            }
            XCTAssertFalse(narrator.isSpeaking)
            XCTAssertEqual(narrator.lamp.level, 0)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(narrator.lamp.level, 0)
        }
    }

    func testReplacingAndStoppingNarration() async throws {
        let entries = try Catalog().entries
        let narrator = DexNarrator()
        narrator.speak(entries[0])
        narrator.speak(entries[1])
        XCTAssertTrue(narrator.isSpeaking)
        narrator.stop()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(narrator.isSpeaking)
        XCTAssertNil(narrator.unavailableMessage)
        XCTAssertNil(narrator.playbackLevels())
    }
}
